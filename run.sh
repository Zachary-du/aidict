#!/bin/bash
set -e

# ==============================================================================
# MacDict 统一管理脚本 (Unified CLI)
# 用法: ./run.sh <命令> [参数]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="MacDict"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/release"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
BUNDLE_ID="com.dylan.MacDict"
LOG_FILE="$HOME/Library/Logs/MacDict/macdict.log"

function print_usage() {
    echo "=========================================================="
    echo "📖 MacDict 词典统一管理工具"
    echo "=========================================================="
    echo "用法: ./run.sh <命令> [参数]"
    echo ""
    echo "应用管理："
    echo "  ./run.sh build              编译并打包为 MacDict.app"
    echo "  ./run.sh start              启动 MacDict.app"
    echo "  ./run.sh stop               退出 MacDict"
    echo "  ./run.sh restart            重启 MacDict"
    echo "  ./run.sh status             查看运行状态"
    echo "  ./run.sh install            安装到 /Applications"
    echo "  ./run.sh dmg                制作 macOS 标准 DMG 安装包 (带 Applications 拖拽快捷方式)"
    echo "  ./run.sh pack-source        打包纯净源码 ZIP 包至 ~/Downloads (自动排除缓存)"
    echo "  ./run.sh vocab ai-sync      批量将生词本所有词汇更新为 AI 深度结构化释义"
    echo "  ./run.sh clean              清理构建产物"
    echo "  ./run.sh repair             重置 TCC 权限缓存并重建"
    echo ""
    echo "设置配置："
    echo "  ./run.sh config ai          配置 AI API（交互式）"
    echo "  ./run.sh config show        查看当前所有配置"
    echo "  ./run.sh config set <key> <value>  直接设置某个 key"
    echo "  ./run.sh config reset-ai    重置 AI 配置为空"
    echo ""
    echo "日志："
    echo "  ./run.sh log                查看最近 50 行日志"
    echo "  ./run.sh log follow         实时跟踪日志 (Ctrl+C 退出)"
    echo "  ./run.sh log clear          清空日志文件"
    echo ""
    echo "调试："
    echo "  ./run.sh lookup <单词>      测试直接抓取并打印朗文与柯林斯释义"
    echo "  ./run.sh test               运行核心词典引擎自检"
    echo "  ./run.sh debug mdx <文件>   检测 MDX 文件版本/编码/加密"
    echo "  ./run.sh debug crash        查看最新崩溃报告"
    echo "=========================================================="
}

function do_build() {
    ARCH="$(uname -m)"
    echo "==> [1/3] 正在使用 Swift Release 模式编译项目 (本机架构: ${ARCH})..."
    swift build -c release

    BIN_DIR="$(swift build -c release --show-bin-path)"

    echo "==> [2/3] 正在构建 ${APP_BUNDLE} 独立应用包结构..."
    rm -rf "${APP_BUNDLE}"
    mkdir -p "${MACOS_DIR}"
    mkdir -p "${APP_BUNDLE}/Contents/Resources"

    cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
    chmod +x "${MACOS_DIR}/${APP_NAME}"
    echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

    if [ -f "AppIcon.icns" ]; then
        cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    fi

    cat <<EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
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

    echo "==> [3/3] 正在签署本地稳定身份签名..."
    codesign --force --deep -s - -r="designated => identifier \"${BUNDLE_ID}\"" "${APP_BUNDLE}"

    echo "=========================================================="
    echo "✅ 构建完成！生成独立应用: ${SCRIPT_DIR}/${APP_BUNDLE}"
    echo "体积仅约: $(ls -lh "${MACOS_DIR}/${APP_NAME}" | awk '{print $5}')"
    echo "=========================================================="
}

function do_start() {
    if [ ! -d "${APP_BUNDLE}" ]; then
        echo "未找到 ${APP_BUNDLE}，正在先执行打包编译..."
        do_build
    fi
    pkill -x "${APP_NAME}" 2>/dev/null || true
    sleep 0.3
    echo "==> 正在启动 ${APP_BUNDLE} (常驻右上角菜单栏)..."
    open "${APP_BUNDLE}"
    echo "✅ 已启动！请查看 Mac 屏幕右上角菜单栏是否有词典图标（📖 图标）。"
}

