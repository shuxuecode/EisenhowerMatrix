import Foundation

/// 任务数据模型 — 对应 Web 版的 tasksCache 条目
struct TaskItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String = ""
    var content: String = ""
    var quadrant: String = "q1"
    var done: Bool = false
    var order: Int = 0
    var deleted: Bool = false
    var deletedAt: TimeInterval?
    var originalQuadrant: String?

    enum CodingKeys: String, CodingKey {
        case id, title, content, quadrant, done, order, deleted
        case deletedAt
        case originalQuadrant
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 兼容 id 可能是 String、Int 或 Double (Web 版可能用数字 ID)
        // 注意：decodeIfPresent 在类型不匹配时抛出异常而非返回 nil，
        // 所以必须用 try? 来优雅降级
        if let idStr = try? container.decodeIfPresent(String.self, forKey: .id) {
            id = idStr
        } else if let idInt = try? container.decodeIfPresent(Int.self, forKey: .id) {
            id = String(idInt)
        } else if let idDouble = try? container.decodeIfPresent(Double.self, forKey: .id) {
            id = String(idDouble)
        } else {
            id = UUID().uuidString
        }

        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        content = (try? container.decodeIfPresent(String.self, forKey: .content)) ?? ""
        quadrant = (try? container.decodeIfPresent(String.self, forKey: .quadrant)) ?? "q1"
        done = (try? container.decodeIfPresent(Bool.self, forKey: .done)) ?? false

        // 兼容 order 可能是 Double 或 Int
        if let orderInt = try? container.decodeIfPresent(Int.self, forKey: .order) {
            order = orderInt
        } else if let orderDouble = try? container.decodeIfPresent(Double.self, forKey: .order) {
            order = Int(orderDouble)
        } else {
            order = 0
        }

        deleted = (try? container.decodeIfPresent(Bool.self, forKey: .deleted)) ?? false

        // 兼容 deletedAt 可能是毫秒级整数或秒级 Double
        if let deletedAtDouble = try? container.decodeIfPresent(Double.self, forKey: .deletedAt) {
            // 如果值 > 1e12，说明是毫秒级，需要转换为秒 (TimeInterval)
            deletedAt = deletedAtDouble > 1e12 ? deletedAtDouble / 1000.0 : deletedAtDouble
        } else if let deletedAtInt = try? container.decodeIfPresent(Int.self, forKey: .deletedAt) {
            // 兼容整型 deletedAt（毫秒级）
            deletedAt = Double(deletedAtInt) / 1000.0
        } else {
            deletedAt = nil
        }

        originalQuadrant = try? container.decodeIfPresent(String.self, forKey: .originalQuadrant)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(quadrant, forKey: .quadrant)
        try container.encode(done, forKey: .done)
        try container.encode(order, forKey: .order)
        try container.encode(deleted, forKey: .deleted)
        // 内存中 deletedAt 为秒级，编码时转换为毫秒以兼容 Web 版 Date.now()
        if let deletedAt = deletedAt {
            try container.encode(deletedAt * 1000.0, forKey: .deletedAt)
        }
        try container.encodeIfPresent(originalQuadrant, forKey: .originalQuadrant)
    }

    init(id: String = UUID().uuidString,
         title: String,
         content: String = "",
         quadrant: String = "q1",
         done: Bool = false,
         order: Int = 0,
         deleted: Bool = false,
         deletedAt: TimeInterval? = nil,
         originalQuadrant: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.quadrant = quadrant
        self.done = done
        self.order = order
        self.deleted = deleted
        self.deletedAt = deletedAt
        self.originalQuadrant = originalQuadrant
    }

    /// 标记为已删除
    /// 内存中统一使用秒（TimeInterval），编码时转换为毫秒以兼容 Web 版
    mutating func markDeleted() {
        deleted = true
        deletedAt = Date().timeIntervalSince1970  // 秒级，与解码后一致
        originalQuadrant = quadrant
    }

    /// 恢复已删除任务
    mutating func restore() {
        deleted = false
        quadrant = originalQuadrant ?? "q1"
        deletedAt = nil
        originalQuadrant = nil
    }
}

/// 持久化数据容器 — 对应 Web 版 data.json 结构
struct PersistedData: Codable {
    var q1: [TaskItem]
    var q2: [TaskItem]
    var q3: [TaskItem]
    var q4: [TaskItem]
    var _trash: [TaskItem]
    var _ts: Int64  // 改为 Int64，与 Web 版 Date.now() (毫秒级整数) 兼容

    enum CodingKeys: String, CodingKey {
        case q1, q2, q3, q4, _trash, _ts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        q1 = PersistedData.decodeArraySafely(from: container, forKey: .q1)
        q2 = PersistedData.decodeArraySafely(from: container, forKey: .q2)
        q3 = PersistedData.decodeArraySafely(from: container, forKey: .q3)
        q4 = PersistedData.decodeArraySafely(from: container, forKey: .q4)
        _trash = PersistedData.decodeArraySafely(from: container, forKey: ._trash)

