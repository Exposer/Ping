#!/bin/bash
# 用 swiftc 编译并打包成 build/Ping.app
# 用法：./build_app.sh [build | run]

set -euo pipefail
cd "$(dirname "$0")"

APP="build/Ping.app"
COMMAND="${1:-build}"

case "$COMMAND" in
    build|run) ;;
    *)
        echo "用法：./build_app.sh [build | run]"
        exit 1
        ;;
esac

# 先在临时目录里组装并签名：项目放在 iCloud 等同步目录时，系统会给 .app 加上
# Finder 属性，codesign 会拒绝签名（detritus not allowed）
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
STAGED_APP="$STAGE/Ping.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

# 直接用 swiftc，只装了 Command Line Tools、没装 Xcode 也能编译
swiftc -O -parse-as-library \
    -target "$(uname -m)-apple-macosx13.0" \
    Sources/Ping/*.swift \
    -o "$STAGED_APP/Contents/MacOS/Ping"

# 图标由 Icon/make_icon.swift 生成，改了图标设计后重新运行：swift Icon/make_icon.swift
cp Icon/AppIcon.icns "$STAGED_APP/Contents/Resources/AppIcon.icns"

cat > "$STAGED_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>Ping</string>
    <key>CFBundleExecutable</key>
    <string>Ping</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.Ping</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Ping</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# 本地 ad-hoc 签名，方便直接运行
codesign --force --sign - "$STAGED_APP"

rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
ditto "$STAGED_APP" "$APP"

echo "已生成：$APP"

if [ "$COMMAND" = "run" ]; then
    # 已经在运行时 open 只会激活旧进程，先退出它才能跑到新编译的版本
    if pkill -f "$APP/Contents/MacOS/Ping"; then
        sleep 0.5
    fi
    open "$APP"
fi
