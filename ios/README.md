# 四象限工作法 — iOS 版

iPhone 原生客户端，基于 SwiftUI 开发。

## 开发环境

- Xcode 15+ 
- iOS 16.0+ 目标
- Swift 5.0

## 运行

1. 用 Xcode 打开 `EisenhowerMatrix.xcodeproj`
2. 选择 iPhone 模拟器（如 iPhone 15）
3. 点击 Run 或 Product → Build

## 功能

- ✅ 垂直滚动卡片布局（四个象限可展开/折叠）
- ✅ 任务增删改查
- ✅ GitHub 数据同步
- ✅ 回收站（Sheet 弹出）
- ✅ 统计卡片
- ✅ iOS 原生交互体验

## 项目结构

```
EisenhowerMatrix/
├── EisenhowerMatrixApp.swift     # App 入口
├── Models/Task.swift             # 数据模型（与 macOS/Web 共享）
├── Services/
│   ├── LocalStorageService.swift # 本地存储
│   └── GitHubService.swift       # GitHub API
├── ViewModels/TaskViewModel.swift # 视图模型
├── Views/
│   ├── ContentView.swift         # 主界面
│   ├── QuadrantCardView.swift    # 象限卡片
│   ├── TaskRowView.swift         # 任务行
│   ├── StatsBarView.swift        # 统计栏
│   ├── TrashSheetView.swift      # 回收站 Sheet
│   └── SettingsSheetView.swift   # 设置 Sheet
├── Resources/Info.plist
└── Assets.xcassets/
```