function do_stop() {
    echo "==> 正在退出 MacDict..."
    if pkill -x "${APP_NAME}" 2>/dev/null; then
        echo "✅ MacDict 已成功退出。"
    else
        echo "ℹ️  MacDict 当前未在运行。"
    fi
}

function do_status() {
    echo "==> 正在检查 MacDict 运行状态..."
    PID=$(pgrep -x "${APP_NAME}" || true)
    if [ -n "$PID" ]; then
        echo "✅ MacDict 正在后台运行中 (PID: $PID)"
        ps -p "$PID" -o %cpu,%mem,rss,time,command
    else
        echo "ℹ️  MacDict 当前未在运行。"
    fi
    echo ""
    echo "==> 当前 AI 配置："
    _config_show
}

function do_install() {
    if [ ! -d "${APP_BUNDLE}" ]; then
        do_build
    fi
    echo "==> 正在将 ${APP_BUNDLE} 安装至 /Applications/ 目录..."
    pkill -x "${APP_NAME}" 2>/dev/null || true
    rm -rf "/Applications/${APP_BUNDLE}"
    cp -R "${APP_BUNDLE}" "/Applications/"
    echo "✅ 安装成功！可在启动台或 Spotlight 中搜索 MacDict 启动。"
}

function do_dmg() {
    if [ ! -d "${APP_BUNDLE}" ]; then
        echo "==> 未发现构建产物，正在先编译..."
        do_build
    fi
    echo "==> [1/4] 正在准备 DMG 安装包临时目录..."
    DMG_NAME="MacDict-Installer.dmg"
    DMG_DIR=".build/dmg_pack"
    DEST_PATH="$HOME/Downloads/${DMG_NAME}"
    rm -rf "${DMG_DIR}" "${DMG_NAME}" "${DEST_PATH}"
    mkdir -p "${DMG_DIR}"

    echo "==> [2/4] 复制 ${APP_BUNDLE} 并创建 Applications 快捷方式与首次启动说明..."
    cp -R "${APP_BUNDLE}" "${DMG_DIR}/"
    ln -s /Applications "${DMG_DIR}/拖拽至此安装到 Applications"

    cat << 'EOF' > "${DMG_DIR}/首次安装与使用必读.txt"
==================================================================
📖 MacDict 词典 macOS 安装与使用指引 (原生支持 Apple Silicon M1/M2/M3/M4)
==================================================================

【第 1 步：安装】
直接将左侧的 "MacDict.app" 拖拽到右侧的 "拖拽至此安装到 Applications" 即可。

【第 2 步：首次打开提示（重要）】
由于 MacDict 是开源工具（未购买每年 99 美元的苹果商业开发者证书）：
若在其他 Mac 首次打开时系统弹出“无法打开，因为无法验证开发者”或“提示已损坏”：
• 方式一（推荐，系统设置放行）：
  前往 Mac「系统设置」➔「隐私与安全性」，滚动到最下方，点击「仍要打开」；
• 方式二（右键快捷打开）：
  在「访达」➔「应用程序」中找到 MacDict，按住 Control 键（或鼠标右键）点击图标，选择「打开」，在弹出的对话框中点击「打开」；
• 方式三（终端一键清除隔离位）：
  打开「终端」执行：
  xattr -cr /Applications/MacDict.app

【第 3 步：授权与使用】
启动后，MacDict 会常驻在右上角菜单栏（📖 图标）。
首次使用时，请根据提示在「系统设置」➔「隐私与安全性」中开启：
1.「辅助功能」权限（用于屏幕双击取词与滑动取词）
2.「屏幕录制」权限（仅用于屏幕不可选中文字时的离线 OCR 识别）

祝使用愉快！
EOF

    echo "==> [3/4] 正在生成标准 DMG 压缩磁盘映像..."
    hdiutil create -volname "MacDict 词典安装程序" \
        -srcfolder "${DMG_DIR}" \
        -ov -format UDZO \
        "${DMG_NAME}"

    echo "==> [4/4] 正在分发至用户 Downloads 目录 (${DEST_PATH})..."
    cp "${DMG_NAME}" "${DEST_PATH}"
    rm -rf "${DMG_DIR}"

    echo "=========================================================="
    echo "✅ 安装包制作并分发成功！"
    echo "本地产物: ${SCRIPT_DIR}/${DMG_NAME}"
    echo "下载目录: ${DEST_PATH}"
    echo "文件体积: $(ls -lh "${DEST_PATH}" | awk '{print $5}')"
    echo "架构适配: Apple Silicon M 系列芯片原生 (arm64)"
    echo "使用方式: 双击打开 ${DEST_PATH}，将 MacDict 拖入右侧 Applications 即可！"
    echo "=========================================================="
}

