# UIBoard V1 实施计划

**产品基线**: [原始方案](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-24-uiboard-product.md) · **原型 Prompt**: [Claude Design](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-24-uiboard-design-prompt.md)

状态：plan 待确认。仓库 `/Users/loopq/dev/git/loopq/uiboard`（已 `git init`，无提交）。本文件自包含：契约、任务、验收、Skill 规格全部内联；产品基线只作为背景，凡与本文件冲突以本文件为准。

## 1. 核心判断

✅ 值得做。核心价值不在「能标注」，而在 **App → Skill 之间那份数据**：它决定 AI 能不能把 #N 精确落到仓库里的模块文件。

- 数据结构：一次 Review = 一张 runtime 截图 + 一组 `Mark{rect, note}` + 可选的设备事实（density / activity / 视图树）。坐标是一切下游能力（原分辨率裁图、px→dp、视图树命中 → view id → 文件）的根。
- 复杂度：三种标注工具收敛成一种数据（rect，零尺寸即 Pin）；Ref A/B 槽位收敛成列表；屏幕预览与导出共用同一个渲染器。
- 风险点：最大的风险是「AI 拿到目录能否定位并修对」，所以 T0 先用手工目录把 Skill 跑通，再开并行开发。

## 2. 相对原始方案的决策变更

| 原始方案 | 本计划 | 原因 |
|---|---|---|
| review.md 只有 #N + 描述，无坐标 | 每个 #N 带 `rect`（px）、`dp`、`crop`、`views` | 模型会下采样截图、标注会遮挡目标；坐标让裁图 / dp 换算 / view 命中都变成确定计算 |
| Pin / Rectangle / Arrow 三工具 | 单工具：点击 = Pin，拖拽 = 框；删除 Arrow | 数据统一为 rect；零工具切换；Arrow 的方向歧义彻底消失 |
| Ref A / Ref B 两个固定槽 | `refs` 列表，导出 `ref-1.png…` | 消除「只有一张就只存 A」的特殊情况 |
| App 不碰代码上下文 | ADB 截图时额外记录 density / 前台 Activity / uiautomator 视图树，App 做坐标命中测试 | App 仍不索引代码，只在唯一可能的时刻记录运行时事实；全部可选、失败不阻塞 |
| ⌘V 语义未定义 | 文本框聚焦 → 粘贴文本；无 runtime → 设为 runtime；已有 runtime → 追加为 ref | 一个手势三个去处必须定死 |
| Skill 按 #1#2#3 直接改代码 | Skill 先产出「关联表 + plan」，遵守目标仓库 plan-first 与编译验证规则 | 与 Avatar-Android 仓库工作流一致 |
| Skill 放 `/ui-review` | 单一源在本仓 `skills/ui-review/`，symlink 到 `~/.claude/skills` 与 `~/.codex/skills` | Claude `/ui-review`、Codex `$ui-review` 共用一份，避免两份副本漂移 |
| Phase 6 才做 Skill | T0 先用手工 review 目录验证 Skill | 最大风险前置；契约冻结后 Codex / Claude 才能并行 |
| History 保留 | 保留只读 History，放最后 | 用户决策 |

## 3. 端到端工作流与断点防护

```text
设备 ──adb──▶ App 截图 ──▶ 标注/描述/参考 ──▶ 原子导出 ──Copy Path──▶ Claude /ui-review | Codex $ui-review
                                                                         │
                     Avatar-Android 仓库 ◀── 关联表 + plan ◀── 读取 review 目录（只读）
                                                                         │
                             编译验证 ──▶ 真机复验 ──▶ 重新截图导出新 review（不回写旧目录）
```

| 环节 | 断点 | 防护（落在哪个任务） |
|---|---|---|
| 设备 → App | Finder 启动的 GUI App 没有 shell PATH，找不到 `adb` | 按顺序探测：设置项覆盖 → `$ANDROID_HOME/platform-tools/adb` → `~/Library/Android/sdk/platform-tools/adb` → `/opt/homebrew/bin/adb` → `/usr/local/bin/adb`；都没有时弹窗引导设置（C2 / U3） |
| 设备 → App | App Sandbox 阻止 `Process` 调用与写 `~/UIReview` | SwiftPM 打包、不带 entitlements，天然非沙盒（T0） |
| 设备 → App | `screencap` 输出数 MB，先 `waitUntilExit` 后读管道会死锁 | 进程封装先并发读完 stdout/stderr 再等退出，带超时 kill（C2） |
| 设备 → App | 设备 `unauthorized` / `offline`、记住的 serial 不在线 | 设备菜单显示状态并禁用；serial 不在线时不自动切换，单设备且无记忆时自动选中（U3） |
| 截图 → 标注 | 新截图 / 粘贴 / 拖入静默覆盖已有标注 | 已有标注时替换 runtime 必须确认（U2） |
| 截图 → 标注 | 在描述框里 ⌘V 被当成粘贴图片 | 本地事件监听：first responder 是文本编辑器时放行（U2） |
| 标注 → 导出 | 描述为空的 #N 交给 AI 无意义 | 有空描述时阻止导出，并聚焦第一张空卡片（U3） |
| 标注 → 导出 | 写到一半的目录被 History / Skill 读到 | 先写 `.HH-mm-ss.tmp/` 再 rename；History 忽略点目录（C1 / C3） |
| 标注 → 导出 | 同一秒导出两次 | 目录名冲突时追加 `-2`、`-3`（C1） |
| 导出 → AI | Codex 触发语法是 `$ui-review`，不是 `/ui-review`；两份 Skill 副本会漂移 | 单一源 + `scripts/install-skill.sh` 同时 symlink 两处（T0.5） |
| 导出 → AI | 自定义工作目录含空格时路径传参出错 | Skill 接受带引号路径；设置项提示路径不宜含空格（S1 / U1） |
| AI → 代码 | 动画页 `uiautomator dump` 拿不到 idle；Compose 默认无 resource-id | `views` 缺失时 Skill 自动降级到 activity + 可见文案 + 视觉搜索，并标注置信度（S1） |
| AI → 代码 | 目标仓库要求先出 plan、编译验证 | Skill 读取目标仓库 AGENTS.md / CLAUDE.md，按其文档路由写 plan，停下等确认（S1） |
| 复验 | 修完后怎么回到 review | review 目录永远只读；plan 头部链接 review 路径；复验 = 重新截图导出一份新 review |

