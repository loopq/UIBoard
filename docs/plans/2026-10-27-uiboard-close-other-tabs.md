# UIBoard 标签右键「Close Other Tabs」

**基线**: [多标签画板](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-28-uiboard-boards-frames.md)

状态（2026-10-27）：已完成，用户验收通过。`swift build` 通过，27 个测试通过，`scripts/bundle.sh` 通过。E2E 用 cliclick 加 System Events 读 AX 树做的（shell 没有录屏权限，截不到窗口内容）：在 38 个标签、其中 2 个 dirty 的情况下，右键干净标签，弹出「Close 37 tabs? / 2 tabs have annotations…」；点 Cancel 后 38 个都在；点 Close 后只剩被右键的那个，它也成为当前标签（执行前当前标签是另一个）；只剩一个标签时菜单项置灰。「全部干净时直接关」这一条没跑完，用户中途确认验收。

3.1 节溢出修复的 E2E（同样用 AX 验证）：导入 24 个标签，窗口宽 1400。第一个标签 x=0，左对齐；「All tabs」菜单在 x=1369，在窗口内（修复前是 3442）。用真实鼠标点开菜单，24 项都在；点被裁掉的 Screen 20，它成为当前标签；点右边缘附近的可见标签 Screen 10，也能正常切换。补跑「全部干净时 Close Other Tabs」：不弹窗，只剩被右键的 Screen 5。

## 1. 核心判断

✅ 值得做。标签右键菜单现在只有 `Close Tab`，想只留一个标签就得逐个点 ×。IDE 和 Safari 都有「关闭其他标签」，用户已经习惯了。

确认弹窗：**要弹，但规则沿用现有的 `isDirty`**（有标注且最新版本未导出）。

| 场景 | 现有行为 | Close Other Tabs |
|---|---|---|
| 被关的标签全部干净（无标注 / 已导出） | 单关：直接关 | 直接关，不弹 |
| 至少一个是 dirty | 单关：弹「Close this tab?」；退出 App：汇总弹一次「N tabs have annotations…」 | 汇总弹**一次**「Close N tabs?」+「M tabs have annotations that haven't been exported.」 |

理由：标注是唯一会丢的用户劳动（截图可以重截，已导出的在 History 里能找回）。逐个弹会很烦，一次都不弹又会丢数据，所以和退出 App 一样汇总弹一次。

## 2. 数据结构

`PendingRemoval.board(UUID)` 改成 `.boards([UUID])`，单关就是只有一个元素的情况，消掉特例：

- `requestClose(_ ids: [UUID])`：`ids` 里有 dirty 的就挂 `pendingRemoval = .boards(ids)`，否则直接 `close`。
- `confirm(.boards(ids))`：逐个 `close(id)`。现有 `close` 关掉当前标签后会选中相邻标签，所以逐个关完后剩下的那个自然成为当前标签，不用额外写选中逻辑。
- 记录的是**要关的 id 列表**，不是「保留哪一个」。弹窗期间如果异步截图新开了标签，它不在列表里，不会被误关。

## 3. 改动

1. `Sources/UIBoard/EditorModel.swift`
   - `PendingRemoval.board(UUID)` → `.boards([UUID])`
   - `requestClose(_ id: UUID)` → `requestClose(_ ids: [UUID])`；`requestCloseCurrent` 改为传 `[id]`
   - `confirm` 的 `.boards` 分支循环调用 `close`
2. `Sources/UIBoard/TabBarView.swift`
   - × 按钮和 `Close Tab` 改为传 `[board.id]`
   - 右键菜单加 `Close Other Tabs`，传 `model.boards.map(\.id).filter { $0 != board.id }`；只有一个标签时 `.disabled`
3. `Sources/UIBoard/EditorView.swift`（弹窗文案）
   - 1 个：沿用「Close this tab?」/「Its N annotations haven't been exported.」，与现状一致
   - 多个：「Close N tabs?」/「M tab(s) have annotations that haven't been exported.」，与退出 App 的文案风格一致

不做：「Close Tabs to the Right」、主菜单 ⌥⌘W 快捷键（Safari 的惯例）。没人提这个需求，要的话再加一行就行。

## 3.1 顺带修：标签溢出时「All tabs」菜单被挤出窗口

E2E 时从 AX 坐标发现：开 38 个标签后，窗口宽 1400，标签栏却居中铺开（x 从 -2085 到 3421），左右两侧的标签都被裁掉，「All tabs」菜单跑到 x=3442，用鼠标点不到。

根因：`.frame(maxWidth: .infinity)` 没写 `minWidth`。这种情况下 frame 宽度取子视图宽度和提议宽度中的较大者，而 `fixedSize` 的标签行约 5500 宽，frame 就变成 5500 宽，`.clipped()` 等于没裁。改成 `.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)` 后，frame 宽度等于提议宽度：标签左对齐，右侧溢出部分被裁掉，菜单固定在最右边。

已知局限：当前标签在右侧被裁掉时看不到它，要通过菜单切换。以后需要的话，再做「滚动到当前标签」。

## 4. 验证

- `swift build`、`swift test`、`scripts/bundle.sh` 全部通过
- 手测：3 个标签全干净 → 右键中间那个 → Close Other Tabs → 直接只剩它，且它是当前标签；其中 1 个有未导出标注 → 弹一次 → Cancel 不动 / Close 只剩它；只有 1 个标签时菜单项置灰；单关 dirty 标签的弹窗文案保持不变
