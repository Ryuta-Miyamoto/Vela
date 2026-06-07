//
//  StatusBarView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/22.
//

import SwiftUI

struct StatusBarView: View {
    var viewModel: FileExplorerViewModel

    private var totalSize: Int64 {
        viewModel.selectedItems.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        HStack(spacing: 0) {
            if viewModel.selectedItems.isEmpty {
                Text("\(viewModel.items.count)項目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(viewModel.items.count)項目 | \(viewModel.selectedItems.count)個選択 (\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
