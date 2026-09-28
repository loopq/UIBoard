# UIBoard 多标签画板 代码审查

- 范围：`b4a44d9..71e74c3`（契约 `d6e193e` + 实现 `71e74c3`）
- 审查方：Codex（`cxd-third` profile，gpt-5.6-sol，只读）
- 对照：[plan](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-28-uiboard-boards-frames.md)、`skills/ui-review/references/review-format.md`
- 结论：Core 的 v1/v2 格式、拼图坐标、按帧 crop / HitTest、帧号顺延、渲染缓存键都没有发现缺陷。报出的 4 条都集中在「异步操作没有绑定稳定的画板身份和内容版本」这类问题上，4 条全部成立，已全部修复。

| # | 严重度 | 问题 | 裁决 | 修复 |
|---|---|---|---|---|
| 1 | High | 导出在取快照后是异步进行的，期间修改的内容会被错误标成「已导出」（✓），之后关闭标签或退出都不再确认，会丢数据 | 成立 | 用版本号代替「已导出」标记：`Board` 的 frames / marks / refs / figmaURL 每次修改都会 `revision += 1`；导出时记录快照的 revision，`isExported = exportedRevision == revision`。导出期间有修改时两个值自然不相等，不需要额外判断 |
| 2 | Medium | 追加帧 / 参考图在异步完成时才去读「当前标签」，期间切换标签会导致内容落到别的标签；目标标签被关闭后会意外新建标签 | 成立 | `Destination.currentBoard` 改为 `.board(UUID)`；所有入口在发起时把 `model.here` 存进局部变量，再启动 Task。目标标签已关闭时新开一个标签承接，截图不丢失 |
| 3 | Medium | 帧标签在 26 帧之后循环（第 27 帧又叫 A），v2 会出现重名帧，`hierarchy-A.xml` 也会被覆盖 | 成立 | 不加上限，改为 Excel 式递增：Z 之后是 AA、AB…，从根上消除重名；新增单元测试，验证 800 个标签互不重复 |
| 4 | Low | 没有标签时，Capture 下拉里的「Add to This Board」被禁用，和路由表不一致 | 成立 | 去掉禁用条件；没有目标标签时自动新建 |

## 验证

- `swift build` 无告警，`swift test` 27 项通过（新增帧标签测试），`scripts/bundle.sh` 通过。
- 用临时调试钩子复现并验证（钩子已删除）：
  - 导出进行中修改描述 → 导出后 `isExported=false`、dirty=1；重新导出后 `isExported=true`。
  - 在 A 发起追加后切到 B → 帧落在 A（A 2 帧，B 1 帧），当前标签仍是 B。
  - 目标标签已关闭 → 新开标签承接（标签数 1 → 2）。
