//
//  VolumesStore.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/10/04.
//

import AppKit

struct VolumeItem: Identifiable, Equatable {
    enum Kind { case startup, `internal`, external, network }

    var id: URL { url }
    let url: URL
    let name: String
    let kind: Kind
    let isEjectable: Bool

    var systemImage: String {
        switch self.kind {
        case .startup, .internal: return "internaldrive.fill"
        case .external:           return "externaldrive.fill"
        case .network:            return "network"
        }
    }
}

// Mounted volumes shown in the sidebar's Locations section. Shared by all windows and kept up to date
// from NSWorkspace's mount / unmount / rename notifications
@Observable
final class VolumesStore {
    static let shared = VolumesStore()

    private(set) var volumes: [VolumeItem] = []

    private static let keys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeIsRootFileSystemKey, .volumeIsInternalKey, .volumeIsLocalKey,
        .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsBrowsableKey,
    ]

    private init() {
        reload()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
    }

    func reload() {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        let items = urls.compactMap { url -> VolumeItem? in
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)),
                  values.volumeIsBrowsable != false else { return nil }
            let isStartup = values.volumeIsRootFileSystem == true
            let kind: VolumeItem.Kind
            if isStartup {
                kind = .startup
            } else if values.volumeIsLocal == false {
                kind = .network
            } else if values.volumeIsInternal == true && values.volumeIsRemovable != true {
                kind = .internal
            } else {
                kind = .external
            }
            return VolumeItem(url: url,
                              name: values.volumeLocalizedName ?? url.lastPathComponent,
                              kind: kind,
                              isEjectable: !isStartup && kind != .internal)
        }
        // The startup disk first, then the rest by name (Finder's order)
        let sorted = items.sorted {
            if ($0.kind == .startup) != ($1.kind == .startup) { return $0.kind == .startup }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        if sorted != volumes { volumes = sorted }
    }

    // Unmounting can take a few seconds (e.g. flushing writes), so it runs asynchronously
    func eject(_ volume: VolumeItem) {
        FileManager.default.unmountVolume(at: volume.url, options: [.allPartitionsAndEjectDisk]) { error in
            guard let error else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L10n.ejectFailed(name: volume.name)
                alert.informativeText = error.localizedDescription
                if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            }
        }
    }
}
