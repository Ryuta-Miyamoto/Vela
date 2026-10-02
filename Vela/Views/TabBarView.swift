//
//  TabBarView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/21.
//

import SwiftUI
import AppKit

struct TabBarView: View {
    var appState: AppState

    // ScrollView のスクロール位置的に、まだ左右へスクロールできる余地があるか
    @State private var canScrollLeft = false
    @State private var canScrollRight = false

    // 左右端の矢印ボタン用に常に確保しておく幅（表示/非表示に関わらず一定にすることで、
    // ScrollView の表示領域幅が変動してちらつくのを防ぐ）
    private let scrollButtonWidth: CGFloat = 28

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                scrollButton(systemName: "chevron.left", help: L10n.scrollTabsLeftHelp, isVisible: canScrollLeft) {
                    guard let firstID = appState.tabs.first?.id else { return }
                    withAnimation { proxy.scrollTo(firstID, anchor: .leading) }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(appState.tabs.enumerated()), id: \.element.id) { index, tab in
                            TabItemView(
                                title: tab.tabTitle,
                                isSelected: appState.selectedIndex == index,
                                onSelect: { appState.selectedIndex = index },
                                onClose: { appState.closeTab(at: index) }
                            )
                            .id(tab.id)
                            Divider().frame(height: 20)
                        }

                        Button(action: { appState.addTab() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 33)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.newTabHelp)
                    }
                }
                .trackScrollability(canScrollLeft: $canScrollLeft, canScrollRight: $canScrollRight)

                scrollButton(systemName: "chevron.right", help: L10n.scrollTabsRightHelp, isVisible: canScrollRight) {
                    guard let lastID = appState.tabs.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastID, anchor: .trailing) }
                }
            }
            .frame(height: 34)
            .background(.bar)
            // タブバー上でのマウスホイール（縦スクロール）を横スクロールとして扱う
            .background(VerticalToHorizontalScrollConverter())
            .overlay(alignment: .bottom) { Divider() }
            // ⌘T などで選択タブが変わったら、見切れていても見える位置までスクロールする
            .onChange(of: appState.selectedIndex) { _, newIndex in
                guard appState.tabs.indices.contains(newIndex) else { return }
                withAnimation { proxy.scrollTo(appState.tabs[newIndex].id) }
            }
        }
    }

    private func scrollButton(systemName: String, help: String, isVisible: Bool, action: @escaping () -> Void) -> some View {
        Group {
            if isVisible {
                Button(action: action) {
                    Image(systemName: systemName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: scrollButtonWidth, height: 33)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help)
            }
        }
        .frame(width: scrollButtonWidth, height: 33)
    }
}

private extension View {
    // onScrollGeometryChange は macOS 15 以降のみ。macOS 14 ではスクロール位置を取得できないため、
    // 左右のスクロールボタンを常に表示する
    @ViewBuilder
    func trackScrollability(canScrollLeft: Binding<Bool>, canScrollRight: Binding<Bool>) -> some View {
        if #available(macOS 15.0, *) {
            onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                ScrollEdges(
                    canScrollLeft: geometry.contentOffset.x > 0.5,
                    canScrollRight: geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 0.5
                )
            } action: { _, newValue in
                canScrollLeft.wrappedValue = newValue.canScrollLeft
                canScrollRight.wrappedValue = newValue.canScrollRight
            }
        } else {
            onAppear {
                canScrollLeft.wrappedValue = true
                canScrollRight.wrappedValue = true
            }
        }
    }
}

private struct ScrollEdges: Equatable {
    var canScrollLeft: Bool
    var canScrollRight: Bool
}

// MARK: - Vertical → Horizontal Scroll

// 配置したビューの範囲内で発生した縦方向のスクロール（マウスホイール・トラックパッドの上下スワイプ）を
// 横スクロールとして扱う。横スクロール専用の ScrollView は縦方向の入力を無視するため、
// ローカルイベントモニタで縦スクロールを横取りし、範囲内の NSScrollView のスクロール位置を直接動かす
private struct VerticalToHorizontalScrollConverter: NSViewRepresentable {
    func makeNSView(context: Context) -> ConverterView { ConverterView() }
    func updateNSView(_ nsView: ConverterView, context: Context) {}

    final class ConverterView: NSView {
        private var monitor: Any?
        private weak var targetScrollView: NSScrollView?

        // ホイール1ノッチ（行単位のイベント）あたりの移動量
        private let lineScrollAmount: CGFloat = 20

        // マウスイベントはすべて下のビューへ素通しする
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                return self.scrollHorizontally(with: event) ? nil : event
            }
        }

        deinit { removeMonitor() }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        // 縦方向のスクロールを横方向として適用する。処理した場合は true（イベントを消費する）
        private func scrollHorizontally(with event: NSEvent) -> Bool {
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  let scrollView = findTargetScrollView(),
                  let documentView = scrollView.documentView else { return false }

            let clipView = scrollView.contentView
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * lineScrollAmount
            let maxX = max(0, documentView.frame.width - clipView.bounds.width)
            // scrollingDeltaY は「ナチュラルなスクロール」設定を反映済み。正の値（上方向）を左へのスクロールに対応させる
            let newX = min(max(clipView.bounds.origin.x - delta, 0), maxX)
            clipView.scroll(to: NSPoint(x: newX, y: clipView.bounds.origin.y))
            scrollView.reflectScrolledClipView(clipView)
            return true
        }

        // タブバーの範囲内にある NSScrollView（SwiftUI の ScrollView の実体）を探す
        private func findTargetScrollView() -> NSScrollView? {
            if let targetScrollView, targetScrollView.window === window { return targetScrollView }
            guard let contentView = window?.contentView else { return nil }
            let frameInWindow = convert(bounds, to: nil)

            func search(_ view: NSView) -> NSScrollView? {
                if let scrollView = view as? NSScrollView,
                   frameInWindow.contains(scrollView.convert(scrollView.bounds, to: nil)) {
                    return scrollView
                }
                for subview in view.subviews {
                    if let found = search(subview) { return found }
                }
                return nil
            }
            targetScrollView = search(contentView)
            return targetScrollView
        }

    }
}

private struct TabItemView: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: 130, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .background(Color.secondary.opacity(isHovered ? 0.25 : 0))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.closeTabHelp)
        }
        .padding(.horizontal, 10)
        .frame(height: 33)
        .frame(minWidth: 80, maxWidth: 160)
        .background(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }
}
