# EisenhowerMatrix macOS App — GitHub 连接与同步机制

## 架构概览

macOS App 通过 GitHub Contents API 实现数据云同步，核心涉及 4 个模块：

```
GitHubSettingsView  ── 用户界面（Token / 仓库 / 分支输入）
    │
TaskViewModel       ── 连接流程编排（验证 → 创建文件 → 拉取数据）
    │
GitHubService       ── GitHub API 请求层（GET/PUT、base64 编解码、SHA 冲突重试）
    │
ConfigStorage       ── 配置持久化（Keychain 存 Token、UserDefaults 存 repo/branch）
```

---

## 连接流程

用户在 Preferences 面板输入 Token、仓库名（`owner/repo`）、分支名后，点击"连接"按钮，触发以下四步验证流程：

### Step 1：验证仓库访问权限

```
GET https://api.github.com/repos/{owner}/{name}
Authorization: token {PAT}
```

失败时根据 HTTP 状态码给出中文提示：
- `401` → "Token 无效或已过期"
- `403` → "权限不足，请检查 Token 授权范围"
- `404` → "仓库不存在或 Token 无权限访问此仓库"

> 验证失败会重置 GitHubService 配置（`gitHub.reset()`）。

### Step 2：验证分支存在

```
GET https://api.github.com/repos/{owner}/{name}/branches/{branch}
Authorization: token {PAT}
```

失败时：
- `404` → "分支 xxx 不存在"

> 同样会重置配置。

### Step 3：确保远端数据文件存在

```
GET  https://api.github.com/repos/{owner}/{name}/contents/eisenhower/data.json?ref={branch}
```

如果文件不存在（GET 返回错误），则自动创建：

```
PUT  https://api.github.com/repos/{owner}/{name}/contents/eisenhower/data.json
Body: { "message": "Create eisenhower/data.json", "content": "{base64}", "branch": "{branch}" }
```

> 此步失败**不重置配置**，保留以便用户重试。

### Step 4：拉取远端数据并合并

```
GET  https://api.github.com/repos/{owner}/{name}/contents/eisenhower/data.json?ref={branch}
```

返回 JSON 包含 `sha` 和 `content`（base64 编码）。解码后与本地数据比较时间戳 `_ts`（毫秒级 Int64），取较新的版本。

> 此步失败也**不重置配置**，保留以便用户重试。

---

## 认证方式

使用 **Personal Access Token (PAT)**，通过 HTTP Header 传递：

```
Authorization: token {PAT}
Accept: application/vnd.github.v3+json
Content-Type: application/json
```

建议使用 **Fine-grained token**，仅需授权单个仓库的 **Contents 读写权限**。

### Token 安全存储

- **Token** → macOS Keychain（`SecItemAdd` / `SecItemCopyMatching`）
  - Key 名：`eisenhower_github_token`
  - Service：`com.eisenhower.matrix`
  - Accessible：`kSecAttrAccessibleAfterFirstUnlock`
- **repo / branch** → UserDefaults（`eisenhower_github_config`）
  - Token 字段在 UserDefaults 中**留空**，不存储敏感信息
- Keychain 写入失败时自动回退到 UserDefaults（保证功能可用）

---

## 数据同步机制

### 初始化加载

1. 先加载本地数据（`UserDefaults` → `PersistedData`）
2. 如果已配置 GitHub，异步拉取远端数据
3. 比较 `_ts` 时间戳，取较新的版本

### 保存数据

每次任务变更触发 `debouncedSave()`（0.5 秒防抖）：

1. **立即保存本地** → UserDefaults（保证数据不丢失）
2. **异步同步到 GitHub** → PUT Contents API

### SHA 冲突处理

PUT 请求需要携带文件当前 SHA。冲突时（`"sha is at xxx but expected yyy"`）：

1. 重新 GET 获取最新 SHA
2. 用新 SHA 重新 PUT
3. 最多重试 1 次

---

## 数据格式兼容性

