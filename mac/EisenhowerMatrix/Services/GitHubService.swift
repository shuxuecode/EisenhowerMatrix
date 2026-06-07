import Foundation

/// GitHub API 服务 — 对应 Web 版的 GitHub API 操作
class GitHubService {
    static let shared = GitHubService()

    private let dataFilePath = "eisenhower/data.json"
    private var fileSha: String?
    private var config: GitHubConfig?
    private let lockQueue = DispatchQueue(label: "com.eisenhower.github-lock", attributes: .concurrent)

    private init() {}

    // MARK: - Configuration

    func configure(with config: GitHubConfig) {
        lockQueue.sync(flags: .barrier) {
            self.config = config
        }
    }

    func reset() {
        lockQueue.sync(flags: .barrier) {
            self.config = nil
            self.fileSha = nil
        }
    }

    var isConfigured: Bool {
        lockQueue.sync {
            config?.isValid ?? false
        }
    }

    private func getSha() -> String? {
        lockQueue.sync {
            fileSha
        }
    }

    private func setSha(_ sha: String?) {
        lockQueue.sync(flags: .barrier) {
            fileSha = sha
        }
    }

    private func currentConfig() -> GitHubConfig? {
        lockQueue.sync {
            config
        }
    }

    private func baseURL() -> String {
        guard let parts = currentConfig()?.repoParts else { return "" }
        return "https://api.github.com/repos/\(parts.owner)/\(parts.name)"
    }

    private func contentsURL() -> String {
        return baseURL() + "/contents/" + dataFilePath
    }

    private func headers() -> [String: String] {
        guard let config = currentConfig() else { return [:] }
        return [
            "Authorization": "Bearer \(config.token)",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json"
        ]
    }

    // MARK: - Base64

    private func base64Encode(_ str: String) -> String {
        guard let data = str.data(using: .utf8) else {
            return ""  // UTF-8 编码失败时返回空串，实际场景中极少发生
        }
        return data.base64EncodedString()
    }

    private func base64Decode(_ str: String) -> String? {
        // 清理 base64 字符串：移除换行、空格等
        let cleaned = str.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let data = Data(base64Encoded: cleaned) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - API Requests

    /// 封装 GET 请求，返回 (Data, HTTPStatusCode)
    private func apiGet(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        headers().forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.requestFailed("非 HTTP 响应")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let msg = parseError(status: httpResponse.statusCode, body: body)
            throw GitHubError.requestFailed(msg)
        }
        return (data, httpResponse.statusCode)
    }

