import SwiftUI

/// 回收站面板 — 固定尺寸弹窗，内容多时内部滚动
struct TrashPanelView: View {
    let deletedTasks: [TaskItem]
    let onRestore: (String) -> Void
    let onPermanentDelete: (String) -> Void
    let onClearTrash: () -> Void
    let onClose: () -> Void

    @State private var expandedContentIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack {
                Text("🗑️ 回收站")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Button("清空回收站") {
                    onClearTrash()
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .foregroundColor(.white.opacity(0.7))
                .cornerRadius(6)
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            if deletedTasks.isEmpty {
                Text("回收站为空")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(deletedTasks) { task in
                            trashItemRow(task)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420, height: 360)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.09, green: 0.13, blue: 0.24).opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(radius: 20)
    }

    private func trashItemRow(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(task.title)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.6))
                    .strikethrough()
                    .lineLimit(1)

                Spacer()

                if let deletedAt = task.deletedAt {
                    Text(formatTime(deletedAt))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
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
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 18, height: 18)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button("恢复") {
                    onRestore(task.id)
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .foregroundColor(.white.opacity(0.7))
                .cornerRadius(6)
                .buttonStyle(.plain)

                Button(action: { onPermanentDelete(task.id) }) {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if expandedContentIds.contains(task.id) && !task.content.isEmpty {
                Text(task.content)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.leading, 4)
            }
        }
        .padding(10)
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
        // timestamp 内存中已是秒级（与解码器和 markDeleted() 一致），直接使用
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}