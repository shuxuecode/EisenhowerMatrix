import Foundation
import Combine
import SwiftUI

/// 主视图模型 — 对应 Web 版 app.js 中的全局状态和数据操作
@MainActor
class TaskViewModel: ObservableObject {
    // MARK: - Published State

    @Published var tasks: [TaskItem] = []
    @Published var toastMessage: String?
    @Published var toastType: ToastType = .success
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0
    @Published var isGitHubConnected: Bool = false
    @Published var showTrash: Bool = false
    @Published var showSettings: Bool = false
    @Published var settingsMessage: String = ""
    @Published var settingsIsError: Bool = false

    // 新增任务标记（用于入场动画）
    @Published var newTaskIds: Set<String> = []

    // 拖拽状态
    @Published var draggedTaskId: String?

    // 破坏性操作确认状态
    @Published var confirmAction: ConfirmAction?

    // MARK: - Services

    private let localStorage = LocalStorageService.shared
    private let gitHub = GitHubService.shared
    private let configStorage = ConfigStorage.shared

    // MARK: - Debounce

    private var saveWorkItem: DispatchWorkItem?
    private var isSyncingToGitHub = false
    private var needsGitHubSyncAfterCurrent = false

    // MARK: - Computed

    /// 非删除任务
    var activeTasks: [TaskItem] {
        tasks.filter { !$0.deleted }
    }

    /// 已删除任务
    var deletedTasks: [TaskItem] {
        tasks.filter { $0.deleted }
            .sorted { ($0.deletedAt ?? 0) > ($1.deletedAt ?? 0) }
    }

    /// 指定象限的任务
    func tasksForQuadrant(_ q: String) -> [TaskItem] {
        tasks.filter { $0.quadrant == q && !$0.deleted }
            .sorted { ($0.order) < ($1.order) }
    }

    /// 统计
    var totalCount: Int { activeTasks.count }
    var doneCount: Int { activeTasks.filter { $0.done }.count }
    var undoneCount: Int { totalCount - doneCount }

    // MARK: - Initialization

    func initialize() async {
        let config = configStorage.load()
        let wasConfigured = config.isValid

        gitHub.configure(with: config)
        isGitHubConnected = wasConfigured

        // 先加载本地数据
        if let local = localStorage.load() {
            tasks = local.allTasks()
        }

        // 如果配置了 GitHub，尝试拉取远端数据
        if gitHub.isConfigured {
            isLoading = true
            startLoadingAnimation()
            do {
                let remote = try await gitHub.fetchData()
                let localTs = localStorage.load()?._ts ?? 0
                let remoteTs = remote._ts
                // 时间戳都是毫秒级 Int64，直接比较
                if remoteTs > localTs {
                    tasks = remote.allTasks()
                    localStorage.save(remote)
                } else if localTs > remoteTs {
                    await syncToGitHub()
                }
                isGitHubConnected = true
            } catch {
                // 初始化拉取失败不改变连接状态，配置仍然有效，下次重试即可
                print("远端数据加载失败: \(error.localizedDescription)")
            }
            stopLoadingAnimation()
            isLoading = false
        }

        // 如果从未配置过 GitHub，弹出设置面板引导用户连接
        if !wasConfigured {
            showSettings = true
        }
    }

    // MARK: - Task CRUD

