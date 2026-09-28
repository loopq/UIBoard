---
name: ui-review
description: 读取 UIBoard 导出的 UI Review 目录（形如 ~/UIReview/YYYY-MM-DD/HH-mm-ss，含 review.md 且 format 为 uiboard-review/1），把每个 #N 问题关联到当前仓库的模块文件（Activity / Fragment / layout / view id），先产出关联表与修复 plan，确认后再改代码。可在路径后附定位提示（文件 / 类名 / 目录 / 一句话，可用 `#N:` 限定到单个问题）。触发：/ui-review <path> [提示]、$ui-review <path> [提示]，或用户贴出 UIReview 目录路径要求修 UI。
---

# UI Review → 模块文件关联与修复

## 输入

- 一个或多个 review 目录路径（可带引号）。review 目录是只读输入，禁止在里面写任何文件。
- 可选的定位提示：参数里凡是「存在且含 `review.md` 的目录」都是 review 路径，其余内容一律是提示。提示可以是文件路径、类名、目录 / 模块、页面描述；以 `#N:` 开头的只作用于第 N 个问题，否则作用于全部。
- 先读 `review.md` frontmatter：`format` 必须是 `uiboard-review/1`，主版本不认识就停下报告。
- 字段含义见 `references/review-format.md`。

## 读取顺序（控制视觉 token）

1. `review.md` 全文。
2. `annotated.png` 看一次，建立各 #N 的整体位置感。
3. 每个 #N 看 `crops/N.png`（原分辨率），细节判断以 crop 为准。
4. `ref-*.png` 只作为正确结果参考。
5. `runtime.png` 只在 crop 不够时看。
6. `hierarchy.xml` 只在需要邻近节点时用 `rg` 按 bounds 或 id 查，不整篇读入。

## 坐标

- `rect: x,y,w,h` 是 runtime.png 像素，原点左上；`w=h=0` 是点。
- 有 `dp` 行时直接拿它和 layout / Figma 的 dp 值比较；没有 `dp` 行说明截图不是 ADB 来源，不要假设 density。
- `crop: 路径 @ ox,oy` 中 `ox,oy` 是 crop 左上角在 runtime 中的坐标。
- Pin 的引线只是连接线，不代表移动方向。
- `views` 的 bounds 是**可见区域**：越出父容器（translation、负 margin）的部分会被裁掉。拿它和 layout 尺寸比较时，以 layout 声明为准，被裁的差值本身就是线索。

## 关联模块文件（每个 #N，按证据强度依次尝试，命中即停）

有提示时，先从提示指向的文件 / 类 / 目录开始找，但结论必须用下面的运行时证据核对：

- 提示与 `views` / `activity` 一致：来源记「一致」，置信度按证据取。
- 提示与运行时证据冲突（例如命中的 id 不在提示的文件里）：**以运行时证据为准**，来源记「冲突」，在根因假设里写明提示指向哪里、证据指向哪里，不要悄悄只采纳一方。
- 没有 `views` 时（Compose、全屏画布、目标无 id、通用容器 activity），提示成为首选入口：能被 activity 或 crop 文案佐证记「高」，否则记「推测」。
- 提示只决定从哪开始找，不限制修改范围；根因在共享组件时按「修复原则」处理。

1. `views`：取 resource-id 的 name → `rg -n '@\+id/<name>\b' --glob '**/res/layout*/**'` → layout 文件:行 → 找引用该 layout 的类（`R.layout.<layout>` 或 `<LayoutCamel>Binding`）→ 在类中找该 view 的使用（`binding.<nameCamel>` / `R.id.<name>`）。同一个 id 出现在多个 layout 时，选同时包含该 #N 其他命中 id（父容器）的那个 layout；仍有多个时再用 activity 所承载的页面链路（Activity → Fragment / ViewPager）排除。
2. `activity`：定位 Activity 类文件，结合 crop 可见内容锁定其 Fragment / Adapter / 子布局。
3. crop 中的可见文案：`rg` 字符串资源的 value → `@string/<name>` / `R.string.<name>` 的使用处。
4. 以上都没有：按视觉结构与页面语义搜索，置信度标「推测」。

resource-id 或 activity 属于第三方包（广告 SDK 等）时标注「非本仓代码」，不改。

## 产出

先输出关联表：

| # | 问题摘要 | 来源（views / activity / 文案 / 提示 / 一致 / 冲突 / 推测） | 证据 | 文件:行 | 置信度（确定/高/推测） | 根因假设 |
|---|---|---|---|---|---|---|

然后：

- 当前仓库的 AGENTS.md / CLAUDE.md 要求先出 plan：按该仓库的文档路由写 plan，标题下一行固定为 `**UI Review**: file://<review 目录绝对路径>`，写完停下等确认。
- 否则：按 #N 顺序直接修改。

## 修复原则

- 用户只指出哪里不对，描述里不包含解法；精确值来自 ref、Figma 与现有代码。
- frontmatter 有 `figma` 且 Figma MCP 可用时，按 node 读取精确尺寸；大帧先 get_metadata + get_screenshot，不要直接对整帧取 design context。
- 修布局 / 组件的根因，不加任意 offset；共享组件确实是根因时才改共享组件。
- 图片尺寸类问题：先比较位图原始尺寸（px ÷ 所在密度桶倍率）与 layout 的 dp。两者相等时只改 View 尺寸会留白或拉伸，需要更大的资源或调整 scaleType。
- 只改与各 #N 相关的代码。

## 验证与收尾

- 按当前仓库规则执行编译验证（如 Android 项目的 assemble 命令）。
- 按 #N 汇总：文件:行、改了什么、为什么；列出需要用户真机复验的点。
- 复验方式：用户重新截图并导出新的 review；不回写旧目录。
