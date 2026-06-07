//
//  QuickLookBridge.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import SwiftUI
import Quartz

struct QuickLookBridge: NSViewRepresentable {
    var url: URL?

    func makeNSView(context: Context) -> QLBridgeView {
        context.coordinator.bridgeView
    }

    func updateNSView(_ nsView: QLBridgeView, context: Context) {
        guard let url else { return }
        nsView.showPreview(for: url)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let bridgeView = QLBridgeView()
    }
}

final class QLBridgeView: NSView, QLPreviewPanelDataSource {
    private var previewURL: URL?

    override var acceptsFirstResponder: Bool { true }

    // NSResponder の非公式プロトコル（Quartz が追加）
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        previewURL != nil
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let url = previewURL else { return nil }
        return url as NSURL
    }

    // MARK: -

    func showPreview(for url: URL) {
        previewURL = url
        window?.makeFirstResponder(self)
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        } else {
            QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
        }
    }
}
