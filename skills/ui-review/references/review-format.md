# UIBoard Review 目录格式

- `format: uiboard-review/1`：单张截图（下文 v1 各节）。
- `format: uiboard-review/2`：一个画板里横排多张截图（帧），见文末「多帧（v2）」一节。
- 读取方遇到不认识的主版本必须停下。

## 目录

```text
<workspace，默认 ~/UIReview>/YYYY-MM-DD/HH-mm-ss/
├── review.md          # 入口
├── runtime.png        # 原图，无标记
├── annotated.png      # 原分辨率 + 编号标记，无长文字
├── crops/1.png …      # 每个 #N 一张，原分辨率，从 runtime 裁出，无标记
├── ref-1.png …        # 可选：正确设计参考
└── hierarchy.xml      # 可选：ADB 截图时的 uiautomator 视图树
```

目录名是本地时间；同一秒导出多次时追加 `-2`、`-3`。目录一旦出现就是完整的（先写临时目录再 rename）。

## review.md 示例

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

黄色选中态应该比紫色底更高，现在两者一样高。

## #2

- rect: 675,2266,0,0
- dp: 257.1,863.2,0.0,0.0
- crop: crops/2.png @ 567,2158

这个 icon 比设计稿明显偏大。
```

## 字段

- 没有值的字段整行省略。`source: adb` 以及 `device` / `density` / `activity` / `dp` / `views` 只在截图来自 ADB 时出现；粘贴、拖入、打开文件的截图没有这些行。
- frontmatter 行顺序固定：`format, created, image, size, source, device, density, activity, figma, refs`。
- `created`：本地时区 ISO 8601，带偏移。
- `device`：`型号 (serial)`，型号下划线转空格；没有型号时只写 serial。
- `activity`：`dumpsys` 给出的 component 原样保留，形如 `包名/.相对类名` 或 `包名/完整类名`。
- `rect: x,y,w,h`：runtime.png 像素坐标，原点左上，整数。`w=h=0` 表示 Pin（点）。
- `dp: x,y,w,h`：`px × 160 / density`，四舍五入保留 1 位小数。
- `crop: 路径 @ ox,oy`：`ox,oy` 是 crop 左上角在 runtime 中的像素坐标。裁图范围 = rect 四周各外扩 `round(0.1 × 图宽)` 后与图片边界求交。
- `views`：最多 3 个视图树节点，按命中度降序，`resource-id [类名 x,y,w,h]`，` · ` 分隔；类名取 class 最后一段；bounds 是 runtime 像素，且是**可见区域**（越出父容器的部分被裁掉）。
- 描述：`## #N` 元数据列表之后的全部正文，原样保留，可以多行。

## 命中规则（views 是怎么来的）

```text
q = rect 为零尺寸 ? 以该点为中心的 2×2 rect : rect
候选 = resource-id 非空、不以 "android:id/" 开头、bounds 面积 > 0 且 < 视图树最大节点面积的 90%、与 q 相交的节点
score = area(q ∩ b) / area(q ∪ b)
按 score 降序；相同则面积小者优先；再相同按视图树文档顺序；取前 3
```

对 Pin 来说，排第一的是包含该点的最小带 id 节点。铺满窗口的容器不参与命中（它们不提供位置信息）；所以 `views` 缺失可能意味着目标节点本身没有 resource-id，此时按 activity + 可见文案定位，也可以按 rect 在 `hierarchy.xml` 里查同位置节点的 `text` / `content-desc`。

## 多帧（v2）

一个画板里有 2 张及以上截图（例如同一页面的两个状态）时导出为 v2；只有 1 张时仍是 v1，逐字不变。

```text
review.md · runtime.png（整板拼图，无标注）· annotated.png（整板拼图 + 标注）· crops/N.png · ref-N.png · hierarchy-A.xml …
```

```markdown
---
format: uiboard-review/2
created: 2026-09-24T18:15:42+08:00
image: runtime.png
size: 2225x2400
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

## #2

- frame: B
- rect: 540,1200,0,0
- crop: crops/2.png @ 432,1092

未选中状态下 Tab 文字颜色太浅。
```

- 帧用字母 A、B、C 标识（Z 之后是 AA、AB…），从左到右横排、顶对齐；帧之间与短帧下方是灰色填充 `#E5E5EA`。
- 顶层 `size` 是拼图尺寸；每帧的 `offset` / `size` 是它在拼图中的位置与原始尺寸。设备相关行（`source/device/density/activity/hierarchy`）按帧给出，缺失就省略。
- 问题编号在整个画板内连续；每个问题多一行 `frame`，其 `rect`、`crop` 原点、`views` bounds 都是**帧内**像素。在拼图 / annotated.png 中的位置 = 该帧 `offset` + 帧内坐标。
- `dp` 用该帧的 density 换算，`views` 用该帧的 `hierarchy-X.xml` 命中；帧没有设备信息时这两行不出现。

## annotated.png 上的标记

- 编号圆徽标按编号循环配色：#1 `#FF3B30`、#2 `#0A84FF`、#3 `#AF52DE`、#4 `#FF9500`、#5 `#34C759`、#6 `#FF2D55`。颜色只用来区分编号，没有其他含义。
- 框：彩色描边矩形，徽标圆心在矩形左上角。
- Pin：小圆环标在目标点上，一条细引线连到右上方的徽标。引线只是连接线，**不表示移动方向**。
