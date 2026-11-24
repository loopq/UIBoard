---
name: ui-bug
description: 把已知的 UI 问题（运行截图 + 问题描述）导出成 UIBoard 同款 review 目录（uiboard-review/1 或 /2），产物可直接交给 /ui-review 修复。格式由 UIBoardCore 生成，与 UIBoard App 手动导出完全一致。触发：AI 测试发现 UI 不通过需要出 review、用户说「把这个 UI 问题导出成 UIBoard / ui-review 目录」「ui-bug」。不用于修复（修复用 ui-review）。
---

# ui-bug：UI 问题 → UIBoard review 目录

## 输入

- 截图：一张或多张（多张 = 同一页面的不同状态，导出为多帧 v2）。必须是设备原始截图，不要裁剪或缩放。
- 视图树（可选）：和截图同时抓的 uiautomator xml。AITest 的 `aitest snap x.png` 会同时留 `x.xml`。有它才能导出 `views` 行，ui-review 定位代码会准很多。
- 设备信息（可选）：serial、型号、density、activity。截图来自 ADB 时尽量给全；`density` 决定是否有 `dp` 行，可用 `adb -s <serial> shell wm density` 取。
- 设计稿（可选）：作为 `refs`，Figma 链接作为 `figma`。
- 问题列表：每条一句「现象 + 应该是什么」，以及位置线索（resource-id、可见文案或区域）。

## 步骤

1. 每个问题确定 `rect: [x, y, w, h]`（截图像素，原点左上）：
   - 有视图树：用 resource-id 或文案在 xml 里找节点，取它的 bounds（`[l,t][r,b]` → `x=l, y=t, w=r-l, h=b-t`）；
   - 没有：看图估一个刚好包住问题区域的矩形，宁可稍大不要漏；
   - 问题只是一个点（某个图标、某个像素位置）：用 Pin，`w=h=0`。
   rect 必须完全在图内。
2. 描述只写现象和期望，不写修法、不猜代码位置（定位交给 ui-review）。
3. 写 JSON（字段见下），调用：
   ```bash
   U=/Users/loopq/dev/git/loopq/uiboard/.build/release/uiboard-export
   [[ -x $U ]] || (cd /Users/loopq/dev/git/loopq/uiboard && swift build -c release --product uiboard-export)
   $U spec.json      # stdout = review 目录绝对路径；非 0 退出时按 stderr 修 JSON 再试
   ```
4. 输出：review 目录路径，以及一行可复制的 `/ui-review <路径>`。

```json
{
  "workspace": "/abs/输出根目录（默认 ~/UIReview；AITest 用 <运行目录>/uireview）",
  "figma": "https://www.figma.com/...",
  "refs": ["/abs/design.png"],
  "frames": [{"image": "/abs/shot.png", "serial": "d77de316", "model": "GM1910", "density": 560,
              "activity": "pkg/.ui.XxxActivity", "hierarchy": "/abs/shot.xml"}],
  "marks": [{"frame": 0, "rect": [96, 412, 888, 180], "note": "现象，应该是什么"}]
}
```

缺的字段直接省略，导出时对应行也会省略。导出目录只读，不要事后手改 review.md。

## 禁止

- 手写或修改 review.md / annotated.png：格式只由 `uiboard-export`（UIBoardCore）生成。
- 在本 skill 里改代码。
