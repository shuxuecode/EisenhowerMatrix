# 四象限工作法 - 艾森豪威尔矩阵 (Eisenhower Matrix)

一个帮助你按紧急/重要程度管理任务的工具，基于艾森豪威尔矩阵（四象限法）理念。

## 项目结构

```
EisenhowerMatrix/
├── web/                    # Web 版 — 部署到 GitHub Pages
│   ├── index.html          # 入口页面
│   ├── css/style.css       # 样式
│   ├── js/app.js           # 主逻辑
│   ├── image/favicon.png   # 图标
│   └── dev/                # 开发归档
├── mac/                    # macOS 原生客户端 (SwiftUI)
│   ├── EisenhowerMatrix/   # App 源码
│   └── EisenhowerMatrix.xcodeproj/
├── upload.sh               # Git 推送辅助脚本
├── LICENSE                 # MIT 许可证
└── README.md               # 本文件
```

## 各版本使用

### Web 版 (GitHub Pages)

在线访问：配置 GitHub Pages 后直接访问 `https://<username>.github.io/EisenhowerMatrix/`

**GitHub Pages 配置步骤：**
1. 进入仓库 Settings → Pages
2. Source 选择 "Deploy from a branch"
3. Branch 选择 `main`
4. Folder 选择 `/web`
5. 点击 Save

本地开发：直接打开 `web/index.html` 即可使用。

### macOS 原生版

1. 用 Xcode 打开 `mac/EisenhowerMatrix.xcodeproj`
2. 选择目标设备（My Mac）
3. 点击 Run 或 Product → Build

## 功能特性

- ✅ 四象限任务分类（紧急&重要 / 重要不紧急 / 紧急不重要 / 不紧急不重要）
- ✅ 拖拽排序
- ✅ 本地持久化存储
- ✅ GitHub 数据同步（Web 版）
- ✅ 回收站功能
- ✅ 统计卡片
- ✅ macOS 原生菜单栏体验

## License

MIT License — 详见 [LICENSE](LICENSE)