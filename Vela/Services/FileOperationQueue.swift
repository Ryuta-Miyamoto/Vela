//
//  FileOperationQueue.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/10/04.
//

import AppKit
import Darwin

// Runs copies and moves one job at a time on a background queue so that large transfers don't freeze
// the UI. While a job runs, `status` drives the progress shown in the status bar. Undo is registered on
// the main thread once the job finishes, for the items that completed.
@Observable
final class FileOperationQueue {
    static let shared = FileOperationQueue()

    nonisolated enum Kind: Sendable { case copy, move }

    // How the destination name is chosen. Resolved on the worker right before each item is copied,
    // so several queued duplicates of the same file don't end up with the same name
    nonisolated enum NameRule: Sendable {
        case keep
        case uniqueCopy(suffix: String)
    }

    nonisolated struct Request: Sendable {
        let source: URL
        let destinationFolder: URL
        let nameRule: NameRule
    }

    struct Status: Equatable {
        let kind: Kind
        let itemCount: Int
        let currentName: String
        let completedBytes: Int64
        // nil while the sizes of the sources are still being added up
        let totalBytes: Int64?
        let queuedCount: Int
        let isCancelling: Bool

        var fraction: Double? {
            guard let totalBytes else { return nil }
            return totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : 0
        }
    }

    // Stays nil for jobs that finish quickly, so instant operations don't flash the progress bar
    private(set) var status: Status?

    private struct Job {
        let kind: Kind
        let requests: [Request]
        let actionName: String
        let completion: () -> Void
    }

    private var pending: [Job] = []
    private var running: (job: Job, progress: TransferProgress, startedAt: Date)?
    private var pollTimer: Timer?
    private let workQueue = DispatchQueue(label: "Vela.FileOperationQueue", qos: .userInitiated)

    private static let statusDelay: TimeInterval = 0.3

    private init() {}

    func enqueue(_ kind: Kind, _ requests: [Request], actionName: String, completion: @escaping () -> Void = {}) {
        guard !requests.isEmpty else { return }
        pending.append(Job(kind: kind, requests: requests, actionName: actionName, completion: completion))
        startNextIfIdle()
    }

    func cancelCurrent() {
        running?.progress.cancel()
        updateStatus()
    }

    private func startNextIfIdle() {
        guard running == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        let progress = TransferProgress()
        running = (job, progress, Date())

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatus() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        let kind = job.kind
        let requests = job.requests
        workQueue.async {
            let outcomes = TransferWorker.perform(kind, requests, progress: progress)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finish(job, outcomes: outcomes) }
            }
        }
    }

    private func updateStatus() {
        guard let running else {
            status = nil
            return
        }
        guard Date().timeIntervalSince(running.startedAt) >= Self.statusDelay else { return }
        let snapshot = running.progress.snapshot()
        let newStatus = Status(kind: running.job.kind,
                               itemCount: running.job.requests.count,
                               currentName: snapshot.currentName,
                               completedBytes: snapshot.completedBytes,
                               totalBytes: snapshot.totalBytes,
                               queuedCount: pending.count,
                               isCancelling: snapshot.isCancelled)
        if newStatus != status { status = newStatus }
    }

    private func finish(_ job: Job, outcomes: [TransferWorker.Outcome]) {
        pollTimer?.invalidate()
        pollTimer = nil
        running = nil
        status = nil

        var failures: [(name: String, message: String)] = []
        for outcome in outcomes {
            switch outcome {
            case .copied(let dest):
                FileOperations.registerCreation(of: dest, actionName: job.actionName)
            case .moved(let source, let dest):
                FileOperations.registerMove(from: source, to: dest, actionName: job.actionName)
            case .failed(let name, let message):
                failures.append((name, message))
            }
        }
        job.completion()
        if !failures.isEmpty { showFailures(failures, kind: job.kind) }
        startNextIfIdle()
    }

    private func showFailures(_ failures: [(name: String, message: String)], kind: Kind) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failures.count == 1
            ? L10n.transferFailed(kind: kind, name: failures[0].name)
            : L10n.transferFailed(kind: kind, count: failures.count)
        // List up to a few reasons; the rest would only make the alert too tall
        let shown = failures.prefix(5).map { failures.count == 1 ? $0.message : "\($0.name): \($0.message)" }
        alert.informativeText = shown.joined(separator: "\n")
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

// MARK: - Progress shared with the worker

// Written by the worker (and by copyfile's callback), read by the main thread's poll timer
nonisolated final class TransferProgress: @unchecked Sendable {
    struct Snapshot {
        let currentName: String
        let completedBytes: Int64
        let totalBytes: Int64?
        let isCancelled: Bool
    }

    private let lock = NSLock()
    private var cancelled = false
    private var totalBytes: Int64?
    // Bytes of files that have finished, plus how far the file being copied has got
    private var finishedBytes: Int64 = 0
    private var currentFileBytes: Int64 = 0
    private var currentName = ""

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }

    func setTotal(_ bytes: Int64) { lock.withLock { totalBytes = bytes } }

    func beginItem(named name: String) { lock.withLock { currentName = name } }

    func updateCurrentFile(copiedBytes: Int64) { lock.withLock { currentFileBytes = copiedBytes } }

    func finishFile(size: Int64) {
        lock.withLock {
            finishedBytes += size
            currentFileBytes = 0
        }
    }

    // copyfile doesn't report every file (e.g. a single non-recursive copy), so once a whole item is done
    // the count is reset to the exact running total
    func finishItem(cumulativeBytes: Int64) {
        lock.withLock {
            finishedBytes = cumulativeBytes
            currentFileBytes = 0
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(currentName: currentName,
                     completedBytes: finishedBytes + currentFileBytes,
                     totalBytes: totalBytes,
                     isCancelled: cancelled)
        }
    }
}

