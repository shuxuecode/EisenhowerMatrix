import SwiftUI

/// iOS 底部统计栏 — 紧凑布局适配手机屏幕
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
        HStack(spacing: 8) {
            // 设置按钮
            Button(action: onOpenSettings) {
                Image(systemName: isGitHubConnected ? "link.circle.fill" : "link.circle")
                    .font(.subheadline)
                    .foregroundColor(isGitHubConnected ? Color(red: 0.42, green: 0.80, blue: 0.47) : .white.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(isGitHubConnected ? Color(red: 0.42, green: 0.80, blue: 0.47).opacity(0.3) : Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")

            // 统计卡片
            MiniStatCard(count: total, label: "总")
            MiniStatCard(count: undone, label: "待")
            MiniStatCard(count: done, label: "完")

            Spacer()

            // 清除已完成按钮
            if done > 0 {
                Button(action: onClearDone) {
                    Text("清除")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            // 回收站按钮
            Button(action: onOpenTrash) {
                HStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.subheadline)
                    if trashCount > 0 {
                        Text("\(trashCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 1, green: 0.85, blue: 0.24))
                    }
                }
                .foregroundColor(trashCount > 0 ? .white : .white.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(trashCount > 0 ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(trashCount == 0)
            .accessibilityLabel("回收站")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
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

struct MiniStatCard: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Color(red: 1, green: 0.85, blue: 0.24))
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
        )
    }
}