    /// 添加任务
    func addTask(title: String, content: String, quadrant: String) {
        let minOrder = tasksForQuadrant(quadrant).map { $0.order }.min() ?? 0
        let newTask = TaskItem(
            title: title,
            content: content,
            quadrant: quadrant,
            order: minOrder - 1
        )
        let taskId = newTask.id
        newTaskIds.insert(taskId)
        tasks.append(newTask)
        debouncedSave()

        // 延迟清除入场动画标记，动画完成后移除
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)  // 0.8 秒
            newTaskIds.remove(taskId)
        }
    }

    /// 切换完成状态
    func toggleTask(_ id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              !tasks[index].deleted else { return }
        tasks[index].done.toggle()
        debouncedSave()
    }

    /// 删除任务（软删除）
    func deleteTask(_ id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].markDeleted()
        debouncedSave()
    }

    /// 恢复任务
    func restoreTask(_ id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].restore()
        debouncedSave()
    }

    /// 彻底删除（需要确认）
    func requestPermanentDelete(_ id: String) {
        confirmAction = .permanentDelete(id)
    }

    func permanentDelete(_ id: String) {
        tasks.removeAll { $0.id == id }
        debouncedSave()
    }

    /// 清空回收站（需要确认）
    func requestClearTrash() {
        confirmAction = .clearTrash
    }

    func clearTrash() {
        tasks.removeAll { $0.deleted }
        debouncedSave()
    }

    /// 清除已完成（需要确认）
    func requestClearDone() {
        confirmAction = .clearDone
    }

    func clearDone() {
        for i in tasks.indices where tasks[i].done && !tasks[i].deleted {
            tasks[i].markDeleted()
        }
        debouncedSave()
    }

    /// 保存编辑
    func saveEdit(id: String, title: String, content: String, quadrant: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].title = title
        tasks[index].content = content
        tasks[index].quadrant = quadrant
        debouncedSave()
    }

    // MARK: - Drag & Drop

    /// 重新排序任务
    func reorderTasks(draggedId: String, targetTaskId: String, before: Bool) {
        guard draggedId != targetTaskId,
              let draggedIndex = tasks.firstIndex(where: { $0.id == draggedId && !$0.deleted }),
              let targetIndex = tasks.firstIndex(where: { $0.id == targetTaskId && !$0.deleted }) else { return }

        let sourceQuadrant = tasks[draggedIndex].quadrant
        let targetQuadrant = tasks[targetIndex].quadrant
        var draggedTask = tasks[draggedIndex]
        draggedTask.quadrant = targetQuadrant

        var updatedTasksById: [String: TaskItem] = [:]
        var targetTasks = tasks.filter { $0.quadrant == targetQuadrant && !$0.deleted && $0.id != draggedId }
            .sorted { $0.order < $1.order }

        let targetPos = targetTasks.firstIndex(where: { $0.id == targetTaskId }) ?? 0
        let insertIdx = before ? targetPos : targetPos + 1
        targetTasks.insert(draggedTask, at: min(insertIdx, targetTasks.count))

        for index in targetTasks.indices {
            targetTasks[index].order = index
            updatedTasksById[targetTasks[index].id] = targetTasks[index]
        }

        if sourceQuadrant != targetQuadrant {
            var sourceTasks = tasks.filter { $0.quadrant == sourceQuadrant && !$0.deleted && $0.id != draggedId }
                .sorted { $0.order < $1.order }
            for index in sourceTasks.indices {
                sourceTasks[index].order = index
                updatedTasksById[sourceTasks[index].id] = sourceTasks[index]
            }
        }

        tasks = tasks.map { updatedTasksById[$0.id] ?? $0 }
        draggedTaskId = nil
        debouncedSave()
    }

    /// 移动到象限
    func moveToQuadrant(taskId: String, quadrant: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId && !$0.deleted }) else { return }
        let oldQuadrant = tasks[index].quadrant
        guard oldQuadrant != quadrant else { return }

        let maxOrder = tasks.filter { $0.quadrant == quadrant && !$0.deleted }.map { $0.order }.max() ?? -1
        tasks[index].quadrant = quadrant
        tasks[index].order = maxOrder + 1

        var sourceTasks = tasks.filter { $0.quadrant == oldQuadrant && !$0.deleted }
            .sorted { $0.order < $1.order }
        var normalizedById: [String: Int] = [:]
        for taskIndex in sourceTasks.indices {
            sourceTasks[taskIndex].order = taskIndex
            normalizedById[sourceTasks[taskIndex].id] = taskIndex
        }
        for taskIndex in tasks.indices {
            if let normalizedOrder = normalizedById[tasks[taskIndex].id] {
                tasks[taskIndex].order = normalizedOrder
            }
        }

        draggedTaskId = nil
        debouncedSave()
    }

    // MARK: - Save

    func debouncedSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.syncToGitHub()
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)

        // 同时立即保存本地
        saveLocal()
    }

    private func saveLocal() {
        let data = PersistedData(from: tasks)
        localStorage.save(data)
    }

    private func syncToGitHub() async {
        guard gitHub.isConfigured else { return }

        if isSyncingToGitHub {
            needsGitHubSyncAfterCurrent = true
            return
        }

        isSyncingToGitHub = true
        defer { isSyncingToGitHub = false }

        repeat {
            needsGitHubSyncAfterCurrent = false
            let data = PersistedData(from: tasks)
            do {
                try await gitHub.saveData(data)
                showToast("已同步", type: .success)
            } catch {
                print("GitHub 同步失败: \(error.localizedDescription)")
                showToast("同步失败", type: .error)
                if !needsGitHubSyncAfterCurrent {
                    return
                }
            }
        } while needsGitHubSyncAfterCurrent
    }

    private func syncErrorMessage(_ error: Error) -> String {
        guard let gitHubError = error as? GitHubError else {
            return "同步失败: \(error.localizedDescription)"
        }
        switch gitHubError {
        case .httpError(401, _):
            return "Token 无效或已过期"
        case .httpError(403, _):
            return "权限不足或请求受限"
        case .httpError(404, _):
            return "仓库、分支或数据文件不可访问"
        case .httpError(409, _):
            return "远端数据已变化，请重新同步"
        case .remoteDataIsNewer:
            return "远端数据较新，请先同步"
        default:
            return "同步失败: \(gitHubError.localizedDescription)"
        }
    }

    func forceSyncNow() async {
        guard gitHub.isConfigured else {
            showSettings = true
            showToast("请先连接 GitHub", type: .error)
            return
        }

        isLoading = true
        startLoadingAnimation()
        defer {
            stopLoadingAnimation()
            isLoading = false
        }

        while isSyncingToGitHub {
            needsGitHubSyncAfterCurrent = true
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        do {
            let remote = try await gitHub.fetchData()
            let localTs = localStorage.load()?._ts ?? 0
            if remote._ts > localTs {
                tasks = remote.allTasks()
                localStorage.save(remote)
                showToast("已拉取最新数据", type: .success)
            } else if localTs > remote._ts {
                await syncToGitHub()
            } else {
                showToast("已是最新", type: .success)
            }
            isGitHubConnected = true
        } catch {
            let message = syncErrorMessage(error)
            print("强制同步失败: \(error.localizedDescription)")
            showToast(message, type: .error)
        }
    }

    // MARK: - GitHub Connection

    /// 根据错误信息提取 HTTP 状态码
    private func extractStatusCode(from msg: String) -> Int? {
        // 错误格式为 "HTTP {status}: {message}" 或 "HTTP {status}"
        let pattern = /^HTTP (\d+)/
        if let match = msg.firstMatch(of: pattern) {
            return Int(match.1)
        }
        // 兜底：也匹配纯数字
        if let match = msg.firstMatch(of: /(\d{3})/) {
            return Int(match.1)
        }
        return nil
    }

    func connectGitHub(token: String, repo: String, branch: String) async {
        settingsMessage = ""
        settingsIsError = false
        isGitHubConnected = false  // 重置连接状态，只有全部验证通过才设为 true

        let config = GitHubConfig(token: token, repo: repo, branch: branch)
        guard config.isValid else {
            settingsMessage = "请输入有效的仓库名 (owner/repo)"
            settingsIsError = true
            return
        }

        gitHub.configure(with: config)

        // 验证仓库
        do {
            _ = try await gitHub.verifyRepo()
        } catch {
            let msg = error.localizedDescription
            let statusCode = extractStatusCode(from: msg)
            switch statusCode {
            case 401:
                settingsMessage = "Token 无效或已过期，请检查后重新输入"
            case 403:
                settingsMessage = "权限不足，请检查 Token 授权范围（建议使用 Fine-grained token，仅需 Contents 读写权限）"
            case 404:
                settingsMessage = "仓库不存在或 Token 无权限访问此仓库"
            default:
                // 也通过消息内容匹配，处理无状态码的情况
                if msg.contains("Bad credentials") {
                    settingsMessage = "Token 无效或已过期，请检查后重新输入"
                } else if msg.contains("Not Found") {
                    settingsMessage = "仓库不存在或 Token 无权限访问此仓库"
                } else {
                    settingsMessage = "连接失败: \(msg)"
                }
            }
            settingsIsError = true
            gitHub.reset()
            return
        }

        // 验证分支
        do {
            _ = try await gitHub.verifyBranch()
        } catch {
            let msg = error.localizedDescription
            let statusCode = extractStatusCode(from: msg)
            switch statusCode {
            case 404:
                settingsMessage = "分支 \(branch) 不存在"
            default:
                if msg.contains("Not Found") {
                    settingsMessage = "分支 \(branch) 不存在"
                } else {
                    settingsMessage = "验证分支失败: \(msg)"
                }
            }
            settingsIsError = true
            gitHub.reset()
            return
        }

        configStorage.save(config)

        // 确保数据文件存在
        isLoading = true
        startLoadingAnimation()
        do {
            try await gitHub.ensureDataFile()
        } catch {
            settingsMessage = "创建数据文件失败: \(error.localizedDescription)"
            settingsIsError = true
            stopLoadingAnimation()
            isLoading = false
            // 不重置配置，保留以便用户重试
            return
        }

        // 加载数据
        do {
            let remote = try await gitHub.fetchData()
            let localTs = localStorage.load()?._ts ?? 0
            // 时间戳都是毫秒级 Int64，直接比较
            if remote._ts > localTs {
                tasks = remote.allTasks()
                localStorage.save(remote)
            } else if localTs > remote._ts {
                await syncToGitHub()
            }
            isGitHubConnected = true
            settingsMessage = ""
            showToast("连接成功，数据加载完成", type: .success)
        } catch {
            let nsError = error as NSError
            // 打印详细错误信息便于调试
            print("GitHub 加载失败:")
            print("  错误域: \(nsError.domain)")
            print("  错误码: \(nsError.code)")
            print("  描述: \(nsError.localizedDescription)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("  底层错误: \(underlying.localizedDescription)")
            }
            if let debugDescription = nsError.userInfo[NSDebugDescriptionErrorKey] as? String {
                print("  调试信息: \(debugDescription)")
            }
            settingsMessage = "加载数据失败: \(nsError.localizedDescription)"
            settingsIsError = true
            // 不重置配置，保留以便用户重试
        }
        stopLoadingAnimation()
        isLoading = false
    }

    func requestDisconnectGitHub() {
        confirmAction = .disconnectGitHub
    }

    func disconnectGitHub() {
        configStorage.save(GitHubConfig())
        gitHub.reset()
        isGitHubConnected = false
        tasks = []
        localStorage.remove()
        showToast("已断开连接，本地数据已清除", type: .success)
    }

    // MARK: - Confirm Action Execution

    /// 执行确认后的破坏性操作
    func executeConfirmedAction() {
        guard let action = confirmAction else { return }
        confirmAction = nil
        switch action {
        case .clearTrash:
            clearTrash()
        case .permanentDelete(let id):
            permanentDelete(id)
        case .disconnectGitHub:
            disconnectGitHub()
        case .clearDone:
            clearDone()
        }
    }

    /// 取消确认操作
    func cancelConfirmedAction() {
        confirmAction = nil
    }

    // MARK: - Toast

    func showToast(_ message: String, type: ToastType) {
        toastMessage = message
        toastType = type

        // 自动隐藏
        Task {
            let duration: UInt64 = type == .error ? 4_000_000_000 : 2_000_000_000
            try? await Task.sleep(nanoseconds: duration)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    // MARK: - Loading Animation

    private var loadingTimer: Timer?

    private func startLoadingAnimation() {
        loadingProgress = 0
        loadingTimer?.invalidate()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let inc = max(1, (90 - self.loadingProgress) * 0.12)
                self.loadingProgress = min(90, self.loadingProgress + inc)
            }
        }
    }

    private func stopLoadingAnimation() {
        loadingTimer?.invalidate()
        loadingTimer = nil
        // 直接归零，不再闪现 100%
        loadingProgress = 0
    }
}

enum ToastType {
    case success
    case error
}

/// 破坏性操作确认类型
enum ConfirmAction: Identifiable {
    case clearTrash
    case permanentDelete(String)  // task id
    case disconnectGitHub
    case clearDone

    var id: String {
        switch self {
        case .clearTrash: return "clearTrash"
        case .permanentDelete(let id): return "permanentDelete-\(id)"
        case .disconnectGitHub: return "disconnectGitHub"
        case .clearDone: return "clearDone"
        }
    }

    var title: String {
        switch self {
        case .clearTrash: return "清空回收站"
        case .permanentDelete: return "永久删除任务"
        case .disconnectGitHub: return "断开 GitHub 连接"
        case .clearDone: return "清除已完成任务"
        }
    }

    var message: String {
        switch self {
        case .clearTrash: return "将永久删除回收站中的所有任务，此操作不可恢复。"
        case .permanentDelete: return "将永久删除此任务，此操作不可恢复。"
        case .disconnectGitHub: return "将断开 GitHub 连接并清除所有本地数据，需要重新连接才能恢复。"
        case .clearDone: return "将把所有已完成任务移入回收站，可从回收站恢复。"
        }
    }
}