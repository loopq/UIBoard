# UIBoard 多标签画板（Boards & Frames）实施计划

**基线**: [V1 实施计划](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-24-uiboard-impl.md)（第 5 节契约在本计划中被扩展，冲突处以本文件为准）

状态：实现完成，自动验证通过；待用户真机验收（⌘⇧A / ⌘⌥A / 「+」格 / 关闭确认 / v2 导出后跑 /ui-review）。

## 1. 核心判断

✅ 值得做。验收 UI 时是「先连续截很多页面，再逐个标注」，还经常要把同一页面的两个状态并排对比。现在的编辑区一次只能放一张截图，而且新截图会替换旧截图。

- 数据结构：`标签 = 画板 = 一个 Review = 一次导出 = 一个 review 目录`；画板内横排 1…N 帧（A、B、C…）。标注属于某一帧，坐标用帧内像素，所以 dp / views / crop 的计算全部照旧按单帧做。
- 消除的特殊情况：所有新截图都是「新标签」或「追加帧」，不再有「替换截图」，替换确认弹窗随之删除；单帧画板导出与 V1 逐字相同，多帧才用 v2。
- 风险点：内存里未导出的画板变多，所以关闭有标注的标签、退出 App 时都要确认。

## 2. 已拍板的决策

| 问题 | 决策 |
|---|---|
| 标签形态 | Android Studio 式自绘标签栏（缩略图 + 页面名 + 问题数 / ✓ + ×）。不用 macOS 原生窗口标签，因为它不能显示缩略图 |
| 一个画板能否多张图 | 能：横排多帧，导出成一张拼图，问题在画板内连续编号 #1…#N |
| Export 范围 | 只导出当前标签 |
| 标签标题 | 缩略图（画板拼图）+ activity 短类名（非 ADB 来源显示 `Screen N`）+ 问题数；已导出且未再修改时显示 ✓ |
| ⌘V | 没有标签时新建标签；有标签时加为当前画板的参考图（保持 V1） |
| Capture 默认 | ⌘⇧A / 点击 Capture 主体 = 新标签；⌘⌥A / Capture 下拉「Add to This Board」= 追加帧 |
| 追加入口 | 最后一帧右侧常驻虚线「+」格：点击弹出 Capture from Device / Import… / Paste Image，也接受拖入 |
| 帧标记 | 用字母 A/B/C（Z 之后是 AA、AB…），刻意不用数字，避免和问题 #1 #2 混淆 |

## 3. 输入路由（唯一规则表）

| 动作 | 没有标签时 | 有标签时 |
|---|---|---|
| ⌘⇧A、点击 Capture 主体 | 新标签 | 新标签 |
| ⌘⌥A、Capture 下拉「Add to This Board」、「+」格 → Capture | 新标签 | 追加帧 |
| ⌘O、toolbar Import | 新标签（多选时每张一个标签） | 新标签 |
| 「+」格 → Import… | — | 追加帧（多选时追加多帧） |
| 「+」格 → Paste Image | — | 追加帧 |
| ⌘V（剪贴板有图、焦点不在有文字的文本框） | 新标签 | 当前画板加参考图 |
| 拖到画板区 / 「+」格 | 新标签 | 追加帧 |
| 拖到标签栏 | 新标签 | 新标签 |
| 拖到 References 区 | — | 参考图 |

其他快捷键：⌘W 关闭当前标签，⌘⇧[ / ⌘⇧] 切换上一个 / 下一个标签，⌘E 导出当前标签。⌘N「New Review」删除（画板只由图片创建，不存在空画板）。

## 4. 数据模型与 Core 契约（T0 冻结）

```swift
public struct Frame { public var image: CGImage; public var facts: DeviceFacts? }
public struct Mark { public var rect: CGRect; public var note: String; public var frame: Int = 0 }   // rect 是帧内像素
public struct Review {
    public var frames: [Frame]; public var marks: [Mark]; public var refs: [CGImage]; public var figmaURL: String
    public init(runtime: CGImage, facts: DeviceFacts? = nil, marks:, refs:, figmaURL:)   // 单帧便捷构造，V1 调用点与 golden 测试不变
    public init(frames: [Frame], marks:, refs:, figmaURL:)
    public var runtime: CGImage { frames[0].image }; public var facts: DeviceFacts? { frames[0].facts }
}
public enum Frame.label(at index) -> String   // 0 → "A"
public enum BoardLayout {
    static func gap(for sizes: [CGSize]) -> CGFloat        // round(0.06 × 最大帧宽)
    static func offsets(for sizes: [CGSize]) -> [CGPoint]  // 横排、顶对齐
    static func size(for sizes: [CGSize]) -> CGSize        // Σ宽 + gap×(n−1) × 最大高
}
AnnotationRenderer.render(runtime: CGImage, marks: [Mark], frame: Int = 0, highlight: Int?) -> CGImage?
```