## 4. 工程结构与技术选型

- SwiftUI + Swift Package Manager，`swift-tools-version:5.10`（Swift 5 语言模式，避开 Swift 6 严格并发给 agent 带来的噪音），`platforms: [.macOS(.v14)]`，用 `@Observable`。
- 不用 Xcode 工程：`.pbxproj` 对 agent 不可靠；SwiftPM 纯文本，`swift build` 对 Codex / Claude 一致可跑。本机 Xcode 16.3 / Swift 6.1 已验证存在。
- 无第三方依赖。XML 用 Foundation `XMLParser`，图片用 ImageIO / CoreGraphics / CoreText，剪贴板与 Finder 用 AppKit。

```text
uiboard/
├── Package.swift
├── AGENTS.md                      # Codex / Claude 共同入口（构建命令、lane 归属、规则）
├── CLAUDE.md -> AGENTS.md
├── Sources/
│   ├── UIBoardCore/               # 纯逻辑，不 import SwiftUI/AppKit；Lane Core 独占
│   │   ├── Model.swift            # Mark / DeviceFacts / Review / AdbDevice / ViewHit
│   │   ├── ImageIngest.swift      # 任意图片 Data ↔ CGImage / PNG
│   │   ├── AnnotationRenderer.swift
│   │   ├── Crop.swift
│   │   ├── ReviewMarkdown.swift
│   │   ├── ReviewExporter.swift   # 原子导出
│   │   ├── ProcessRunner.swift    # 无死锁 + 超时
│   │   ├── Adb.swift              # 定位 / 设备 / 截图 / 事实
│   │   ├── HitTest.swift
│   │   └── HistoryScanner.swift
│   └── UIBoard/                   # SwiftUI App；Lane UI 独占
├── Tests/UIBoardCoreTests/
│   └── Fixtures/                  # golden review.md、adb 原始输出、hierarchy.xml
├── skills/ui-review/              # Skill 唯一源
│   ├── SKILL.md
│   ├── agents/openai.yaml
│   └── references/review-format.md
├── scripts/
│   ├── bundle.sh                  # 打包 build/UIBoard.app
│   └── install-skill.sh
└── docs/plans/ · docs/design/
```

- 验证闭环（等同 Android 的 `assembleNekuDebug`）：每个任务完成后必须 `swift build && swift test && scripts/bundle.sh` 全部通过。
- SwiftPM 可执行 SwiftUI App 的已知坑：`swift run` 启动时需在 App `init` 里 `NSApplication.shared.setActivationPolicy(.regular)` 并激活，否则无窗口焦点、无菜单栏。`swift run` 与 `.app` 的 UserDefaults 域不同（可执行名 vs bundle id），调试时知悉即可。

## 5. 冻结契约（T0 产出，之后各 lane 只读）

### 5.1 数据模型（`Sources/UIBoardCore/Model.swift`，已落地，以代码为准）

- `Mark { rect: CGRect, note }`：runtime.png 像素坐标，原点左上；`rect.size == .zero` 即 Pin（`isPin`）。
- `DeviceFacts { serial, model?, densityDpi?, activity?, hierarchyXML? }`：仅 ADB 来源；`activity` 原样保留 dumpsys 的 component。
- `Review { runtime: CGImage, facts?, marks, refs: [CGImage], figmaURL }`：像素尺寸由 `runtime` 派生（`pixelSize`）。
- `AdbDevice { id(serial), model?, state }`、`ViewHit { resourceId, className, bounds }`、`HistoryDay { date, items: [HistoryItem { time, dir }] }`。
- `Palette.rgb(at:)`：编号颜色循环，UI 卡片与渲染器共用。
- `UIBoardError`：带 `errorDescription`，UI 直接展示。

编号与颜色不存储，永远由下标派生：删除 #2 后原 #3 自动变 #2，没有「重新编号」逻辑。

### 5.2 Core 公开 API（T0 写签名 + 占位实现，Lane Core 只填函数体、不改签名）

