import SwiftUI

/// 统计栏 + 回收站 — 固定在窗口底部的操作栏
struct StatsBarView: View {
    let total: Int
    let undone: Int
    let done: Int
    let trashCount: Int
    let isGitHubConnected: Bool
    let onClearDone: () -> Void
    let onOpenTrash: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 设置按钮 — 固定在左侧
            Button(action: onOpenSettings) {
                HStack(spacing: 6) {
                    Image(systemName: isGitHubConnected ? "link.circle.fill" : "link.circle")
                        .font(.subheadline)
                    Text("设置")
                        .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isGitHubConnected ? Color(red: 0.42, green: 0.80, blue: 0.47).opacity(0.3) : Color.white.opacity(0.1))
                .foregroundColor(isGitHubConnected ? Color(red: 0.42, green: 0.80, blue: 0.47) : .white.opacity(0.7))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isGitHubConnected ? Color(red: 0.42, green: 0.80, blue: 0.47).opacity(0.5) : Color.white.opacity(0.2),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer()

            StatCard(count: total, label: "总任务")
            StatCard(count: undone, label: "待完成")
            StatCard(count: done, label: "已完成")

            if done > 0 {
                Button(action: onClearDone) {
                    Text("清除已完成")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // 回收站按钮 — 固定在右侧
            Button(action: onOpenTrash) {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.subheadline)
                    Text("回收站")
                        .font(.subheadline)
                    if trashCount > 0 {
                        Text("(\(trashCount))")
                            .font(.caption)
                            .foregroundColor(Color(red: 1, green: 0.85, blue: 0.24))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(trashCount > 0 ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                .foregroundColor(trashCount > 0 ? .white : .white.opacity(0.5))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(trashCount == 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(
            Rectangle()
                .fill(Color(red: 0.08, green: 0.10, blue: 0.20).opacity(0.95))
                .overlay(
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct StatCard: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(Color(red: 1, green: 0.85, blue: 0.24))
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}