- 渲染器只画 `mark.frame == frame` 的标注，编号 = 该标注在整个 `marks` 数组里的下标 + 1，颜色 = `Palette.rgb(at: 下标)`；常量按该帧宽度计算，徽标 clamp 在该帧范围内。单帧调用结果与 V1 像素一致。
- 编号与颜色仍由下标派生；删除一帧时，删掉它的标注，并把更后面帧的标注 `frame` 减 1。

## 5. 导出格式 v2（只用于多帧）

单帧画板：输出与 V1 逐字相同（`format: uiboard-review/1`、`hierarchy.xml`），现有 golden 不变。

多帧画板：

```text
<workspace>/YYYY-MM-DD/HH-mm-ss/
├── review.md
├── runtime.png          # 整板拼图，无标注，帧间与短帧下方填 #E5E5EA
├── annotated.png        # 整板拼图 + 全部标注
├── crops/N.png          # 从标注所属帧裁出（帧内坐标，规则同 V1）
├── ref-N.png
└── hierarchy-A.xml …    # 有视图树的帧各一份
```

```markdown
---
format: uiboard-review/2
created: 2026-09-24T18:15:42+08:00
image: runtime.png
size: 2225x2400
figma: https://www.figma.com/design/pw7H7us12aHi2IqHDi0bdm/Neku?node-id=128-22976
refs: [ref-1.png]
frames:
  - frame: A
    offset: 0,0
    size: 1080x2400
    source: adb
    device: Pixel 7 (37091JEHN)
    density: 420
    activity: com.stickermobi.avatarmaker/.ui.task.TaskCenterActivity
    hierarchy: hierarchy-A.xml
  - frame: B
    offset: 1145,0
    size: 1080x2400
---

# UI Review

## #1

- frame: A
- rect: 96,412,888,180
- dp: 36.6,157.0,338.3,68.6
- crop: crops/1.png @ 0,304
- views: …

描述
```

- 顶层行顺序：`format, created, image, size, figma, refs, frames`；帧内行顺序：`frame, offset, size, source, device, density, activity, hierarchy`。没有值的行省略，规则同 V1。
- issue 的 `rect` / `crop` 原点 / `views` bounds 都是**帧内**像素；在拼图中的位置 = 帧 `offset` + 帧内坐标。`dp`、`views` 只在该帧有设备事实时出现。
- 完整期望输出见 `Tests/UIBoardCoreTests/Fixtures/golden-review-v2.md`（输入 `golden-input-v2.json`）。

## 6. 任务

### T0 契约（Claude，main）

- [x] 更新 `Model.swift`（`Frame`、`Mark.frame`、`Review.frames` 与两个 init）、`API.swift`（`BoardLayout` 签名、渲染器 `frame` 参数），现有实现保持可编译、V1 测试全绿。
- [x] `golden-input-v2.json` + `golden-review-v2.md`（手算）；`review-format.md` 增加 v2 小节。
- [x] 提交基线，建 `main_frames` worktree。

### Lane Core（Codex，worktree `main_frames`）

- [x] C1 `BoardLayout` 实现；渲染器按帧过滤 + 全局编号 + 帧内 clamp。
- [x] C2 导出：单帧走 V1 原路径；多帧写拼图 runtime / annotated、帧内 crops、`hierarchy-X.xml`、v2 markdown。
- [x] 测试：v1 golden 逐字不变；v2 golden 逐字一致；拼图尺寸与帧 B 像素出现在 offset 处；渲染器只画指定帧的标注且编号全局；多帧导出目录内容完整。

### Lane UI（Claude，main）

- [x] U1 `EditorModel` 改为 `boards: [Board]` + `current`；设备事实任务按帧 id 回填（取代 token）；Board 的标注 / 参考图 / Figma / 帧任何修改都清除「已导出」状态。
- [x] U2 标签栏：缩略图、标题、问题数 / ✓、×（悬停或选中时显示）；拖入标签栏新建；⌘W / ⌘⇧[ / ⌘⇧]。
- [x] U3 画板：帧横排（间距按 `BoardLayout.gap` 缩放）、帧头「A ×」（单帧时不显示 ×）、每帧独立渲染与手势、「+」格（菜单 + 拖入）、卡片在多帧时显示帧字母。
- [x] U4 Capture 分体按钮（`Menu(primaryAction:)`）、⌘⌥A、按第 3 节路由所有输入；删除替换确认与 ⌘N。
- [x] U5 关闭有未导出标注的标签要确认；删除有标注的帧要确认；退出时有未导出画板要确认（`applicationShouldTerminate`）。
- [x] U6 History 缩略图改为 aspect fit（多帧拼图较宽）。

