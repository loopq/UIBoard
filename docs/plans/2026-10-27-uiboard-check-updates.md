# UIBoard 检查更新（GitHub Releases）与版本号规划

**基线**: [应用图标与 GitHub Release](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-29-uiboard-icon-release.md) · [V1 实施计划 第 5 节冻结契约](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-24-uiboard-impl.md)

状态（2026-10-27）：已实现并通过 E2E，未 commit。用户已确认两点：删除 v1.0.0，从 0.1.0 重新开始；App 内一键安装并重新打开。`swift build` 通过，32 个测试通过（新增 5 个 `UpdateTests`），`scripts/bundle.sh` 通过，默认版本号为 `dev`。`release.sh` 门禁实测：`1.0`、`v0.2.0` 因格式被拦；在 v1.0.0 仍是 Latest 时，`0.1.0` 和 `1.0.0` 被递增门禁拦；`1.0.1` 通过门禁后停在「working tree not clean」。

E2E 没有等 0.1.0 发布，直接拿 GitHub 上真实的 v1.0.0 当「新版本」，从本地 `VERSION=0.0.1` 的包升级。没有录屏权限，所以用 System Events 读 AX 树、文件系统和进程来判断：
- A dev 版：启动后不写 `lastUpdateCheck`，说明没有自动检查；手动检查只显示 toast「Development build — the latest release is 1.0.0」。
- B 0.0.1 版启动：自动弹出「UIBoard 1.0.0 is available / You have 0.0.1…」，三个按钮都在。
- C 点 Later 后重启：15 秒内没有弹窗，`lastUpdateCheck` 没有变化。
- D 有未导出标注时点 Install and Relaunch：磁盘上已换成 1.0.0，弹出现有的「Quit UIBoard?」。点 Cancel 后 toast「Update installed — reopen UIBoard to use 1.0.0」，等待重开的子进程被结束，原进程继续运行，标签和标注都还在。之后正常退出，没有被意外重新打开。
- E 正常流程：旧进程退出，约 1 秒后从 `/Applications` 起新进程，版本 1.0.0，没有 quarantine，`codesign --verify --strict` 通过，「应用程序」里没有残留。
- F 从只读目录运行时安装：弹出「Couldn't install UIBoard 1.0.0」和系统权限错误，按钮是 Open Release Page / Cancel；原 App 仍是 0.0.1，没有残留。

没有测的：断网时的报错（没有改本机网络）；Release Notes / Open Release Page 按钮（只调用 `NSWorkspace.open`，测了会在用户浏览器里开页面）。有一次手动检查点了菜单没有弹窗，之后重试和换场景都没再复现；判断是自动化操作当时没把 App 切到前台，不是代码问题。测完已用 `install-app.sh` 把「应用程序」里的 App 恢复成最新的 dev 版，并删掉了测试写入的 `lastUpdateCheck`。

## 1. 核心判断

✅ 值得做。组员是用 README 里的 curl 命令装的，不知道什么时候有新版本，每次更新还得翻出那条命令。

| 事实 | 影响 |
|---|---|
| v1.0.0 已发布，并且是 Latest；它没有更新功能 | 1.0.0 的用户无论选哪种方案，都得手动重装一次，之后才能自动更新 |
| `bundle.sh` 默认 `VERSION=0.1`，`install-app.sh` 本地装的就是 `0.1` | 开发版必须排除在更新之外，否则本地新代码会被提示「更新」到更旧的 release |
| `api.github.com/repos/loopq/UIBoard/releases/latest` 免登录可用，每个 IP 每小时 60 次；返回 `tag_name`、`html_url`、`assets[UIBoard.zip]`，自动排除 draft 和 prerelease | 不需要 token，每天自动查一次远低于限额 |
| 只有 ad-hoc 签名，没有公证。curl 和 URLSession 下载的文件不带 quarantine，但 `ditto` 默认会保留 quarantine | 解压时用 `--noqtn`；不能让用户走浏览器下载（macOS 15 上没有绕过入口） |

## 2. 版本号

- 格式 `MAJOR.MINOR.PATCH`，tag 为 `vX.Y.Z`。唯一来源是 `release.sh` 的参数，流向是 tag → Info.plist，仓库里不放 VERSION 文件。
- 0.x 阶段：加功能 MINOR+1，修 bug PATCH+1。
- **首个带更新功能的版本是 0.1.0。** 已发布的 v1.0.0 删除（用户已确认），理由如下：
  - 如果保留 v1.0.0 再发 0.1.0：GitHub 会把最新创建的 0.1.0 标为 Latest，curl 和更新检查都能用，但 release 列表里出现 1.0.0 → 0.1.0 的倒退，`release.sh` 的递增门禁也过不了。
  - 删除 v1.0.0 不影响任何自动流程，因为 1.0.0 没有更新功能。由用户执行 `gh release delete v1.0.0 --cleanup-tag --yes`。
- 本地构建：`bundle.sh` 默认 `VERSION=dev`。dev 版本不自动检查；手动检查只提示「这是开发版，最新 release 是 X」，不提供安装。
- `release.sh` 新增门禁：版本号必须是 `X.Y.Z`，并且必须大于当前 Latest，防止发错号导致 Latest 倒退。

## 3. 更新流程

