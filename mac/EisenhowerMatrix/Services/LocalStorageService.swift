import Foundation

/// 本地存储服务 — 对应 Web 版的 localStorage 操作
class LocalStorageService {
    static let shared = LocalStorageService()
    private let dataKey = "eisenhower_data"
    private let corruptBackupKey = "eisenhower_data_corrupt_backup"

    private init() {}

    func load() -> PersistedData? {
        guard let data = UserDefaults.standard.data(forKey: dataKey) else { return nil }
        do {
            return try JSONDecoder().decode(PersistedData.self, from: data)
        } catch {
            UserDefaults.standard.set(data, forKey: corruptBackupKey)
            print("本地数据解析失败，原始数据已备份: \(error)")
            return nil
        }
    }

    func save(_ data: PersistedData) {
        do {
            let encoded = try JSONEncoder().encode(data)
            UserDefaults.standard.set(encoded, forKey: dataKey)
        } catch {
            print("保存本地数据失败: \(error)")
        }
    }

    func remove() {
        UserDefaults.standard.removeObject(forKey: dataKey)
    }
}

/// GitHub 配置存储 — 全部使用 UserDefaults
class ConfigStorage {
    static let shared = ConfigStorage()
    private let configKey = "eisenhower_github_config"

    private init() {}

    func load() -> GitHubConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(GitHubConfig.self, from: data) else {
            return GitHubConfig()
        }
        return config
    }

    func save(_ config: GitHubConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
}