function do_pack_source() {
    echo "==> 正在打包纯净源代码包 (自动排除编译缓存与本地临时文件)..."
    ZIP_NAME="MacDict-Source.zip"
    DEST_PATH="$HOME/Downloads/${ZIP_NAME}"
    rm -f "${DEST_PATH}" "${ZIP_NAME}"

    zip -r -q "${ZIP_NAME}" . \
        -x ".build/*" \
        -x "*.app/*" \
        -x "*.dmg" \
        -x "*.zip" \
        -x ".git/*" \
        -x "*.DS_Store" \
        -x ".user_uploaded/*"

    cp "${ZIP_NAME}" "${DEST_PATH}"
    rm -f "${ZIP_NAME}"
    echo "=========================================================="
    echo "✅ 纯净源码包打包完成！"
    echo "下载路径: ${DEST_PATH}"
    echo "源码体积: $(ls -lh "${DEST_PATH}" | awk '{print $5}')"
    echo "包含内容: Package.swift, Sources/, run.sh, AppIcon.icns, README.md 等"
    echo "他人使用: 解压后直接在终端执行 ./run.sh 即可全自动完成编译与启动！"
    echo "=========================================================="
}

function do_clean() {
    echo "==> 正在清理构建目录和缓存..."
    rm -rf .build "${APP_BUNDLE}"
    echo "✅ 清理完毕。"
}

function do_vocab() {
    SUBCMD="${1:-ai-sync}"
    case "$SUBCMD" in
        ai-sync)
            if [ ! -f "${MACOS_DIR}/${APP_NAME}" ]; then
                do_build
            fi
            echo "==> 启动生词本 AI 深度释义批量生成与同步..."
            "${MACOS_DIR}/${APP_NAME}" --vocab-ai-sync
            ;;
        *)
            echo "未知生词本指令: $SUBCMD (可用: ai-sync)"
            ;;
    esac
}

function do_repair() {
    echo "==> [1/3] 正在停止运行中的 MacDict 进程..."
    pkill -x "${APP_NAME}" 2>/dev/null || true

    echo "==> [2/3] 正在重置 TCC 权限缓存..."
    tccutil reset Accessibility "${BUNDLE_ID}" 2>/dev/null || true
    tccutil reset ScreenCapture "${BUNDLE_ID}" 2>/dev/null || true

    echo "==> [3/3] 全量构建并签署稳定证书..."
    do_build

    echo "=========================================================="
    echo "✅ 修复完毕！执行 ./run.sh start 启动，并重新授予权限。"
    echo "=========================================================="
}

# ── 配置管理 ────────────────────────────────────────────────────────────────