```swift
public enum ImageIngest {
    public static func decode(_ data: Data) throws -> CGImage
    public static func png(_ image: CGImage) throws -> Data
}
public enum AnnotationRenderer { public static func render(runtime: CGImage, marks: [Mark], highlight: Int?) -> CGImage? }
public enum Crop { public static func rect(for mark: Mark, in size: CGSize) -> CGRect }
public enum ReviewMarkdown { public static func render(_ review: Review, created: Date, hits: [[ViewHit]]) -> String }
public enum ReviewExporter { public static func export(_ review: Review, workspace: URL, now: Date) throws -> URL }
public enum HitTest { public static func views(for rect: CGRect, hierarchyXML: Data) -> [ViewHit] }
public struct Adb {
    public static func locate(override: String?) -> URL?
    public init(executable: URL)
    public func devices() async throws -> [AdbDevice]
    public func screencap(serial: String) async throws -> Data
    public func facts(serial: String, model: String?) async -> DeviceFacts
}
public enum HistoryScanner { public static func scan(workspace: URL) -> [HistoryDay] }   // HistoryDay / HistoryItem 见 Model.swift
```

### 5.3 导出目录

```text
<workspace，默认 ~/UIReview>/YYYY-MM-DD/HH-mm-ss/
├── review.md          # 入口
├── runtime.png        # 原图，无标记
├── annotated.png      # 原分辨率 + 标记，无长文字
├── crops/1.png …      # 每个 #N 一张，原分辨率，从 runtime 裁（无标记）
├── ref-1.png …        # 可选
└── hierarchy.xml      # 可选，仅 ADB 且 dump 成功
```

- 本地时间命名。先写到同级 `.HH-mm-ss.tmp/`，全部成功后 `moveItem` 为正式名；冲突追加 `-2`、`-3`。失败时删除 tmp 目录并抛错。
- 所有输入图片进入 App 时统一用 `ImageIngest.decode` 解码成 `CGImage`，导出时统一用 `ImageIngest.png` 编码。内存里只有一种表示，导出只有一条路径；UI 只解码一次，拖拽预览不会每帧重新解码。

### 5.4 review.md 格式 v1（同时落地为 `skills/ui-review/references/review-format.md`）

```markdown
---
format: uiboard-review/1
created: 2026-09-24T18:15:42+08:00
image: runtime.png
size: 1080x2400
source: adb
device: Pixel 7 (37091JEHN)
density: 420
activity: com.stickermobi.avatarmaker/.ui.task.TaskCenterActivity
figma: https://www.figma.com/design/xxx?node-id=128-22976
refs: [ref-1.png, ref-2.png]
---

# UI Review

## #1

- rect: 96,412,888,180
- dp: 36.6,157.0,338.3,68.6
- crop: crops/1.png @ 0,304
- views: com.stickermobi.avatarmaker:id/rewards_tab [TextView 96,400,444,192] · com.stickermobi.avatarmaker:id/bonus_tab [TextView 540,400,444,192]

黄色选中态应比紫色底更高，以设计稿为准。

## #2

- rect: 540,1200,0,0
- dp: 205.7,457.1,0,0
- crop: crops/2.png @ 432,1092

这个 icon 比设计稿明显偏大。
```

字段规则（写一次，全体适用）：

- 没有值的字段整行省略，不写空值。`source: adb` 只在有设备事实时出现；粘贴 / 拖入 / 打开文件的截图没有 `source` / `device` / `density` / `activity` / `dp` / `views` 这些行。
- `rect: x,y,w,h`：runtime.png 像素，原点左上，整数；`w=h=0` 表示 Pin（点）。
- `dp`：`px × 160 / density`，四舍五入保留 1 位小数，整数也写成 `157.0` / `0.0`。
- `crop: 路径 @ ox,oy`：`ox,oy` 是 crop 左上角在 runtime 中的像素坐标。
- `views`：最多 3 个，按命中度降序，`resource-id [类名 x,y,w,h]`，用 ` · ` 分隔；类名取 `class` 最后一个 `.` 之后的部分；bounds 同为 runtime 像素。
- `device`：`型号 (serial)`，型号取 `adb devices -l` 的 `model:`，下划线转空格；没有型号时只写 serial。
- `created`：本地时区 ISO 8601，带偏移，如 `2026-09-24T18:15:42+08:00`。
- frontmatter 行顺序固定：`format, created, image, size, source, device, density, activity, figma, refs`。文件以换行结尾。
- 描述是 `## #N` 下方元数据列表之后的全部正文，原样输出，不做转义。
- `format` 主版本变化 = 破坏性变更，Skill 遇到不认识的主版本必须停下。

### 5.5 渲染常量（W = 图片像素宽；屏幕预览与导出共用 `AnnotationRenderer`）

| 元素 | 规则 |
|---|---|
| 线宽 s | `max(3, round(W × 0.004))`（1080 → 4px） |
| 编号徽标 | 直径 `d = round(W × 0.05)`（1080 → 54px），填充 palette 色，白色描边 s，白色粗体数字，字号 `round(0.52d)`（1080 → 28px） |
| 框 | palette 色描边 s；徽标圆心放在框左上角 |
| Pin | 圆环半径 `round(W × 0.012)`，描边 s；徽标圆心在 `(x + o, y − o)`，`o = round(W × 0.089)`（1080 → 96px）；引线线宽 `max(2, round(0.75s))`（1080 → 3px），从圆环边缘连到徽标 |
| 越界 | 徽标圆心 clamp 到 `[d/2, W − d/2] × [d/2, H − d/2]`，引线随之变短，不做翻转分支 |
| 选中高亮 | 仅屏幕预览：`highlight` 对应标记的描边与引线线宽 ×2；导出传 `nil` |
| palette | `#FF3B30` `#0A84FF` `#AF52DE` `#FF9500` `#34C759` `#FF2D55` 循环 |
| 描边对齐 | 以路径为中心（CoreGraphics 默认）。正式稿的 CSS 描边画在内侧，两者差 s/2 像素，忽略 |

