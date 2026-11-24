# UIBoard — Agent Guide

UIBoard 是一个 macOS 小工具：把 App 运行截图上的 UI 问题标成 #1 #2 #3，导出目录交给 Claude / Codex 的 `ui-review` skill 去定位代码并修复。

- 实施计划（唯一事实源）：`docs/plans/2026-09-24-uiboard-impl.md`，动手前先读第 5 节「冻结契约」。
- 视觉稿：`docs/design/A–H*.png`，源码 `docs/design/claude-design/`。
- 以上都在 `docs/` 下，只存本地、不进 git（见「文档」）；新 clone 里没有，契约以 `Model.swift`、`API.swift` 的代码为准。
- 所有回复与文档使用简体中文；代码标识保持英文。

## 构建与验证

每个任务完成后必须全部通过：

```bash
swift build
swift test
scripts/bundle.sh        # 产出 build/UIBoard.app
```

调试运行：`swift run UIBoard`，或直接打开 `build/UIBoard.app`。

安装 / 更新到「应用程序」：`scripts/install-app.sh`（先退出正在运行的 UIBoard；脚本会重新打包并覆盖 `/Applications/UIBoard.app`）。

发布 GitHub Release：`scripts/release.sh 0.2.0`（需先 `gh auth login`，且 HEAD 已推送到 origin/main；产物是 `UIBoard.zip`）。版本号必须是 `X.Y.Z` 且大于当前 Latest，因为 App 内的「Check for Updates…」靠它判断有没有新版。本地打包默认版本号是 `dev`，不参与 App 内更新。改图标：编辑 `assets/AppIcon.svg`，然后运行 `scripts/make-icon.sh`。

## 目录归属（并行 lane）

| 目录 | 归属 |
|---|---|
| `Sources/UIBoardCore/**`、`Tests/**` | Lane Core |
| `Sources/UIBoard/**` | Lane UI |
| `skills/**`、`scripts/install-skill.sh` | Lane Skill |
| `Package.swift`、`Sources/UIBoardCore/Model.swift` | 契约：只在主 checkout 修改，改动前先更新 plan 第 5 节 |
| `Sources/UIBoardCore/API.swift` | 签名是契约，冻结；函数体由 Lane Core 填 |

各 lane 只改自己的目录，只勾 plan 里自己小节的 checkbox。

## 文档（只存本地，不进 git）

`docs/` 整个在 `.gitignore` 里：plan、review、PRD 副本、视觉稿会越积越多，体积持续膨胀，只做本地备份。新文档照常写到下表的位置，不要 `git add -f`，也不要为了能提交挪到别处。

| 文件 | 路径 |
|---|---|
| 实施 plan / 设计 | `docs/plans/YYYY-MM-DD-<topic>.md`，topic 跟事务走，见名知意 |
| review | `docs/reviews/<plan 文件名>-review.md` |
| 飞书 PRD 本地副本 | `docs/feishu-prds/YYYY-MM-DD-<topic>.md`；引用它的 plan 标题下写 `**PRD**: [飞书原文](...) · [本地副本](../feishu-prds/...)` |
| 视觉稿 | `docs/design/` |

- 正文用简体中文，代码标识、命令、路径保留英文。
- 不建 `docs/agents/`、`docs/superpowers/`、根目录 `reviews/` 等其他落点；skill 默认路径一律改到上表。
- `git status` 看不到这些文件是正常的；确认文档已生成用直接读取或 `git check-ignore -v <路径>`。

## 规则

- 不新增第三方依赖。
- `UIBoardCore` 禁止 `import SwiftUI` / `import AppKit`，只用 Foundation / CoreGraphics / CoreText / ImageIO / UniformTypeIdentifiers。
- 不修改 `API.swift` 里的公开签名；Lane Core 只填函数体，可以新增 internal 文件。
- UI 系统控件优先：toolbar、Menu、sheet、alert、Settings Form 都用 SwiftUI 自带控件，图标用 SF Symbols；自定义色用 `NSColor(name:dynamicProvider:)`，禁止 asset catalog（`swift build` 不跑 actool）。
- 测试测行为，禁止读源码文本做断言。
- 未经用户要求不 `git commit`，禁止 `git push`。
