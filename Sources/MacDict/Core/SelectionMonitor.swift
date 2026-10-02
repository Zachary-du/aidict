import AppKit
import Carbon

@MainActor
public final class SelectionMonitor {
    public static let shared = SelectionMonitor()

    private var lookupHotKeyRef: EventHotKeyRef?
    private var toggleHoverHotKeyRef: EventHotKeyRef?
    private var toggleShortcutHotKeyRef: EventHotKeyRef?

    private init() {}

    public func start() {
        registerCarbonHotKeys()
    }

    private func registerCarbonHotKeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { (handler, event, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if status == noErr {
                DispatchQueue.main.async {
                    SelectionMonitor.shared.handleHotKeyTriggered(id: hotKeyID.id)
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        // 1. 划词查词热键: Option + D (id: 1)
        let hotKeyID1 = EventHotKeyID(signature: OSType(0x4D444354), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(optionKey), hotKeyID1, GetApplicationEventTarget(), 0, &lookupHotKeyRef)

        // 2. 悬停取词独立开关热键: Option + Command + H (id: 2)
        let hotKeyID2 = EventHotKeyID(signature: OSType(0x4D444354), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(optionKey | cmdKey), hotKeyID2, GetApplicationEventTarget(), 0, &toggleHoverHotKeyRef)

        // 3. 划词查词独立开关热键: Option + Command + S (id: 3)
        let hotKeyID3 = EventHotKeyID(signature: OSType(0x4D444354), id: 3)
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey | cmdKey), hotKeyID3, GetApplicationEventTarget(), 0, &toggleShortcutHotKeyRef)
    }

    private func handleHotKeyTriggered(id: UInt32) {
        switch id {
        case 1:
            // 划词查词触发
            triggerSelectionLookup()
        case 2:
            // 切换悬停取词开关
            ToggleManager.shared.toggleHoverLookup()
        case 3:
            // 切换划词开关
            ToggleManager.shared.toggleShortcutLookup()
        default:
            break
        }
    }

    public func triggerSelectionLookup() {
        guard SettingsStore.shared.isShortcutLookupEnabled else {
            ToggleManager.shared.showNotification(title: "提示", message: "快捷键查词当前处于关闭状态", icon: "exclamationmark.triangle")
            return
        }

        let mousePos = NSEvent.mouseLocation
        var sniffed = TextSniffer.shared.getSelectedTextFromFrontmostApp()

        // 终极双保险：在终端、SSH控制台或网页等特殊非原生界面，若无法直接复制选区，自动嗅探光标处的词
        if sniffed == nil {
            sniffed = TextSniffer.shared.getTextAtCursor(screenPoint: mousePos)
        }

        if let sniffed = sniffed {
            HUDPanel.shared.show(at: mousePos, source: .manual)
            DictionaryEngine.shared.lookup(
                word: sniffed.word,
                context: sniffed.contextSentence,
                sourceApp: sniffed.sourceAppName
            )
        } else {
            ToggleManager.shared.showNotification(title: "划词查词", message: "未检测到选中文本", icon: "text.cursor")
        }
    }
}