以上常量已和 Claude Design 正式稿（`docs/design/claude-design/PhoneShot.dc.html`）核对一致。Pin 偏移、引线线宽、编号字号三项按正式稿修订过：偏移 54px 时引线只剩约 36px，几乎看不见。

### 5.6 裁图规则

`pad = round(0.1 × W)`；`crop = rect.insetBy(-pad, -pad) ∩ 图片边界`。Pin 的 rect 零尺寸，自然得到 `2pad` 正方形，不需要分支。

### 5.7 命中测试

```text
q = rect 为零尺寸 ? 以该点为中心的 2×2 rect : rect
候选 = hierarchy 中 resource-id 非空、不以 "android:id/" 开头、bounds 面积 > 0、且与 q 相交的节点
score = area(q ∩ b) / area(q ∪ b)
按 score 降序；score 相同则面积小者优先；再相同按 hierarchy 文档顺序；取前 3
```

Pin 用 2×2 rect 后，IoU 自动偏向包含该点的最小节点，与框共用一条路径。uiautomator 的 `bounds="[x1,y1][x2,y2]"` 转为 `x,y,w,h`。

### 5.8 ADB 命令表

| 用途 | 命令 | 解析 | 超时 | 失败处理 |
|---|---|---|---|---|
| 设备列表 | `adb devices -l` | 跳过首行；`serial state k:v…`，`model:` 取型号 | 5s | 报错提示 |
| 截图 | `adb -s S exec-out screencap -p` | 校验 PNG 签名 `89 50 4E 47` | 10s | 报错，不替换当前截图 |
| density | `adb -s S shell wm density` | 优先 `Override density: N`，否则 `Physical density: N` | 3s | 省略字段 |
| activity | `adb -s S shell "dumpsys activity activities \| grep -E 'topResumedActivity\|mResumedActivity'"` | 首行中含 `/` 的 token | 5s | 省略字段 |
| 视图树 | `adb -s S exec-out uiautomator dump /dev/tty` | 截取到 `</hierarchy>` 为止（丢弃尾部 `UI hierchary dumped to…`） | 8s | 省略字段 |

截图先行（它是事实本体），事实在截图完成后后台并发抓取；导出时等待事实任务结束（受上述超时约束）。

## 6. Codex / Claude 并行方式

- T0 串行，在主 checkout 由 Claude 完成（契约设计 + 真机 spike 需要和用户交互）。
- T0 验收通过后，用 `/create-worktree` 开两个 worktree，两个 agent 同时跑：

| Lane | 执行者 | 独占目录 | 任务 |
|---|---|---|---|
| Core | Codex（`codex` CLI 在 worktree 内执行） | `Sources/UIBoardCore/**`、`Tests/**` | C1–C3 |
| UI | Claude | `Sources/UIBoard/**`、`docs/design/**` | U1–U4 |
| Skill | Claude（UI lane 空档或集成阶段） | `skills/**`、`scripts/install-skill.sh` | S1 |

- 接口 = 5.1 / 5.2 的签名。UI lane 面对 T0 的占位实现编译；任何一方需要改签名，停下回到主 checkout 改契约，不在 lane 内私改。
- 本 plan 文件入库。各 lane 只勾自己小节的 checkbox，不同 hunk 互不冲突，`/apply-worktree` cherry-pick 可干净合入。
- worktree 模型需要在 lane 分支内提交才能 apply；lane 开始前由用户授权该分支内提交。提交信息：`Core > 做了什么` / `UI > 做了什么` / `Skill > 做了什么`。

## 7. 任务

### T0 基础与契约验证（串行，Claude，主 checkout）

- [x] T0.1 工程骨架：`Package.swift`（`UIBoardCore` library、`UIBoard` executable、`UIBoardCoreTests`）、`.gitignore`（`.build/`、`build/`、`.DS_Store`）、`AGENTS.md`（构建命令、第 4 节验证闭环、第 6 节 lane 归属、「不新增第三方依赖」「不 import SwiftUI/AppKit 进 Core」）、`CLAUDE.md -> AGENTS.md` symlink。
- [x] T0.2 写 5.1 模型与 5.2 全部签名；函数体为占位（抛 `UIBoardError.notImplemented` 或返回空）。`swift build` 通过。
- [x] T0.3 `scripts/bundle.sh`：`swift build -c release` → 组装 `build/UIBoard.app`（`Contents/MacOS/UIBoard` + `Info.plist`：`CFBundleIdentifier=com.loopq.uiboard`、`CFBundleExecutable=UIBoard`、`CFBundlePackageType=APPL`、`LSMinimumSystemVersion=14.0`、`NSHighResolutionCapable=true`）→ `codesign --force -s - build/UIBoard.app`。不写 entitlements（非沙盒）。
- [ ] T0.4 真机 spike（需用户连一台设备，在 Avatar-Android 上操作；等设备期间 C2 先用 `Fixtures/adb/` 下的合成样例，spike 后用真实输出替换并补测）：
  - 在 TaskCenter（普通 XML 页）、静态编辑器、Spine 编辑器（持续动画）三个页面分别执行 5.8 全部命令，记录耗时与成败。
  - 验证 `uiautomator` bounds 与 `screencap` 像素坐标系一致（取一个已知 view，比对 bounds 与截图上位置）。
  - 原始输出存入 `Tests/UIBoardCoreTests/Fixtures/adb/`（`devices-l.txt`、`wm-density.txt`、`dumpsys-activity.txt`、`uiautomator-*.xml`），供 C2 做解析测试。
  - 结论写回本节下方「spike 记录」。
