import SwiftUI

/// iOS 主内容视图 — 垂直滚动卡片布局
struct ContentView: View {
    @EnvironmentObject var viewModel: TaskViewModel

    var body: some View {
        ZStack(alignment: .top) {
            // 背景
            backgroundGradient

            // 主内容
            VStack(spacing: 0) {
                // 加载条
                if viewModel.isLoading && viewModel.loadingProgress > 0 {
                    loadingBar
                }

                // 象限卡片 — 垂直滚动
                quadrantScrollView

                // 底部统计栏
                StatsBarView(
                    total: viewModel.totalCount,
                    undone: viewModel.undoneCount,
                    done: viewModel.doneCount,
                    trashCount: viewModel.deletedTasks.count,
                    isGitHubConnected: viewModel.isGitHubConnected,
                    onClearDone: { viewModel.requestClearDone() },
                    onOpenTrash: { viewModel.showTrash = true },
                    onOpenSettings: { viewModel.showSettings = true }
                )
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .sheet(isPresented: $viewModel.showTrash) {
            TrashSheetView(
                deletedTasks: viewModel.deletedTasks,
                onRestore: { viewModel.restoreTask($0) },
                onPermanentDelete: { viewModel.requestPermanentDelete($0) },
                onClearTrash: { viewModel.requestClearTrash() }
            )
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsSheetView()
                .environmentObject(viewModel)
        }
        .alert(isPresented: Binding(
            get: { viewModel.confirmAction != nil },
            set: { if !$0 { viewModel.cancelConfirmedAction() } }
        )) {
            Alert(
                title: Text(viewModel.confirmAction?.title ?? ""),
                message: Text(viewModel.confirmAction?.message ?? ""),
                primaryButton: .destructive(Text("确认")) {
                    viewModel.executeConfirmedAction()
                },
                secondaryButton: .cancel {
                    viewModel.cancelConfirmedAction()
                }
            )
        }
        .overlay(alignment: .top) {
            // Toast
            if let message = viewModel.toastMessage {
                toastView(message: message)
            }
        }
        .task {
            await viewModel.initialize()
        }
    }

    // MARK: - 背景

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.10, blue: 0.18),
                Color(red: 0.09, green: 0.13, blue: 0.24),
                Color(red: 0.06, green: 0.20, blue: 0.38)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - 象限滚动视图

    private var quadrantScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(QuadrantConfig.all) { config in
                    QuadrantCardView(
                        config: config,
                        tasks: viewModel.tasksForQuadrant(config.id),
                        newTaskIds: viewModel.newTaskIds,
                        onToggle: { viewModel.toggleTask($0) },
                        onDelete: { viewModel.deleteTask($0) },
                        onAdd: { title, content in
                            viewModel.addTask(title: title, content: content, quadrant: config.id)
                        },
                        onEdit: { id, title, content, quadrant in
                            viewModel.saveEdit(id: id, title: title, content: content, quadrant: quadrant)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - 加载条

    private var loadingBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.59, blue: 1),
                            Color(red: 0.42, green: 0.80, blue: 0.47),
                            Color(red: 1, green: 0.85, blue: 0.24)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: geo.size.width * (viewModel.loadingProgress / 100), height: 3)
                .animation(.easeOut(duration: 0.3), value: viewModel.loadingProgress)
        }
        .frame(height: 3)
    }

    // MARK: - Toast

    private func toastView(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(viewModel.toastType == .success
                        ? Color(red: 0.42, green: 0.80, blue: 0.47).opacity(0.85)
                        : Color(red: 0.91, green: 0.27, blue: 0.38).opacity(0.85))
            )
            .padding(.top, 50)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}