    /// 封装 PUT 请求，返回 (Data, HTTPStatusCode)
    private func apiPut(_ url: URL, body: [String: Any]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        headers().forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.requestFailed("非 HTTP 响应")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let status = httpResponse.statusCode
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            let msg = parseError(status: status, body: bodyStr)
            throw GitHubError.requestFailed(msg)
        }
        return (data, httpResponse.statusCode)
    }

    /// 解析错误，格式为 "HTTP {status}: {message}" 或 "HTTP {status}"
    private func parseError(status: Int, body: String) -> String {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String {
            return "HTTP \(status): \(message)"
        }
        return "HTTP \(status)"
    }

    // MARK: - Data Operations

    /// 拉取远端数据文件
    func fetchData() async throws -> PersistedData {
        guard currentConfig() != nil else {
            throw GitHubError.notConfigured
        }
        let config = currentConfig()!
        let branch = config.branch
        let urlStr = contentsURL() + "?ref=\(branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch)"
        guard let url = URL(string: urlStr) else {
            throw GitHubError.invalidURL
        }

        let (data, _) = try await apiGet(url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubError.decodingFailed("GitHub API 返回了非预期的响应格式")
        }

        // 检查是否是错误响应
        if let errorMessage = json["message"] as? String {
            throw GitHubError.requestFailed(errorMessage)
        }

        guard let sha = json["sha"] as? String,
              let content = json["content"] as? String else {
            throw GitHubError.decodingFailed("API 响应中缺少 sha 或 content 字段")
        }

        setSha(sha)

        guard let decoded = base64Decode(content),
              let decodedData = decoded.data(using: .utf8) else {
            throw GitHubError.decodingFailed("base64 解码失败")
        }

        // 使用 JSONSerialization 先验证
        guard let decodedJson = try? JSONSerialization.jsonObject(with: decodedData, options: []) else {
            if let rawStr = String(data: decodedData, encoding: .utf8) {
                throw GitHubError.decodingFailed("JSON 格式无效: \(rawStr.prefix(200))")
            }
            throw GitHubError.decodingFailed("JSON 格式无效")
        }

        // 调试：打印实际的 JSON 键
        if let dict = decodedJson as? [String: Any] {
            print("GitHub 数据键: \(dict.keys.sorted())")
            print("_ts 类型: \(type(of: dict["_ts"]))，值: \(dict["_ts"] ?? "nil")")
        }

        // 使用自定义解码器处理 Web 版数据格式
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let persisted = try decoder.decode(PersistedData.self, from: decodedData)
            return persisted
        } catch let DecodingError.typeMismatch(type, context) {
            throw GitHubError.decodingFailed("类型不匹配 (\(type)): \(context.debugDescription) 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        } catch let DecodingError.valueNotFound(type, context) {
            throw GitHubError.decodingFailed("值未找到 (\(type)): 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        } catch let DecodingError.keyNotFound(key, context) {
            throw GitHubError.decodingFailed("键未找到 (\(key)): 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        } catch let DecodingError.dataCorrupted(context) {
            throw GitHubError.decodingFailed("数据损坏: \(context.debugDescription) 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        } catch let decodeError {
            throw GitHubError.decodingFailed("未知解码错误: \(decodeError)")
        }
    }

    /// 验证仓库访问权限
    func verifyRepo() async throws -> Int {
        guard let url = URL(string: baseURL()) else {
            throw GitHubError.invalidURL
        }
        let (_, statusCode) = try await apiGet(url)
        return statusCode
    }

    /// 验证分支存在
    func verifyBranch() async throws -> Int {
        guard let config = currentConfig(),
              let url = URL(string: baseURL() + "/branches/\(config.branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.branch)") else {
            throw GitHubError.invalidURL
        }
        let (_, statusCode) = try await apiGet(url)
        return statusCode
    }

    /// 确保数据文件存在
    func ensureDataFile() async throws {
        let config = currentConfig()
        let branch = config?.branch ?? "main"
        let urlStr = contentsURL() + "?ref=\(branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch)"
        guard let url = URL(string: urlStr) else {
            throw GitHubError.invalidURL
        }

        do {
            let (data, _) = try await apiGet(url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let sha = json?["sha"] as? String {
                setSha(sha)
            }
        } catch {
            // 文件不存在，创建之
            let defaultData = PersistedData()
            let encoded = try JSONEncoder().encode(defaultData)
            guard let content = String(data: encoded, encoding: .utf8) else {
                throw GitHubError.decodingFailed("编码默认数据失败")
            }
            let body: [String: Any] = [
                "message": "Create \(dataFilePath)",
                "content": base64Encode(content),
                "branch": branch
            ]
            guard let putURL = URL(string: contentsURL()) else { return }
            let (result, _) = try await apiPut(putURL, body: body)
            let json = try JSONSerialization.jsonObject(with: result) as? [String: Any]
            if let contentObj = json?["content"] as? [String: Any],
               let sha = contentObj["sha"] as? String {
                setSha(sha)
            }
        }
    }

    /// 保存数据文件到 GitHub
    func saveData(_ persistedData: PersistedData, message: String = "Update data") async throws {
        guard let config = currentConfig() else {
            throw GitHubError.notConfigured
        }

        let encoded = try JSONEncoder().encode(persistedData)
        guard let content = String(data: encoded, encoding: .utf8) else {
            throw GitHubError.decodingFailed("编码数据失败")
        }
        let encodedContent = base64Encode(content)

        var body: [String: Any] = [
            "message": message,
            "content": encodedContent,
            "branch": config.branch
        ]

        if let sha = getSha() {
            body["sha"] = sha
        } else {
            // 尝试获取最新 SHA
            let branch = config.branch
            let urlStr = contentsURL() + "?ref=\(branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch)"
            if let url = URL(string: urlStr) {
                do {
                    let (data, _) = try await apiGet(url)
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let sha = json?["sha"] as? String {
                        body["sha"] = sha
                    }
                } catch {}
            }
        }

        guard let url = URL(string: contentsURL()) else {
            throw GitHubError.invalidURL
        }

        // 重试一次（冲突时）
        for attempt in 0..<2 {
            do {
                let (result, _) = try await apiPut(url, body: body)
                let json = try JSONSerialization.jsonObject(with: result) as? [String: Any]
                if let contentObj = json?["content"] as? [String: Any],
                   let sha = contentObj["sha"] as? String {
                    setSha(sha)
                }
                return
            } catch {
                if attempt == 0, case .requestFailed(let msg) = error as? GitHubError,
                   msg.contains("is at") && msg.contains("but expected") {
                    // 冲突重试：重新获取 SHA
                    let branch = config.branch
                    let retryUrlStr = contentsURL() + "?ref=\(branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch)"
                    if let retryUrl = URL(string: retryUrlStr) {
                        let (retryData, _) = try await apiGet(retryUrl)
                        let retryJson = try JSONSerialization.jsonObject(with: retryData) as? [String: Any]
                        if let sha = retryJson?["sha"] as? String {
                            body["sha"] = sha
                        }
                    }
                    continue
                }
                throw error
            }
        }
    }
}

// MARK: - Errors

enum GitHubError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case requestFailed(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "GitHub 未配置"
        case .invalidURL: return "无效的 URL"
        case .requestFailed(let msg): return msg
        case .decodingFailed(let msg): return msg
        }
    }
}