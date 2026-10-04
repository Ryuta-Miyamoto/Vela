//
//  TabBarView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/21.
//

import SwiftUI
import AppKit

struct TabBarView: View {
    var pane: PaneState
    // In dual pane mode only the active pane's selected tab is underlined in the accent color
    var isActivePane = true
    var onClose: (Int) -> Void

    // ScrollView のスクロール位置的に、まだ左右へスクロールできる余地があるか
    @State private var canScrollLeft = false
    @State private var canScrollRight = false

    // 左右端の矢印ボタン用に常に確保しておく幅（表示/非表示に関わらず一定にすることで、
    // ScrollView の表示領域幅が変動してちらつくのを防ぐ）
    private let scrollButtonWidth: CGFloat = 28

    // ドラッグによるタブの並べ替え状態
    @State private var drag: TabDrag?
    @State private var tabWidths: [UUID: CGFloat] = [:]
    @State private var autoScroller = TabAutoScroller()

    private static let viewportSpace = "TabBarViewport"

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                scrollButton(systemName: "chevron.left", help: L10n.scrollTabsLeftHelp, isVisible: canScrollLeft) {
                    guard let firstID = pane.tabs.first?.id else { return }
                    withAnimation { proxy.scrollTo(firstID, anchor: .leading) }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                            // タブと右隣の区切り線をひとまとまりとして並べ替える
                            HStack(spacing: 0) {
                                TabItemView(
                                    title: tab.tabTitle,
                                    isSelected: pane.selectedIndex == index,
                                    isActivePane: isActivePane,
                                    onSelect: { pane.selectedIndex = index },
                                    onClose: { onClose(index) }
                                )
                                Divider().frame(height: 20)
                            }
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: TabWidthsKey.self, value: [tab.id: geometry.size.width])
                                }
                            }
                            .offset(x: dragOffset(for: tab.id, at: index))
                            .zIndex(drag?.tabID == tab.id ? 1 : 0)
                            .gesture(reorderGesture(for: tab.id))
                            .id(tab.id)
                        }

                        Button(action: { pane.addTab() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 33)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.newTabHelp)
                    }
                    .background(ScrollViewAccessor { autoScroller.scrollView = $0 })
                }
                .coordinateSpace(name: Self.viewportSpace)
                .trackScrollability(canScrollLeft: $canScrollLeft, canScrollRight: $canScrollRight)
                .onPreferenceChange(TabWidthsKey.self) { tabWidths = $0 }

                scrollButton(systemName: "chevron.right", help: L10n.scrollTabsRightHelp, isVisible: canScrollRight) {
                    guard let lastID = pane.tabs.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastID, anchor: .trailing) }
                }
            }
            .frame(height: 34)
            .background(.bar)
            // タブバー上でのマウスホイール（縦スクロール）を横スクロールとして扱う
            .background(VerticalToHorizontalScrollConverter())
            .overlay(alignment: .bottom) { Divider() }
            // ⌘T などで選択タブが変わったら、見切れていても見える位置までスクロールする
            // （ドラッグ開始時の選択では、ポインタ下のタブがずれないようスクロールしない）
            .onChange(of: pane.selectedIndex) { _, newIndex in
                guard drag == nil, pane.tabs.indices.contains(newIndex) else { return }
                withAnimation { proxy.scrollTo(pane.tabs[newIndex].id) }
            }
        }
    }

    // MARK: Drag to Reorder

    // ドラッグ中のタブはポインタに追従させ、他のタブは挿入先を空けるようにずらして表示する。
    // 配列の並べ替えはドロップ時に一度だけ行う
    //
    // ポインタ位置はスクロールしない表示領域の座標で受け取り、ドラッグ開始からのスクロール量を足して
    // タブ列上の移動量に換算する。表示領域の端に近づくと自動スクロールする
    private func reorderGesture(for tabID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(Self.viewportSpace))
            .onChanged { value in
                guard let sourceIndex = pane.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                if drag == nil {
                    drag = TabDrag(tabID: tabID, sourceIndex: sourceIndex, targetIndex: sourceIndex,
                                   pointerTranslation: 0, startScrollX: autoScroller.scrollX, translation: 0)
                    pane.selectedIndex = sourceIndex
                }
                drag?.pointerTranslation = value.translation.width
                updateDrag()
                autoScroller.update(pointerX: value.location.x) { updateDrag() }
            }
            .onEnded { _ in
                autoScroller.stop()
                guard let drag else { return }
                // 配列の並べ替えとオフセットの解除を同じアニメーションで行うと、他のタブは見た目の位置を保ったまま、
                // ドラッグ中のタブだけが挿入先へ収まる
                withAnimation(.easeInOut(duration: 0.15)) {
                    pane.moveTab(from: drag.sourceIndex, to: drag.targetIndex)
                    self.drag = nil
                }
            }
    }

    // ポインタの移動量とスクロール量から、ドラッグ中のタブの位置と挿入先を更新する
    private func updateDrag() {
        guard let current = drag else { return }
        let width = tabWidths[current.tabID] ?? 0
        let startMinX = layoutMinX(at: current.sourceIndex)
        let scrolled = autoScroller.scrollX - current.startScrollX
        // タブ列の外へははみ出さないようにする
        let maxMinX = max(0, pane.tabs.reduce(0) { $0 + (tabWidths[$1.id] ?? 0) } - width)
        let translation = min(max(startMinX + current.pointerTranslation + scrolled, 0), maxMinX) - startMinX
        let targetIndex = targetIndex(forCenterX: startMinX + translation + width / 2, draggedIndex: current.sourceIndex)

        drag?.translation = translation
        if current.targetIndex != targetIndex {
            withAnimation(.easeInOut(duration: 0.15)) { drag?.targetIndex = targetIndex }
        }
    }

    private func dragOffset(for tabID: UUID, at index: Int) -> CGFloat {
        guard let drag else { return 0 }
        if drag.tabID == tabID { return drag.translation }
        let draggedWidth = tabWidths[drag.tabID] ?? 0
        if drag.sourceIndex < index && index <= drag.targetIndex { return -draggedWidth }
        if drag.targetIndex <= index && index < drag.sourceIndex { return draggedWidth }
        return 0
    }

    // 並べ替え前のレイアウトでの、index 番目のタブの左端
    private func layoutMinX(at index: Int) -> CGFloat {
        pane.tabs.prefix(index).reduce(0) { $0 + (tabWidths[$1.id] ?? 0) }
    }

    // ドラッグ中のタブの中心より左に中心がある他のタブの数が、移動後のインデックスになる
    private func targetIndex(forCenterX centerX: CGFloat, draggedIndex: Int) -> Int {
        var count = 0
        for index in pane.tabs.indices where index != draggedIndex {
            let width = tabWidths[pane.tabs[index].id] ?? 0
            if layoutMinX(at: index) + width / 2 < centerX { count += 1 }
        }
        return count
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

private struct TabDrag {
    let tabID: UUID
    let sourceIndex: Int
    var targetIndex: Int
    // 表示領域上でのポインタの移動量
    var pointerTranslation: CGFloat
    // ドラッグ開始時のスクロール位置
    let startScrollX: CGFloat
    // タブ列上での移動量（ドラッグ中のタブのオフセット）
    var translation: CGFloat
}

// MARK: - Auto Scroll While Dragging

// ドラッグ中のポインタが表示領域の端に近づいたら、端からの近さに応じた速さでタブ列をスクロールし続ける
private final class TabAutoScroller {
    weak var scrollView: NSScrollView?

    private var timer: Timer?
    private var velocity: CGFloat = 0
    private var onScroll: (() -> Void)?

    // 端からこの幅の範囲に入るとスクロールを始める
    private let edgeZone: CGFloat = 32
    // 1フレームあたりの最大移動量
    private let maxStep: CGFloat = 12

    var scrollX: CGFloat { scrollView?.contentView.bounds.origin.x ?? 0 }

    // pointerX は表示領域の左端を 0 とした座標
    func update(pointerX: CGFloat, onScroll: @escaping () -> Void) {
        guard let scrollView else { return }
        let width = scrollView.contentView.bounds.width
        if pointerX < edgeZone {
            velocity = -maxStep * min(1, (edgeZone - pointerX) / edgeZone)
        } else if pointerX > width - edgeZone {
            velocity = maxStep * min(1, (pointerX - (width - edgeZone)) / edgeZone)
        } else {
            stop()
            return
        }
        self.onScroll = onScroll
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onScroll = nil
    }

    private func step() {
        guard let scrollView, let documentView = scrollView.documentView else { return stop() }
        let clipView = scrollView.contentView
        let maxX = max(0, documentView.frame.width - clipView.bounds.width)
        let newX = min(max(clipView.bounds.origin.x + velocity, 0), maxX)
        guard newX != clipView.bounds.origin.x else { return }
        clipView.scroll(to: NSPoint(x: newX, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
        onScroll?()
    }
}

// 配置したビューを含む NSScrollView（SwiftUI の ScrollView の実体）を取得する
private struct ScrollViewAccessor: NSViewRepresentable {
    let onResolve: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: AccessorView, context: Context) {}

    final class AccessorView: NSView {
        var onResolve: ((NSScrollView?) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onResolve?(enclosingScrollView)
        }
    }
}

private struct TabWidthsKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
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
    let isActivePane: Bool
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
                Rectangle().fill(isActivePane ? Color.accentColor : Color.secondary.opacity(0.4)).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }
}
