import SwiftUI

/// GitHub 设置面板 — 从主界面右下角设置按钮触发的 overlay 弹窗
struct GitHubSettingsPanelView: View {
    @EnvironmentObject var viewModel: TaskViewModel

    @State private var token: String = ""
    @State private var owner: String = ""
    @State private var repoName: String = ""
    @State private var branch: String = ""
    @State private var isConnecting: Bool = false
    @State private var isTokenMasked: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false

    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack {
                Text("🔗 GitHub 同步设置")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

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
                .padding(.vertical, 6)
                .background(viewModel.isGitHubConnected ? Color(red: 0.42, green: 0.80, blue: 0.47).opacity(0.15) : Color.white.opacity(0.08))
                .cornerRadius(8)
            }
            .padding(.bottom, 16)

            Divider()
                .background(Color.white.opacity(0.15))
                .padding(.bottom, 16)

            // 认证信息
            VStack(alignment: .leading, spacing: 8) {
                Text("认证信息")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.7))

                HStack(spacing: 8) {
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
                        .onTapGesture {
                            if isTokenMasked {
                                token = ""
                                isTokenMasked = false
                            }
                        }

                    if isTokenMasked {
                        Button("更换 Token") {
                            token = ""
                            isTokenMasked = false
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.white.opacity(0.7))
                        .cornerRadius(8)
                        .buttonStyle(.plain)
                    }
                }

                Text("建议使用 Fine-grained token，仅需授权单个仓库的 Contents 读写权限。")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.bottom, 16)

            // 仓库信息
            VStack(alignment: .leading, spacing: 8) {
                Text("仓库信息")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.7))

                HStack(spacing: 8) {
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
                        .frame(width: 100)
                }
            }
            .padding(.bottom, 16)

            // 操作按钮
            HStack(spacing: 12) {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.30, green: 0.59, blue: 1).opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(red: 0.30, green: 0.59, blue: 1).opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isConnecting || (token.isEmpty && !isTokenMasked))

                if viewModel.isGitHubConnected {
                    Button("断开连接") {
                        viewModel.requestDisconnectGitHub()
                        resetForm()
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.91, green: 0.27, blue: 0.38).opacity(0.3))
                    .foregroundColor(Color(red: 0.91, green: 0.27, blue: 0.38))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(red: 0.91, green: 0.27, blue: 0.38).opacity(0.4), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("关闭") {
                    onClose()
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .foregroundColor(.white.opacity(0.7))
                .cornerRadius(8)
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            // 状态消息
            if !statusMessage.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(statusIsError ? Color(red: 0.91, green: 0.27, blue: 0.38) : Color(red: 0.42, green: 0.80, blue: 0.47))
                            .font(.subheadline)
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(statusIsError ? Color(red: 0.91, green: 0.27, blue: 0.38) : Color(red: 0.42, green: 0.80, blue: 0.47))
                    }

                    if statusIsError {
                        Text("排查建议：\n• 检查 Token 是否有效且未过期\n• 确认用户名和仓库名正确\n• Token 需要有 Contents 读写权限\n• 仓库和分支必须存在且可访问")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(statusIsError ? Color(red: 0.91, green: 0.27, blue: 0.38).opacity(0.15) : Color(red: 0.42, green: 0.80, blue: 0.47).opacity(0.15))
                )
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.09, green: 0.13, blue: 0.24).opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(radius: 20)
        .onAppear {
            let config = ConfigStorage.shared.load()
            if config.isValid && !config.token.isEmpty {
                token = "••••••••"
                isTokenMasked = true
            }
            // 拆分 "owner/repo" → owner + repoName
            let parts = config.repo.split(separator: "/")
            if parts.count == 2 {
                owner = String(parts[0])
                repoName = String(parts[1])
            } else {
                owner = config.repo  // 兜底：整个字符串放 owner
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
            statusMessage = "连接成功，数据加载完成 ✓"
            statusIsError = false
        } else if !viewModel.settingsMessage.isEmpty {
            statusMessage = viewModel.settingsMessage
            statusIsError = viewModel.settingsIsError
        } else {
            statusMessage = "连接失败，请检查网络连接后重试"
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