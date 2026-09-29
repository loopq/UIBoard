# UIBoard 应用图标与 GitHub Release

**基线**: [V1 实施计划](file:///Users/loopq/dev/git/loopq/uiboard/docs/plans/2026-09-24-uiboard-impl.md)

状态（2026-09-29）：已定深靛图标、v1.0.0、只出 arm64。代码已完成并验证：`swift build` 通过，27 个测试通过，`VERSION=1.0.0 scripts/bundle.sh` 通过；Info.plist 里有 `CFBundleIconFile`；`codesign -v --strict` 通过，zip 解压后同样通过；`NSWorkspace` 取到的就是新图标。另外 `install-skill.sh` 补了 `mkdir -p`（组员机器上可能没有 `~/.codex/skills`，原来会直接报错退出）。待办：commit → 用户 push → `gh auth login` → `scripts/release.sh 1.0.0`。

## 1. 核心判断

✅ 值得做。

- 图标：`build/UIBoard.app` 没有 `Contents/Resources` 和 `CFBundleIconFile`，Finder 和 Dock 里显示的是通用可执行文件图标。放一个 `.icns` 并在 Info.plist 里声明即可，不需要 asset catalog（`swift build` 本来就不跑 actool）。
- Release：组员没必要装 Swift 工具链自己编译。把打好的 zip 挂到 GitHub Releases 就能下载。仓库是 public，不需要授权。

关键风险：

| 风险 | 事实 | 处理 |
|---|---|---|
| Gatekeeper 拦截 | `bundle.sh` 只做 ad-hoc 签名，没有公证。浏览器下载会带 quarantine，macOS 15 会提示「Apple 无法验证」，而且没有右键打开的绕过方式 | 主路径改用终端一行命令安装：curl 下载的文件不带 quarantine，因此不会弹 Gatekeeper。浏览器下载作为备用，README 写明「系统设置 → 隐私与安全性 → 仍要打开」和 `xattr` 两种解法。上限：彻底解决需要 Developer ID 签名加公证（$99/年），真有需要再升级 |
| 架构 | 本机 arm64，默认产物只能在 Apple Silicon 上运行 | 默认只出 arm64。组员里有 Intel Mac 时，release 构建加 `--arch arm64 --arch x86_64` 出通用二进制 |
| 只装 App 不够 | 下游 `ui-review` skill 也要装 | README 写明 clone 本仓后执行 `scripts/install-skill.sh`（symlink 方式，之后 `git pull` 就能更新） |
| 版本号写死 | `bundle.sh` 里固定写着 `0.1` | 改为读取 `VERSION` 环境变量，默认值仍为 `0.1`，`install-app.sh` 行为不变 |

## 2. 改动

1. 图标（深靛方案，候选预览：`file:///tmp/uiboard-icon/final.png`）
   - `assets/AppIcon.svg`：源文件。1024 画布，824 圆角矩形（rx 185，Big Sur 模板）；倾斜的手机截图，底部被圆角裁掉；#1 红框加红色徽标、#2 蓝色 Pin 加引线；配色直接用 5.5 节 palette 和正式稿里截图的配色。
   - `assets/AppIcon.icns`：生成物，入库。这样打包不依赖 `rsvg-convert`。
   - `scripts/make-icon.sh`：SVG → iconset（16–1024 共 10 张）→ `iconutil -c icns`。只在改图标时执行，依赖 `brew install librsvg`。
2. `scripts/bundle.sh`：建 `Contents/Resources` 并拷入 `AppIcon.icns`；Info.plist 加 `CFBundleIconFile=AppIcon`；`CFBundleShortVersionString` 和 `CFBundleVersion` 都取 `${VERSION:-0.1}`。
3. `scripts/release.sh <version>`：
   - 门禁：工作区干净；`git fetch` 后 `HEAD == origin/main`（保证 tag 指向的代码就是打包用的代码）；`v<version>` 在远端不存在。
   - `swift test` → `VERSION=<version> scripts/bundle.sh` → `ditto -c -k --keepParent` 打包成 `build/UIBoard.zip`。用 ditto 不用 zip，是因为 zip 可能破坏签名。
   - `gh release create v<version> build/UIBoard.zip --repo loopq/UIBoard --target <HEAD sha> --notes <安装命令> --generate-notes`。remote 用的是 SSH 别名 `github-personal`，所以显式传 `--repo`。
   - 资源名固定为 `UIBoard.zip`，这样 `releases/latest/download/UIBoard.zip` 永远指向最新版。
   - 脚本不执行 `git push`；tag 由 GitHub 在创建 release 时生成。
4. `README.md`：在开头加「下载安装」一节，面向组员：一行安装命令、浏览器下载时的解法、skill 安装方式、更新方式（重跑同一条命令）。
5. `AGENTS.md`「构建与验证」加一行：发布用 `scripts/release.sh <version>`，需要先装好 `gh` 并登录。

一次性前置：`brew install gh`（agent 执行）；`gh auth login` 需要交互，由用户用个人账号 loopq 登录。

## 3. 验证

- `swift build`、`swift test`、`scripts/bundle.sh` 全部通过。
- `plutil -p build/UIBoard.app/Contents/Info.plist` 里有 `CFBundleIconFile`；`codesign -v build/UIBoard.app` 通过；打开 App 后 Dock 显示新图标。
- 解压 `build/UIBoard.zip` 到临时目录，`codesign -v` 仍然通过。
- 发布后，`curl -sIL .../releases/latest/download/UIBoard.zip` 最终返回 200；用一行安装命令装到临时目录，确认能启动。

## 4. 待确认

- 图标方案：深靛（推荐）/ 蓝色 / 浅色。
- 首个版本号。
- 组员里是否有 Intel Mac。