- [x] T0.5 契约落地 + Skill v0：
  - `skills/ui-review/references/review-format.md` = 5.4–5.7 原文。
  - `skills/ui-review/SKILL.md` 与 `agents/openai.yaml` 按第 8 节写入。
  - `scripts/install-skill.sh` 按第 8 节写入并执行；确认 `~/.claude/skills/ui-review`、`~/.codex/skills/ui-review` 均为指向本仓的 symlink。
  - `Tests/UIBoardCoreTests/Fixtures/golden-review.md`：与 5.4 示例同构的标准样例（C1 的 golden 测试对照它）。
- [ ] T0.6 手工 review 目录 + 双 agent 试跑（最大风险验证）：
  - 用户在 Avatar-Android 上挑一个真实 UI 问题页面（至少 3 个 #N，其中 1 个用 Pin），agent 用 T0.4 的命令抓 `runtime.png` / `hierarchy.xml` / density / activity，按用户指定的坐标手写 `review.md` 与 `crops/`，放到 `~/UIReview/YYYY-MM-DD/HH-mm-ss/`。
  - 在 Avatar-Android 目录分别执行 Claude `/ui-review <path>` 与 Codex `$ui-review <path>`，只看关联表，不让其改代码。
  - 通过标准：有 `views` 的 #N，两家都关联到正确的 layout 文件与引用类；无 `views` 的 #N 至少一家给出正确文件或诚实标注「推测」。不通过 → 回改 5.4 格式或 Skill，再测，通过前不开 lane。

门槛调整（2026-09-28）：没有设备时 T0.4 / T0.6 不阻塞 lane。若 T0.6 试跑后需要改格式，C1 只需跟改 `ReviewMarkdown` 与 golden，成本可控。

T0 记录：
- `swift build` / `swift test` / `scripts/bundle.sh` 通过，产出 `build/UIBoard.app`（ad-hoc 签名）。
- `scripts/install-skill.sh` 已执行：`~/.claude/skills/ui-review`、`~/.codex/skills/ui-review` 均为指向本仓的 symlink。
- golden：`Fixtures/golden-input.json`（输入）+ `golden-hierarchy.xml` → 期望 `golden-review.md`（3 个 #N：框命中 3 个 view、Pin 命中最小节点、Pin 无命中不输出 views）。
- remote：`git@github.com:loopq/UIBoard.git`。

spike 记录：（T0.4 / T0.6 完成后填写）

### Lane Core（Codex，worktree）

- [ ] C1 导出链路（`ImageIngest` / `AnnotationRenderer` / `Crop` / `ReviewMarkdown` / `ReviewExporter`）：
  - `decode`：ImageIO 解码任意 PNG / JPG / TIFF / HEIC，解码失败抛错；`png`：ImageIO 编码 PNG。
  - 渲染严格按 5.5；输出像素尺寸 = runtime 尺寸。
  - 导出严格按 5.3；`hits` 由 `HitTest` 按 mark 计算后传入 markdown。
  - 测试（行为，不测源码文本）：markdown 与 `golden-review.md` 逐字一致；`facts == nil` 时不输出 `source/device/density/activity/dp/views` 行；无 figma / 无 refs 时对应 frontmatter 行消失；crop 在四角边界被正确 clamp、Pin 得到 `2pad` 正方形；渲染输出尺寸等于输入；导出后目录内容完整、无残留 `.tmp` 目录；同秒二次导出得到 `-2`；导出中途失败（不可写目录）不留下正式目录。
- [ ] C2 ADB 与命中测试（`ProcessRunner` / `Adb` / `HitTest`）：
  - `ProcessRunner.run(executable:args:timeout:) async throws -> (stdout: Data, stderr: Data, status: Int32)`：先并发读尽两个管道再等退出；超时 `terminate` 并抛超时错误。
  - `Adb.locate` 按第 3 节顺序探测，检查 `isExecutableFile`。
  - 解析函数全部为纯函数，输入 T0.4 fixture。
  - 测试：`devices -l` 解析出 serial / model / state（含 unauthorized、offline）；density 优先 Override；activity 从 dumpsys 行取出 component；uiautomator 输出去尾；`HitTest` 在 fixture 上对一个已知框返回正确 resource-id 排第一、Pin 返回包含该点的最小节点、`android:id/*` 被排除；`ProcessRunner` 对产生 > 1MB 输出的命令（如 `head -c 2000000 /dev/zero`）不死锁、对 `sleep 5` 在 1s 超时。
- [ ] C3 `HistoryScanner`：扫描 `workspace/YYYY-MM-DD/HH-mm-ss*`，要求目录内存在 `review.md`，忽略点目录与不匹配命名的目录，日期降序、时间降序。测试用临时目录构造正常 / 点目录 / 缺 review.md / 非法命名四种情况。

### Lane UI（Claude，worktree）

视觉以 `docs/design/A-*.png` … `H-*.png` 正式稿为准，源码在 `docs/design/claude-design/`（重新渲染：`python3 docs/design/claude-design/render.py`）。`docs/design/prototype/` 是早期原型，已被正式稿取代，仅作历史参考。标注几何一律以第 5.5 节为准。

