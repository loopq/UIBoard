# UIBoard 帧拖拽（换序 / 垂直错位）+ 标尺辅助线

**基线**: [多标签画板](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-28-uiboard-boards-frames.md)（第 8 节「帧不支持拖动排序」在本计划中解除）
**来源**: [飞书 todo t143118](https://applink.feishu.cn/client/todo/detail?guid=96a2ab6b-7439-44d4-b6f9-2b00114a9c45&suite_entity_num=t143118)「UIBoard 支持拖拽某个画板，设计那边想要走查的时候对比，以及辅助线的形式」；辅助线参考 Figma `View > Rulers ⇧R`

状态（2026-11-06）：已实现，E2E 通过，待用户验收。`swift build`、`swift test`（32 个通过）、`scripts/bundle.sh` 均通过。E2E 记录见第 7 节。

## 1. 核心判断

✅ 值得做。设计走查时要把两帧并排对比：把 C 拖到 A 旁边，再上下错开，让两帧里的同一个元素对齐到同一条线上，才看得出间距或位置差了多少。现在帧固定横排、顶对齐，也没有参考线，只能靠目测。

- 数据结构：多出来的是两份**只用于预览**的状态，也就是帧的垂直错位和辅助线，都不进 `Review`。只有「换序」改的是导出数据（`frames` 的顺序 + `mark.frame` 的映射）。
- 消除的特殊情况：帧、辅助线、标尺共用同一套「板内像素 ↔ 视图坐标」映射（`BoardGeometry`），不让三处各自去算 HStack 居中的偏移。
- 风险点：换序要正确重映射 `mark.frame`，否则标注会跑到别的帧上。错位和辅助线不能 bump `revision`，否则只是拖一下就会把已导出的 ✓ 清掉。

## 2. 已拍板的决策（2026-11-06 用户确认）

| 问题 | 决策 |
|---|---|
| 「拖拽面板调整顺序」指什么 | 画板内的**帧左右换序**，不涉及标签栏 |
| 帧上下拖动的错位要不要导出 | **仅预览**。导出仍是顶对齐拼图，Core 与导出格式不改 |
| 辅助线开关关闭时 | **关闭即清除**：关掉标尺，同时清空所有画板的辅助线；再打开时没有残留 |
| 换序后的帧字母 | 跟着位置走：拖到第 1 位的就是 A。标注编号 #N 不变（仍按创建顺序） |
| 开关入口 | 菜单 `View > Show Rulers`（⌘⇧R，避开 ⌘R 刷新设备）+ toolbar 上的 `ruler` 图标 Toggle |

## 3. 交互

### 3.1 拖帧（帧头「A」条）

- 按住帧头拖动：整列（帧头 + 截图）跟手移动，抬起时：
  - **水平方向**：按被拖帧中心点落在哪两帧之间，决定插入的位置。
  - **一次拖动只做一件事**：位置变了就只换序，丢弃垂直位移；位置没变，垂直位移才累加到错位 `shift`（板内像素，取整）。E2E 中发现：横向换序时手会带出几 pt 的纵向抖动，以前会留下约 8px 肉眼难辨的错位，干扰比对。
- 双击帧头：错位归零。
- 拖帧的同时不画标注。帧头里的 × 是 Button，点击优先，不受影响。

### 3.2 标尺与辅助线（仿 Figma）

- 开启后，画布上边和左边各出现一条 18pt 标尺，刻度是**板内像素**，原点是帧 A 的左上角（不随错位移动）。刻度步长从 1/2/5×10ⁿ 里取，保证标签间距 ≥ 60pt。
- 从上标尺往下拖，生成水平辅助线；从左标尺往右拖，生成垂直辅助线。拖动时显示数值，例如 `Y 412`。
- 辅助线横穿整个画布，跨所有帧，1pt，颜色用 Figma 风格的红 `#F24822`。数值标签是红底白字，数字不带千分位（E2E 中发现红字直接压在彩色截图上看不清）。
- 悬停在辅助线上，光标变成 resize 形状，可以拖动；拖回标尺上就删除。
- 关闭开关（⌘⇧R、菜单或 toolbar）会清空全部辅助线。

## 4. 数据结构

```swift
// EditorModel.swift（仅 UI target）
struct Guide: Identifiable { let id = UUID(); var axis: Axis; var value: CGFloat }   // .horizontal → value 是 y；板内像素

struct Board {
    var frames: [BoardFrame] { didSet { revision += 1 } }   // 换序改这里 → 自然清 ✓
    ...
    var shifts: [UUID: CGFloat] = [:]   // 帧 id → 垂直错位，无 didSet，不进 revision、不导出
    var guides: [Guide] = []            // 同上
}

final class EditorModel {
    var showsRulers = false             // 不持久化
    func moveFrame(_ from: Int, to: Int)        // frames 换序 + marks.frame 按置换重映射；selected 是标注下标，不变
    func shiftFrame(_ id: UUID, by dy: CGFloat) / resetShift(_ id: UUID)
    func toggleRulers()                          // 关 → 所有 boards.guides = []
}
```

- `shifts` 用帧 id 作 key，不用下标：换序时错位跟着帧走，不用额外处理。删帧时顺手删掉 key。
- 错位不放在 `BoardFrame` 上，因为 `frames` 的 didSet 会 bump `revision`，错位一变就会清掉 ✓。

## 5. 布局重写：`BoardGeometry`

`BoardView` 现在用 `HStack(alignment: .top)` 居中，辅助线和标尺拿不到帧的真实位置。改为显式布局：

```swift
struct BoardGeometry {
    let scale: CGFloat
    let origin: CGPoint                 // 板内 (0,0) 在视图里的位置
    func view(_ p: CGPoint) -> CGPoint  // 板内像素 → 视图
    func board(_ p: CGPoint) -> CGPoint // 视图 → 板内像素
}
```

- 帧 x 沿用 `BoardLayout.offsets`，y = `shifts[id]`。fit 包围盒的纵向范围是 `min(0, min shift)…max(hᵢ + shiftᵢ)`，只按**已提交**的错位计算，拖动中不重新缩放，避免抖动。
- 标尺开启时，fit 区域左边和上边各让出 18pt，标尺不压住帧。
- 每一列用 `ZStack(alignment: .topLeading)` + `.offset` 定位。帧、「+」格、辅助线、标尺刻度都通过同一个 `BoardGeometry` 换算坐标。
- `FrameCanvas` 内部仍用帧内坐标画标注，`MarkGeometry` 不改。

## 6. 改动清单（全部在 Lane UI，Core / 导出 / skill 零改动）

1. `Sources/UIBoard/EditorModel.swift`：`Guide`、`Board.shifts/guides`、`showsRulers`、`moveFrame`、`shiftFrame/resetShift`、`toggleRulers`；`removeFrame` 顺带清理 `shifts`。
2. `Sources/UIBoard/CanvasView.swift`：`BoardGeometry`；`BoardView` 改为显式布局；`FrameHeader` 加拖动和双击手势；新增 `RulerView`（SwiftUI `Canvas` 画刻度）和 `GuideLine`（命中条 + NSCursor + 拖动 / 删除）。
3. `Sources/UIBoard/UIBoardApp.swift`：`CommandGroup(before: .toolbar)` 加 `Show Rulers` Toggle，⌘⇧R。
4. `Sources/UIBoard/EditorView.swift`：toolbar 加 `ruler` Toggle，没有画板时置灰。
5. `Sources/UIBoard/Theme.swift`：`Color.guide`（`#F24822`）。

不做：标签栏拖拽换序（用户确认不需要）、错位导出、辅助线持久化、吸附（snap 到帧边缘或标注边缘）、撤销。

## 7. 验证

- [x] `swift build`、`swift test`（32 个）、`scripts/bundle.sh` 均通过（现有 golden 不受影响，因为导出没改）。
- E2E（2026-11-06，`build/UIBoard.app`；用临时调试钩子让 App 自己把窗口写成 PNG，用 cliclick 发送真实鼠标事件；验证完钩子和测试导出目录都已删除）：
  - [x] 3 帧，A、C 各有标注：把 C 拖到最前面后，帧顺序变成 THREE/ONE/TWO，标注 #2 跟着 THREE（卡片显示 A），#1 跟着 ONE（卡片显示 B）；导出的 v2 拼图按新顺序排列，review.md 里 #1 的 frame 是 B、#2 的 frame 是 A
  - [x] 只做上下拖动、不换序：B 下移后，已导出的 ✓ 仍在；再次导出的拼图仍是顶对齐，B 的 offset 仍是 `1145,0`
  - [x] 换序时故意带 30pt 纵向抖动：三帧仍然顶对齐（修复后）
  - [x] 双击帧头，错位归零
  - [x] ⌘⇧R 打开标尺，原点在帧 A 左上角，刻度步长 200；从上 / 左标尺各拖出一条线，读数是 Y / X 1144（等于 B 的左边缘，1080+65−1）；拖动横线可以移动；把竖线拖回标尺就删掉了
  - [x] ⌘⇧R 关闭后，再从 View 菜单打开：没有残留线，菜单项打勾
  - [x] 有辅助线时导出：annotated.png 里没有辅助线
  - [ ] 切换标签时各画板的辅助线互不影响：未测（cliclick 很难新建第二个标签）。代码上 `guides` 存在各自的 Board 里

## 8. 已知天花板

- 辅助线的命中条（±3pt）压在帧上面，在辅助线上按下去会拖动线，不会画标注。偏开几个像素起笔即可；要改的话，可以做成按住 ⌥ 才能拖线。
- 标尺单位是截图像素，不是 dp。同一画板里的帧密度可能不同，所以没法统一换算成 dp。需要的话，可以在只有一种 density 时显示 dp。
- 错位和辅助线只在内存里，关闭标签后就没了，这正是「仅预览」的语义。
- 没有吸附，靠肉眼对齐 + 拖动时显示的数值。
