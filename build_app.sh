#!/bin/bash
set -e

APP_NAME="MacDict"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> 正在使用 Swift release 模式进行极致性能编译..."
swift build -c release

echo "==> 正在构建 ${APP_BUNDLE} 应用包结构..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.dylan.MacDict</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>MacDict 词典</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>MacDict 需要辅助功能权限以提供屏幕悬停取词与快捷键选词查询服务。</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MacDict 使用离线 Vision OCR 技术识别屏幕不可选中区域的词汇。</string>
</dict>
</plist>
EOF

echo "==> 正在签署应用以满足 macOS 本地运行要求..."
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

echo "=========================================================="
echo "✅ 构建完成！生成独立应用：${APP_BUNDLE}"
echo "你可以直接双击运行，或将其拖拽至 /Applications (应用程序) 目录中使用！"
echo "=========================================================="
