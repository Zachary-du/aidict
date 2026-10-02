import Foundation
import CoreServices

/// 单词直观认知意象服务（深度底层通透理解）
/// 严格遵循“核心画面 + 具象感知 + 灵魂本义与场景贯通”三段式认知架构
/// 让学习者一下深刻顿悟，过目难忘，融会贯通所有场景与引申变体
public final class IntuitiveConceptService: @unchecked Sendable {
    public static let shared = IntuitiveConceptService()

    private let memoryCache = NSCache<NSString, NSString>()

    // MARK: - 精选高频核心意象知识库（0 毫秒即时呈现深度通透解析）
    private let curatedConceptMap: [String: String] = [
        "dedicate": """
        **核心画面**：“画圈贴专属标签（划归专用，绝不混用）”

        想象桌上有一大堆资源（可以是一块土地、一台设备、一笔钱，甚至是你自己的全部精力）。

        你走过去，拿记号笔把它单独圈出来，贴上一张大红色的专属标签，并在上面写着：
        “此项资源从今往后，百分之百只属于这个特定用途/人，其他任何人不准挪用，绝不掺杂任何旁鹜。”

        这就是 **dedicate** 的灵魂本义（源自拉丁语：庄严宣告并专门划出）。理解了这个画面，所有场景和变体就全部贯通了：
        • **献身/奉献**：把自己的全部时间和心血“单独划归”给某项崇高事业（dedicate one's life to science）；
        • **题献/落成**：把建成的纪念碑或写成的书“专属划归”给某位伟人或所爱之人（dedicate a book to my mother）；
        • **专属/专用**：在技术与工程中把某台服务器或频道单独划给特定任务（a dedicated server）。
        """,

        "width": """
        **核心画面**：“双手向左右平展，测量两端界限的横向跨度”

        想象你面前有一扇门、一张桌子或一块屏幕。你伸出双手，一左一右同时向两侧水平拉开，一直碰到最左边缘和最右边缘。

        你两手之间拉开的这段开阔距离，就是它的 **width**。

        **灵魂本义与场景贯通**：源自古英语 *wīd*（宽广、开阔）。在英语的空间认知中，它是与垂直高度（height）垂直相交的“横向延展维度”。掌握了这个向两侧张开的骨架画面：
        • **物理尺寸**：测量物体自左至右的跨度，是“宽度”；
        • **视野与格局**：思想或眼界向两侧无拘无束地舒展，是“广度/宽广”（width of vision / width of knowledge）；
        • **行业专指**：在纺织与印刷中，布匹或纸卷横向的一整幅，也是“门幅/幅宽”。
        """,

        "height": """
        **核心画面**：“抬头自下而上垂直攀升，克服重力向高空延伸”

        想象你站在一棵参天大树或摩天大楼的正下方。你仰起头，视线从地面紧贴着树干笔直向上攀升，一直穿透云霄到达最高顶点。这种从底座到顶峰克服重力的垂直距离，就是 **height**。

        **灵魂本义与场景贯通**：源自古英语 *hēah*（高耸）。它专指摆脱地表束缚、沿重力反方向向上攀升的垂直维度。掌握了这个自下而上的攀升画面：
        • **垂直尺寸**：测量人或建筑物的垂直高低，是“身高/高度”；
        • **空中位置**：飞行器或山峰距离海平面的高空跨度，是“海拔/空高”；
        • **状态极致**：事业、激情或温度冲刺到最顶峰，是“鼎盛时期/极点”（at the height of his career）。
        """,

        "depth": """
        **核心画面**：“从平静表层向幽暗深处层层沉浸探底”

        想象你站在一处清澈见底的幽潭边，手中拿着一块沉石投入水中。石头穿透水面，在水波中缓缓下沉，经过浅水区、昏暗层，最终沉入潭底。从表面向下垂直沉降的全部距离，就是 **depth**。

        **灵魂本义与场景贯通**：源自古英语 *dēop*（深沉、内聚）。它专指从表层向内部隐蔽处探寻的纵深维度。理解了这个向内沉潜的画面：
        • **物理纵深**：水池、峡谷由上至下的距离，是“水深/深度”；
        • **思想层次**：剖析问题摆脱肤浅浮躁、触及底层本质，是“深刻/深度”（depth of thought）；
        • **感官浓度**：色彩浓烈饱满、声音低沉浑厚，也是“深厚浓郁”（depth of color/sound）。
        """,

        "length": """
        **核心画面**：“沿着主要行进方向，首尾相贯的一维直线贯穿”

        想象你站在一条笔直延伸到地平线尽头的铁轨上。你放眼望去，铁轨从你脚下向远方无限延伸，首尾贯穿一条主干轴线。这种沿着物体主轴向远方延展的距离，就是 **length**。

        **灵魂本义与场景贯通**：源自古英语 *lang*（长久、延绵）。它是三维空间中最显著、主导的一维延伸轴线。理解了这个首尾相贯的延展画面：
        • **物理轴向**：测量物体主要方向的尺寸，是“长度”；
        • **时间长轴**：从起点延续至终点的一整段时间，是“时长/篇幅”（length of time）；
        • **竞技身位**：赛马或赛艇比赛中领先对手一个马身或船身，也叫一个 **length**。
        """,

        "elevate": """
        **核心画面**：“双手自下方平稳托举，将物体缓缓升入更高台阶”

        想象面前有一座低矮的台座，上面放着一件贵重艺术品。你走上前去，双手从底部稳稳托住它，平稳地向上举起，把它放置到更高一层、更加显眼的基座上。

        **灵魂本义与场景贯通**：源自拉丁语 *leuis*（轻盈、举起）。核心动作是赋予轻力并自下而上托升。掌握了这个托升动作：
        • **物理抬高**：把物体或肢体向上抬升，是“抬起/垫高”（elevate feet）；
        • **职场晋升**：把一个人的职位或社会地位提升到领导层，是“晋升/提拔”（elevated to director）；
        • **境界升华**：思想、品味或精神境界脱离平庸走向高雅，是“升华/提升层次”。
        """,

        "absorb": """
        **核心画面**：“干瘪海绵投入水中，瞬间将周围水分子全部吸纳同化”

        想象一块干燥紧缩的黄色海绵被丢进水碗里。它在一瞬间舒展开来，四周的水流被强力吸入每一个微小孔隙中，水与海绵融为一体，碗里的水消失了，海绵变得饱满而沉重。

        **灵魂本义与场景贯通**：源自拉丁语 *sorbere*（吮吸、吞没）。核心在于“将外物完全吸入体内并变为自身一部分”。掌握了这个吸附融合的画面：
        • **物理吸纳**：纸巾吸水、海绵吸液，是物理“吸收”；
        • **知识内化**：全神贯注地读书，把信息完全消化化为己用，是“汲取/领会”（absorb knowledge）；
        • **精神沉浸**：整个人被某件事完全吸引住，思绪无暇旁顾，就是“全神贯注/深深吸引”（absorbed in work）；
        • **经济兼并**：大企业出资将小公司全面收编合并，也是“兼并/吸收”。
        """,

        "reflect": """
        **核心画面**：“光线击中无瑕镜面后原路弹回，或在静夜中凝视倒影”

        想象深夜里你来到一面平滑如镜的冰湖前。你用手电筒照射冰面，光束瞬间折射弹向天空；接着你俯身凝视水面，看到了自己清晰的倒影与满天星斗，思绪开始向过去的记忆回溯。

        **灵魂本义与场景贯通**：源自拉丁语 *flectere*（折弯、弹回）。核心动作是“力量撞上界面后往回折返”。理解了这个光影折返与向内观照的画面：
        • **物理折回**：光线或声音遇到障碍弹回，是物理“反射/回响”；
        • **水面倒影**：湖水或镜子呈现景物模样，是“倒映/映射”；
        • **心智内省**：心智力量从外部世界折回自身内心、回看过去的行为，就是“反思/沉思”（reflect on the past）；
        • **事实体现**：某项政策的成果折射出团队的努力，也是“反映/体现”。
        """,

        "clarify": """
        **核心画面**：“浑浊泥水经过静置沉淀与滤纸过滤，瞬间变为晶莹剔透的甘泉”

        想象你手中拿着一杯刚从河道舀上来的黄泥水，昏暗浑浊、难见底细。你将它倒入一层精密滤网中，水中的泥沙杂质被全部截留剥离，下方滴落出来的水滴纯净透亮、纤尘不染，杯底的花纹一览无余。

        **灵魂本义与场景贯通**：源自拉丁语 *clarus*（明亮、清晰）。核心动作是“剥离所有杂质与混淆，显露纯粹透亮的本质”。掌握了这个滤净去浊的画面：
        • **烹饪澄净**：浑浊的黄油去除沉淀变为澄净，是烹饪中的“澄清”（clarified butter）；
        • **阐明事实**：把模糊不清、充满争议的事情解释得明明白白，是“阐明/澄清”（clarify a situation）；
        • **思维通透**：困扰许久的疑云彻底散去，事情全貌瞬间在脑海中清晰展现。
        """,

        "sustain": """
        **核心画面**：“坚厚双掌置于重物底部，任由岁月流逝依然持久稳稳托住”

        想象头顶上方悬着一块沉重的石梁。你迈开双腿扎稳马步，双臂高高举起，用掌心死死顶住石梁底部。哪怕时间一分一秒过去，手臂酸痛，但你的核心力量源源不断输出，石梁自始至终绝不坠落。

        **灵魂本义与场景贯通**：源自拉丁语 *sub-*（在下方）+ *tenere*（紧紧握住/托住）。核心动作是“在底部持续提供支撑力”。理解了这个自下而上稳固托举的画面：
        • **供养生存**：持续提供食物与能量让生命维持下去，是“赡养/维持”（sustain life）；
        • **生态运转**：让一个经济体或生态系统持久运转而不崩溃，是“可持续”（sustainable）；
        • **司法支持**：法庭上法官认可反对意见的合理性予以采纳，也是“维持/支持判定”（objection sustained）；
        • **经受考验**：身体或意志经受住重大打击而不垮掉，是“遭受/经受”（sustain an injury）。
        """,

        "resilience": """
        **核心画面**：“高山青竹被厚重积雪压至触地，积雪滑落瞬间猛烈弹回原本挺拔姿态”

        想象狂风暴雪中的一根翠竹。漫天大雪堆积在竹枝上，将笔直的竹竿压得几乎贴到地面。然而竹身内部纤维韧性十足，宁弯不折；当一阵风吹落积雪的刹那，青竹砰地一声破雪而起，瞬间弹回昂首挺立的傲然英姿。

        **灵魂本义与场景贯通**：源自拉丁语 *resilire*（向后弹回）。核心在于“遭受外力严重挤压变形后，能凭借内在弹性完美复原”。掌握了这个压不跨、弹得回的坚韧画面：
        • **材料弹性**：橡胶或弹簧受压后恢复原状，是物理“弹性/回弹力”；
        • **心理韧性**：人生遭遇挫折、失败或重大创伤后迅速振作走出阴霾，是“心理韧性/复原力”；
        • **系统抗逆**：城市网络或经济体系遭遇外部危机冲击后迅速恢复运行，也是“韧性/恢复力”。
        """,

        "focus": """
        **核心画面**：“凸透镜将四散的阳光汇聚于唯一一点，骤然燃起炽热火苗”

        想象夏日午后，你手持一块凸透镜对准地面枯叶。原本普照大地的漫散阳光，在穿透镜片后被急剧向中心压缩，最终化为一个小如针尖、极度耀眼的白炽光斑。几秒之内，光斑处青烟升腾，火苗瞬间点燃。

        **灵魂本义与场景贯通**：源自拉丁语 *focus*（壁炉、火焰中心）。核心在于“将分散的能量全部聚拢于单一中心点”。理解了这个聚光成火的画面：
        • **光学对焦**：调节镜头使光线汇聚在感光元件上形成清晰成像，是光学“对焦”；
        • **精力专注**：将散漫的心思与精力全部收拢投入到当下唯一的任务中，是“全神贯注/专注”（focus on work）；
        • **讨论核心**：整个会议或辩论讨论的最关键争论点，就是“核心焦点”（the main focus）。
        """
    ]

