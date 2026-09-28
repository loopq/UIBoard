# UI Review Board MVP — Implementation Plan

## 1. 背景

在 Vibe Coding / AI 辅助 UI 开发过程中，页面主体通常可以较快完成，但最后一阶段的 UI 微调沟通成本很高。

典型场景包括：

* 某个组件位置不对
* 留白看起来不合理
* 图标、字体、对齐方式和设计稿不一致
* 局部区域需要参考 Figma 重新调整
* AI 很难仅凭“这里不对”“按钮偏低”准确知道问题位置

目前常见做法是：

1. 运行 App
2. 截图
3. 在截图上画框、箭头、文字
4. 将截图发给 AI
5. 再用自然语言解释问题

问题在于，当截图内同时存在多个 UI 问题时，图片上会出现大量文字、箭头和方框，视觉信息非常混乱。

因此需要一个非常轻量的 Mac 工具，用于把：

> “这个 UI 的 #1、#2、#3 有问题”

整理成 AI 可以直接理解的结构化视觉上下文。

---

# 2. 产品定位

这是一个：

**Visual Context Builder for AI Coding**

不是 UI 自动测试工具。

不是 Figma Diff 工具。

不是 UI Agent。

不是自动修复工具。

不是截图编辑器。

它只负责：

> 把 Runtime UI 中存在问题的位置标清楚，并附上文字说明和正确设计参考，然后导出一个目录交给 Codex / Claude。

---

# 3. 核心设计原则

整个 MVP 必须始终遵循以下原则。

## 3.1 极度轻量

优先：

* 能用
* 快
* 操作少
* 实现简单

而不是：

* 功能完整
* 架构完美
* 自动化程度高
* 数据模型复杂

遇到功能取舍时使用下面这条原则：

> 如果一个功能不能明显降低“截图 → 描述问题 → 交给 AI”的成本，V1 不做。

---

## 3.2 人负责指出问题，不负责解决问题

用户不应该被要求知道：

* 正确 spacing 是多少
* 应该改哪个 padding
* 应该改哪个 Compose Modifier
* 应该修改哪个文件

例如用户只需要描述：

> #1 头像和标题之间留白明显太大，以设计稿为准。

而不是：

> 把 padding 从 24dp 改成 16dp。

精确参数由：

* Figma
* Reference Design
* 当前代码

共同提供给 Codex / Claude。

---

## 3.3 图片负责 Where，文字负责 What

不要把大量文字直接写在截图上。

Annotated Screenshot 只负责表达：

* #1 在哪里
* #2 在哪里
* #3 在哪里

右侧 Issue Panel 负责表达：

* 什么地方有问题
* 需要参考什么设计

因此：

```text
Annotated Image = Where

Issue Description = What

Reference Image = Expected

Figma URL = Exact Design Context
```

---

# 4. 整体工作流

```text
Android App
    ↓
运行到存在 UI 问题的页面
    ↓
Mac UI Review Board
    ↓
ADB Capture / Paste / Drag & Drop
    ↓
获得 Runtime Screenshot
    ↓
使用 Pin / Rectangle / Arrow 标注
    ↓
产生 #1 #2 #3...
    ↓
右侧填写对应 Issue 描述
    ↓
可选添加：
- Ref A
- Ref B
- Figma URL
    ↓
Export
    ↓
生成 Review Directory
    ↓
Copy Path
    ↓
交给 Codex / Claude Skill
    ↓
AI 在当前代码项目中自行定位实现并修改
```

工具自身到 Export 为止。

后续代码修改不属于本 App。

---

# 5. MVP 页面

只需要三个主要界面。

## 5.1 Review Editor

核心页面。

大部分时间都在这里操作。

布局：

```text
┌───────────────────────────────────────────────────────┐
│ Device ▼   Capture   Import   Ref A   Ref B   Export │
├────────────────────────────┬──────────────────────────┤
│                            │                          │
│                            │ #1                      │
│                            │ [ description ]          │
│                            │                          │
│     Runtime Screenshot     │ #2                      │
│                            │ [ description ]          │
│        ①                   │                          │
│                            │ #3                      │
│    ┌──────────┐            │ [ description ]          │
│    │    ②     │            │                          │
│    └──────────┘            │                          │
│              ─────→ ③      │                          │
│                            │                          │
├────────────────────────────┴──────────────────────────┤
│ Figma URL                                              │
└───────────────────────────────────────────────────────┘
```

左侧：

Runtime Screenshot + Annotation。

右侧：

Issue Description。

---

## 5.2 Device Picker

ADB 多设备时使用。

类似 Android Studio 的设备选择方式。

