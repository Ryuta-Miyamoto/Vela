//
//  DirectoryWatcher.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/10/03.
//

import Foundation
import CoreServices

// 表示中のディレクトリを FSEvents で監視し、中身が変わったら onChange を呼ぶ。
// DispatchSource（kqueue）だと項目の追加・削除・名前変更しか拾えないが、FSEvents はファイルの
// 書き込み（サイズ・更新日の変化）も親ディレクトリのイベントとして届くため、ダウンロード中の
// ファイルサイズなども追従できる
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let watchedPath: String
    private let onChange: () -> Void

    init?(url: URL, onChange: @escaping () -> Void) {
        // FSEvents は /tmp → /private/tmp のようにシンボリックリンクを解決した実パスで通知してくる
        self.watchedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let flags = Array(UnsafeBufferPointer(start: flags, count: count))
            // ストリームはメインキューに載せているので、コールバックは常にメインスレッドで呼ばれる
            MainActor.assumeIsolated { watcher.handle(paths: paths, flags: flags) }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context,
            [watchedPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        ) else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        // FSEvents はサブディレクトリ以下の変更も届けてくるので、監視対象の直下の変更だけを拾う。
        // 取りこぼしが起きた（MustScanSubDirs）ときは念のため読み直す
        let mustRescan = flags.contains { $0 & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 }
        let isDirectChange = paths.contains {
            URL(fileURLWithPath: $0).standardizedFileURL.path == watchedPath
        }
        if mustRescan || isDirectChange { onChange() }
    }
}
