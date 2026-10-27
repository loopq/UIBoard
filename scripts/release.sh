#!/bin/bash
# scripts/release.sh 0.2.0 -> GitHub release v0.2.0 with build/UIBoard.zip. Needs `gh auth login`; never pushes.
set -euo pipefail
VERSION="${1:?usage: scripts/release.sh <version>, e.g. 0.2.0}"
TAG="v$VERSION"
REPO="loopq/UIBoard"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
abort() { echo "abort: $*" >&2; exit 1; }

# The in-app updater only orders strict X.Y.Z and only offers versions above the installed one.
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || abort "version must be X.Y.Z, got $VERSION"
LATEST="$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null || true)"
LATEST="${LATEST#v}"
if [ -n "$LATEST" ]; then
  [ "$VERSION" != "$LATEST" ] && [ "$(printf '%s\n%s\n' "$LATEST" "$VERSION" | sort -V | tail -1)" = "$VERSION" ] \
    || abort "$VERSION must be greater than the latest release $LATEST"
fi

[ -z "$(git status --porcelain)" ] || abort "working tree not clean"
git fetch -q origin main
SHA="$(git rev-parse HEAD)"
[ "$SHA" = "$(git rev-parse origin/main)" ] || abort "HEAD is not origin/main; push first so the tag matches the build"
! git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null || abort "$TAG already exists on origin"

swift test
VERSION="$VERSION" scripts/bundle.sh
ZIP="$ROOT/build/UIBoard.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/UIBoard.app "$ZIP"

# Asset name stays UIBoard.zip so releases/latest/download/UIBoard.zip always points at the newest build.
gh release create "$TAG" "$ZIP" --repo "$REPO" --target "$SHA" --title "UIBoard $VERSION" --generate-notes --notes "$(cat <<EOF
## 安装 / 更新

已装 0.1.0 及以上版本：在 App 里点「UIBoard → Check for Updates…」，一键安装并重新打开。

首次安装，或从 0.1.0 之前的版本升级：先退出正在运行的 UIBoard，再在终端执行：

\`\`\`bash
curl -fL https://github.com/$REPO/releases/latest/download/UIBoard.zip -o /tmp/UIBoard.zip && rm -rf /Applications/UIBoard.app && ditto -x -k /tmp/UIBoard.zip /Applications && open /Applications/UIBoard.app
\`\`\`

仅支持 Apple Silicon、macOS 14+。用浏览器下载以及安装 ui-review skill 的方法见 [README](https://github.com/$REPO#下载安装)。
EOF
)"