示例：

```text
Devices

✓ Pixel 7
  37091JEHN

  Android Emulator
  emulator-5554

[ Refresh ]
```

要求：

* 启动时读取一次 `adb devices`
* 支持 Refresh
* 记住最后选择的 Device Serial
* App 重启后优先恢复
* 如果设备不存在，则等待用户重新选择
* 多设备时不要随意自动切换

ADB 实际执行必须始终使用 serial：

```bash
adb -s <serial> exec-out screencap -p
```

---

## 5.3 History

只展示已经 Export 的 Review。

不展示草稿。

按日期分类：

```text
2026-09-24

┌─────────────┐
│ thumbnail   │
└─────────────┘
18:15:42

┌─────────────┐
│ thumbnail   │
└─────────────┘
17:42:31
```

History 信息只需要：

* Date
* Time
* Annotated Screenshot thumbnail

点击之后：

* 查看导出的内容
* Reveal in Finder
* Copy Path

V1 不要求重新编辑 History。

---

# 6. Runtime Screenshot 输入

支持三个入口。

## 6.1 ADB Capture

Android 主入口。

用户手动触发。

可以使用：

* Toolbar Button
* Keyboard Shortcut

例如：

```text
⌘ + Shift + A
```

流程：

```text
当前选择的 Device
↓
adb screencap
↓
Runtime Screenshot
↓
进入 Editor
```

不做：

* 自动截图
* 自动监听页面变化
* 自动 Device Polling
* 自动 Review Loop

---

## 6.2 Paste

支持：

```text
⌘ + V
```

Clipboard 图片直接作为 Runtime Screenshot。

---

## 6.3 Drag & Drop

允许任意 PNG / JPG 拖入。

这样工具不仅限于 Android。

未来：

* iOS
* Web
* Flutter
* React Native
* Desktop

都可以使用。

ADB 只是一个 Input Adapter。

---

# 7. Annotation

左侧只允许三个工具。

不要继续增加。

## 7.1 Pin

点击某个位置：

```text
①
```

适合非常局部的问题。

---

## 7.2 Rectangle

框选区域：

```text
┌───────────┐
│     ②     │
└───────────┘
```

适合：

* 组件
* 一组布局
* 较大 UI 区域

---

## 7.3 Arrow

```text
③ ─────→
```

箭头只表达：

> 指向这个目标。

不要给 Arrow 定义“移动方向”的语义。

避免 AI 将：

```text
→
```

错误理解成：

> 向右移动。

---

# 8. Annotation 编号和颜色

每新增一个 Annotation：

```text
#1
#2
#3
...
```

自动生成对应 Issue。

颜色只用于区分不同 Issue。

例如：

```text
#1 red
#2 blue
#3 purple
#4 orange
```

不要让颜色代表：

* spacing
* alignment
* typography
* error severity

V1 不需要 Issue Classification。

目标只是快速对应：

```text
左边 #2
↔
右边 #2
```

---

# 9. Issue Panel

每个 Annotation 自动对应一个 Issue。

Issue V1 只有一个核心字段：

```text
Description
```

例如：

```text
#1

头像与标题之间的间距明显偏大，
请以正确设计图和 Figma 为准。
```

不需要：

* Type
* Priority
* Status
* Assignee
* Expected dp
* Current dp
* Related file
* Related module

不要把 Bug Tracker 的复杂度带进来。

---

# 10. Reference Design

最多支持两张正确设计图：

```text
Ref A
Ref B
```

来源：

* Drag & Drop
* Paste
* File Picker

不做：

* Figma 自动截图
* Figma API Image Export
* Pixel Diff
* Overlay
* Slider Compare
* 自动差异检测

Reference 的作用仅仅是：

> 给用户和 AI 一个正确视觉结果。

如果只有一张，就只保存 Ref A。

---

# 11. Figma URL

整个 Review 支持一个全局 Figma URL。

例如：

```text
https://figma.com/...
```

仅保存链接。

V1 App 自身：

* 不解析 Figma
* 不调用 Figma API
* 不登录 Figma
* 不读取 Node

之后 Codex / Claude 如果具备 Figma MCP 或其他能力，可以自行使用该 URL 获取进一步设计上下文。

这样避免把 Figma 集成复杂度引入 App。

---

# 12. Export

用户点击 Export 后才创建正式历史数据。

Export 前所有内容可以视为临时编辑状态。

Export Directory：

```text
~/UIReview/
```

目录结构：

```text
UIReview/
├── 2026-09-24/
│   ├── 18-15-42/
│   │   ├── runtime.png
│   │   ├── annotated.png
│   │   ├── ref-a.png
│   │   ├── ref-b.png
│   │   └── review.md
│   │
│   └── 19-04-21/
│
└── 2026-09-25/
```