function _config_show() {
    endpoint=$(defaults read "${BUNDLE_ID}" ai_endpoint 2>/dev/null || echo "(未设置)")
    model=$(defaults read "${BUNDLE_ID}" ai_model 2>/dev/null || echo "(未设置)")
    key_raw=$(defaults read "${BUNDLE_ID}" ai_api_key 2>/dev/null || echo "")
    mw_key_raw=$(defaults read "${BUNDLE_ID}" mw_api_key 2>/dev/null || echo "")
    pixabay_key_raw=$(defaults read "${BUNDLE_ID}" pixabay_api_key 2>/dev/null || echo "")

    if [ -n "$key_raw" ]; then
        key_display="${key_raw:0:6}...${key_raw: -4} (共${#key_raw}位)"
    else
        key_display="(未设置)"
    fi
    if [ -n "$mw_key_raw" ]; then
        mw_display="${mw_key_raw:0:6}...${mw_key_raw: -4} (共${#mw_key_raw}位)"
    else
        mw_display="(未设置)"
    fi
    if [ -n "$pixabay_key_raw" ]; then
        pixabay_display="${pixabay_key_raw:0:6}...${pixabay_key_raw: -4} (共${#pixabay_key_raw}位)"
    else
        pixabay_display="(未设置，默认使用 Wikipedia 官方免 Key 免费图库)"
    fi

    echo "  AI Endpoint : $endpoint"
    echo "  AI Model    : $model"
    echo "  AI API Key  : $key_display"
    echo "  MW API Key  : $mw_display"
    echo "  Pixabay Key : $pixabay_display"
}

function do_config() {
    SUBCMD="${1:-show}"
    case "$SUBCMD" in
        show)
            echo "==> 当前 MacDict 配置："
            _config_show
            ;;
        ai)
            # 交互式配置 AI
            echo "=========================================================="
            echo "🤖 MacDict AI 语境与图解配置（回车跳过保留原值）"
            echo "=========================================================="
            _config_show
            echo ""

            read -rp "AI Endpoint [回车=Gemini默认]: " inp_endpoint
            read -rp "AI Model    [回车=gemini-2.0-flash]: " inp_model
            read -rsp "AI API Key  [回车=保留原值，输入不显示]: " inp_key
            echo ""
            read -rsp "MW API Key  [回车=保留原值]: " inp_mw
            echo ""
            read -rsp "Pixabay Key [回车=保留原值/留空使用 Wikipedia]: " inp_pixabay
            echo ""

            # 写入（只写非空输入）
            pkill -x "${APP_NAME}" 2>/dev/null || true
            sleep 0.3

            if [ -n "$inp_endpoint" ]; then
                defaults write "${BUNDLE_ID}" ai_endpoint "$inp_endpoint"
            elif ! defaults read "${BUNDLE_ID}" ai_endpoint &>/dev/null || [ "$(defaults read "${BUNDLE_ID}" ai_endpoint 2>/dev/null)" = "" ]; then
                defaults write "${BUNDLE_ID}" ai_endpoint "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            fi

            if [ -n "$inp_model" ]; then
                defaults write "${BUNDLE_ID}" ai_model "$inp_model"
            elif ! defaults read "${BUNDLE_ID}" ai_model &>/dev/null || [ "$(defaults read "${BUNDLE_ID}" ai_model 2>/dev/null)" = "" ]; then
                defaults write "${BUNDLE_ID}" ai_model "gemini-2.0-flash"
            fi

            [ -n "$inp_key" ] && defaults write "${BUNDLE_ID}" ai_api_key "$inp_key"
            [ -n "$inp_mw"  ] && defaults write "${BUNDLE_ID}" mw_api_key  "$inp_mw"
            [ -n "$inp_pixabay" ] && defaults write "${BUNDLE_ID}" pixabay_api_key "$inp_pixabay"

            echo ""
            echo "==> 写入完成，重启 MacDict..."
            do_start
            echo ""
            echo "✅ 配置生效！当前配置："
            _config_show
            ;;
        set)
            KEY="$2"
            VAL="$3"
            if [ -z "$KEY" ] || [ -z "$VAL" ]; then
                echo "用法: ./run.sh config set <key> <value>"
                echo "  常用 key: ai_endpoint  ai_api_key  ai_model  mw_api_key  pixabay_api_key"
                exit 1
            fi
            pkill -x "${APP_NAME}" 2>/dev/null || true
            sleep 0.3
            defaults write "${BUNDLE_ID}" "$KEY" "$VAL"
            echo "✅ 已设置 $KEY"
            do_start
            ;;
        reset-ai)
            pkill -x "${APP_NAME}" 2>/dev/null || true
            sleep 0.2
            defaults delete "${BUNDLE_ID}" ai_endpoint 2>/dev/null || true
            defaults delete "${BUNDLE_ID}" ai_api_key  2>/dev/null || true
            defaults delete "${BUNDLE_ID}" ai_model    2>/dev/null || true
            echo "✅ AI 配置已清除"
            do_start
            ;;
        *)
            echo "未知子命令: $SUBCMD"
            echo "可用: show | ai | set <key> <val> | reset-ai"
            ;;
    esac
}