        // 兼容多种时间戳格式：Int64、Double、或字符串
        // 注意：decodeIfPresent 在类型不匹配时抛异常而非返回 nil，用 try? 优雅降级
        if let tsInt = try? container.decodeIfPresent(Int64.self, forKey: ._ts) {
            _ts = tsInt
        } else if let tsDouble = try? container.decodeIfPresent(Double.self, forKey: ._ts) {
            // 如果是秒级 Double，转换为毫秒
            _ts = Int64(tsDouble * 1000.0)
        } else if let tsInt32 = try? container.decodeIfPresent(Int32.self, forKey: ._ts) {
            // 兼容 32 位整数
            _ts = Int64(tsInt32)
        } else {
            _ts = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(q1, forKey: .q1)
        try container.encode(q2, forKey: .q2)
        try container.encode(q3, forKey: .q3)
        try container.encode(q4, forKey: .q4)
        try container.encode(_trash, forKey: ._trash)
        try container.encode(_ts, forKey: ._ts)
    }

    init() {
        q1 = []
        q2 = []
        q3 = []
        q4 = []
        _trash = []
        _ts = 0
    }

    /// 从 tasksCache 构建
    init(from tasks: [TaskItem]) {
        q1 = []
        q2 = []
        q3 = []
        q4 = []
        _trash = []
        // 使用毫秒级时间戳，与 Web 版 Date.now() 一致
        _ts = Int64(Date().timeIntervalSince1970 * 1000.0)

        for t in tasks {
            if t.deleted {
                _trash.append(t)
            } else {
                switch t.quadrant {
                case "q1": q1.append(t)
                case "q2": q2.append(t)
                case "q3": q3.append(t)
                case "q4": q4.append(t)
                default: q1.append(t)  // 兜底归入 q1
                }
            }
        }
    }

    /// 合并到 tasksCache
    func allTasks() -> [TaskItem] {
        return q1 + q2 + q3 + q4 + _trash
    }

    /// 逐个解码任务数组，跳过单个失败的任务而非丢弃整个象限
    static func decodeArraySafely<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> [TaskItem] {
        // 先尝试整体解码（最快路径）
        if let array = try? container.decodeIfPresent([TaskItem].self, forKey: key) {
            return array
        }
        // 整体解码失败 → 尝试逐个解码保留尽可能多的数据
        guard let rawArray = try? container.decodeIfPresent([AnyCodable].self, forKey: key) else {
            return []
        }
        var result: [TaskItem] = []
        for item in rawArray {
            if let data = try? JSONEncoder().encode(item),
               let task = try? JSONDecoder().decode(TaskItem.self, from: data) {
                result.append(task)
            }
        }
        if result.count < rawArray.count {
            print("⚠️ 象限 \(key.stringValue) 有 \(rawArray.count - result.count) 个任务解码失败被跳过")
        }
        return result
    }
}

/// 通用 Codable 包装器，用于逐个解码未知结构的 JSON 对象
struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) { value = intVal }
        else if let doubleVal = try? container.decode(Double.self) { value = doubleVal }
        else if let boolVal = try? container.decode(Bool.self) { value = boolVal }
        else if let strVal = try? container.decode(String.self) { value = strVal }
        else if let arrayVal = try? container.decode([AnyCodable].self) { value = arrayVal }
        else if let dictVal = try? container.decode([String: AnyCodable].self) { value = dictVal }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intVal as Int: try container.encode(intVal)
        case let doubleVal as Double: try container.encode(doubleVal)
        case let boolVal as Bool: try container.encode(boolVal)
        case let strVal as String: try container.encode(strVal)
        case let arrayVal as [AnyCodable]: try container.encode(arrayVal)
        case let dictVal as [String: AnyCodable]: try container.encode(dictVal)
        case is NSNull: try container.encodeNil()
        default: try container.encode(String(describing: value))
        }
    }
}

/// 象限配置
struct QuadrantConfig: Identifiable {
    let id: String
    let num: String
    let cls: String
    let title: String
    let subtitle: String
    let action: String

    static let all: [QuadrantConfig] = [
        QuadrantConfig(id: "q2", num: "II", cls: "q2", title: "✨ 重要不紧急", subtitle: "价值最高，重点投入", action: "📅 制定计划，安排时间专注完成"),
        QuadrantConfig(id: "q1", num: "I", cls: "q1", title: "🔥 重要且紧急", subtitle: "危机模式，立即处理", action: "⚡ 立即执行，不可拖延"),
        QuadrantConfig(id: "q4", num: "IV", cls: "q4", title: "💤 不重要不紧急", subtitle: "浪费时间，尽量消除", action: "🚫 尽量避免，减少消耗"),
        QuadrantConfig(id: "q3", num: "III", cls: "q3", title: "😅 不重要但紧急", subtitle: "干扰陷阱，学会拒绝", action: "🤝 授权他人，学会委婉拒绝")
    ]
}

/// GitHub 配置
struct GitHubConfig: Codable {
    var token: String
    var repo: String
    var branch: String

    static let defaultBranch = "main"

    init(token: String = "", repo: String = "", branch: String = defaultBranch) {
        self.token = token
        self.repo = repo
        self.branch = branch
    }

    var isValid: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && repoParts != nil
    }

    var repoParts: (owner: String, name: String)? {
        let parts = repo.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let owner = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !name.isEmpty else { return nil }
        return (owner, name)
    }
}