**系统控件优先**：系统已有的控件一律用系统的，不照着设计稿像素自己画：
- toolbar 用 `.toolbar`；设备选择用 `Menu`（两行副标题系统不支持时，退化为单行 `Pixel 7 · 37091JEHN`，不自绘菜单）；
- 导出成功用 `.sheet`，替换确认用 `.alert` + `role: .destructive`，设置页用 `Settings` scene + `Form` + `.formStyle(.grouped)`；
- 按钮用 `.bordered` / `.borderedProminent`，图标一律用 SF Symbols（`iphone`、`camera.viewfinder`、`square.and.arrow.down`、`clock`、`square.and.arrow.up`、`link`、`photo`、`cursorarrow.click`、`checkmark.circle.fill`、`doc.on.doc`、`folder`、`arrow.clockwise`、`exclamationmark.triangle.fill`）。

下表的数值只用于自绘的界面：画布、Issue 卡片、References 条、Figma 输入框、空状态、History 网格。

颜色：能用系统语义色的直接用（文字 `.primary` / `.secondary` / `tertiaryLabelColor`，分隔线 `separatorColor`，输入框底色 `textBackgroundColor`，强调色 `Color.accentColor`）；其余自定义色用 `NSColor(name:dynamicProvider:)` 做成深浅色动态色。**不要用 asset catalog**：`swift build` 不跑 actool，编不进去。

| 自定义色 | 浅色 | 深色 |
|---|---|---|
| canvas | `#ECECEC` | `#1E1E1E` |
| panel（右侧检查器） | `#F6F6F6` | `#262626` |
| card | `#FFFFFF` | `#2E2E2E` |
| cardline | 黑 8% | 白 7% |
| selbg（选中卡片） | `#EAF3FF` | `#0A84FF` 16% |
| ctrl（计数胶囊底） | 黑 5% | 白 8% |
| dash（虚线框） | 黑 22% | 白 22% |
| shotline（截图描边） | 黑 12% | 白 14% |

| 区域 | 数值（pt） |
|---|---|
| 右侧检查器 | 宽 340，左分隔线 1；内边距 16 |
| Issues 标题 | 13 semibold；计数胶囊高 16、最小宽 18、11 medium、secondary 文字、ctrl 底 |
| Issue 卡片 | 列表间距 8，距标题 12；卡片内边距 12（右侧 28 给 ×），圆角 8，1pt cardline 描边，card 底；选中时 selbg 底 + 1pt accent 描边 |
| 卡片编号 | 20 圆，11 bold 白字，palette 色 |
| 卡片描述 | 行高 20，最小高 40；删除 × 图标 9，点击区 16，距右 8、距上 10 |
| References | 顶部分隔线；标题 11 semibold secondary + 计数胶囊；缩略图 64×142，圆角 4，1pt shotline；间距 8；添加格为 1pt dash 虚线、圆角 4，`plus` 16 |
| Figma 输入框 | 高 28，距上 12，圆角 6，1pt 分隔线色描边，左右内边距 8，`link` 13 + 间距 6；占位文字 tertiary |
| 画布 | canvas 底；截图按比例 fit、居中，1pt shotline 描边 |
| 空状态拖放区 | 440×560，2pt dash 虚线，圆角 16；`photo` 48；标题 15 semibold，距图标 16；快捷键键帽高 20、圆角 4、12pt、card 底 + cardline 描边 |
| 检查器空状态 | `cursorarrow.click` 22 + secondary 文字 `Click to pin · Drag to frame`，居中 |
| 导出成功 sheet | 宽 440，内边距 20；`checkmark.circle.fill` 32 绿色；标题 bold，距图标 12；路径框高 28、SF Mono 12、可选中，距标题 8；按钮区距路径框 20，右对齐，间距 8 |
| History | 窗口 900×640，内边距 24；日期组间距 32；日期 13 bold + 计数胶囊；网格间距 24，距日期 12；缩略图 120×267，圆角 6，1pt 描边；hover 时改为 2pt accent 描边，右上角内缩 6 处浮出两个 24pt 圆形按钮（白 96% 底 + 轻阴影，图标 13）；时间 11 secondary |
| Settings | 560×260，内边距 24；标签列宽 80；路径 SF Mono 12；`Auto-detected` 标签 11 medium，文字 `#1E8A3C`，底色 `#34C759` 15%，圆角 4；表单下方说明 11 secondary，距表单 8 |

- [ ] U1 App 外壳：`@main` App、主窗口（默认 1280×820）、统一 toolbar、`@Observable EditorModel`、空状态拖放区、Settings（⌘,）：workspace 目录（默认 `~/UIReview`，选择面板）、adb 路径覆盖；菜单「打开 UIReview 文件夹」。激活策略按第 4 节。
- [ ] U2 编辑器：
  - 画布显示 `AnnotationRenderer.render(..., highlight: selected)` 的结果，按比例 fit；视图坐标 ↔ 图片像素换算集中在一个函数。
  - 鼠标：位移 < 4pt 视为点击 → Pin；否则拖拽 → 框；拖拽中把「进行中的框」作为临时 mark 交给同一渲染器预览。画布点击永远新建标记，**画布上不做选中/拖动**（避免与「在框内再点 Pin」冲突）。
  - 新增 mark 后右侧自动出现卡片并聚焦其描述框。卡片：彩色编号徽标 + 多行描述 + × 删除；点卡片 = 选中（画布高亮）；选中后 ⌫（非编辑态）删除。
  - 输入规则：拖到画布 → runtime；拖到 References 区 → ref；⌘O → runtime；⌘V 按第 2 节规则，用 `NSEvent.addLocalMonitorForEvents(.keyDown)` 判断 first responder 是否为 `NSText`，是则放行；追加 ref 时给轻提示。
  - 已有标记时替换 runtime（截图 / 拖入 / ⌘O / ⌘N）弹确认「将清空 N 个标注」。
  - 右侧底部：References 缩略图条（+ 选择文件、拖入、hover ×）；Figma URL 单行输入（trim）。