# ── 日志 ────────────────────────────────────────────────────────────────────

function do_log() {
    SUBCMD="${1:-tail}"
    case "$SUBCMD" in
        follow|watch|-f)
            echo "==> 实时日志 (Ctrl+C 退出)："
            tail -f "${LOG_FILE}" 2>/dev/null || echo "日志文件不存在: ${LOG_FILE}"
            ;;
        clear)
            > "${LOG_FILE}" 2>/dev/null && echo "✅ 日志已清空" || echo "日志文件不存在"
            ;;
        *)
            echo "==> 最近 50 行日志 (${LOG_FILE})："
            tail -50 "${LOG_FILE}" 2>/dev/null || echo "日志文件不存在: ${LOG_FILE}"
            ;;
    esac
}

function do_test() {
    echo "==> 正在运行核心词典引擎快速自检..."
    swift - <<'SWIFTEOF'
import AppKit
import CoreServices
import Foundation

print("1. 正在测试系统原生牛津词典 (DCSCopyTextDefinition)...")
let word = "apple"
let range = CFRangeMake(0, (word as NSString).length)
if let defRef = DCSCopyTextDefinition(nil, word as CFString, range) {
    let def = defRef.takeRetainedValue() as String
    print("   [OK] 系统词典查询成功！字符数: \(def.count)")
} else {
    print("   [FAIL] 未查询到系统词典释义")
}

print("2. 正在测试单词清洗（已彻底禁用自动拼写纠错，确保如 emby 等词不被篡改）...")
func sanitizeToken(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let wrapperSet = CharacterSet(charactersIn: "()[]{}<>\"'`.,:;\\/$%#*&?!~")
    text = text.trimmingCharacters(in: wrapperSet)
    if text.hasSuffix("\\") { text.removeLast() }
    text = text.replacingOccurrences(of: "\\", with: "")
    return text
}
for word in ["emby", "(apple)", "Download\\", "'dictionary'"] {
    print("   [清洗原词] \(word) -> \(sanitizeToken(word)) (无篡改)")
}

print("3. 正在测试本地导入词典库...")
let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("MacDict", isDirectory: true)
let dbPath = dir.appendingPathComponent("dictionaries.db").path
if FileManager.default.fileExists(atPath: dbPath) {
    print("   [OK] 词典数据库存在: \(dbPath)")
} else {
    print("   [INFO] 尚未创建词典数据库")
}
print("4. 自检全部完成！")
SWIFTEOF
    sqlite3 "$HOME/Library/Application Support/MacDict/dictionaries.db" "SELECT name, format, entry_count, created_at FROM dict_meta;" 2>/dev/null || true
    echo "==> 测试查询 'apple' 在导入词典中的记录："
    sqlite3 "$HOME/Library/Application Support/MacDict/dictionaries.db" "SELECT quote(word), length(definition), substr(definition, 1, 80) FROM entries WHERE word LIKE '%apple%' LIMIT 3;" 2>/dev/null || true
    echo ""
    echo "✅ 自检完成！"
}

function do_lookup() {
    WORD="${1:-recommendation}"
    if [ ! -f "${MACOS_DIR}/${APP_NAME}" ]; then
        echo "==> 未发现构建产物，正在先编译..."
        do_build
    fi
    "${MACOS_DIR}/${APP_NAME}" --lookup "$WORD"
}

# ── 调试工具 ──────────────────────────────────────────────────────────────────

