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
                Text(L10n.itemCount(viewModel.items.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(L10n.itemCount(viewModel.items.count)) | \(L10n.selectedCount(viewModel.selectedItems.count)) (\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let status = FileOperationQueue.shared.status {
                TransferProgressView(status: status)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// Progress of the copy or move running in the background, with a button to stop it
private struct TransferProgressView: View {
    let status: FileOperationQueue.Status

    private var detail: String {
        if status.isCancelling { return L10n.cancellingTransfer }
        guard let total = status.totalBytes else { return L10n.preparingTransfer }
        return L10n.transferBytes(completed: ByteCountFormatter.string(fromByteCount: status.completedBytes, countStyle: .file),
                                  total: ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n.transferTitle(kind: status.kind, name: status.currentName, count: status.itemCount))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if status.queuedCount > 0 {
                Text(L10n.queuedTransfers(status.queuedCount))
                    .foregroundStyle(.secondary)
            }
            if let fraction = status.fraction {
                ProgressView(value: fraction)
                    .frame(width: 100)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
            Button {
                FileOperationQueue.shared.cancelCurrent()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(status.isCancelling)
            .help(L10n.cancelTransferHelp)
        }
        .font(.caption)
        .frame(maxWidth: 420, alignment: .trailing)
    }
}
