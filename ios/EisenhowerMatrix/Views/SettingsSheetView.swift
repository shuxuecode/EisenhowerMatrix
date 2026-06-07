import SwiftUI

/// iOS GitHub 设置 Sheet — 使用 iOS 原生 Sheet 而非 Overlay
struct SettingsSheetView: View {
    @EnvironmentObject var viewModel: TaskViewModel
    @Environment(\.dismiss) var dismiss

    @State private var token: String = ""
    @State private var owner: String = ""
    @State private var repoName: String = ""
    @State private var branch: String = ""
    @State private var isConnecting: Bool = false
    @State private var isTokenMasked: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false

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

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 连接状态指示
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.isGitHubConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(viewModel.isGitHubConnected
                                    ? Color(red: 0.42, green: 0.80, blue: 0.47)
                                    : Color(red: 0.91, green: 0.27, blue: 0.38))
                            Text(viewModel.isGitHubConnected ? "已连接" : "未连接")
                                .font(.subheadline)
                                .foregroundColor(viewModel.isGitHubConnected
                                    ? Color(red: 0.42, green: 0.80, blue: 0.47)
                                    : .white.opacity(0.5))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(viewModel.isGitHubConnected ? Color(red: 0.42, green: 0.80, blue: 0.47).opacity(0.15) : Color.white.opacity(0.08))
                        .cornerRadius(8)

                        // 认证信息
                        VStack(alignment: .leading, spacing: 6) {
                            Text("认证信息")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.7))

                            HStack(spacing: 8) {
                                if isTokenMasked {
                                    Text("••••••••")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(10)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(8)

                                    Button("更换") {
                                        token = ""
                                        isTokenMasked = false
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.15))
                                    .foregroundColor(.white.opacity(0.7))
                                    .cornerRadius(8)
                                    .buttonStyle(.plain)
                                } else {
                                    SecureField("github_pat_xxxxxxxxxxxx", text: $token)
                                        .textFieldStyle(.plain)
                                        .padding(10)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                }
                            }

                            Text("建议使用 Fine-grained token，仅需授权单个仓库的 Contents 读写权限。")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        }

                        // 仓库信息
                        VStack(alignment: .leading, spacing: 6) {
                            Text("仓库信息")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.7))

                            TextField("用户名，如 myusername", text: $owner)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                )

                            TextField("仓库名，如 my-repo", text: $repoName)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                )

                            TextField("分支，默认 main", text: $branch)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }

                        // 操作按钮
                        VStack(spacing: 8) {
                            Button(action: { Task { await connect() } }) {
                                HStack(spacing: 6) {
                                    if isConnecting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .frame(width: 14, height: 14)
                                    }
                                    Text(isConnecting ? "连接中..." : "连接 GitHub")
                                        .font(.subheadline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.30, green: 0.59, blue: 1).opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .disabled(isConnecting || (token.isEmpty && !isTokenMasked))

                            if viewModel.isGitHubConnected {
                                Button("断开连接") {
                                    viewModel.requestDisconnectGitHub()
                                    resetForm()
                                }
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.91, green: 0.27, blue: 0.38).opacity(0.3))
                                .foregroundColor(Color(red: 0.91, green: 0.27, blue: 0.38))
                                .cornerRadius(10)
                                .buttonStyle(.plain)
                            }
                        }

                        // 状态消息
                        if !statusMessage.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                        .foregroundColor(statusIsError ? Color(red: 0.91, green: 0.27, blue: 0.38) : Color(red: 0.42, green: 0.80, blue: 0.47))
                                        .font(.caption)
                                    Text(statusMessage)
                                        .font(.caption)
                                        .foregroundColor(statusIsError ? Color(red: 0.91, green: 0.27, blue: 0.38) : Color(red: 0.42, green: 0.80, blue: 0.47))
                                }

                                if statusIsError {
                                    Text("排查建议：\n• 检查 Token 是否有效且未过期\n• 确认用户名和仓库名正确\n• Token 需要有 Contents 读写权限")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(statusIsError ? Color(red: 0.91, green: 0.27, blue: 0.38).opacity(0.15) : Color(red: 0.42, green: 0.80, blue: 0.47).opacity(0.15))
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("🔗 GitHub 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.09, green: 0.13, blue: 0.24), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            let config = ConfigStorage.shared.load()
            if config.isValid && !config.token.isEmpty {
                token = "••••••••"
                isTokenMasked = true
            }
            let parts = config.repo.split(separator: "/")
            if parts.count == 2 {
                owner = String(parts[0])
                repoName = String(parts[1])
            } else {
                owner = config.repo
                repoName = ""
            }
            branch = config.branch == "main" ? "" : config.branch
        }
    }

    private func connect() async {
        let savedConfig = ConfigStorage.shared.load()
        let actualToken: String
        if isTokenMasked {
            actualToken = savedConfig.token
        } else {
            actualToken = token
        }

        guard !actualToken.isEmpty else {
            statusMessage = "请输入 Token"
            statusIsError = true
            isTokenMasked = false
            token = ""
            return
        }
        guard !owner.trimmingCharacters(in: .whitespaces).isEmpty else {
            statusMessage = "请输入用户名"
            statusIsError = true
            return
        }
        guard !repoName.trimmingCharacters(in: .whitespaces).isEmpty else {
            statusMessage = "请输入仓库名"
            statusIsError = true
            return
        }

        let fullRepo = "\(owner.trimmingCharacters(in: .whitespaces))/\(repoName.trimmingCharacters(in: .whitespaces))"
        let actualBranch = branch.trimmingCharacters(in: .whitespaces).isEmpty ? "main" : branch.trimmingCharacters(in: .whitespaces)

        isConnecting = true
        statusMessage = ""
        statusIsError = false

        await viewModel.connectGitHub(token: actualToken, repo: fullRepo, branch: actualBranch)

        isConnecting = false

        if viewModel.isGitHubConnected {
            token = "••••••••"
            isTokenMasked = true
            statusMessage = "连接成功 ✓"
            statusIsError = false
        } else if !viewModel.settingsMessage.isEmpty {
            statusMessage = viewModel.settingsMessage
            statusIsError = viewModel.settingsIsError
        } else {
            statusMessage = "连接失败，请检查网络后重试"
            statusIsError = true
        }
    }

    private func resetForm() {
        token = ""
        owner = ""
        repoName = ""
        branch = ""
        isTokenMasked = false
        statusMessage = ""
    }
}