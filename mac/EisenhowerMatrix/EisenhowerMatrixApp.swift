import SwiftUI

/// 艾森豪威尔矩阵 macOS 应用入口
@main
struct EisenhowerMatrixApp: App {
    @StateObject private var viewModel = TaskViewModel()

    var body: some Scene {
        WindowGroup("四象限工作法 - 艾森豪威尔矩阵") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 900, minHeight: 680)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // 自定义菜单
            CommandGroup(replacing: .newItem) {
                Button("添加任务到 Q2") {
                    viewModel.addTask(title: "新任务", content: "", quadrant: "q2")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("添加任务到 Q1") {
                    viewModel.addTask(title: "新任务", content: "", quadrant: "q1")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button("清除已完成") {
                    viewModel.requestClearDone()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            CommandMenu("同步") {
                Button("强制同步") {
                    Task {
                        await viewModel.forceSyncNow()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                if viewModel.isGitHubConnected {
                    Divider()
                    Button("断开 GitHub") {
                        viewModel.requestDisconnectGitHub()
                    }
                }

                Divider()

                Button("设置...") {
                    viewModel.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}