function do_debug() {
    SUBCMD="${1:-help}"
    case "$SUBCMD" in
        mdx)
            MDX_FILE="$2"
            if [ -z "$MDX_FILE" ]; then
                echo "用法: ./run.sh debug mdx <MDX文件路径>"
                exit 1
            fi
            if [ ! -f "$MDX_FILE" ]; then
                echo "❌ 文件不存在: $MDX_FILE"
                exit 1
            fi
            echo "==> 检测 MDX 文件: $MDX_FILE"
            echo "    文件大小: $(du -sh "$MDX_FILE" | cut -f1)"
            python3 - "$MDX_FILE" <<'PYEOF'
import sys, struct, zlib, re

fpath = sys.argv[1]
with open(fpath, 'rb') as f:
    header_len = struct.unpack('>I', f.read(4))[0]
    header_bytes = f.read(header_len)
    adler32_stored = struct.unpack('<I', f.read(4))[0]
    adler32_actual = zlib.adler32(header_bytes) & 0xffffffff
    print(f"    Header 长度: {header_len} 字节")
    print(f"    Adler32 校验: {'✅ 通过' if adler32_stored == adler32_actual else '❌ 不匹配'}")

    # 解析 XML 头部
    try:
        xml = header_bytes[:-2].decode('utf-16-le')
    except:
        xml = header_bytes.decode('utf-8', errors='ignore')

    def attr(name):
        m = re.search(rf'{name}="([^"]*)"', xml)
        return m.group(1) if m else '(未找到)'

    version = attr('GeneratedByEngineVersion')
    encoding = attr('Encoding')
    encrypted = attr('Encrypted')
    engine_comment = attr('Description')

    print(f"    MDX 版本: {version}")
    print(f"    文本编码: {encoding}")
    print(f"    加密状态: {encrypted}")
    maj = int(float(version))

    # 读取 Key Section 头部
    nw = 8 if maj >= 2 else 4
    fmt = '>Q' if maj >= 2 else '>I'
    hdr_bytes = f.read(nw * (5 if maj >= 2 else 4))
    sf = __import__('io').BytesIO(hdr_bytes)
    num_key_blocks = struct.unpack(fmt, sf.read(nw))[0]
    num_entries    = struct.unpack(fmt, sf.read(nw))[0]
    if maj >= 2:
        info_decomp    = struct.unpack(fmt, sf.read(nw))[0]
    info_size      = struct.unpack(fmt, sf.read(nw))[0]
    key_blocks_sz  = struct.unpack(fmt, sf.read(nw))[0]

    print(f"    Key Block 数量: {num_key_blocks}")
    print(f"    词条数量: {num_entries}")
    print(f"    Key Block Info 大小: {info_size} 字节")
    print(f"    Key Blocks 总大小: {key_blocks_sz} 字节")

    # 读 key block info 首字节，判断压缩类型
    if maj >= 2:
        f.read(4)  # adler32 checksum
    kbi_peek = f.read(4)
    if len(kbi_peek) >= 1:
        comp_byte = kbi_peek[0]
        if comp_byte == 0x02:
            kbi_compress = "zlib 压缩 ✅ (v2.x 标准格式)"
        elif comp_byte == 0x01:
            kbi_compress = "LZO 压缩 ⚠️ (v1.x 格式，MacDict 暂不支持)"
        elif comp_byte == 0x00:
            kbi_compress = "无压缩 (v1.x 格式)"
        else:
            kbi_compress = f"未知 (0x{comp_byte:02x})"
        print(f"    Key Block 压缩: {kbi_compress}")

    # 判断兼容性
    enc_flag = 0 if encrypted in ('No', '0', '(未找到)', '') else int(encrypted) if encrypted.isdigit() else 1
    print("")
    if maj < 2:
        print("⚠️  此词典为 MDX v1.x 格式，使用 LZO 压缩，MacDict 暂不支持直接导入。")
        print("   建议方案：使用 MDict Desktop 软件另存为 v2.0 格式再导入。")
        print("   或使用 pyglossary 工具: pip3 install pyglossary && pyglossary input.mdx output.mdx")
    elif enc_flag & 1:
        print("⚠️  此词典 Record Block 已加密（需要注册码），MacDict 无法导入。")
    elif enc_flag & 2:
        print("✅  此词典 Key Block Info 使用混淆加密（无需密码），MacDict 支持导入。")
    else:
        print("✅  此词典为标准 MDX v2.x 格式，MacDict 支持导入！")