### Skill（Claude）

- [x] 读取 v1 / v2 两种格式：v2 读 `frames`，按 issue 的 `frame` 取该帧的 density / activity / `hierarchy-X.xml`；定位时 activity 按帧取。
- [x] 一次传多个 review 目录时，关联表的 # 前缀加目录名，例如 `10-33-49#1`。

### 集成

- [x] ~~`/apply-worktree main_frames`~~ 未用 worktree（见下方记录）；`swift build && swift test && scripts/bundle.sh` 通过。

  执行记录（2026-09-28）：
  - Codex 两次派发都异常退出（第一次跑到一半、第二次立即退出），连最简单的只读探测都没有输出；事后确认原因是官方额度耗尽（不是 CLI 升级），之后改用 `cxd-third` profile 调用。空的 `main_frames` worktree 已清理，Core lane 改由 Claude 在 main 上完成。
  - 26 个测试通过（新增 `BoardTests` 5 个：BoardLayout、拼图偏移与空隙色、按帧渲染与全局编号、v2 golden 逐字节、多帧导出目录）；v1 golden 不变。
  - 调试钩子端到端（钩子已删除，不入库）：2 个标签（其中一个 2 帧、3 个标注）→ 导出为 v2（拼图 2225×2400，编号 A:#1 #3、B:#2）→ 标签显示 ✓；导出后再修改会自动清除 ✓；关闭有未导出标注的标签、删除带标注的帧都会弹确认；删除 B 帧后，它的标注被删、其余标注的帧号正确；菜单只剩一个 ⌘W（Close Tab）。
  - 端到端中发现并修复：帧头被 `Spacer` 撑宽，和帧不对齐（改成固定为帧宽）；`borderlessButton` 样式的 Menu 会把「+」格压成一行文字（改为 `.menuStyle(.button)` + `.buttonStyle(.plain)`）。
- [x] 临时调试钩子端到端（验证后删除）：2 个标签，其中一个 2 帧，每帧都有标注；截图检查标签栏、画板、导出目录与 v2 review.md。
- [x] Codex 审查（cxd-third）：4 条全部成立并已修复，详见 [review](file:///Users/loopq/dev/git/loopq/uiboard/docs/reviews/2026-09-28-uiboard-boards-frames-review.md)。
- [x] 修复用户反馈「标签点不动」（`5a135e6`）：根因是标签栏外层的横向 `ScrollView` 紧贴 unified toolbar 下方时收不到点击（同一窗口里 Issue 卡片的纵向 ScrollView、References 的横向 ScrollView 都正常）。已去掉 ScrollView，标签改为 Button，右侧加「全部标签」菜单兜底溢出；同时修了隐藏的 × 仍能被点到、标签内边距点不到、标题被撑到 170pt 三个问题。验证方式：窗口激活后，用 `NSApp.postEvent` 发送排队的鼠标事件（`sendEvent` 会和文本框的鼠标跟踪循环互相等待，不能用），标签 1/2 互切、全部标签菜单、卡片选中、References「+」都通过。
- [ ] 用户真机：⌘⇧A 新标签、⌘⌥A 追加、「+」格、关闭确认、导出后跑 `/ui-review`。
- [x] `scripts/install-app.sh` 更新「应用程序」里的版本。

## 7. 验收

- [ ] 连续 ⌘⇧A 三次得到三个标签；⌘⌥A 在当前画板追加帧，出现在「+」格位置并提示 `Added frame B`
- [ ] 标注在哪一帧起笔就属于哪一帧，拖出帧边界会被限制在帧内；编号在画板内全局连续
- [ ] 删除帧、删除标注后编号与帧字母正确顺延
- [ ] 关闭未导出的有标注标签、退出 App 都有确认；已导出且未修改的标签关闭不确认
- [ ] 单帧导出与 V1 完全一致；多帧导出为 v2，AI 能按 `frame` + `offset` 在 annotated.png 上找到对应位置
- [ ] Claude `/ui-review` 与 Codex `$ui-review` 能读 v2，并正确关联到多帧中各自的页面文件

## 8. 已知天花板

- 帧数量不设上限：标签按 A…Z、AA、AB… 递增（Codex 审查发现原先的 A–Z 循环会导致重名）。
- 所有画板都在内存里：一帧 1440×3120 解码后约 18MB，20 帧约 360MB；退出前未导出的画板不会持久化（有退出确认兜底）。如果需要跨重启保留，再加草稿落盘。
- 不同设备的帧按原始像素并排，分辨率不同时视觉比例不一致；同一设备的状态对比不受影响。
- 帧不支持拖动排序；需要时再加。
