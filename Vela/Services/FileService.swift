//
//  FileService.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import Foundation

final class FileService {
    static let shared = FileService()
    private init() {}

    func contents(of directory: URL, includeHidden: Bool = false) -> [FileItem] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden { options.insert(.skipsHiddenFiles) }

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: options
        ) else { return [] }

        return urls.compactMap { url in
            guard let res = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return FileItem(
                name: url.lastPathComponent,
                url: url,
                size: Int64(res.fileSize ?? 0),
                modifiedDate: res.contentModificationDate ?? Date(),
                isDirectory: res.isDirectory ?? false
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