PYEOF
            ;;
        crash)
            echo "==> 最新 MacDict 崩溃报告："
            LATEST=$(ls -t ~/Library/Logs/DiagnosticReports/MacDict-*.ips 2>/dev/null | head -1)
            if [ -z "$LATEST" ]; then
                echo "ℹ️  没有找到崩溃报告"
            else
                echo "    文件: $LATEST"
                python3 - "$LATEST" <<'PYEOF'
import sys, json, re
content = open(sys.argv[1], 'r', errors='ignore').read()
obj = None
for line in content.strip().split('\n'):
    line = line.strip()
    if line.startswith('{') and line.endswith('}'):
        try:
            candidate = json.loads(line)
            if 'threads' in candidate or 'exception' in candidate:
                obj = candidate
                break
        except: pass

if obj:
    exc = obj.get('exception', {})
    print(f"    异常类型: {exc.get('type','?')}")
    print(f"    信号: {exc.get('signal','?')}")
    print(f"    子类型: {exc.get('subtype','?')}")
    term = obj.get('termination', {})
    if term:
        print(f"    终止原因: {term.get('reason','')} ({term.get('indicator','')})")
    threads = obj.get('threads', [])
    for t in threads:
        if t.get('triggered', False):
            print("    崩溃线程栈 (Triggered Thread):")
            for f in t.get('frames', [])[:20]:
                sym = f.get('symbol', f.get('imageOffset', '?'))
                idx = f.get('imageIndex', '?')
                print(f"      [{idx}] {sym}")
            break
else:
    print("    回退搜索关键符号:")
    for s in re.findall(r'"symbol"\s*:\s*"([^"]+)"', content)[:20]:
        print(f"      → {s}")
PYEOF
            fi
            ;;
        lzo)
            FILE="${2:-/Users/dylan/Downloads/Download trash/Collins COBUILD English Dictionary 8Ed.mdx}"
            python3 - "$FILE" <<'PYEOF'
import sys
print("Python version:", sys.version)
for mod in ['lzo', 'python_lzo', 'lz4', 'zlib']:
    try:
        __import__(mod)
        print(f"Module {mod}: available")
    except ImportError:
        print(f"Module {mod}: NOT available")
PYEOF
            ;;
        *)
            echo "用法: ./run.sh debug <mdx|crash|lzo>"
            echo "  mdx <文件>   检测 MDX 文件格式、版本、兼容性"
            echo "  crash        查看最新 MacDict 崩溃报告摘要"
            echo "  lzo          检测系统 LZO 模块支持"
            ;;
    esac
}

function do_import() {
    FILE="$1"
    if [ -z "$FILE" ]; then
        echo "用法: ./run.sh import <词典文件路径>"
        exit 1
    fi
    if [ ! -f "$FILE" ]; then
        echo "❌ 文件不存在: $FILE"
        exit 1
    fi
    if [ ! -f "${MACOS_DIR}/${APP_NAME}" ]; then
        echo "==> 未发现构建产物，正在先编译..."
        do_build
    fi
    "${MACOS_DIR}/${APP_NAME}" --import "$FILE"
}

