# UIBoard Import 改为「打开 review 目录」

**基线**: [多标签画板](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-28-uiboard-boards-frames.md)（第 3 节输入路由中「⌘O、toolbar Import」一行由本计划改写）· [实施计划第 5 节冻结契约](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-24-uiboard-impl.md)
**测试数据**: `/Users/loopq/Downloads/归档 2`（同事导出的 3 个 v2 review：4/5/3 帧，共 6 个 Pin）

状态（2026-11-09）：已实现。`swift build`、`swift test`（36 个通过）、`scripts/bundle.sh` 均通过。E2E 已跑一部分，用户叫停（AX 自动化会抢鼠标焦点），未测项见第 6 节。

## 1. 核心判断

✅ 值得做。同事把 review 目录发过来，现在用 Import 打开看不到他画的标注：Import 只认图片（`ImageSource.open` 的 `allowedContentTypes = [.image]`），全仓库没有任何读取 `review.md` 的代码。选 `runtime.png` 得到的是没有标注的拼图，选 `annotated.png` 得到的是标注已经烧进像素、无法编辑的图，拖文件夹则没有任何反应。

而单张图片早就有别的入口：⌘V 粘贴、拖入、「+」格里的 Import…。toolbar 上的 Import 再导入一遍图片是重复功能，没有意义。

- **数据结构**：不新增任何结构。导出用的 `Review`（frames + facts + marks + refs + figmaURL）就是 `review.md` + `runtime.png` 能还原的全部信息。导入是导出的逆运算：`目录 → Review → Board`。
- **消除特殊情况**：「选中的是 review 目录本身」和「选中的是装着多个 review 的父目录（如 `归档 2`）」用同一条规则处理：只取「该目录本身 + 它的直接子目录」中含 `review.md` 的那些，不需要 if 分支。v1 是 v2 只有 1 帧的特例：frames 列表只有一项，偏移为 0,0，facts 写在顶层。
- **风险点**：输入来自别人的文件（信任边界）。必须校验格式版本、帧是否在拼图范围内、标注的 frame 是否存在、rect 是否越界。坏数据不能崩溃，也不能打开一个标注位置错乱的画板。

## 2. 决策

| 问题 | 决策 |
|---|---|
| toolbar Import、菜单 ⌘O | **只用来打开 review 目录**，不再导入图片。菜单项改名为 `Import Review…`，toolbar 文字仍为 `Import` |
| 「+」格 → Import… | 不变，仍是追加图片帧 |
| 拖入 | 拖到画板区或标签栏：**文件夹**按 review 打开（新功能，此前无反应），**图片**行为不变。拖到 References 区时忽略文件夹 |
| 选中的目录 | 可多选。每个选中项取「自身 + 直接子目录」中含 `review.md` 的目录，每个 review 打开为一个新标签。都找不到时报错 `No UIBoard review found in “xxx”.` |
| 部分目录损坏 | 好的照常打开，坏的统一用一个 alert 列出目录名和原因 |
| 打开后的标签状态 | 视为**已导出**（显示 ✓，未修改就关闭不弹确认），因为内容和磁盘上一致。改动后照常变脏 |
| 再次 Export | 照常写到 workspace 下新的时间戳目录，**永远不覆盖**同事的原目录 |
| 还原范围 | 帧图像、帧顺序、设备信息（serial / model / density / activity / 视图树）、标注（frame / rect / note）、参考图、Figma 链接。`dp` / `crop` / `views` 是派生值，不读，再次导出时重新计算 |

## 3. Core（契约变更，先改实施计划第 5 节）

`API.swift` 新增（只加不改）：

```swift
public enum ReviewImporter {
    /// url 自身 + 直接子目录中含 review.md 的目录，按路径排序
    public static func directories(in url: URL) -> [URL]
    /// review 目录 → Review；格式错误抛 UIBoardError.importFailed
    public static func load(_ directory: URL) throws -> Review
}
```

`Model.swift` 中 `UIBoardError` 新增 `case importFailed(String)`，提示文案为 `Import failed: …`。

实现放在新的 internal 文件 `Sources/UIBoardCore/ImportSupport.swift`：

1. **frontmatter**：读取第一对 `---` 之间的内容。顶层是 `key: value`；`frames:` 下面 `  - ` 开头表示新的一帧，`    ` 缩进的行是这一帧的字段。`format` 只接受 `uiboard-review/1` 和 `uiboard-review/2`。
2. **帧**：v2 按 `offset` + `size` 从 `runtime.png` 切出每一帧（拼图是顶对齐，原点在左上，与 `BoardComposer` 一致）。v1 直接使用整张 `runtime.png`。
3. **设备信息**：有 `source: adb` 才生成 `DeviceFacts`。`device: MI 9 (6e9b5937)` 按最后一个 ` (` 拆成 model 和 serial；没有括号时整个值作为 serial。视图树：v2 读 `hierarchy: hierarchy-X.xml`，v1 读 `hierarchy.xml`（如果存在）。
4. **标注**：以 `## #N` 切段。`- frame: X` 按字母换回下标（v1 固定为 0），`- rect: x,y,w,h` 是帧内坐标。bullet 后第一个空行之后、下一个 `## #` 之前的内容是 note，去掉首尾空白，保留中间的换行。
5. **参考图与 Figma**：读 `refs: [ref-1.png, …]` 对应的文件，以及 `figma:` 的值。
6. **校验（任一失败即抛错）**：`review.md` 或 `runtime.png` 缺失或无法解码；格式版本未知；帧矩形超出 runtime；标注的 frame 字母不存在；rect 有负值或越出所在帧；frames 为空；视图树或参考图引用的文件不存在。