数据流：GitHub latest → `Release { version, page, asset }` → `Updates.isNewer(release.version, than: 当前版本)` → 弹窗 → 安装 → 重新打开。

**触发**
- 菜单「UIBoard → Check for Updates…」：每次都给出结果。有新版就弹窗，已是最新就 toast，失败就 alert。
- 启动时自动检查：距上次检查满 24 小时才查（记录在 UserDefaults），只在有新版时弹窗，失败不提示；dev 构建不查。
- 弹窗：「UIBoard 0.2.0 is available」/「You have 0.1.0.」，按钮为 `Install and Relaunch`（默认）、`Release Notes`（打开 release 页）、`Later`。

**Install and Relaunch**（用户已确认）
1. 用 URLSession 把 `UIBoard.zip` 下载到与目标 App 同卷的临时目录（`FileManager` 的 `itemReplacementDirectory`）。
2. `ditto -x -k --noqtn` 解压。
3. 校验：bundle id 与当前 App 一致；`CFBundleShortVersionString` 等于 release 版本；`codesign --verify --strict` 通过。
4. 用 `FileManager.replaceItemAt` 原子替换 `Bundle.main.bundleURL`。运行中的进程不受影响。
5. 启动一个 `sh` 子进程：等本进程退出后 `open` 新 App。然后调用 `NSApp.terminate`。
6. `terminate` 只有在退出被取消时才会返回（比如有未导出标注，用户在退出确认框点了 Cancel）。这时结束子进程，toast「Update installed — reopen UIBoard to use 0.2.0」。复用现有的退出确认逻辑，不需要改 AppDelegate。

第 1–4 步任何一步失败，原 App 都不会被改动。失败时弹 alert 显示原因，并提供 `Open Release Page`。没有 `/Applications` 写权限的非管理员账号也会走到这个分支。

信任边界：HTTPS 加上 GitHub 仓库所有者。ad-hoc 签名只能校验完整性，不能校验身份。代码里用注释标出这个上限，升级路径是 Developer ID 加公证，或者给 zip 加 EdDSA 签名。

备选方案：只提示，按钮是「打开 Release 页」或「复制 curl 安装命令」。代码少很多，但前者会遇到 Gatekeeper 问题，后者每次更新都要开终端、先手动退出 App。

## 4. 改动

契约（先改 impl plan 第 5.1 和 5.2 节，再改代码）：
- `Model.swift`：新增 `public struct Release: Equatable { version, page, asset }`，以及 `UIBoardError.updateFailed(String)`。
- `API.swift`：新增
  ```swift
  public enum Updates {
      public static func latest(repo: String) async throws -> Release
      public static func isNewer(_ candidate: String, than current: String) -> Bool   // 只认 X.Y.Z，其他（dev/空）一律 false
      public static func install(_ release: Release, over app: URL) async throws      // 下载 → 解压 → 校验 → 原子替换
  }
  ```

Core / Tests：
- `Sources/UIBoardCore/UpdateSupport.swift`：内部实现，`ditto`、`codesign` 复用 `ProcessRunner`。
- `Tests/UIBoardCoreTests/UpdateTests.swift` 和 `Fixtures/release-latest.json`，覆盖：`isNewer` 的各种情况（包括 dev、两段式、10 > 9）；解析 JSON（包括缺少 `UIBoard.zip` asset 时报错）；用 `file://` 的 zip 安装一个 ad-hoc 签名的假 App，替换成功；bundle id 或版本不匹配时报错，并且目标 App 不变。

UI：
- `EditorModel.swift`：新增 `availableUpdate: Release?`、`isUpdating`。
- 新文件 `Sources/UIBoard/Updater.swift`（EditorModel 的 extension）：`checkForUpdates(manual:)`、`installUpdate(_:)`、重新打开逻辑、当前版本读取。
- `UIBoardApp.swift`：在 `CommandGroup(after: .appInfo)` 加 `Check for Updates…`，更新进行中时置灰；启动时触发自动检查。
- `EditorView.swift`：在 `EditorAlerts` 里加更新弹窗。
- `Prefs`：新增 `lastUpdateCheck` 和仓库常量 `loopq/UIBoard`。

脚本与文档：
- `bundle.sh`：默认 `VERSION=dev`。
- `release.sh`：加版本格式门禁和递增门禁；release notes 写明 0.1.0 起可在 App 内更新。
- README / AGENTS.md：更新说明（1.0.0 用户需要手动重装一次），发版示例改成 `0.x`。

不做：跳过此版本、设置里的自动检查开关、prerelease 通道、增量更新、Intel 版。以后需要再加。

## 5. 发布与验证

- `swift build`、`swift test`、`scripts/bundle.sh` 全部通过。
- 发布（用户执行）：commit → push → `gh release delete v1.0.0 --cleanup-tag --yes` → `scripts/release.sh 0.1.0`。
- E2E（发布后）：用 `VERSION=0.0.1 scripts/bundle.sh` 打包，装到 `/Applications` → Check for Updates → 弹出 0.1.0 → Install and Relaunch → 重新打开后版本是 0.1.0，没有 quarantine，`codesign` 通过。另外验证：
  - 有未导出标注时，在退出确认框点 Cancel → 出现 toast，App 照常可用，下次打开就是新版本；
  - dev 构建手动检查只显示提示，不提供安装；
  - 断网时手动检查会报错；
  - 24 小时内重启不会重复检查。
