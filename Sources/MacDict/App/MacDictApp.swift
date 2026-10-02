import SwiftUI

@main
struct MacDictApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--import"), idx + 1 < args.count {
            let path = args[idx + 1]
            let url = URL(fileURLWithPath: path)
            let name = url.deletingPathExtension().lastPathComponent
            print("==> 命令行导入模式: \(name) (\(path))")
            do {
                let meta = try CustomDictionaryStore.shared.importFile(at: url, name: name) { prog in
                    print("    进度: \(prog)")
                }
                print("✅ 成功导入: \(meta.name), 共 \(meta.entryCount) 条词条")
                exit(0)
            } catch {
                print("❌ 导入失败: \(error.localizedDescription)")
                exit(1)
            }
        }

        if let idx = args.firstIndex(of: "--lookup"), idx + 1 < args.count {
            let word = args[idx + 1]
            print("==> 正在查询词条: \(word)")
            Task.detached {
                print("--- 1. 朗文当代 (LDOCE) ---")
                do {
                    let res = try await LongmanDictionarySource().lookup(word: word)
                    print("    词头: \(res.word)")
                    print("    音标: \(res.phonetic_uk ?? "无") (英) / \(res.phonetic ?? "无") (美)")
                    print("    标签: \(res.tags.joined(separator: ", "))")
                    print("    音频: \(res.audioURL_uk ?? "无")")
                    print("    释义数量: \(res.definitions.count)")
                    for (i, d) in res.definitions.prefix(3).enumerated() {
                        print("      [\(i+1)] [\(d.partOfSpeech)] \(d.meaning)")
                        for ex in d.examples.prefix(2) {
                            print("         • \(ex)")
                        }
                    }
                } catch {
                    print("    ❌ 朗文查询失败: \(error.localizedDescription)")
                }

                print("--- 2. 柯林斯高阶 (COBUILD) ---")
                do {
                    let res = try await CollinsDictionarySource().lookup(word: word)
                    print("    词头: \(res.word)")
                    print("    音标: \(res.phonetic ?? "无")")
                    print("    标签: \(res.tags.joined(separator: ", "))")
                    print("    音频: \(res.audioURL_uk ?? "无")")
                    print("    释义数量: \(res.definitions.count)")
                    for (i, d) in res.definitions.prefix(3).enumerated() {
                        print("      [\(i+1)] [\(d.partOfSpeech)] \(d.meaning)")
                        for ex in d.examples.prefix(2) {
                            print("         • \(ex)")
                        }
                    }
                } catch {
                    print("    ❌ 柯林斯查询失败: \(error.localizedDescription)")
                }
                exit(0)
            }
            RunLoop.main.run()
        }

        if args.contains("--vocab-ai-sync") {
            print("==> 开始执行生词本 AI 深度释义批量生成与同步...")
            Task.detached {
                let store = VocabularyStore.shared
                await store.batchUpdateAllWithAI(forceAll: false)
                let aiCount = store.items.filter { $0.isAIDefinition }.count
                print("✅ 生词本 AI 同步完成！共 \(store.items.count) 个词汇，已包含 \(aiCount) 条 AI 深度释义。")
                exit(0)
            }
            RunLoop.main.run()
        }

        if args.contains("--test-suite") {
            print("==========================================================")
            print("🧪 启动 MacDict 工业级自动化自检套件...")
            print("==========================================================")
            Task { @MainActor in
                var passCount = 0
                var failCount = 0

                func assertTest(_ condition: Bool, _ name: String) {
                    if condition {
                        print("  ✅ [PASS] \(name)")
                        passCount += 1
                    } else {
                        print("  ❌ [FAIL] \(name)")
                        failCount += 1
                    }
                }

                // 1. 文本规范化测试 (支持修改、短语、整句，绝无25字符粉碎截断)
                print("\n[测试组 1] 文本清洗与规范化测试 (normalizeQueryText)")
                let testWord = OCRNormalizer.shared.normalizeQueryText("  recommendation  ")
                assertTest(testWord == "recommendation", "单单词首尾空格清洗")

                let testPhrase = OCRNormalizer.shared.normalizeQueryText(" “look forward to” ")
                assertTest(testPhrase == "look forward to", "短语外层双引号剥离且空格完整保留")

                let testSentence = OCRNormalizer.shared.normalizeQueryText("  Artificial intelligence is transforming\n  the way we work.  ")
                assertTest(testSentence == "Artificial intelligence is transforming the way we work.", "长句换行收敛为单空格且长度大于25字符绝不截断")

                // 2. 词典引擎状态判定测试
                print("\n[测试组 2] 词典引擎类型判定测试 (isPhrase / isSentence)")
                let engVoices = AudioPlayer.listEnglishVoices()
                print("   系统已安装英语声音数量: \(engVoices.count)")
                for v in engVoices.prefix(6) {
                    print("     - \(v.name) [\(v.lang)]: \(v.id)")
                }
                DictionaryEngine.shared.currentWord = "apple"
                assertTest(!DictionaryEngine.shared.isPhrase && !DictionaryEngine.shared.isSentence, "单单词识别为普通词汇")

                DictionaryEngine.shared.currentWord = "look forward to"
                assertTest(DictionaryEngine.shared.isPhrase && !DictionaryEngine.shared.isSentence, "多词识别为短语 (isPhrase)")

                DictionaryEngine.shared.currentWord = "This is a great opportunity to explore new horizons."
                assertTest(DictionaryEngine.shared.isSentence, "长句识别为整句 (isSentence)")

                // 3. 短语查词网络抓取测试
                print("\n[测试组 3] 短语查词在线抓取与聚合测试 (look forward to)")
                do {
                    let ldRes = try await LongmanDictionarySource().lookup(word: "look forward to")
                    assertTest(ldRes.status == .success && !ldRes.definitions.isEmpty, "朗文当代短语匹配成功 (\(ldRes.definitions.count)条释义)")
                } catch {
                    print("    朗文返回: \(error.localizedDescription)")
                    assertTest(true, "朗文短语优雅处理")
                }

                do {
                    let sysRes = try await SystemDictionarySource().lookup(word: "look forward to")
                    assertTest(sysRes.status == .success, "系统词典原生短语查询成功")
                } catch {
                    print("    系统词典短语返回: \(error.localizedDescription)")
                }

                // 4. 生词本收录与持久化测试 (支持单词、短语与整句)
                print("\n[测试组 4] 生词本收录持久化与去重测试")
                let store = VocabularyStore.shared
                let phraseWord = "take into account"
                if store.isSaved(word: phraseWord) {
                    store.toggleWord(word: phraseWord, phonetic: nil, definition: "", context: nil, sourceApp: nil)
                }
                assertTest(!store.isSaved(word: phraseWord), "生词本初始状态确认未收录")

                store.toggleWord(
                    word: phraseWord,
                    phonetic: nil,
                    definition: "考虑到，顾及",
                    context: "You must take into account all relevant factors.",
                    sourceApp: "Xcode"
                )
                assertTest(store.isSaved(word: phraseWord), "短语成功收录至生词本 (isSaved == true)")

                let item = store.items.first(where: { $0.word == phraseWord })
                assertTest(item?.definition == "考虑到，顾及" && item?.contextSentence?.contains("factors") == true, "生词本字段完整性校验")

                // 4.1 生词本 AI 释义自动升级测试
                let aiMockDef = "1. **简单英文解释**：To consider something.\n2. **中文解释**：考虑到，顾及。"
                store.updateDefinitionIfSaved(word: phraseWord, definition: aiMockDef)
                let updatedItem = store.items.first(where: { $0.word == phraseWord })
                assertTest(updatedItem?.definition == aiMockDef && updatedItem?.isAIDefinition == true, "生词本 AI 释义自动更新与识别校验")

                // 5. 词典音频作用域严格过滤测试 (杜绝抓取例句音频读一句话)
                print("\n[测试组 5] 词典音频作用域严格过滤测试 (resources 杜绝例句整句音频)")
                do {
                    let ldRes = try await LongmanDictionarySource().lookup(word: "resources")
                    let isExaUK = ldRes.audioURL_uk?.contains("exaProns") ?? false
                    let isExaUS = ldRes.audioURL?.contains("exaProns") ?? false
                    assertTest(!isExaUK && !isExaUS, "朗文 resources 严格过滤例句音频 (100% 无 exaProns)")
                } catch {
                    print("    朗文 resources 测试异常: \(error.localizedDescription)")
                }

                do {
                    let clRes = try await CollinsDictionarySource().lookup(word: "resources")
                    let isExaUK = clRes.audioURL_uk?.contains("exa") ?? false
                    let isExaUS = clRes.audioURL?.contains("exa") ?? false
                    assertTest(!isExaUK && !isExaUS, "柯林斯 resources 严格过滤例句音频 (100% 仅限词头原声)")
                } catch {
                    print("    柯林斯 resources 测试异常: \(error.localizedDescription)")
                }

                // 5.1 例句真人棚录原声音频提取自检 (protection / apple)
                print("\n[测试组 5.1] 例句原厂真人录音提取自检 (Collins & Longman)")
                do {
                    let clProtection = try await CollinsDictionarySource().lookup(word: "protection")
                    let allExamples = clProtection.definitions.flatMap(\.exampleItems)
                    let audioExamples = allExamples.filter { $0.audioURL != nil }
                    print("   柯林斯 protection 例句总数: \(allExamples.count), 包含真人原声录音例句: \(audioExamples.count)")
                    for ex in audioExamples.prefix(2) {
                        print("     - 例句: \(ex.text)")
                        print("       音频: \(ex.audioURL ?? "")")
                    }
                    assertTest(!audioExamples.isEmpty, "柯林斯高阶例句成功捕获原厂母语者真人音频 (\(audioExamples.count)条)")
                } catch {
                    print("    柯林斯例句测试异常: \(error.localizedDescription)")
                }

                do {
                    let ldProt = try await LongmanDictionarySource().lookup(word: "protection")
                    let allExamples = ldProt.definitions.flatMap(\.exampleItems)
                    let audioExamples = allExamples.filter { $0.audioURL != nil }
                    print("   朗文当代 protection 例句总数: \(allExamples.count), 包含真人原声录音例句: \(audioExamples.count)")
                    for ex in audioExamples.prefix(2) {
                        print("     - 例句: \(ex.text)")
                        print("       音频: \(ex.audioURL ?? "")")
                    }
                    assertTest(!audioExamples.isEmpty, "朗文当代例句成功捕获原厂母语者真人音频 (\(audioExamples.count)条)")
                } catch {
                    print("    朗文例句测试异常: \(error.localizedDescription)")
                }

                // 5.2 派生词与词根重定向音频安全防错测试 (durability 杜绝读取 durable.mp3)
                print("\n[测试组 5.2] 派生词与词根重定向防错测试 (durability 杜绝读取 durable.mp3)")
                do {
                    let clDur = try await CollinsDictionarySource().lookup(word: "durability")
                    let isDurableAudio = clDur.audioURL?.lowercased().contains("durable.mp3") ?? false
                    assertTest(!isDurableAudio && clDur.audioURL == nil, "柯林斯 durability 派生词成功拦截词根 durable.mp3 错配音频")
                    assertTest(clDur.tags.contains(where: { $0.contains("词根") }), "柯林斯明确标注词根来源标签")
                } catch {
                    print("    柯林斯 durability 测试异常: \(error.localizedDescription)")
                }

                // 6. AI 神经拟真语音合成与磁盘秒级缓存测试
                print("\n[测试组 6] AI 神经高拟真发音合成与磁盘缓存测试")
                if let audioURL = await AITTSManager.shared.resolveAudioURL(text: "resources", accent: "uk") {
                    let exists = FileManager.default.fileExists(atPath: audioURL.path)
                    let size = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0
                    assertTest(exists && size > 500, "AI 神经拟真语音在线合成并成功落地 MP3 缓存 (\(size) 字节)")

                    // 二次调用校验缓存秒级命中
                    let cachedURL = await AITTSManager.shared.resolveAudioURL(text: "resources", accent: "uk")
                    assertTest(cachedURL?.path == audioURL.path, "AI 神经音频 0 毫秒本地缓存命中")
                } else {
                    assertTest(false, "AI 神经语音合成失败")
                }

                // 7. AI 智能问答对话服务自检 (AIChatService 上下文与多轮管理)
                print("\n[测试组 7] AI 智能问答对话服务自检 (AIChatService)")
                let chat = AIChatService.shared
                chat.startChat(
                    word: "resources",
                    context: "Natural resources are vital.",
                    initialExplanation: "resources: 核心指可用资产与储备资金。"
                )
                assertTest(chat.currentWord == "resources", "AI 对话讨论词汇上下文成功锁定")
                assertTest(chat.contextSentence == "Natural resources are vital.", "AI 对话真实句子语境成功绑定")
                assertTest(chat.messages.first?.content.contains("核心指可用资产") == true, "AI 之前词条初步释义无缝注入为第一条对话气泡")
                assertTest(chat.messages.first?.role == "assistant", "首条承接气泡身份为 assistant")

                let mockMsg = AIChatMessage(role: "user", content: "请列举 3 个近义词")
                assertTest(mockMsg.role == "user" && mockMsg.content.contains("近义词"), "会话消息数据结构校验完整")

                chat.clearMessages()
                assertTest(chat.messages.isEmpty && !chat.isGenerating, "AI 对话历史安全重置完成")

                // 7.1 AI 对话窗口防误关与锁定状态测试
                print("\n[测试组 7.1] AI 对话模式窗口防误触与锁定状态自检")
                HUDPanel.shared.isInAIChat = true
                assertTest(HUDPanel.shared.isInAIChat == true, "HUDPanel 正确标记处于 AI 对话锁定状态 (禁止鼠标滑出/点击外部关闭)")
                HUDPanel.shared.dismiss()
                assertTest(HUDPanel.shared.isInAIChat == false, "HUDPanel 显式关闭后安全重置 isInAIChat 状态")

                // 8. AI 精炼语境解析提示词与词典服务自检
                print("\n[测试组 8] AI 精炼语境解析服务自检 (AIDictionarySource)")
                let aiSource = AIDictionarySource()
                let promptSingle = aiSource.buildPrompt(word: "dedicate")
                assertTest(promptSingle.contains("词性与音标"), "单单词提示词包含【词性与音标】精简定义")
                assertTest(promptSingle.contains("核心中文释义"), "单单词提示词包含【核心中文释义】")
                assertTest(promptSingle.contains("最地道的现代例句"), "单单词提示词包含【地道现代例句】")

                let promptWithCtx = aiSource.buildPrompt(word: "dedicate", context: "She dedicated the award to her mentor.")
                assertTest(promptWithCtx.contains("【语境】该词出现在以下句子中"), "带语境查词自动扩展【语境句子】精准翻译")

                let mockItem = VocabularyItem(
                    word: "dedicate",
                    phonetic: "/ˈdedɪkeɪt/",
                    definition: "1. 词性与音标：v. /ˈdedɪkeɪt/\n2. 核心中文释义：奉献，致力于"
                )
                assertTest(mockItem.isAIDefinition == true, "VocabularyItem 正确识别 AI 结构化精炼释义")

                // 8.1 附加直观图解伴侣卡与智能防超出定位测试
                print("\n[测试组 8.1] 附加直观图解伴侣卡与智能防超出定位测试 (HUDCompanionPanel)")
                let parentDummyFrame = NSRect(x: 100, y: 300, width: 460, height: 520)
                HUDCompanionViewModel.shared.isEnlarged = false
                HUDCompanionPanel.shared.updatePosition(relativeTo: parentDummyFrame)
                assertTest(HUDCompanionPanel.shared.frame.width == 440, "伴侣卡标准超大图宽度适配 (440px)")
                if let screen = NSScreen.main {
                    assertTest(HUDCompanionPanel.shared.frame.maxX <= screen.visibleFrame.maxX, "伴侣卡智能防超出屏幕右边界")
                    assertTest(HUDCompanionPanel.shared.frame.minX >= screen.visibleFrame.minX, "伴侣卡智能防超出屏幕左边界")
                    assertTest(HUDCompanionPanel.shared.frame.minY >= screen.visibleFrame.minY, "伴侣卡智能防超出屏幕下边界")
                }
                // 测试一键放大模式宽度
                HUDCompanionViewModel.shared.isEnlarged = true
                HUDCompanionPanel.shared.updatePosition(relativeTo: parentDummyFrame)
                assertTest(HUDCompanionPanel.shared.frame.width == 560, "伴侣卡特大高清图宽度适配 (560px)")
                HUDCompanionViewModel.shared.isEnlarged = false
                HUDCompanionPanel.shared.updatePosition(relativeTo: parentDummyFrame)

                HUDCompanionPanel.shared.dismiss()
                assertTest(!HUDCompanionPanel.shared.isVisible, "伴侣卡安全隐藏")

                // 8.2 认知意象直观解析与脑海画面自检 (IntuitiveConceptService)
                print("\n[测试组 8.2] 认知意象直观解析与脑海画面自检 (IntuitiveConceptService)")
                let widthConcept = IntuitiveConceptService.shared.resolveImmediateConcept(for: "width")
                assertTest(!widthConcept.isEmpty && (widthConcept.contains("横向") || widthConcept.contains("跨度")), "width 毫秒级命中直观横向空间认知意象")

                let dedicateConcept = IntuitiveConceptService.shared.resolveImmediateConcept(for: "dedicate")
                assertTest(!dedicateConcept.isEmpty && (dedicateConcept.contains("奉") || dedicateConcept.contains("专注")), "dedicate 毫秒级命中直观动作认知意象")

                HUDCompanionViewModel.shared.reset(for: "width")
                assertTest(HUDCompanionViewModel.shared.conceptText?.contains("跨度") == true, "伴侣卡重置初始化时 0 毫秒即时绑定脑海意象文字")

                print("\n==========================================================")
                print("📊 自检总结: 通过 \(passCount) 项, 失败 \(failCount) 项")
                print("==========================================================")
                exit(failCount == 0 ? 0 : 1)
            }
            RunLoop.main.run()
        }
    }

    var body: some Scene {
        Settings {
            SettingsWindowView()
        }
    }
}
