import SwiftUI

/// 单个任务行视图 — 对应 Web 版的 task-item
struct TaskRowView: View {
    let task: TaskItem
    let index: Int
    let isNew: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: (String, String, String, String) -> Void  // id, title, content, quadrant
    @Binding var editingTrigger: String?  // 当值 == task.id 时触发编辑

    @State private var isEditing: Bool = false
    @State private var editTitle: String = ""
    @State private var editContent: String = ""
    @State private var editQuadrant: String = ""
    @State private var isCollapsed: Bool = true
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 序号
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.7))
                .frame(minWidth: 16, alignment: .center)

            // 完成复选框
            Button(action: onToggle) {
                Circle()
                    .strokeBorder(task.done ? Color.white : Color.white.opacity(0.6), lineWidth: 2)
                    .background(
                        Circle()
                            .fill(task.done ? Color.white.opacity(0.8) : Color.clear)
                    )
                    .frame(width: 22, height: 22)
                    .overlay(
                        Group {
                            if task.done {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black.opacity(0.7))
                            }
                        }
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? "标记未完成" : "标记完成")

            // 任务内容
            if isEditing {
                editFormView
            } else {
                taskDisplayView
            }

            // 操作按钮
            HStack(spacing: 4) {
                if !task.content.isEmpty {
                    Button(action: { isCollapsed.toggle() }) {
                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCollapsed ? "展开内容" : "收起内容")
                }

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除任务")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .opacity(task.done ? 0.5 : 1.0)
        .overlay(
            task.done ?
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(height: 1)
                }
                .padding(.horizontal, 50)
                : nil
        )
        .scaleEffect(isNew ? 0.85 : 1.0)
        .animation(.easeOut(duration: 0.3), value: isNew)
        .onAppear {
            // 入场动画由 scaleEffect + .animation 自动驱动
        }
        .onChange(of: editingTrigger) { newValue in
            if newValue == task.id && !isEditing {
                startEditing()
                editingTrigger = nil  // 消费触发信号
            }
        }
    }

    // MARK: - 显示模式

    private var taskDisplayView: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 标题：折叠态单行截断，展开态完整显示
            Text(task.title)
                .font(.callout)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(isCollapsed ? 1 : nil)
                .fixedSize(horizontal: false, vertical: !isCollapsed)

            // 内容：折叠态单行截断，展开态最多3行
            if !task.content.isEmpty {
                if isCollapsed {
                    Text(task.content)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                } else {
                    Text(task.content)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onTapGesture(count: 2) {
            startEditing()
        }
    }

    // MARK: - 编辑模式

    private var editFormView: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("标题", text: $editTitle)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(6)
                .background(Color.white.opacity(0.25))
                .cornerRadius(6)
                .foregroundColor(.white)

            TextField("内容（可选）", text: $editContent)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .padding(6)
                .background(Color.white.opacity(0.25))
                .cornerRadius(6)
                .foregroundColor(.white)

            Picker("象限", selection: $editQuadrant) {
                Text("I 重要且紧急").tag("q1")
                Text("II 重要不紧急").tag("q2")
                Text("III 不重要但紧急").tag("q3")
                Text("IV 不重要不紧急").tag("q4")
            }
            .pickerStyle(.menu)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(6)
            .background(Color.white.opacity(0.25))
            .cornerRadius(6)

            HStack(spacing: 6) {
                Button("保存") {
                    saveEdit()
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.35))
                .foregroundColor(.white)
                .cornerRadius(6)
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)

                Button("取消") {
                    cancelEdit()
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .foregroundColor(.white.opacity(0.7))
                .cornerRadius(6)
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .onAppear {
            editTitle = task.title
            editContent = task.content
            editQuadrant = task.quadrant
        }
    }

    private func startEditing() {
        editTitle = task.title
        editContent = task.content
        editQuadrant = task.quadrant
        isEditing = true
    }

    private func saveEdit() {
        let trimmedTitle = editTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        onEdit(task.id, trimmedTitle, editContent.trimmingCharacters(in: .whitespaces), editQuadrant)
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
    }

    }