- [ ] U3 设备、截图、导出：
  - toolbar 设备 `Menu`：列出设备与状态（非 `device` 状态禁用）、Refresh（⌘R）；启动时读一次；UserDefaults 记住 `lastDeviceSerial`；记住的设备不在线时不自动切换；无记忆且只有一台在线时自动选中。
  - Capture（⌘⇧A）：`screencap` → `decode` → 进入编辑器；随后后台抓 `facts`，toolbar 显示小进度。adb 未找到时弹窗引导去 Settings。
  - Export（⌘E）：无 runtime 或无 mark 时禁用；存在空描述时阻止并聚焦第一张空卡片；等待事实任务结束后调用 `ReviewExporter.export`；成功 sheet 显示路径，按钮 `Copy Path`（默认，⏎）与 `Reveal in Finder`；失败显示错误原文。导出后保留当前内容，⌘N 新建。
- [ ] U4 History 窗口（⌘Y，独立 `Window` scene）：`HistoryScanner` 结果按日期分组；缩略图用 `CGImageSourceCreateThumbnailAtIndex` 读 `annotated.png`；显示时间；每项 `Copy Path` / `Reveal in Finder` / 双击用默认应用打开 `annotated.png`。窗口出现时重新扫描。只读。

### Lane Skill

- [ ] S1 Skill 定稿：根据 T0.6 暴露的问题修订第 8 节内容；在集成后用 App 真实导出的目录再跑一次 Claude 与 Codex。

### 集成

- [ ] I1 `/apply-worktree` 合回 Core 与 UI lane；在主 checkout 跑 `swift build && swift test && scripts/bundle.sh`。
- [ ] I2 端到端：Finder 双击 `build/UIBoard.app`（验证 GUI 环境下 adb 探测）→ 连接设备 → ⌘⇧A → 标 3 个问题（含 Pin）→ 加 1 张 Figma 复制的 ref（⌘V）→ 填 Figma URL → ⌘E → Copy Path → 在 Avatar-Android 分别跑 Claude `/ui-review` 与 Codex `$ui-review`，得到关联表与 plan。

## 8. Skill 规格

### `skills/ui-review/SKILL.md`

```markdown
---
name: ui-review
description: 读取 UIBoard 导出的 UI Review 目录（形如 ~/UIReview/YYYY-MM-DD/HH-mm-ss，含 review.md 且 format 为 uiboard-review/1），把每个 #N 问题关联到当前仓库的模块文件（Activity / Fragment / layout / view id），先产出关联表与修复 plan，确认后再改代码。触发：/ui-review <path>、$ui-review <path>，或用户贴出 UIReview 目录路径要求修 UI。
---

# UI Review → 模块文件关联与修复

## 输入

- 一个或多个 review 目录路径（可带引号）。review 目录是只读输入，禁止写入任何文件。
- 先读 `review.md` frontmatter：`format` 必须是 `uiboard-review/1`，主版本不认识就停下报告。
- 格式细节见 `references/review-format.md`。

## 读取顺序（控制视觉 token）

1. `review.md` 全文。
2. `annotated.png` 看一次，建立各 #N 的整体位置感。
3. 每个 #N 看 `crops/N.png`（原分辨率），细节判断以 crop 为准。
4. `ref-*.png` 只作为正确结果参考。
5. `runtime.png` 只在 crop 不够时看。
6. `hierarchy.xml` 只在需要邻近节点时用 grep / rg 按 bounds 或 id 查，不整篇读入。

## 坐标

- `rect: x,y,w,h` 是 runtime.png 像素，原点左上；`w=h=0` 是点。
- 有 `dp` 行时直接用它和 layout / Figma 的 dp 值比较；没有 `dp` 行说明来源不是 ADB，不要假设 density。
- `crop: 路径 @ ox,oy` 中 `ox,oy` 是 crop 左上角在 runtime 中的坐标。

## 关联模块文件（每个 #N，按证据强度，命中即停）

1. `views`：取 resource-id 的 name → 在仓库 `res/layout*/` 中 `rg -n '@\+id/<name>\b'` → layout 文件:行 → 找引用该 layout 的类（`R.layout.<layout>` 或 `<LayoutCamel>Binding`）→ 在类中找该 view 的使用（`binding.<nameCamel>` / `R.id.<name>`）。
2. `activity`：定位 Activity 类文件，结合 crop 可见内容锁定其 Fragment / Adapter / 子布局。
3. crop 中的可见文案：`rg` 字符串资源 value → `@string/<name>` / `R.string.<name>` 使用处。
4. 以上都没有：按视觉结构与页面语义搜索，置信度标「推测」。

resource-id 或 activity 属于第三方包（广告 SDK 等）时标注「非本仓代码」，不改。

## 产出

先输出关联表：

| # | 问题摘要 | 证据 | 文件:行 | 置信度（确定/高/推测） | 根因假设 |

然后：

- 当前仓库的 AGENTS.md / CLAUDE.md 要求先出 plan 时：按该仓库文档路由写 plan，标题下一行固定为 `**UI Review**: file://<review 目录绝对路径>`，写完停下等确认。
- 否则：按 #N 顺序直接修改。

