# UIBoard 原型 Prompt（Claude Design）

**实施计划**: [UIBoard V1 实施计划](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-24-uiboard-impl.md) · **正式稿**: [Claude Design](https://claude.ai/design/p/cc7a89b4-de47-4d46-950b-e53ecab4c53a?file=UIBoard+Design.dc.html)

用法：把下方「Prompt」整段贴进 Claude Design，同时上传 8 张中保真原型图作为附件。产出后把每个画板导出 PNG，放到 `docs/design/`，文件名沿用原型图的编号（`A-editor-empty.png`、`B-editor-working.png`……），UI lane 以它为视觉基准。

原型图（2x，布局与标注几何已按实施计划定稿，视觉留给 Claude Design 精修）：

| 画板 | 文件 |
|---|---|
| A 空状态 | [A-editor-empty.png](file:///Users/loopq/dev/git/loopq/uiboard/docs/design/prototype/A-editor-empty.png) |
| B 工作状态（主画板） | [B-editor-working.png](file:///Users/loopq/dev/git/loopq/uiboard/docs/design/prototype/B-editor-working.png) |
| C 深色 | [C-editor-working-dark.png](file:///Users/loopq/dev/git/loopq/uiboard/docs/design/prototype/C-editor-working-dark.png) |
| D 设备菜单 | [D-device-menu.png](file:///Users/loopq/dev/git/loopq/uiboard/docs/design/prototype/D-device-menu.png) |
| E 导出成功 | [E-export-sheet.png](file:///Users/loopq/dev/git/loopq/uiboard/docs/design/prototype/E-export-sheet.png) |
| F 替换确认 | [F-replace-alert.png](file:///Users/loopq/dev/git/loopq/uiboard/docs/design/prototype/F-replace-alert.png) |
| G History | [G-history.png](file:///Users/loopq/dev/git/loopq/uiboard/docs/design/prototype/G-history.png) |
| H Settings | [H-settings.png](file:///Users/loopq/dev/git/loopq/uiboard/docs/design/prototype/H-settings.png) |

原型源文件是 [uiboard-prototype.html](file:///Users/loopq/dev/git/loopq/uiboard/docs/design/prototype/uiboard-prototype.html)，用 `#A`…`#H` 切换画板。改完执行 `docs/design/prototype/render.sh` 重新导出（依赖本机 Google Chrome）。

状态：2026-09-24 已完成。Project archive 已归档到 `docs/design/claude-design/`（没有收 `uploads/`，那就是 prototype 的原图）。执行 `python3 docs/design/claude-design/render.py` 会把 A–H 渲染成 `docs/design/*.png`（2x）。

标注样式以实施计划 5.5 节为准。已按正式稿修订过一次：Pin 徽标偏移 96px、引线 3px、编号字号 28px。之后如果设计稿再出现别的画法，仍以实施计划为准。

## Prompt

```text
为一款 macOS 桌面工具设计高保真静态设计稿，名字叫 UIBoard。

【附件】
我附上了 8 张中保真原型图（A–H）。布局、信息结构、每个画板的内容和标注的几何画法以原型图为准，不要改动；你负责把视觉提升到正式设计稿水准：对齐、间距节奏、控件质感、图标、深浅色一致性。原型里的手机截图只是示意内容，可以画得更精致，但标注的位置关系要保持。

【产品是什么】
开发者用它把 App 运行截图上的 UI 问题标成 #1 #2 #3，每个编号写一句描述，附上正确设计参考图和 Figma 链接，然后导出一个目录交给 AI 编程助手去改代码。它是一个安静、高效的工具，不是截图美化软件，也不是 Bug 管理系统。用户每次打开它只想在几十秒内完成：截图 → 标注 → 描述 → 导出。

【视觉风格】
- macOS 15 Sequoia 原生扁平风格，看起来像 Apple 自带的工具（参考「预览」「备忘录」「Xcode 检查器」的克制程度）。
- 统一标题栏 + toolbar，左上角红黄绿交通灯按钮。
- 字体 SF Pro（正文 13pt，次要信息 11pt，路径用 SF Mono 12pt）。图标全部用 SF Symbols 线性风格。
- 扁平：不用渐变、不用拟物、不用厚重毛玻璃和大阴影。分隔只靠 1px 细线和浅灰底色层级。
- 强调色用系统蓝 #0A84FF，只用在主按钮和选中态。
- 需要浅色和深色两套。浅色画布背景 #ECECEC、面板 #F6F6F6；深色画布背景 #1E1E1E、面板 #262626。
- 界面文案用英文，用户填写的描述用中文示例。

【标注样式（必须严格一致）】
截图以 1080×2400 像素的手机截图为基准：
- 编号徽标：实心圆，直径约为截图宽度的 5%，白色 4px 描边，中间白色粗体数字。
- 框选：4px 彩色描边矩形，编号徽标的圆心压在矩形左上角。
- Pin：4px 彩色描边的小圆环（半径约为截图宽度的 1.2%），一条同色细引线连到右上方的编号徽标，徽标不遮挡被指的点。
- 颜色按编号循环：#1 #FF3B30，#2 #0A84FF，#3 #AF52DE，#4 #FF9500，#5 #34C759，#6 #FF2D55。颜色只用来区分编号，没有其他含义。
- 当前选中的标注线宽加倍，其余不变。
- 截图上除了编号以外不出现任何文字。

【主窗口布局，1280×820】
- Toolbar 从左到右：设备选择器（手机图标 + "Pixel 7" + 下拉箭头的胶囊按钮）、Capture 按钮（camera.viewfinder 图标，悬停提示 ⌘⇧A）、Import 按钮；右侧：History 按钮、Export 主按钮（系统蓝实心，⌘E）。
- 左侧大区域是画布，手机截图按比例居中，四周留白，截图带 1px 细描边。
- 右侧是 340pt 宽的检查器面板，自上而下：
  1. 标题 "Issues" + 数量灰色标签。
  2. Issue 卡片列表：每张卡片左上是与标注同色的编号徽标，右侧是多行描述文本框，右上角悬停出现 × 删除。选中卡片有浅蓝底和 1px 蓝色描边。
  3. "References" 小节：竖版缩略图（约 64×142pt）横向排列，最后一个是虚线 + 号添加格。
  4. 最底部 "Figma" 单行输入框，左侧 link 图标。

【请产出以下画板】

A. 编辑器空状态（浅色）
画布中央是大号虚线圆角拖放区，里面一个 SF Symbol 插图和三行提示："Drop a screenshot"、"⌘V to paste"、"⌘⇧A to capture from device"。右侧面板显示一句灰色引导："Click to pin · Drag to frame"。Export 按钮置灰。

B. 编辑器工作状态（浅色，主画板，最重要）
画布上是一张社交类 Android App 的截图（顶部头像 + 标题栏、下方两个 Tab、再下方是两列卡片网格和底部导航）。上面有 3 个标注：
- #1 红色框，框住头像与标题之间的区域；
- #2 蓝色框，框住两个 Tab 所在的横条，处于选中态（线宽加倍）；
- #3 紫色 Pin，点在底部导航的一个图标上，引线连到右上方的徽标。
右侧 3 张卡片，#2 为选中态，描述分别是：
#1「头像和标题之间的留白明显偏大，以设计稿为准。」
#2「黄色选中态应该比紫色底更高，现在两者一样高。」
#3「这个 icon 比设计稿明显偏大。」
References 区有 2 张缩略图（设计稿截图）。Figma 输入框里有一条 figma.com/design/... 链接。Toolbar 设备选择器显示 "Pixel 7"，Export 可用。

C. 编辑器工作状态（深色）
与 B 内容完全相同的深色版本。

D. 设备菜单展开
在 B 的基础上展开设备选择器的原生 macOS 下拉菜单：
- ✓ Pixel 7 — 第二行灰色小字 37091JEHN
- Android Emulator — 第二行灰色小字 emulator-5554
- Galaxy S23 — 置灰，右侧黄色小警告图标和 "unauthorized"
- 分隔线
- Refresh，右侧快捷键 ⌘R

E. 导出成功 sheet
从窗口顶部落下的原生 sheet，宽约 440pt：绿色 checkmark.circle 图标、标题 "Exported"、一行 SF Mono 路径 "~/UIReview/2026-09-24/18-15-42"（可选中文本样式），底部按钮 "Reveal in Finder"（次按钮）和 "Copy Path"（系统蓝主按钮、默认回车）。背景是被压暗的 B。

F. 替换确认弹窗
原生 alert：标题 "Replace screenshot?"，正文 "This will clear 3 annotations."，按钮 "Cancel" 和红色破坏性按钮 "Replace"。背景是 B。

G. History 窗口（浅色，900×640）
独立窗口，标题 "History"。内容按日期分组，分组标题 "2026-09-24"、"2026-09-23"，粗体 13pt。每组下面是网格排列的竖版缩略图卡片（缩略图是带彩色编号标注的手机截图，约 120×266pt），缩略图下方是时间 "18:15:42"。悬停某张卡片时右上角浮出两个小图标按钮：复制路径（doc.on.doc）和在 Finder 中显示（folder）。只读，没有编辑入口。

H. Settings 窗口（浅色，560×260）
标题 "Settings"。一个分组表单，两行：
- "Workspace"：SF Mono 路径 "~/UIReview"，右侧 "Choose…" 按钮；
- "adb"：灰色 SF Mono 路径 "~/Library/Android/sdk/platform-tools/adb"（过长时省略号截断），后面一个绿色小标签 "Auto-detected"，右侧 "Choose…" 按钮。
表单下方一行灰色小字："Keep paths free of spaces — the export path is passed to Claude / Codex as a command argument."

【要求】
- 所有画板共用同一套组件和间距（8pt 网格），像一个真实可实现的 SwiftUI 应用，只用系统控件能做到的样式。
- 不要加入任何我没列出的功能（没有图层面板、没有颜色选择器、没有文字标注工具、没有箭头工具、没有登录、没有分享到云端）。
- 每个画板标注编号和名称，方便我导出 PNG。
```
