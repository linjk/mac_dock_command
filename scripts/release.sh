#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh [x.y.z] [--install]

  当前版本只看仓库根目录 VERSION。
  不传 x.y.z 时补丁自动 +1（0.1.0 → 0.1.1），并写回 VERSION 与 Info.plist。
  每次发布 CFBundleVersion +1。
  VERSION 与 Info.plist 不一致则直接失败，避免写错。
  产物：dist/BarCmd.app 与 dist/BarCmd-<version>.zip
  --install 覆盖 /Applications/BarCmd.app 并打开。不删命令 YAML。
EOF
  exit 1
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"
PLIST="$ROOT/BarCmd/BarCmd/Resources/Info.plist"
PROJECT="$ROOT/BarCmd/BarCmd.xcodeproj"
DERIVED="$ROOT/.build/release"
DIST="$ROOT/dist"
PBUDDY=/usr/libexec/PlistBuddy

VERSION=""
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage ;;
    --install) INSTALL=1 ;;
    *)
      if [[ -n "$VERSION" ]]; then
        echo "多余参数：$arg" >&2
        usage
      fi
      VERSION="$arg"
      ;;
  esac
done

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "找不到 $VERSION_FILE" >&2
  exit 1
fi
if [[ ! -f "$PLIST" ]]; then
  echo "找不到 $PLIST" >&2
  exit 1
fi

current_short="$(tr -d '[:space:]' < "$VERSION_FILE")"
plist_short="$("$PBUDDY" -c 'Print :CFBundleShortVersionString' "$PLIST")"
current_build="$("$PBUDDY" -c 'Print :CFBundleVersion' "$PLIST")"

if [[ "$current_short" != "$plist_short" ]]; then
  echo "VERSION ($current_short) 与 Info.plist ($plist_short) 不一致，先对齐再发布" >&2
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  if [[ ! "$current_short" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "无法从 VERSION ($current_short) 自动升补丁，请传入 x.y.z" >&2
    exit 1
  fi
  VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
elif [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "版本号必须是 x.y.z：$VERSION" >&2
  exit 1
fi

if [[ ! "$current_build" =~ ^[0-9]+$ ]]; then
  echo "CFBundleVersion 必须是整数：$current_build" >&2
  exit 1
fi
next_build=$((current_build + 1))

restore_version() {
  printf '%s\n' "$current_short" > "$VERSION_FILE"
  "$PBUDDY" -c "Set :CFBundleShortVersionString $current_short" "$PLIST"
  "$PBUDDY" -c "Set :CFBundleVersion $current_build" "$PLIST"
}

printf '%s\n' "$VERSION" > "$VERSION_FILE"
"$PBUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
"$PBUDDY" -c "Set :CFBundleVersion $next_build" "$PLIST"
trap restore_version ERR

printf '版本 %s (build %s)，已写入 VERSION\n' "$VERSION" "$next_build"

xcodebuild \
  -project "$PROJECT" \
  -scheme BarCmd \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  build

APP="$DERIVED/Build/Products/Release/BarCmd.app"
if [[ ! -d "$APP" ]]; then
  echo "编译成功但找不到 $APP" >&2
  exit 1
fi

rm -rf "$DIST/BarCmd.app"
mkdir -p "$DIST"
ditto "$APP" "$DIST/BarCmd.app"

ZIP="$DIST/BarCmd-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$DIST/BarCmd.app" "$ZIP"

trap - ERR
echo "已生成 $ZIP"

if [[ "$INSTALL" -eq 1 ]]; then
  killall BarCmd 2>/dev/null || true
  sleep 0.3
  rm -rf /Applications/BarCmd.app
  ditto "$DIST/BarCmd.app" /Applications/BarCmd.app
  open /Applications/BarCmd.app
  echo "已安装 /Applications/BarCmd.app"
fi
