import SwiftUI

/// iOS 象限卡片视图 — 垂直布局，可展开/折叠
struct QuadrantCardView: View {
    let config: QuadrantConfig
    let tasks: [TaskItem]
    let newTaskIds: Set<String>
    let onToggle: (String) -> Void
    let onDelete: (String) -> Void
    let onAdd: (String, String) -> Void
    let onEdit: (String, String, String, String) -> Void

    @State private var isExpanded: Bool = true
    @State private var showInput: Bool = false
    @State private var inputTitle: String = ""
    @State private var inputContent: String = ""
    @State private var editingTaskId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部（点击可展开/折叠）
            headerView

            // 内联输入
            if showInput {
                inlineInputView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 任务列表（展开时显示）
            if isExpanded {
                taskListView
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(quadrantGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: showInput)
    }

    // MARK: - 象限渐变

    private var quadrantGradient: LinearGradient {
        switch config.id {
        case "q1":
            return LinearGradient(
                colors: [Color(red: 0.91, green: 0.27, blue: 0.38), Color(red: 1, green: 0.42, blue: 0.42)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case "q2":
            return LinearGradient(
                colors: [Color(red: 0.30, green: 0.59, blue: 1), Color(red: 0.42, green: 0.80, blue: 0.47)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case "q3":
            return LinearGradient(
                colors: [Color(red: 1, green: 0.62, blue: 0.26), Color(red: 1, green: 0.85, blue: 0.24)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case "q4":
            return LinearGradient(
                colors: [Color(red: 0.61, green: 0.35, blue: 0.71), Color(red: 0.88, green: 0.34, blue: 0.99)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(
                colors: [Color.gray, Color.gray.opacity(0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: - 子视图

    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(config.action)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            // 任务计数
            if !tasks.isEmpty {
                Text("\(tasks.filter { !$0.done }.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
            }

            // 展开/折叠按钮
            Button(action: { isExpanded.toggle() }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "折叠" : "展开")

            // 添加按钮
            Button(action: {
                withAnimation { showInput.toggle() }
                if showInput {
                    inputTitle = ""
                    inputContent = ""
                }
            }) {
                Image(systemName: "plus")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.25))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加任务")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
    }

    private var inlineInputView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("标题", text: $inputTitle)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .onSubmit { addTask() }

                Button("添加") {
                    addTask()
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(8)
                .buttonStyle(.plain)
            }

            TextField("内容（可选）", text: $inputContent)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.white.opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var taskListView: some View {
        Group {
            if tasks.isEmpty {
                Text("暂无任务")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .padding(.bottom, 6)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRowView(
                            task: task,
                            index: index,
                            isNew: newTaskIds.contains(task.id),
                            onToggle: { onToggle(task.id) },
                            onDelete: { onDelete(task.id) },
                            onEdit: { id, title, content, quadrant in
                                onEdit(id, title, content, quadrant)
                            },
                            editingTrigger: $editingTaskId
                        )
                        .contextMenu {
                            Button("编辑") {
                                editingTaskId = task.id
                            }
                            Button("删除", role: .destructive) {
                                onDelete(task.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - 添加任务

    private func addTask() {
        let title = inputTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let content = inputContent.trimmingCharacters(in: .whitespaces)
        onAdd(title, content)
        inputTitle = ""
        inputContent = ""
        withAnimation { showInput = false }
    }
}