    private init() {
        memoryCache.countLimit = 400
    }

    /// 立即同步解析单词认知意象（0 毫秒即刻返回深度解析，确保卡片永不留白）
    public func resolveImmediateConcept(for word: String) -> String {
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanWord.isEmpty else { return "" }

        // 1. 内存缓存命中
        if let cached = memoryCache.object(forKey: cleanWord as NSString) {
            return cached as String
        }

        // 2. 精选深度通透认知库命中
        if let curated = curatedConceptMap[cleanWord] {
            memoryCache.setObject(curated as NSString, forKey: cleanWord as NSString)
            return curated
        }

        // 3. 从 macOS 本地牛津词典提取并精炼意象 (离线 0 毫秒)
        if let localSynthesized = synthesizeFromSystemDictionary(word: cleanWord) {
            memoryCache.setObject(localSynthesized as NSString, forKey: cleanWord as NSString)
            return localSynthesized
        }

        // 4. 通用优雅启发式兜底
        let fallback = """
        **核心画面**：“在脑海中勾勒「\(cleanWord)」特有的具象实体与物理动作”

        想象在具体生活或工作场景中，该词所指代的核心对象或动作过程正鲜活展开。

        **灵魂本义**：把握住其实体形态与行为意向，便能在不同语境中自然融会贯通其引申义与搭配习惯。
        """
        return fallback
    }

