import SwiftUI

/// 象限视图 — 对应 Web 版的 quadrant 卡片
struct QuadrantView: View {
    let config: QuadrantConfig
    let tasks: [TaskItem]
    let newTaskIds: Set<String>
    let onToggle: (String) -> Void
    let onDelete: (String) -> Void
    let onAdd: (String, String) -> Void
    let onEdit: (String, String, String, String) -> Void
    let onDragStart: (String) -> Void
    let onDrop: (String, Bool) -> Void
    let onDropToQuadrant: (String) -> Void

    @State private var showInput: Bool = false
    @State private var inputTitle: String = ""
    @State private var inputContent: String = ""
    @State private var isDragOver: Bool = false

    // 编辑状态（通过 editingTaskId 触发 TaskRowView 进入编辑模式）
    @State private var editingTaskId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            headerView

            // 内联输入
            if showInput {
                inlineInputView
            }

            // 任务列表 — ScrollView 在弹性布局中填满剩余空间
            taskListView
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(quadrantGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    isDragOver ? Color.white.opacity(0.9) : Color.clear,
                    lineWidth: isDragOver ? 4 : 0
                )
        )
        .overlay(quadrantNumberOverlay, alignment: .topTrailing)
        .overlay(addButtonOverlay, alignment: .topTrailing)
        .onDrop(of: [.text], isTargeted: $isDragOver) { providers, location in
            handleDrop(providers: providers, location: location)
        }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(config.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            + Text(" \(config.subtitle)")
                .font(.callout)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.8))

            Text(config.action)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var quadrantNumberOverlay: some View {
        Text(config.num)
            .font(.system(size: 60, weight: .bold))
            .foregroundColor(.white.opacity(0.15))
            .padding(.top, 14)
            .padding(.trailing, 65)
    }

    private var addButtonOverlay: some View {
        Button(action: {
            showInput.toggle()
            if showInput {
                inputTitle = ""
                inputContent = ""
            }
        }) {
            Image(systemName: "plus")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.2))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .padding(.trailing, 15)
        .accessibilityLabel("添加任务")
    }

    private var inlineInputView: some View {
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
                .onSubmit {
                    addTask()
                }

            TextField("内容（可选）", text: $inputContent)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.white.opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                )

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

            Button("取消") {
                showInput = false
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.15))
            .foregroundColor(.white.opacity(0.7))
            .cornerRadius(8)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var taskListView: some View {
        ScrollView {
            if tasks.isEmpty {
                Text("暂无任务")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(task: task, index: index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func taskRow(task: TaskItem, index: Int) -> some View {
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
        .onDrag {
            onDragStart(task.id)
            return NSItemProvider(object: task.id as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers, location in
            handleItemDrop(providers: providers, location: location, taskId: task.id)
        }
        .contextMenu {
            Button("编辑") {
                editingTaskId = task.id  // 触发 TaskRowView 进入编辑模式
            }
            Button("删除", role: .destructive) {
                onDelete(task.id)
            }
        }
    }

    // MARK: - 拖放处理

    private func handleDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        // 如果拖到任务项上，由任务项处理
        // 否则改变象限
        if let provider = providers.first {
            provider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, _ in
                if let id = data as? String {
                    DispatchQueue.main.async {
                        onDropToQuadrant(id)
                    }
                }
            }
        }
        return true
    }

    private func handleItemDrop(providers: [NSItemProvider], location: CGPoint, taskId: String) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, _ in
            if let id = data as? String, id != taskId {
                DispatchQueue.main.async {
                    let before = location.y < 20  // 在目标上半部分
                    onDrop(taskId, before)
                }
            }
        }
        return true
    }

    // MARK: - 添加任务

    private func addTask() {
        let title = inputTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let content = inputContent.trimmingCharacters(in: .whitespaces)
        onAdd(title, content)
        inputTitle = ""
        inputContent = ""
        showInput = false
    }
}