## 修复原则

- 用户只指出哪里不对，描述里不包含解法；精确值来自 ref、Figma 与现有代码。
- frontmatter 有 `figma` 且 Figma MCP 可用时按 node 读取精确尺寸；大帧先 get_metadata + get_screenshot，不要直接对整帧取 design context。
- 修布局 / 组件根因，不加任意 offset；共享组件确实是根因时才改共享组件。
- 只改与各 #N 相关的代码。

## 验证与收尾

- 按当前仓库规则执行编译验证（如 Android 项目的 assemble 命令）。
- 按 #N 汇总：文件:行、改了什么、为什么；列出需要用户真机复验的点。
- 复验方式：用户重新截图并导出新的 review；不回写旧目录。
```

### `skills/ui-review/agents/openai.yaml`

```yaml
interface:
  display_name: "UI Review"
  short_description: "Map UIBoard review issues to module files and fix them"
  default_prompt: "Use $ui-review with this UIReview directory path."
policy:
  allow_implicit_invocation: true
```

### `scripts/install-skill.sh`

```bash
#!/bin/bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)/skills/ui-review"
for dir in "$HOME/.claude/skills" "$HOME/.codex/skills"; do
  dest="$dir/ui-review"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "abort: $dest is a real directory, remove it first" >&2
    exit 1
  fi
  ln -sfn "$SRC" "$dest"
  echo "linked $dest -> $SRC"
done
```

先判断「存在且不是 symlink」再 `ln -sfn`：对真实目录直接 `ln -sfn` 会把 link 建进目录里面，这是经典坑。只装本机，不考虑跨机器同步。

## 9. 验收

### Capture
- [ ] Finder 启动的 `.app` 能找到 adb 并截图
- [ ] 多设备可选、可刷新、状态可见；重启 App 后恢复上次设备
- [ ] ⌘V 粘贴、拖入 PNG/JPG 可作为 runtime；描述框内 ⌘V 仍是文本粘贴

### Annotation
- [ ] 点击产生 Pin、拖拽产生框，编号自动；删除中间项后编号与颜色自动顺延
- [ ] 新标记自动聚焦描述；点卡片高亮对应标记
- [ ] 已有标记时替换截图必须确认

### Reference / Figma
- [ ] ref 可通过 ⌘V（已有 runtime 时）、拖入、选择文件添加，可删除
- [ ] Figma URL 可保存到 review.md

### Export
- [ ] 目录结构与 review.md 严格符合 5.3 / 5.4；`swift test` golden 通过
- [ ] annotated.png 与屏幕预览一致，编号在 Claude 下采样后仍清晰可读
- [ ] 空描述阻止导出；导出过程中无 `.tmp` 目录残留
- [ ] 成功 sheet：Copy Path（默认）/ Reveal in Finder

### History
- [ ] 按日期分组、显示时间与缩略图；Copy Path / Reveal / 打开可用；不显示未完成目录

### AI Handoff
- [ ] Claude `/ui-review` 与 Codex `$ui-review` 均可触发，读取同一份 Skill
- [ ] 有 `views` 的 #N 关联到正确 layout 与引用类；无 `views` 时降级并标注置信度
- [ ] 在 Avatar-Android 中先产出带 `**UI Review**:` 头的 plan，确认后才改代码，并跑 `./gradlew assembleNekuDebug`

## 10. 已知天花板与升级路径

- 画布不支持缩放：Retina 屏上 fit 显示对大部分标注够用；若精细标注困难，升级为 `ScrollView` + 放大手势。
- 每次拖拽都整图重渲染：M 系列上 1080×2400 预估十毫秒级；若卡顿，改为缓存底图、只把进行中的框画在 SwiftUI overlay。
- ⌘⇧A 仅 App 内有效：全局热键需 `RegisterEventHotKey`，真实需要时再加。
- `uiautomator dump` 在持续动画页可能失败、Compose 页默认无 resource-id：降级为 activity + 文案 + 视觉搜索；若 Compose 页增多，可在项目侧开启 `testTagsAsResourceId`。
- 导出后不可再编辑：需要修改就重新导出一份。
- 单个 review 只有一张 runtime：多状态问题（如 Tab 选中 / 未选中）导出多份，Skill 支持一次传多个路径。

## 11. 未决项

- [x] 中保真原型已产出：`docs/design/prototype/`（A–H 八张，源文件 `uiboard-prototype.html`，重新导出用 `render.sh`）。
- [x] Claude Design 正式稿已产出，已归档到 `docs/design/claude-design/` 并渲染为 `docs/design/A–H` PNG；数值已并入 Lane UI，标注常量已按正式稿修订第 5.5 节。
- [ ] T0.4 真机 spike 结果未知：uiautomator 在 Spine 编辑器上是否可用、bounds 与截图坐标是否一致。
- [ ] lane 分支内提交需用户授权。
