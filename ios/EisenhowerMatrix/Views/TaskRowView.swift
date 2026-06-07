import SwiftUI

/// iOS 任务行视图 — 与 macOS 版类似但移除键盘快捷键
struct TaskRowView: View {
    let task: TaskItem
    let index: Int
    let isNew: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: (String, String, String, String) -> Void
    @Binding var editingTrigger: String?

    @State private var isEditing: Bool = false
    @State private var editTitle: String = ""
    @State private var editContent: String = ""
    @State private var editQuadrant: String = ""
    @State private var isCollapsed: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // 序号
            Text("\(index + 1)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.7))
                .frame(minWidth: 14, alignment: .center)

            // 完成复选框
            Button(action: onToggle) {
                Circle()
                    .strokeBorder(task.done ? Color.white : Color.white.opacity(0.6), lineWidth: 2)
                    .background(
                        Circle()
                            .fill(task.done ? Color.white.opacity(0.8) : Color.clear)
                    )
                    .frame(width: 20, height: 20)
                    .overlay(
                        Group {
                            if task.done {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
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
            if !task.content.isEmpty && !isEditing {
                Button(action: { isCollapsed.toggle() }) {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除任务")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
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
                .padding(.horizontal, 40)
                : nil
        )
        .scaleEffect(isNew ? 0.85 : 1.0)
        .animation(.easeOut(duration: 0.3), value: isNew)
        .onChange(of: editingTrigger) { newValue in
            if newValue == task.id && !isEditing {
                startEditing()
                editingTrigger = nil
            }
        }
    }

    // MARK: - 显示模式

    private var taskDisplayView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(isCollapsed ? 1 : nil)
                .fixedSize(horizontal: false, vertical: !isCollapsed)

            if !task.content.isEmpty {
                if isCollapsed {
                    Text(task.content)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                } else {
                    Text(task.content)
                        .font(.caption)
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
                .font(.subheadline)
                .padding(6)
                .background(Color.white.opacity(0.25))
                .cornerRadius(6)
                .foregroundColor(.white)

            TextField("内容（可选）", text: $editContent)
                .textFieldStyle(.plain)
                .font(.caption)
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
            .font(.caption)
            .foregroundColor(.white)
            .padding(6)
            .background(Color.white.opacity(0.25))
            .cornerRadius(6)

            HStack(spacing: 6) {
                Button("保存") {
                    saveEdit()
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.35))
                .foregroundColor(.white)
                .cornerRadius(6)
                .buttonStyle(.plain)

                Button("取消") {
                    cancelEdit()
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .foregroundColor(.white.opacity(0.7))
                .cornerRadius(6)
                .buttonStyle(.plain)
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