    /// 异步拉取认知意象：本地立即保障 + AI 深度提炼（按用户专属要求生成深度启发解析）
    public func fetchConcept(for word: String) async -> String {
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanWord.isEmpty, !cleanWord.contains(" ") else {
            return resolveImmediateConcept(for: word)
        }

        // 1. 若内存缓存已存在（可能来自此前的 AI 提炼），直接返回
        if let cached = memoryCache.object(forKey: cleanWord as NSString) {
            return cached as String
        }

        let baselineConcept = resolveImmediateConcept(for: cleanWord)

        // 2. 检查是否配置了 AI API Key
        let s = SettingsStore.shared
        let apiKey = s.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return baselineConcept
        }

        let endpoint = s.aiEndpoint.isEmpty
            ? "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            : s.aiEndpoint
        guard let url = URL(string: endpoint) else {
            return baselineConcept
        }
        let model = s.aiModel.isEmpty ? "gemini-2.0-flash" : s.aiModel

        // 3. 严格遵循用户指导：构建深度启发的三段式认知结构（核心画面 + 具象感知 + 灵魂本义与场景贯通）
        let systemPrompt = """
        你是一位精通认知语言学、语源学与形象思维的顶级学者。你的专长是通过“核心物理画面 + 具象生活场景 + 词根物理动作贯通”，让学习者一下深刻顿悟单词的灵魂本质，彻底融会贯通所有场景与引申变体。

        请针对英文单词「\(cleanWord)」，提供一段深刻透彻、极具启发性的深度认知解析，严格按照以下三段结构输出：

        **核心画面**：“用简短精炼、生动形象的物理动作或生活场景提炼该词最本质的核心喻象（如：画圈贴专属标签、双手向左右平展测量跨度）”

        **具象感知**：以“想象……”开启一个具体生动的生活或物理场景，引导学习者在脑海中身临其境地观察、动作与体会该词的物理过程。

        **灵魂本义与场景贯通**：揭示该词的词根/拉丁语本质物理动作，并清晰点拨“理解了这个核心画面，该词的所有常见含义与引申变体是如何一脉相通的”（列出2~3个典型应用场景，说明它们本质上都是这个画面的自然延伸）。

        写作规范：
        1. 深入浅出，通俗透彻却极具认知穿透力，富有启发感，让读者产生“一下子全顿悟了”的豁然开朗感；
        2. 严禁使用 Emoji 表情符号，严禁空洞生硬的词典式复述，严禁低俗套话；
        3. 使用规范的 Markdown 格式输出，加粗核心词，排版呼吸感强，字数在150~230字之间。
        """
        let userPrompt = "请为英文单词「\(cleanWord)」提供一段深刻顿悟的认知画面与灵魂本义解析，帮我彻底贯通理解所有引申义。"

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userPrompt]
            ],
            "temperature": 0.3,
            "max_tokens": 500
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return baselineConcept
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 10
        let session = URLSession(configuration: cfg)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return baselineConcept
            }

            struct Choice: Decodable {
                struct Msg: Decodable { let content: String }
                let message: Msg
            }
            struct Resp: Decodable { let choices: [Choice] }

            let decoded = try JSONDecoder().decode(Resp.self, from: data)
            if let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
                memoryCache.setObject(content as NSString, forKey: cleanWord as NSString)
                return content
            }
        } catch {
            // 网络异常时静默降级为本地精炼意象
        }

        return baselineConcept
    }

    // MARK: - 从 macOS 系统原生 Oxford 词典提取核心释义并合成认知意象
    private func synthesizeFromSystemDictionary(word: String) -> String? {
        let range = CFRangeMake(0, (word as NSString).length)
        guard let defRef = DCSCopyTextDefinition(nil, word as CFString, range) else { return nil }
        let rawDef = defRef.takeRetainedValue() as String

        // 提取中文字符串
        var chineseMatches: [String] = []
        let hanPattern = #"\p{Han}{2,10}"#
        if let regex = try? NSRegularExpression(pattern: hanPattern) {
            let nsStr = rawDef as NSString
            let results = regex.matches(in: rawDef, range: NSRange(location: 0, length: nsStr.length))
            for m in results.prefix(3) {
                chineseMatches.append(nsStr.substring(with: m.range))
            }
        }

        var coreEngPhrase = ""
        let lines = rawDef.components(separatedBy: .newlines)
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if (t.hasPrefix("the ") || t.hasPrefix("a ") || t.hasPrefix("to ") || t.hasPrefix("of ")) && t.count > 15 && t.count < 100 {
                coreEngPhrase = t
                break
            }
        }

        if !chineseMatches.isEmpty {
            let chSummary = chineseMatches.joined(separator: "、")
            return """
            **核心画面**：“在脑海中聚焦「\(chSummary)」的本质场景”

            想象在现实世界中，与 \(coreEngPhrase.isEmpty ? "该概念" : "“\(coreEngPhrase)”") 相关的核心动作与对象。

            **灵魂本义与场景贯通**：核心意指「\(chSummary)」。掌握了这一底层物理或空间动作，该词在不同语境下的各种引申含义即可迎刃而解。
            """
        }

        return nil
    }

    public func clearCache() {
        memoryCache.removeAllObjects()
    }
}