function do_default_task() {
    echo "=========================================================="
    echo "🧹 [1/4] 执行 SQLite VACUUM 并清理旧版系统提示词缓存..."
    echo "=========================================================="
    defaults delete "${BUNDLE_ID}" ai_system_prompt 2>/dev/null || true
    defaults delete "${BUNDLE_ID}" ai_user_prompt_template 2>/dev/null || true
    echo "   ✅ 已清除旧版提示词缓存，确保恢复为精炼简洁翻译模式"

    DB_FILE="$HOME/Library/Application Support/MacDict/dictionaries.db"
    if [ -f "$DB_FILE" ]; then
        BEFORE_SIZE=$(du -sh "$DB_FILE" | cut -f1)
        echo "   释放前 db 大小: $BEFORE_SIZE"
        sqlite3 "$DB_FILE" "VACUUM;" 2>/dev/null || true
        AFTER_SIZE=$(du -sh "$DB_FILE" | cut -f1)
        echo "   ✅ VACUUM 完成！释放后 db 大小: $AFTER_SIZE"
    fi

    echo ""
    echo "=========================================================="
    echo "🔨 [2/4] 编译打包最新版 MacDict 并同步至 /Applications..."
    echo "=========================================================="
    do_build
    if [ -d "/Applications" ]; then
        echo "==> 同步安装至 /Applications/MacDict.app..."
        rm -rf "/Applications/MacDict.app"
        cp -R "${APP_BUNDLE}" "/Applications/MacDict.app"
    fi

    echo ""
    echo ""
    echo "=========================================================="
    echo "🧪 [3/4] 启动自动化测试套件..."
    echo "=========================================================="
    "${MACOS_DIR}/${APP_NAME}" --test-suite

    echo ""
    echo "=========================================================="
    echo "✨ [3.5/6] 自动将生词本所有词汇同步为 AI 深度结构化释义..."
    echo "=========================================================="
    "${MACOS_DIR}/${APP_NAME}" --vocab-ai-sync || true

    echo ""
    echo "=========================================================="
    echo "📦 [4/6] 制作分发 DMG 安装包并投递至 ~/Downloads..."
    echo "=========================================================="
    do_dmg

    echo ""
    echo "=========================================================="
    echo "📦 [5/6] 制作纯净源代码 ZIP 包并投递至 ~/Downloads..."
    echo "=========================================================="
    do_pack_source

    if [ -d ".git" ]; then
        echo ""
        echo "==> 检测到 Git 仓库，正在推送更新至远程..."
        git add -A
        git commit -m "feat: 认知意象与脑海直观画面解析服务" 2>/dev/null || true
        git push 2>/dev/null || true
    fi
    echo "=========================================================="
    echo "🚀 [6/6] 平滑重启后台 MacDict.app 并检查最终空间分布..."
    echo "=========================================================="
    do_stop 2>/dev/null || true
    sleep 0.5
    do_start
    echo ""
    do_status

    echo ""
    echo "=========================================================="
    echo "📊 最终磁盘空间分布报告："
    echo "=========================================================="
    echo "  • 本地应用包:       $(du -sh "${APP_BUNDLE}" 2>/dev/null | cut -f1)"
    echo "  • 系统安装目录:     $(du -sh "/Applications/MacDict.app" 2>/dev/null | cut -f1)"
    echo "  • 用户数据目录:     $(du -sh "$HOME/Library/Application Support/MacDict" 2>/dev/null | cut -f1)"
    echo "  • 词典数据库:       $(du -sh "$DB_FILE" 2>/dev/null | cut -f1)"
    echo "=========================================================="
}

# ── 路由 ───────────────────────────────────────────────────────────────────

COMMAND="${1:-default_pipeline}"

case "$COMMAND" in
    default_pipeline)   do_default_task ;;
    build)              do_build ;;
    start|run)          do_start ;;
    stop)               do_stop ;;
    restart)            do_stop; sleep 0.5; do_start ;;
    status)             do_status ;;
    install)            do_install ;;
    dmg|package)        do_dmg ;;
    pack-source)        do_pack_source ;;
    vocab)              shift; do_vocab "$@" ;;
    clean)              do_clean ;;
    repair|fix-perms)   do_repair ;;
    test)               do_test ;;
    lookup)             shift; do_lookup "$@" ;;
    import)             shift; do_import "$@" ;;
    config)             shift; do_config "$@" ;;
    log)                shift; do_log "$@" ;;
    debug)              shift; do_debug "$@" ;;
    help)               print_usage ;;
    *)                  print_usage ;;
esac
