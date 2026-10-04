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

    nonisolated static let resourceKeys: [URLResourceKey] = [
        .fileSizeKey, .contentModificationDateKey, .creationDateKey,
        .localizedTypeDescriptionKey, .isDirectoryKey, .isPackageKey, .isHiddenKey,
    ]

    func contents(of directory: URL, includeHidden: Bool = false) -> [FileItem] {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden { options.insert(.skipsHiddenFiles) }

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Self.resourceKeys, options: options
        ) else { return [] }

        return urls.compactMap(Self.item(at:))
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // Also used off the main thread by SubfolderSearch
    nonisolated static func item(at url: URL) -> FileItem? {
        guard let res = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
        return FileItem(
            name: url.lastPathComponent,
            url: url,
            size: Int64(res.fileSize ?? 0),
            modifiedDate: res.contentModificationDate ?? Date(),
            createdDate: res.creationDate ?? Date(),
            kind: res.localizedTypeDescription ?? "",
            isDirectory: res.isDirectory ?? false,
            isPackage: res.isPackage ?? false,
            isHidden: res.isHidden ?? false
        )
    }
}
