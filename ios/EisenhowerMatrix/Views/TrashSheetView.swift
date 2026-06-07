import SwiftUI

/// iOS 回收站 Sheet — 使用 iOS 原生 Sheet 而非 Overlay
struct TrashSheetView: View {
    let deletedTasks: [TaskItem]
    let onRestore: (String) -> Void
    let onPermanentDelete: (String) -> Void
    let onClearTrash: () -> Void

    @State private var expandedContentIds: Set<String> = []
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                // 背景
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.13, blue: 0.24),
                        Color(red: 0.06, green: 0.10, blue: 0.18)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    if deletedTasks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.3))
                            Text("回收站为空")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(deletedTasks) { task in
                                    trashItemRow(task)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .navigationTitle("🗑️ 回收站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.09, green: 0.13, blue: 0.24), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !deletedTasks.isEmpty {
                        Button("清空") {
                            onClearTrash()
                        }
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    private func trashItemRow(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(task.title)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .strikethrough()
                    .lineLimit(1)

                Spacer()

                if let deletedAt = task.deletedAt {
                    Text(formatTime(deletedAt))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }

                if !task.content.isEmpty {
                    Button(action: {
                        if expandedContentIds.contains(task.id) {
                            expandedContentIds.remove(task.id)
                        } else {
                            expandedContentIds.insert(task.id)
                        }
                    }) {
                        Image(systemName: expandedContentIds.contains(task.id) ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button("恢复") {
                    onRestore(task.id)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .foregroundColor(.white.opacity(0.7))
                .cornerRadius(6)
                .buttonStyle(.plain)

                Button(action: { onPermanentDelete(task.id) }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 16, height: 16)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if expandedContentIds.contains(task.id) && !task.content.isEmpty {
                Text(task.content)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.leading, 4)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func formatTime(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}