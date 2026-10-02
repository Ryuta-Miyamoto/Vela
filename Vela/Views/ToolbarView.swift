//
//  ToolbarView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import SwiftUI

struct ToolbarView: View {
    @Bindable var viewModel: FileExplorerViewModel

    @State private var isEditing = false
    @State private var editingPath = ""
    @State private var hoveredIndex: Int? = nil
    @FocusState private var searchFocused: Bool

    private var pathComponents: [String] { viewModel.currentURL.pathComponents }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: viewModel.goBack) { Image(systemName: "chevron.left") }
                .disabled(!viewModel.canGoBack)
            Button(action: viewModel.goForward) { Image(systemName: "chevron.right") }
                .disabled(!viewModel.canGoForward)
            Button(action: viewModel.goUp) { Image(systemName: "arrow.up") }
                .disabled(!viewModel.canGoUp)

            Divider().frame(height: 18)

            addressBar
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isEditing ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                )

            Divider().frame(height: 18)

            // Cmd+F hidden trigger
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()

            searchField

            Divider().frame(height: 18)

            Button { viewModel.toggleHiddenFiles() } label: {
                Image(systemName: viewModel.showHiddenFiles ? "eye" : "eye.slash")
            }
            .help(viewModel.showHiddenFiles ? "隠しファイルを非表示" : "隠しファイルを表示")
            .keyboardShortcut(".", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .onChange(of: viewModel.id) { _, _ in resetEditing() }
        // タブ切り替えだけでなく、ファイル一覧のダブルクリックや戻る/進むなど
        // 編集モード以外の経路でパスが変わった時も編集モードを抜ける
        .onChange(of: viewModel.currentURL) { _, _ in resetEditing() }
    }

    private func resetEditing() {
        isEditing = false
        editingPath = ""
    }

    @ViewBuilder
    private var addressBar: some View {
        if isEditing {
            TextField("パスを入力", text: $editingPath)
                .textFieldStyle(.plain)
                .onSubmit { commitEdit() }
                .onExitCommand { isEditing = false }
        } else {
            HStack(spacing: 0) {
                ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                    let isLast = index == pathComponents.count - 1
                    Button {
                        navigateTo(index: index)
                    } label: {
                        Text(component)
                            .fontWeight(isLast ? .semibold : .regular)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(hoveredIndex == index ? Color.secondary.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredIndex = $0 ? index : nil }

                    if !isLast {
                        Text("›").foregroundStyle(.tertiary).padding(.horizontal, 2)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { enterEditMode() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)

            TextField("検索", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.escape) {
                    viewModel.searchText = ""
                    searchFocused = false
                    return .handled
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(searchFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func enterEditMode() {
        editingPath = viewModel.currentURL.path
        isEditing = true
    }

    private func commitEdit() {
        let trimmed = editingPath.trimmingCharacters(in: .whitespaces)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir), isDir.boolValue {
            viewModel.navigate(to: URL(fileURLWithPath: trimmed))
        }
        isEditing = false
    }

    private func navigateTo(index: Int) {
        let path = index == 0 ? "/" : "/" + pathComponents[1...index].joined(separator: "/")
        viewModel.navigate(to: URL(fileURLWithPath: path))
    }
}