命名规则：

```text
YYYY-MM-DD/
    HH-mm-ss/
```

不要：

* feature name
* module name
* project name
* UUID
* title

目录结构保持纯时间。

History 可以直接根据 Date + Time 查询。

---

# 13. Export 文件说明

## runtime.png

原始 Runtime Screenshot。

不含任何标记。

---

## annotated.png

Runtime Screenshot +：

* Pin
* Rectangle
* Arrow
* #1 #2 #3

不包含长文字。

---

## ref-a.png

可选。

正确设计 Reference A。

---

## ref-b.png

可选。

正确设计 Reference B。

---

## review.md

自动生成。

用户不需要手动编辑 Markdown。

格式保持稳定、简单。

示例：

```markdown
# UI Review

Figma:
https://figma.com/example

References:
- ref-a.png
- ref-b.png

## #1

头像和标题之间的留白明显过大。
请根据设计稿确定正确效果。

## #2

Tab 区域整体垂直位置不对。

## #3

这个 icon 的大小与设计稿明显不同。
```

如果没有 Figma：

省略 Figma Section。

如果没有 Reference：

省略 References。

---

# 14. Export 完成后的 UX

不要只有：

```text
Export Success
```

应该显示：

```text
Exported

/Users/.../UIReview/2026-09-24/18-15-42

[ Copy Path ]
[ Reveal in Finder ]
```

主动作：

```text
Copy Path
```

因为下一个动作通常就是：

```text
把路径交给 Codex / Claude
```

---

# 15. History 实现

History 不需要数据库。

不需要 session.json。

不需要复杂 persistence。

直接扫描：

```text
~/UIReview/YYYY-MM-DD/HH-mm-ss/
```

目录。

每个 Review：

* 日期来自父目录
* 时间来自目录名
* thumbnail 使用 annotated.png

UI：

```text
Date Section
    ↓
Time
Thumbnail
```

点击：

```text
Open
Copy Path
Reveal in Finder
```

V1 History 是只读浏览器。

---

# 16. 本地持久化

只需要保存少量设置：

```text
workspaceDirectory

lastSelectedDeviceSerial
```

可以再保存：

```text
window size
window position
```

但不是必须。

不要为此引入数据库。

NSUserDefaults / Preferences 类方案即可。

---

# 17. Codex / Claude Skill

App 和 AI Coding Agent 必须保持解耦。

Review App：

> 创建视觉上下文。

Skill：

> 使用视觉上下文修改代码。

Skill 第一版输入只需要：

```text
review_path
```

例如：

```text
/ui-review /Users/.../UIReview/2026-09-24/18-15-42
```

Skill 行为：

```text
1. 读取 review.md

2. 查看 annotated.png

3. 根据需要查看 runtime.png

4. 查看 ref-a.png / ref-b.png

5. 如果存在 Figma URL：
   在可用情况下读取 Figma Context

6. 在当前打开的代码项目中自行寻找相关实现

7. 根据 #1 #2 #3 顺序修改

8. 不要求 Review App 提供：
   - module
   - file
   - class
   - Compose component
```

AI 自己负责代码搜索和定位。

不要让 Review App 变成代码索引工具。

---

# 18. Skill 推荐约束

可以给 Codex / Claude Skill 使用下面的规则：

```text
Use the supplied UI Review directory as visual context.

Read review.md first.

Use annotated.png to identify exactly which visual region each numbered issue refers to.

Use runtime.png when the annotation obscures useful visual information.

Use ref-a.png and ref-b.png only as correct visual references.

If a Figma URL exists, use it when available to determine exact layout, typography, spacing or component properties.

Do not assume the user's visual description contains the exact implementation solution.

The user identifies what looks wrong. You are responsible for locating the implementation cause.

Search the current repository for the relevant UI implementation.

Prefer fixing the underlying layout/component cause instead of applying arbitrary offset hacks.

Only modify code relevant to the reported issues unless a shared component is clearly the root cause.

After implementation, summarize changes issue-by-issue.
```

---

# 19. 非目标 / Explicit Non-Goals

以下内容 V1 明确禁止实现，除非基础版本已经真实使用后证明必须增加。

## 不做 AI 自动化

不做：

```text
Screenshot
↓
AI Review
↓
AI Fix
↓
ADB Capture
↓
AI Review
↓
Loop
```

原因：

多模态上下文成本很高。

UI 微调容易产生大量低价值视觉 Token 消耗。

用户继续作为 Human-in-the-loop。

