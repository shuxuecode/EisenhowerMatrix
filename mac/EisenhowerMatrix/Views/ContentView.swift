import SwiftUI

/// 主内容视图 — 底部栏固定，象限动态填满上方空间
struct ContentView: View {
    @EnvironmentObject var viewModel: TaskViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 象限网格 — 动态填满上方空间
            matrixGrid

            // 底部固定栏 — 统计 + 回收站
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
        .background(backgroundGradient)
        .overlay(alignment: .center) {
            // 回收站遮罩层
            if viewModel.showTrash {
                Color.black.opacity(0.5)
                    .onTapGesture {
                        viewModel.showTrash = false
                    }
            }
        }
        .overlay(alignment: .center) {
            // 设置遮罩层
            if viewModel.showSettings {
                Color.black.opacity(0.5)
                    .onTapGesture {
                        viewModel.showSettings = false
                    }
            }
        }
        .overlay(alignment: .center) {
            // 回收站面板
            if viewModel.showTrash {
                TrashPanelView(
                    deletedTasks: viewModel.deletedTasks,
                    onRestore: { viewModel.restoreTask($0) },
                    onPermanentDelete: { viewModel.requestPermanentDelete($0) },
                    onClearTrash: { viewModel.requestClearTrash() },
                    onClose: { viewModel.showTrash = false }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .center) {
            // 设置面板
            if viewModel.showSettings {
                GitHubSettingsPanelView(onClose: { viewModel.showSettings = false })
                    .environmentObject(viewModel)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            // 加载条
            if viewModel.loadingProgress > 0 {
                loadingBar
            }
        }
        .overlay(alignment: .top) {
            // Toast
            if let message = viewModel.toastMessage {
                toastView(message: message)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showTrash)
        .animation(.easeInOut(duration: 0.25), value: viewModel.showSettings)
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

    // MARK: - 矩阵网格

    /// 使用嵌套 HStack/VStack 实现动态高度分配，
    /// 每个象限均等地分享可用空间，随窗口变化而动态缩放
    private var matrixGrid: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 16
            let topPadding: CGFloat = 16
            let bottomPadding: CGFloat = 0
            let sidePadding: CGFloat = 20

            let availableWidth = geo.size.width - sidePadding * 2 - spacing
            let availableHeight = geo.size.height - topPadding - bottomPadding - spacing

            let colWidth = availableWidth / 2
            let rowHeight = availableHeight / 2

            VStack(spacing: spacing) {
                // 第一行：重要不紧急(q2) + 重要且紧急(q1)
                HStack(spacing: spacing) {
                    quadrantCard(for: QuadrantConfig.all[0], width: colWidth, height: rowHeight)
                    quadrantCard(for: QuadrantConfig.all[1], width: colWidth, height: rowHeight)
                }

                // 第二行：不重要不紧急(q4) + 不重要但紧急(q3)
                HStack(spacing: spacing) {
                    quadrantCard(for: QuadrantConfig.all[2], width: colWidth, height: rowHeight)
                    quadrantCard(for: QuadrantConfig.all[3], width: colWidth, height: rowHeight)
                }
            }
            .padding(.horizontal, sidePadding)
            .padding(.top, topPadding)
        }
    }

    private func quadrantCard(for config: QuadrantConfig, width: CGFloat, height: CGFloat) -> some View {
        QuadrantView(
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
            },
            onDragStart: { viewModel.draggedTaskId = $0 },
            onDrop: { targetId, before in
                viewModel.reorderTasks(targetTaskId: targetId, before: before)
            },
            onDropToQuadrant: { taskId in
                viewModel.moveToQuadrant(taskId: taskId, quadrant: config.id)
            }
        )
        .frame(width: width, height: height)
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
                .frame(width: geo.size.width * (viewModel.loadingProgress / 100), height: 4)
                .animation(.easeOut(duration: 0.3), value: viewModel.loadingProgress)
        }
        .frame(height: 4)
        .opacity(viewModel.isLoading && viewModel.loadingProgress > 0 ? 1 : 0)
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                viewModel.toastType == .success
                                    ? Color(red: 0.42, green: 0.80, blue: 0.47).opacity(0.5)
                                    : Color(red: 0.91, green: 0.27, blue: 0.38).opacity(0.5),
                                lineWidth: 1
                            )
                    )
            )
            .padding(.top, 8)
    }
}