import Foundation
import Combine
import SwiftUI

/// 主视图模型 — iOS 版，移除了 macOS 特有的 willTerminateNotification
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

    // 拖拽状态（iOS 用长按拖拽）
    @Published var draggedTaskId: String?

    // 破坏性操作确认状态
    @Published var confirmAction: ConfirmAction?

    // MARK: - Services

    private let localStorage = LocalStorageService.shared
    private let gitHub = GitHubService.shared
    private let configStorage = ConfigStorage.shared

    // MARK: - Debounce

    private var saveWorkItem: DispatchWorkItem?

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
                if remoteTs > localTs {
                    tasks = remote.allTasks()
                    localStorage.save(remote)
                }
                isGitHubConnected = true
            } catch {
                print("远端数据加载失败: \(error.localizedDescription)")
            }
            stopLoadingAnimation()
            isLoading = false
        }

        // 如果从未配置过 GitHub，清空本地数据并弹出设置面板引导用户连接
        if !wasConfigured {
            tasks = []
            localStorage.remove()
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

        // 延迟清除入场动画标记
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
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
    func reorderTasks(targetTaskId: String, before: Bool) {
        guard let draggedId = draggedTaskId,
              let draggedIndex = tasks.firstIndex(where: { $0.id == draggedId }),
              let targetIndex = tasks.firstIndex(where: { $0.id == targetTaskId }) else { return }

        let sourceQuadrant = tasks[draggedIndex].quadrant
        let targetQuadrant = tasks[targetIndex].quadrant

        tasks[draggedIndex].quadrant = targetQuadrant

        var qTasks = tasks.filter { $0.quadrant == targetQuadrant && $0.id != draggedId }
            .sorted { $0.order < $1.order }

        let targetPos = qTasks.firstIndex(where: { $0.id == targetTaskId }) ?? 0
        let insertIdx = before ? targetPos : targetPos + 1
        qTasks.insert(tasks[draggedIndex], at: insertIdx)

        for (i, _) in qTasks.enumerated() {
            qTasks[i].order = i
        }

        var sourceTasks: [TaskItem] = []
        if sourceQuadrant != targetQuadrant {
            sourceTasks = tasks.filter { $0.quadrant == sourceQuadrant }
                .sorted { $0.order < $1.order }
            for (i, _) in sourceTasks.enumerated() {
                sourceTasks[i].order = i
            }
        }

        var allTasks = qTasks
        if sourceQuadrant != targetQuadrant {
            allTasks += sourceTasks
        }
        let otherQuadrants = sourceQuadrant == targetQuadrant
            ? [] : [sourceQuadrant, targetQuadrant]
        let remainingQuadrants = ["q1", "q2", "q3", "q4"].filter { !otherQuadrants.contains($0) }
        for q in remainingQuadrants {
            let qItems = tasks.filter { $0.quadrant == q }
                .sorted { $0.order < $1.order }
            allTasks += qItems
        }
        tasks = allTasks
        debouncedSave()
    }

    /// 移动到象限
    func moveToQuadrant(taskId: String, quadrant: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let oldQuadrant = tasks[index].quadrant
        guard oldQuadrant != quadrant else { return }

        tasks[index].quadrant = quadrant
        let maxOrder = tasks.filter { $0.quadrant == quadrant }.map { $0.order }.max() ?? -1
        tasks[index].order = maxOrder + 1
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
        saveLocal()
    }

    private func saveLocal() {
        let data = PersistedData(from: tasks)
        localStorage.save(data)
    }

    private func syncToGitHub() async {
        guard gitHub.isConfigured else { return }
        let data = PersistedData(from: tasks)
        do {
            try await gitHub.saveData(data)
            showToast("已同步", type: .success)
        } catch {
            print("GitHub 同步失败: \(error.localizedDescription)")
            showToast("同步失败", type: .error)
        }
    }

    // MARK: - GitHub Connection

    private func extractStatusCode(from msg: String) -> Int? {
        let pattern = /^HTTP (\d+)/
        if let match = msg.firstMatch(of: pattern) {
            return Int(match.1)
        }
        if let match = msg.firstMatch(of: /(\d{3})/) {
            return Int(match.1)
        }
        return nil
    }

    func connectGitHub(token: String, repo: String, branch: String) async {
        settingsMessage = ""
        settingsIsError = false
        isGitHubConnected = false

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
                settingsMessage = "权限不足，请检查 Token 授权范围"
            case 404:
                settingsMessage = "仓库不存在或 Token 无权限访问此仓库"
            default:
                if msg.contains("Bad credentials") {
                    settingsMessage = "Token 无效或已过期"
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
            return
        }

        // 加载数据
        do {
            let remote = try await gitHub.fetchData()
            let localTs = localStorage.load()?._ts ?? 0
            if remote._ts > localTs {
                tasks = remote.allTasks()
                localStorage.save(remote)
            }
            isGitHubConnected = true
            settingsMessage = ""
            showToast("连接成功，数据加载完成", type: .success)
        } catch {
            let nsError = error as NSError
            settingsMessage = "加载数据失败: \(nsError.localizedDescription)"
            settingsIsError = true
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

    // MARK: - Confirm Action

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

    func cancelConfirmedAction() {
        confirmAction = nil
    }

    // MARK: - Toast

    func showToast(_ message: String, type: ToastType) {
        toastMessage = message
        toastType = type

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
    case permanentDelete(String)
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
        case .disconnectGitHub: return "将断开 GitHub 连接并清除所有本地数据。"
        case .clearDone: return "将把所有已完成任务移入回收站，可从回收站恢复。"
        }
    }
}