Web 版与 macOS 版共用同一份 `eisenhower/data.json`，但数据类型可能不一致。自定义解码器使用 `try?` 逐级降级处理：

### TaskItem 字段兼容

| 字段 | App 类型 | Web 可能类型 | 处理方式 |
|------|---------|-------------|---------|
| `id` | `String` | `String` / `Int` / `Double` | `try? String` → `try? Int` → `try? Double` → UUID |
| `order` | `Int` | `Int` / `Double` | `try? Int` → `try? Double` → 0 |
| `deletedAt` | `Double?` (秒) | `Double` (秒或毫秒) / `Int` (毫秒) | `try? Double` (>1e12 ÷1000) → `try? Int` (÷1000) → nil |
| `title` / `content` / `quadrant` | `String` | `String` / null | `try? String` ?? 默认值 |
| `done` / `deleted` | `Bool` | `Bool` / null | `try? Bool` ?? 默认值 |
| `originalQuadrant` | `String?` | `String` / null | `try? String` |

> **关键点**：Swift 的 `decodeIfPresent` 在值存在但类型不匹配时**抛出 `DecodingError.typeMismatch`** 而非返回 nil。因此所有多类型兼容解码必须使用 `try?` 而不是 `try`，否则降级分支永远不会执行。

### PersistedData._ts 时间戳兼容

| 来源 | 类型 | 处理方式 |
|------|------|---------|
| Web `Date.now()` | `Int64` (毫秒) | 直接使用 |
| 旧版数据 | `Double` (秒或毫秒) | `try? Double` → ×1000 转毫秒 |
| 32 位整数 | `Int32` | `try? Int32` → 转 Int64 |

### 数据文件路径

固定为 `eisenhower/data.json`（相对于仓库根目录）。

---

## 网络权限与沙盒配置

App 启用 macOS App Sandbox，entitlements 文件声明以下权限：

| 权限 | 说明 |
|------|------|
| `com.apple.security.app-sandbox` | 启用沙盒 |
| `com.apple.security.network.client` | 允许出站网络请求（访问 GitHub API） |
| `com.apple.security.files.user-selected.read-only` | 用户选择的文件只读访问 |

> **如果没有 `network.client` 授权，沙盒会静默拦截所有出站网络请求，这是连接 GitHub 失败的根本原因。**

### ATS 配置

`Info.plist` 中配置了 `NSAppTransportSecurity`：
- `NSAllowsArbitraryLoads = false`（安全优先）
- 为 `github.com` 和 `api.github.com` 巻加 TLS 例外声明
- 最低 TLS 版本：1.2

---

## 错误处理

### 连接阶段错误

| 步骤 | 错误类型 | 处理 |
|------|---------|------|
| 验证仓库 | 401/403/404 | 中文提示 + 重置配置 |
| 验证分支 | 404 | 中文提示 + 重置配置 |
| 创建数据文件 | 任意 | 保留配置，允许重试 |
| 拉取数据 | 任意 | 保留配置，允许重试 |

### 错误信息格式

`GitHubService.parseError()` 输出格式为 `"HTTP {status}: {message}"`，确保 HTTP 状态码始终包含在错误信息中。`TaskViewModel` 通过 `extractStatusCode()` 正则提取状态码，并用 `switch` 分类处理。

### 同步阶段错误

- PUT SHA 冲突 → 自动重试（最多 1 次）
- 同步失败 → Toast 提示"同步失败"，本地数据已保存不丢失

---

## 线程安全

`GitHubService` 中 `config` 和 `fileSha` 为共享可变状态，使用 `DispatchQueue` 保护：

- 读操作 → `lockQueue.sync { }`（并发读）
- 写操作 → `lockQueue.sync(flags: .barrier) { }`（独占写）
- 封装为 `currentConfig()` / `getSha()` / `setSha()` 方法

所有公开方法（`configure` / `reset`）均通过 barrier 写入，确保线程安全。