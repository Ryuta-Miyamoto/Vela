//
//  SubfolderSearch.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/10/04.
//

import Foundation

// Searches a folder and everything below it for names containing the query. Walks the tree itself
// rather than asking Spotlight, so external drives, unindexed folders and hidden files (when shown)
// are covered too. Runs on a background queue and hands matches to the main thread in batches
nonisolated final class SubfolderSearch: @unchecked Sendable {
    // Searching from a high-level folder can match a huge number of items; stop there
    static let resultLimit = 5000

    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }

    func start(root: URL, query: String, includeHidden: Bool,
               onBatch: @escaping @MainActor @Sendable ([FileItem]) -> Void,
               onFinish: @escaping @MainActor @Sendable (_ reachedLimit: Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            func deliver(_ batch: [FileItem]) {
                guard !batch.isEmpty else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { onBatch(batch) } }
            }
            func finish(reachedLimit: Bool) {
                DispatchQueue.main.async { MainActor.assumeIsolated { onFinish(reachedLimit) } }
            }

            // Like Finder, don't look inside apps and other packages
            var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
            if !includeHidden { options.insert(.skipsHiddenFiles) }
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: FileService.resourceKeys,
                options: options, errorHandler: { _, _ in true }
            ) else { return finish(reachedLimit: false) }

            var batch: [FileItem] = []
            var count = 0
            var lastDelivery = Date()
            while let url = enumerator.nextObject() as? URL {
                if isCancelled { return }
                guard url.lastPathComponent.localizedCaseInsensitiveContains(query),
                      let item = FileService.item(at: url) else { continue }
                batch.append(item)
                count += 1
                if count >= Self.resultLimit {
                    deliver(batch)
                    return finish(reachedLimit: true)
                }
                if Date().timeIntervalSince(lastDelivery) > 0.15 {
                    deliver(batch)
                    batch = []
                    lastDelivery = Date()
                }
            }
            deliver(batch)
            finish(reachedLimit: false)
        }
    }
}