天花板：note 正文中如果有一行恰好是 `## #数字`，会被误判为下一个标注。导出格式本身无法区分这种情况，`ui-review` skill 也一样，因此不处理。

## 4. UI

- `EditorModel`
  - `importReviews()`：调用 `NSOpenPanel`（只能选目录，可多选），然后调 `openReviews(_:)`。
  - `openReviews(_ urls: [URL])`：`flatMap(ReviewImporter.directories)` 后逐个 `load`，每个结果调 `add(review:)`，错误汇总后通过 `report` 显示。成功时 toast `Opened N reviews`。
  - `add(review:)`：`boardCounter += 1`，用 `Review` 构造 `Board`（`BoardFrame(image:facts:)`），之后设置 `exportedRevision = revision`，追加并选中该标签。
  - `drop(_:to:)`：文件夹交给 `openReviews`，图片交给原来的 `open(_:to:)`。
- `ImageSource.load(_ providers:)` 改为返回 `(images: [Data], folders: [URL])`。目录 URL 放进 `folders`，其他逻辑不变。调用方：Canvas 和 TabBar 改为 `model.drop(…)`，Inspector 只取 `.images`。
- toolbar Import 和菜单 ⌘O 改为调用 `importReviews()`。help 文案：`Open exported review folders in new tabs (⌘O)`。
- 空状态 `EmptyDropZone` 增加一行提示：`⌘O  to import a review`。

## 5. 不做

- History 窗口里的「在 UIBoard 中打开」：没人提出这个需求。双击仍然用预览打开 `annotated.png`。
- 回写或覆盖原 review 目录。
- 读取 `.zip`：解压是 Finder 的事。

## 6. 验证

- `swift build`、`swift test`、`scripts/bundle.sh` 全部通过。
- 新增 `Tests/UIBoardCoreTests/ImportTests.swift`，只测行为：
  1. **v2 往返**：3 帧，尺寸不同，其中一帧较矮；部分帧有 facts 和视图树，一帧没有 facts；Pin、矩形、跨帧标注、多行 note、2 张参考图、Figma 链接。先 `export` 再 `load`，比较 frames 尺寸与像素、facts、marks、refs 和 figma。再导出一次，`review.md` 除 `created` 外逐字节相同。
  2. **v1 往返**：分别测有 facts（含 `hierarchy.xml`）和无 facts 两种情况。
  3. **`directories(in:)`**：传入 review 目录本身得到 1 个；传入父目录（2 个 review + 1 个无关目录）得到 2 个；传入空目录得到 0 个。
  4. **坏输入**：缺 `review.md`、未知 format、缺 `runtime.png`、frame 字母不存在、rect 越界、帧超出 runtime，都应抛出 `importFailed`。
- E2E（真实 App，用 `归档 2`）：⌘O 选择 `归档 2`，应打开 3 个标签，标题分别为 SearchActivity / AvatarFullScreenEditorActivity / AvatarPublishActivity，共 6 个 Pin 位置正确，note 一致。把 `10-56-21` 文件夹拖到画布上应再开一个标签。不做修改直接 ⌘W 不弹确认。再次导出一个标签到临时 workspace，与原目录 `diff review.md` 应只有 `created` 不同。「+」格的 Import… 仍能追加图片帧。

### E2E 记录（2026-11-09）

dev 构建复制为 `UIBoardDev.app`（独立的 bundle id 和进程名，避免和正在运行的 `/Applications/UIBoard.app` 混在一起），用 AX 驱动。这台机器没有屏幕录制权限，画面通过重新导出的图片来核对。测试导出的目录和临时文件都已删除。

- [x] ⌘O 选择父目录（`归档 2` 的副本）：打开 3 个标签，帧数分别为 4、5、3，每条标注的所在帧和 note 都与原 `review.md` 一致
- [x] ⌘O 选择单个 review 目录：多开一个标签
- [x] 刚导入、未修改的标签执行 Close Tab：不弹确认
- [x] 3 个标签分别再次导出：`review.md` 只有 `created` 不同；`hierarchy-*.xml` 逐字节相同；`runtime.png` 和 `crops/*` 逐像素相同；`annotated.png` 只差 2–44 字节，单通道最大差 13/255，都在引线和角标的抗锯齿边缘，属于不同机器的渲染差异，标注位置一致
- [ ] 拖文件夹到画板区或标签栏：未测
- [ ] 导入后修改再关闭，应弹出确认：未测（自动化操作失败）
- [ ] 选择不含 review 的文件夹或损坏的 review 时的 alert 文案：未测（Core 的抛错已由单测覆盖）
- [ ] 「+」格 Import… 追加图片帧：未测（代码未改动）
- [ ] 空状态新增的 ⌘O 提示：未看到画面