// MARK: - Worker

nonisolated enum TransferWorker {
    enum Outcome: Sendable {
        case copied(dest: URL)
        case moved(from: URL, to: URL)
        case failed(name: String, message: String)
    }

    static func perform(_ kind: FileOperationQueue.Kind,
                        _ requests: [FileOperationQueue.Request],
                        progress: TransferProgress) -> [Outcome] {
        // Moves within a volume are just renames and finish instantly, so only copied bytes count
        let needsCopy = requests.map { kind == .copy || !isSameVolume($0.source, $0.destinationFolder) }
        var sizes: [Int64] = []
        for (request, copies) in zip(requests, needsCopy) {
            if progress.isCancelled { return [] }
            sizes.append(copies ? totalSize(of: request.source, progress: progress) : 0)
        }
        progress.setTotal(sizes.reduce(0, +))

        var outcomes: [Outcome] = []
        var cumulative: Int64 = 0
        for (index, request) in requests.enumerated() {
            if progress.isCancelled { break }
            let source = request.source
            progress.beginItem(named: source.lastPathComponent)
            let dest = destination(for: request)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: dest.path])
                }
                if !needsCopy[index] {
                    try FileManager.default.moveItem(at: source, to: dest)
                    outcomes.append(.moved(from: source, to: dest))
                } else {
                    try copy(source, to: dest, progress: progress)
                    if kind == .move {
                        // A move across volumes is a copy followed by deleting the original
                        try FileManager.default.removeItem(at: source)
                        outcomes.append(.moved(from: source, to: dest))
                    } else {
                        outcomes.append(.copied(dest: dest))
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                outcomes.append(.failed(name: source.lastPathComponent, message: error.localizedDescription))
            }
            cumulative += sizes[index]
            progress.finishItem(cumulativeBytes: cumulative)
        }
        return outcomes
    }

    private static func destination(for request: FileOperationQueue.Request) -> URL {
        let source = request.source
        switch request.nameRule {
        case .keep:
            return request.destinationFolder.appendingPathComponent(source.lastPathComponent)
        case .uniqueCopy(let suffix):
            return FileOperations.uniqueURL(in: request.destinationFolder,
                                            baseName: source.deletingPathExtension().lastPathComponent,
                                            pathExtension: source.pathExtension,
                                            suffix: suffix)
        }
    }

    private static func isSameVolume(_ source: URL, _ destinationFolder: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        // A symbolic link reports the volume it sits on, not the one it points to, so follow the destination.
        // The source itself is moved as is (a link stays a link), so its own volume is the right one
        guard let a = try? source.resourceValues(forKeys: key).volumeIdentifier as? NSObject,
              let b = try? destinationFolder.resolvingSymlinksInPath().resourceValues(forKeys: key).volumeIdentifier as? NSObject
        else { return false }
        return a.isEqual(b)
    }

    private static func totalSize(of url: URL, progress: TransferProgress) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true, values.isSymbolicLink != true else { return Int64(values.fileSize ?? 0) }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                              options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            if progress.isCancelled { break }
            guard let v = try? child.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.fileSize ?? 0)
        }
        return total
    }

    // Same as Finder: clones on APFS when possible, keeps metadata and copies symbolic links as links.
    // Unlike FileManager.copyItem, copyfile reports progress and can be stopped part way
    private static func copy(_ source: URL, to dest: URL, progress: TransferProgress) throws {
        guard let state = copyfile_state_alloc() else { throw POSIXError(.ENOMEM) }
        defer { copyfile_state_free(state) }

        let callback: copyfile_callback_t = { what, stage, state, src, _, ctx in
            guard let ctx else { return COPYFILE_CONTINUE }
            let progress = Unmanaged<TransferProgress>.fromOpaque(ctx).takeUnretainedValue()
            if progress.isCancelled { return COPYFILE_QUIT }
            if stage == COPYFILE_ERR { return COPYFILE_QUIT }
            switch (what, stage) {
            case (COPYFILE_COPY_DATA, COPYFILE_PROGRESS):
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                progress.updateCurrentFile(copiedBytes: Int64(copied))
            case (COPYFILE_RECURSE_FILE, COPYFILE_FINISH):
                var info = stat()
                if let src, lstat(src, &info) == 0 { progress.finishFile(size: Int64(info.st_size)) }
            default:
                break
            }
            return COPYFILE_CONTINUE
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(progress).toOpaque())

        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_CLONE | COPYFILE_EXCL)
        let result = copyfile(source.path, dest.path, state, flags)
        let code = errno
        guard result != 0 else { return }

        // Don't leave a half-copied item behind. The destination didn't exist before (checked by the caller)
        try? FileManager.default.removeItem(at: dest)
        if progress.isCancelled { throw CancellationError() }
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
