#!/usr/bin/env bash
# Tokenomics 免费发布脚本（ad-hoc 签名 + DMG，无需 Apple Developer Program）
#
# 用法：
#   ./scripts/release.sh                 # 用 project.yml 里的 MARKETING_VERSION
#   ./scripts/release.sh 0.2.0           # 指定版本号
#
# 产物：
#   build/export/Tokenomics.app
#   build/Tokenomics-<version>.dmg
#
# 前置依赖：
#   - Xcode（不是 Command Line Tools）：sudo xcode-select -s /Applications/Xcode.app
#   - brew install xcodegen
#   - （可选，做更漂亮的 DMG）brew install create-dmg

set -euo pipefail

# ---------- 配置 ----------
SCHEME="Tokenomics"
CONFIGURATION="Release"
APP_NAME="Tokenomics"
BUNDLE_ID="com.tokenomics.Tokenomics"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
EXPORT_OPTIONS_PLIST="${BUILD_DIR}/ExportOptions.plist"

cd "${ROOT_DIR}"

# ---------- 版本号 ----------
if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  VERSION="$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | awk -F'"' '{print $2}')"
fi
if [[ -z "${VERSION:-}" ]]; then
  echo "❌ 无法确定版本号，请传参或在 project.yml 设置 MARKETING_VERSION"
  exit 1
fi
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "▶︎ 版本号: ${VERSION}"

# ---------- 环境检查 ----------
if ! xcode-select -p | grep -q "Xcode.app"; then
  echo "❌ xcode-select 当前指向 Command Line Tools，无法 archive。"
  echo "   请先执行：sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi
command -v xcodegen >/dev/null || { echo "❌ 需要 xcodegen：brew install xcodegen"; exit 1; }

# ---------- 清理 ----------
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# ---------- 生成 Xcode 工程 ----------
echo "▶︎ xcodegen generate"
xcodegen generate >/dev/null

# ---------- Archive（关闭一切签名，留给后面 ad-hoc 重签） ----------
echo "▶︎ xcodebuild archive (unsigned)"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=macOS" \
  -archivePath "${ARCHIVE_PATH}" \
  MARKETING_VERSION="${VERSION}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  archive | xcpretty 2>/dev/null || true

# 兜底：如果上一步 pipefail，直接再跑一次不带 xcpretty 看完整日志
if [[ ! -d "${ARCHIVE_PATH}" ]]; then
  xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "generic/platform=macOS" \
    -archivePath "${ARCHIVE_PATH}" \
    MARKETING_VERSION="${VERSION}" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    archive
fi

# ---------- 直接从 archive 拷出 .app（不用 exportArchive，避免它强行要证书） ----------
echo "▶︎ 从 archive 中提取 .app"
mkdir -p "${EXPORT_DIR}"
rm -rf "${APP_PATH}"
cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${APP_PATH}"

# ---------- Ad-hoc 签名（递归，启用 Hardened Runtime） ----------
echo "▶︎ ad-hoc 签名（identity = -）"
codesign --force --deep --sign - \
  --options runtime \
  --entitlements "${ROOT_DIR}/Tokenomics/Tokenomics.entitlements" \
  --timestamp=none \
  "${APP_PATH}"

# 自检
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
echo "✅ 签名 OK"

# ---------- 打 DMG ----------
echo "▶︎ 打 DMG"
rm -f "${DMG_PATH}"

if command -v create-dmg >/dev/null; then
  # 漂亮版：拖拽到 Applications 安装
  create-dmg \
    --volname "${APP_NAME} ${VERSION}" \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "${APP_NAME}.app" 140 180 \
    --app-drop-link 400 180 \
    --hide-extension "${APP_NAME}.app" \
    --no-internet-enable \
    "${DMG_PATH}" \
    "${EXPORT_DIR}" \
    || true
fi

# 兜底：用系统自带 hdiutil
if [[ ! -f "${DMG_PATH}" ]]; then
  echo "▶︎ 回退到 hdiutil"
  STAGING_DIR="${BUILD_DIR}/dmg_staging"
  rm -rf "${STAGING_DIR}"
  mkdir -p "${STAGING_DIR}"
  cp -R "${APP_PATH}" "${STAGING_DIR}/"
  ln -s /Applications "${STAGING_DIR}/Applications"

  hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"

  rm -rf "${STAGING_DIR}"
fi

# DMG 本身也 ad-hoc 签一下（防止部分网盘传输破坏校验）
codesign --force --sign - "${DMG_PATH}" || true

echo
echo "🎉 完成！"
echo "   App : ${APP_PATH}"
echo "   DMG : ${DMG_PATH}"
echo
echo "📝 用户首次打开提示（贴到 Release Notes）:"
echo "   1) 双击 DMG → 把 Tokenomics 拖到 Applications"
echo "   2) 右键 Tokenomics → 打开 → 在弹窗里再点一次「打开」"
echo "   或一行命令去掉隔离属性："
echo "      xattr -dr com.apple.quarantine /Applications/Tokenomics.app"