---

## 不做 Pixel Diff

Runtime 和 Figma：

* 尺寸可能不同
* 字体 Rasterization 不同
* Status Bar 不同
* 数据内容不同

像素级 Diff 的收益远低于实现复杂度。

---

## 不做自动测量

App 不需要知道：

```text
当前 24dp
正确 16dp
```

这些交给 Figma + AI。

---

## 不做项目关联

不要让用户填写：

* Project
* Module
* Feature
* File
* Class

原因：

这会显著增加使用负担。

同时可能过早限制 AI 的搜索范围。

---

## 不做结构化 Issue 管理

不做：

* Priority
* Severity
* Status
* Tags
* Category

Issue 只有：

```text
Number
Annotation
Description
```

---

## 不做数据库

文件系统就是数据源。

---

## 不做历史版本

第一次 Export 即生成一份历史。

V1 不需要复杂修改 / Revision / Version。

---

## 不做云同步

完全 Local First。

---

# 20. 推荐开发顺序

不要同时开发所有东西。

按照最短闭环推进。

## Phase 1 — Skeleton

目标：

App 能运行。

实现：

* Mac App Shell
* 左右布局
* 图片显示
* Paste
* Drag & Drop
* Workspace Directory

完成条件：

可以加载一张截图。

---

## Phase 2 — Annotation

实现：

* Pin
* Rectangle
* Arrow
* 自动编号
* Issue Panel
* Description

完成条件：

可以在截图上产生：

```text
#1
#2
#3
```

并填写对应描述。

---

## Phase 3 — Export

实现：

* annotated.png rendering
* runtime.png
* review.md
* Ref A
* Ref B
* Figma URL
* Date / Time directory
* Copy Path
* Reveal in Finder

完成条件：

已经可以实际把 Review Directory 扔给 Codex / Claude 使用。

到这里其实就已经是一个完整可用产品。

---

## Phase 4 — ADB

实现：

* adb devices
* Device Picker
* Refresh
* remember selected device
* adb screencap
* shortcut

完成条件：

Android 开发过程中不需要手工截图传文件。

---

## Phase 5 — History

实现：

* scan workspace folders
* date sections
* annotated thumbnail
* time
* Copy Path
* Reveal in Finder

完成条件：

能够快速找到之前 Export 的 Review。

---

## Phase 6 — Codex / Claude Skill

实现：

```text
/ui-review <review_path>
```

读取导出的 Review Context，并完成代码修改。

---

# 21. MVP 验收标准

只有下面这些真正全部工作，才认为 V1 完成。

### Capture

* 可以通过 ADB 截图
* 多设备可以选择
* 可以刷新设备
* 能记住上一个 Device
* 可以 Paste
* 可以 Drag & Drop

### Annotation

* Pin 可用
* Rectangle 可用
* Arrow 可用
* 自动编号
* Issue Description 与编号对应

### Reference

* 可以添加 Ref A
* 可以添加 Ref B
* 可以保存 Figma URL

### Export

能够生成：

```text
runtime.png
annotated.png
ref-a.png (optional)
ref-b.png (optional)
review.md
```

目录：

```text
YYYY-MM-DD/HH-mm-ss/
```

Export 后：

* Copy Path
* Reveal in Finder

### History

* 可以根据日期浏览
* 显示时间
* 显示 annotated.png thumbnail
* 可以 Copy Path
* 可以 Reveal in Finder

### AI Handoff

给 Codex / Claude 一个 Review Directory Path 后，AI 能够明确知道：

* 当前 UI 长什么样
* #1 / #2 / #3 分别在哪里
* 每个 Issue 的描述是什么
* 正确设计参考是什么
* Figma 在哪里

然后 AI 自行进入当前代码项目定位和修改。

---

# 22. 最终产品边界

整个系统保持如下职责划分：

```text
Android / Runtime
负责产生当前 UI

UI Review Board
负责：
Where + What + Reference

Figma
负责：
Correct Design Context

Codex / Claude
负责：
Find Code + Understand Cause + Fix
```

Review Board 永远不要逐渐变成：

```text
IDE
+
Figma Client
+
AI Agent
+
Visual Testing Platform
+
Bug Tracker
```

如果未来确实需要这些能力，也应该基于真实使用痛点单独增加。

V1 的成功标准不是功能数量。

而是：

> 开发者遇到 UI 微调问题时，可以在几十秒内完成截图、#1/#2/#3 标注、描述、Reference 添加和 Export，然后把一个路径直接交给 Codex / Claude。

只要这个流程比“截图以后在聊天里反复解释哪里有问题”明显顺畅，V1 就已经成立。
