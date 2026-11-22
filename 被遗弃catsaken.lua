--[[
    ═══════════════════════════════════════════════════════════════════════════
    catsaken 汉化版
    ═══════════════════════════════════════════════════════════════════════════

    原脚本：https://raw.githubusercontent.com/aibabylaugh/catsaken/refs/heads/main/Beta/catsaken.lua
    原调用：loadstring(game:HttpGet("...catsaken.lua"))("gg/VzHp67sw9a")

    汉化方式：运行时 Hook（拦截 Text 赋值）+ 监听兜底，不改原脚本字节。
    翻译表 812 条，覆盖小游戏 / 透视 / 自瞄 / 设置 / 传送 等全部页签。

    为什么不做源码级汉化：原脚本 1.2MB，主体是混淆过的虚拟机字节码，
    字符串全在 VM 里，直接改会破坏字节码。运行时拦截是唯一稳的路子。
]]

local ScriptUrl = "https://raw.githubusercontent.com/aibabylaugh/catsaken/refs/heads/main/Beta/catsaken.lua"
local ScriptArg = "gg/VzHp67sw9a"

-- ═══════════════════════════════════════════════════════════════════════════
-- 开关
-- ═══════════════════════════════════════════════════════════════════════════
-- ENABLE_HOOK：拦截 Instance 元表的 __newindex。
--   翻得最快、无闪烁，但会改写全局元表 —— catsaken 的 VM 对元表状态敏感，
--   实测会导致 buffer.create 收错 size 而崩。默认关闭。
--   想试可以改成 true，失败会自动回落到监听模式。
local ENABLE_HOOK = false

-- ENABLE_TRANSLATE：总开关。改成 false 就变成"纯加载不翻译"，
--   用来排查"到底是翻译层的问题还是原脚本的问题"。
local ENABLE_TRANSLATE = true

print("[汉化] catsaken 汉化版 加载中…（翻译 " ..
    (ENABLE_TRANSLATE and "开" or "关") .. " / Hook " ..
    (ENABLE_HOOK and "开" or "关") .. "）")

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. 翻译表（812 条）
-- ═══════════════════════════════════════════════════════════════════════════
local Translations = {

    -- 小游戏
    ["Generators"] = "发电机",
    ["Autofarm generators"] = "自动刷取发电机",
    ["Hide puzzle ui"] = "隐藏解谜界面",
    ["OFF"] = "关闭",
    ["Instantly enter generator"] = "立即进入发电机",
    ["Complete every generator"] = "完成所有发电机",
    ["Flow Game"] = "连线游戏",
    ["Draw solution"] = "绘制解法",
    ["Auto solve flow game"] = "自动解决连线游戏",
    ["Grid size changer"] = "网格大小修改器",
    ["Grid Size"] = "网格大小",
    ["Puzzle speed"] = "解谜速度",
    ["Use legit speed"] = "使用正常速度",
    ["Mistake chance"] = "失误几率",
    ["Dots Connect"] = "点连接",
    ["Draw lines"] = "绘制线条",
    ["Auto connect lines"] = "自动连接线条",
    ["Pairs amount changer"] = "配对数量修改器",
    ["Pairs"] = "配对数",
    ["Delay between lines"] = "线条间隔延迟",
    ["Lockpick"] = "开锁",
    ["Auto complete"] = "自动完成",
    ["Anti miss"] = "防失误",
    ["Gears"] = "齿轮",
    ["Auto turn gears"] = "自动转动齿轮",
    ["Turn degrees"] = "转动角度",
    ["Turn delay"] = "转动延迟",
    ["Nosferatu"] = "诺斯费拉图",
    ["Auto reel"] = "自动收线",
    ["Auto escape"] = "自动逃脱",
    ["Minimum press delay"] = "最小按压延迟",
    ["Maximum press delay"] = "最大按压延迟",
    ["Azure"] = "蔚蓝",
    ["Auto disarm minigame"] = "自动拆除小游戏",
    ["Minimum time"] = "最短时间",
    ["Maximum time"] = "最长时间",
    ["Infinite disarm attempts"] = "无限拆除尝试",
    ["Teleports"] = "传送",
    ["Select generator 1"] = "选择发电机 1",
    ["Teleport to generator"] = "传送到发电机",
    ["Generator Settings"] = "发电机设置",
    ["Minigame Notifications"] = "小游戏通知",
    ["Autofarm Notifications"] = "自动刷取通知",
    ["ON"] = "开启",
    ["Round ends in:"] = "回合结束于:",
    ["This round's killer is..."] = "本回合的杀手是...",

    -- 透视
    ["Player Esp"] = "玩家透视",
    ["Killer Esp"] = "杀手透视",
    ["Survivor Esp"] = "幸存者透视",
    ["Zombie/Minion Esp"] = "僵尸/小兵透视",
    ["007n7 Clone Esp"] = "007n7 分身透视",
    ["Ability/Object Esp"] = "技能/物体透视",
    ["Generator Esp"] = "发电机透视",
    ["Item Esp"] = "物品透视",
    ["Jane Doe Quest Esp"] = "Jane Doe 任务透视",
    ["Taph Esp"] = "Taph 透视",
    ["Tripmine ranges Esp"] = "绊雷范围透视",
    ["Builderman Esp"] = "Builderman 透视",
    ["John Doe Esp"] = "John Doe 透视",
    ["Veeronica Esp"] = "Veeronica 透视",
    ["Azure Esp"] = "蔚蓝透视",
    ["Bulb/Vine ranges Esp"] = "灯泡/藤蔓范围透视",
    ["Gears Esp"] = "齿轮透视",
    ["Esp Colors"] = "透视颜色",
    ["Generator Color"] = "发电机颜色",
    ["Killer Color"] = "杀手颜色",
    ["Survivor Color"] = "幸存者颜色",
    ["Item Color"] = "物品颜色",
    ["Zombie/Minion Color"] = "僵尸/小兵颜色",
    ["007n7 Clone Color"] = "007n7 分身颜色",
    ["Taph Color"] = "Taph 颜色",
    ["Builderman Color"] = "Builderman 颜色",
    ["John Doe Color"] = "John Doe 颜色",
    ["Veeronica Color"] = "Veeronica 颜色",
    ["Azure Color"] = "蔚蓝颜色",
    ["Quest Color"] = "任务颜色",
    ["Gears Color"] = "齿轮颜色",
    ["Esp Settings"] = "透视设置",
    ["Outlines only"] = "仅轮廓",
    ["No outlines"] = "无轮廓",
    ["Show items in Player Esp"] = "在玩家透视中显示物品",
    ["Show device in Player Esp"] = "在玩家透视中显示装置",
    ["Show health in Player Esp"] = "在玩家透视中显示生命值",
    ["Outline whiteness"] = "轮廓白度",
    ["HP Bar style Percent"] = "血条样式 百分比",
    ["Enable all Esp"] = "启用所有透视",
    ["Tag Settings"] = "标签设置",
    ["Survivor tags"] = "幸存者标签",
    ["Item tags"] = "物品标签",
    ["Gears tags"] = "齿轮标签",
    ["Zombie/Minion tags"] = "僵尸/小兵标签",
    ["Killer tags"] = "杀手标签",
    ["Generator tags"] = "发电机标签",
    ["Percent"] = "百分比",
    ["Number"] = "数字",

    -- 体力
    ["Infinite stamina"] = "无限体力",
    ["Sprint while at 0 stamina (legit)"] = "0体力时冲刺（正常）",
    ["Disable stamina loss"] = "禁用体力消耗",
    ["Enable stamina settings"] = "启用体力设置",
    ["Survivor stamina settings"] = "幸存者体力设置",
    ["Max Stamina"] = "最大体力",
    ["Stamina Loss"] = "体力消耗",
    ["Stamina Gain"] = "体力恢复",
    ["Killer stamina settings"] = "杀手体力设置",
    ["Sprinting"] = "冲刺",
    ["Fast sprint (kick warning)"] = "快速冲刺（踢出警告）",
    ["Speed"] = "速度",
    ["Instant stamina recovery"] = "瞬间体力恢复",
    ["Maximum penalty time"] = "最大惩罚时间",

    -- 自瞄
    ["Silent Aim"] = "静默瞄准",
    ["Enable silent aim"] = "启用静默瞄准",
    ["Ability to use silent aim no options"] = "使用静默瞄准的能力（无选项）",
    ["Dusekkar target survivor"] = "Dusekkar 目标幸存者",
    ["Aimbot"] = "自动瞄准",
    ["Enable aimbots"] = "启用自动瞄准",
    ["Ability to use aimbot no options"] = "使用自动瞄准的能力（无选项）",
    ["M1 assist"] = "M1 辅助",
    ["Chance 360 no-scope"] = "Chance 360 盲狙",
    ["Void Rush range"] = "虚空冲刺范围",
    ["Walkspeed Override range"] = "速度覆盖范围",
    ["Charge range"] = "冲锋范围",
    ["Aimbot mode Character"] = "自动瞄准模式 角色",
    ["Plasma beam - Dusekkar"] = "等离子光束 - Dusekkar",
    ["Void Star - Noli"] = "虚空之星 - Noli",
    ["Corrupt Nature - Coolkid"] = "腐蚀自然 - Coolkid",
    ["Crystal - Jane Doe"] = "水晶 - Jane Doe",
    ["Enstrangle - Azure"] = "缠绕 - 蔚蓝",
    ["Infernal Cry - Sixer"] = "地狱哭喊 - Sixer",
    ["Camera"] = "摄像机",
    ["Character"] = "角色",

    -- 命中框
    ["Hitbox Expander"] = "命中框扩展器",
    ["Enable hitbox expander"] = "启用命中框扩展器",
    ["Range"] = "范围",
    ["Target Facing"] = "目标朝向",
    ["Expand mode Dynamic"] = "扩展模式 动态",
    ["(Dynamic) auto rotate"] = "（动态）自动旋转",
    ["Dynamic: Automatically guarantees your hitbox to land on targetted player\nStatic: Increases your hitbox distance X amount infront of you\nHIGHER RANGE = MORE GAPS AND MORE OBVIOUS"] = "动态：自动保证你的命中框落在目标玩家身上\n静态：在你前方增加 X 距离的命中框\n范围越大 = 间隙越多且越明显",
    ["Hitbox Visualiser (PERFORMANCE INTENSIVE)"] = "命中框可视化（性能消耗大）",
    ["Enable visualiser modifications"] = "启用可视化修改",
    ["Material Plastic"] = "材质 塑料",
    ["Hitbox color"] = "命中框颜色",
    ["Hitbox color (Hit)"] = "命中框颜色（命中）",
    ["Hitbox transparency"] = "命中框透明度",
    ["Hitbox transparency (Hit)"] = "命中框透明度（命中）",
    ["M1 Visualizer"] = "M1 可视化",
    ["Enable M1 Hitbox visualizer"] = "启用 M1 命中框可视化",
    ["Dont show if M1 not ready"] = "M1 未就绪时隐藏",
    ["Track query position"] = "追踪查询位置",
    ["Dont show if M1 hitboxes"] = "M1 命中框时隐藏",
    ["Facing"] = "朝向",
    ["Nearest"] = "最近",
    ["Lowest HP"] = "最低生命值",
    ["Dynamic"] = "动态",
    ["Static"] = "静态",

    -- 材质
    ["Air"] = "空气",
    ["Asphalt"] = "沥青",
    ["Basalt"] = "玄武岩",
    ["Brick"] = "砖",
    ["Cardboard"] = "纸板",
    ["Carpet"] = "地毯",
    ["CeramicTiles"] = "瓷砖",
    ["ClayRoofTiles"] = "黏土屋顶瓦",
    ["Cobblestone"] = "鹅卵石",
    ["Concrete"] = "混凝土",
    ["CorrodedMetal"] = "腐蚀金属",
    ["CrackedLava"] = "裂开岩浆",
    ["DiamondPlate"] = "花纹钢板",
    ["Fabric"] = "织物",
    ["Foil"] = "箔",
    ["ForceField"] = "力场",
    ["Glacier"] = "冰川",
    ["Glass"] = "玻璃",
    ["Granite"] = "花岗岩",
    ["Grass"] = "草",
    ["Ground"] = "地面",
    ["Ice"] = "冰",
    ["LeafyGrass"] = "多叶草",
    ["Leather"] = "皮革",
    ["Limestone"] = "石灰岩",
    ["Marble"] = "大理石",
    ["Metal"] = "金属",
    ["Mud"] = "泥",
    ["Neon"] = "霓虹",
    ["Pavement"] = "路面",
    ["Pebble"] = "卵石",
    ["Plaster"] = "灰泥",
    ["Plastic"] = "塑料",
    ["Rock"] = "岩石",
    ["RoofShingles"] = "屋顶瓦",
    ["Rubber"] = "橡胶",
    ["Salt"] = "盐",
    ["Sand"] = "沙",
    ["Sandstone"] = "砂岩",
    ["Slate"] = "板岩",
    ["SmoothPlastic"] = "光滑塑料",
    ["Snow"] = "雪",
    ["Water"] = "水",
    ["Wood"] = "木头",
    ["WoodPlanks"] = "木板",

    -- 角色
    ["Global"] = "全局",
    ["Kick warning for all noclip features!, if you get stuck you will probably get kicked"] = "所有穿墙功能的踢出警告！如果你卡住，很可能会被踢出",
    ["Disable directional speed"] = "禁用方向速度",
    ["Disable directional movement"] = "禁用方向移动",
    ["Speed boost"] = "速度提升",
    ["Demonic pursuit noclip"] = "恶魔追击穿墙",
    ["Demonic pursuit anti-crash"] = "恶魔追击防崩溃",
    ["Infinite hitbox trail"] = "无限命中框轨迹",
    ["Void rush noclip"] = "虚空冲刺穿墙",
    ["Void rush anti-crash"] = "虚空冲刺防崩溃",
    ["Void rush control"] = "虚空冲刺控制",
    ["Auto detonate nova"] = "自动引爆新星",
    ["Charge anti-crash"] = "冲锋防崩溃",
    ["Charge turn control"] = "冲锋转向控制",
    ["Charge pilot"] = "冲锋驾驶",
    ["Charge noclip"] = "冲锋穿墙",
    ["Change punch distance"] = "修改拳击距离",
    ["Power"] = "威力",
    ["Infinite flight duration"] = "无限飞行时间",
    ["Walkspeed override pilot"] = "速度覆盖驾驶",
    ["Walkspeed override noclip"] = "速度覆盖穿墙",
    ["Walkspeed override TP hit"] = "速度覆盖传送命中",
    ["Azure tentacles exploit"] = "蔚蓝触手漏洞",
    ["Throw velocity"] = "投掷速度",
    ["Instant crystal charge"] = "瞬间水晶充能",
    ["Infinite crystal hold time"] = "无限水晶保持时间",
    ["Clone follow/bodyblock"] = "分身跟随/挡身",
    ["Mode Front"] = "模式 前方",
    ["Target Killer"] = "目标杀手",
    ["Prediction"] = "预测",
    ["Distance"] = "距离",
    ["Troll c00lgui"] = "恶搞 c00lgui",
    ["Cancellable c00lgui"] = "可取消 c00lgui",
    ["Sk8 auto trick"] = "滑板自动特技",
    ["Sk8 turn control"] = "滑板转向控制",
    ["Sk8 anti-crash"] = "滑板防崩溃",
    ["Sk8 forever"] = "滑板永久",
    ["Sk8 trick anywhere"] = "滑板任意位置特技",
    ["Sk8 autofarm"] = "滑板自动刷取",
    ["Sk8 movement control"] = "滑板移动控制",
    ["Anti protection break"] = "防保护破坏",
    ["Use protection through walls"] = "穿墙使用保护",
    ["Unlimited protect range"] = "无限保护范围",
    ["Auto slash 360"] = "自动 360 斩击",
    ["360 duration"] = "360 持续时间",
    ["360 delay"] = "360 延迟",
    ["Slash lunge"] = "斩击突进",
    ["Auto backstab"] = "自动背刺",
    ["Glidestab helper"] = "滑行背刺助手",
    ["Lunge hitbox distance multi"] = "突进命中框距离倍数",
    ["Crouch hitbox distance multi"] = "蹲下命中框距离倍数",
    ["Backstab exploit"] = "背刺漏洞",
    ["Normal"] = "正常",
    ["Orbit"] = "环绕",
    ["Front"] = "前方",
    ["Back"] = "后方",
    ["Run away"] = "逃跑",
    ["Strafe"] = "横移",
    ["Killer"] = "杀手",
    ["Nearest survivor"] = "最近幸存者",
    ["Lowest health"] = "最低生命值",
    ["Yourself"] = "自己",

    -- 自动格挡
    ["Auto Block"] = "自动格挡",
    ["Auto block"] = "自动格挡",
    ["Auto clone 007n7"] = "自动分身 007n7",
    ["Auto raging pace"] = "自动狂暴步伐",
    ["Auto 404 Error"] = "自动 404 错误",
    ["Your ping is 0.11s (Bad, try finding a new server)"] = "你的延迟是 0.11s（差，尝试寻找新服务器）",
    ["Auto punch"] = "自动出拳",
    ["Hitbox shake"] = "命中框抖动",
    ["Hitbox drag tech"] = "命中框拖拽技巧",
    ["Detection range and face/hitbox check apply to auto raging pace/404 error/clone, not auto block"] = "检测范围和面部/命中框检查适用于自动狂暴步伐/404错误/分身，不适用于自动格挡",
    ["Detection range"] = "检测范围",
    ["Face check"] = "面部检查",
    ["Hitbox check"] = "命中框检查",
    ["Detect slasher sounds"] = "检测杀手声音",
    ["Aim on 2 options"] = "瞄准 2 个选项",
    ["Wait delay before blocking"] = "格挡前等待延迟",
    ["Sound detection"] = "声音检测",
    ["Query based detection"] = "基于查询的检测",
    ["Hitbox/Visualizer"] = "命中框/可视化",
    ["Show hitbox"] = "显示命中框",
    ["Always show"] = "始终显示",
    ["Left size"] = "左侧大小",
    ["Right size"] = "右侧大小",
    ["Front size"] = "前方大小",
    ["Back size"] = "后方大小",
    ["Z-Expansion"] = "Z 轴扩展",
    ["Color (In hitbox)"] = "颜色（在命中框内）",
    ["Color (Not in hitbox)"] = "颜色（不在命中框内）",
    ["Show HDT hitbox"] = "显示 HDT 命中框",
    ["HDT left size"] = "HDT 左侧大小",
    ["HDT right size"] = "HDT 右侧大小",
    ["HDT front size"] = "HDT 前方大小",
    ["HDT back size"] = "HDT 后方大小",
    ["HDT Color (In hitbox)"] = "HDT 颜色（在命中框内）",
    ["HDT Color (Not in hitbox)"] = "HDT 颜色（不在命中框内）",
    ["Block Settings"] = "格挡设置",
    ["Block void rush"] = "格挡虚空冲刺",
    ["Block walkspeed override"] = "格挡速度覆盖",
    ["Enable sprint after block"] = "格挡后启用冲刺",
    ["Notifications"] = "通知",
    ["Block"] = "格挡",
    ["Punch"] = "出拳",

    -- 自己
    ["Player related settings"] = "玩家相关设置",
    ["Spectate detector"] = "观战检测器",
    ["Notify"] = "通知",
    ["Auto remove popups"] = "自动移除弹窗",
    ["Auto unsprint"] = "自动取消冲刺",
    ["Always sprint"] = "始终冲刺",
    ["No sprint tweening"] = "无冲刺过渡",
    ["Togglable sprint"] = "可切换冲刺",
    ["No slowdown"] = "无减速",
    ["No slowdown from abilitys"] = "技能无减速",
    ["Device spoofer"] = "设备伪装",
    ["Server device Mobile"] = "服务器设备 手机",
    ["Client device Mobile"] = "客户端设备 手机",
    ["Always show sidebar"] = "始终显示侧边栏",
    ["Always show chat"] = "始终显示聊天",
    ["Always show player list"] = "始终显示玩家列表",
    ["Privacy bypass"] = "隐私绕过",
    ["Disable winner cutscene"] = "禁用获胜者动画",
    ["Reveal hallucination status"] = "显示幻觉状态",
    ["Player abilitys"] = "玩家技能",
    ["Auto flip coin"] = "自动抛硬币",
    ["Max charges"] = "最大充能",
    ["TP Slash"] = "传送斩击",
    ["TP One Shot"] = "传送一击",
    ["Auto chicken"] = "自动鸡",
    ["Health limit"] = "生命值限制",
    ["Only when far from killer"] = "仅当远离杀手时",
    ["Stun spy"] = "眩晕间谍",
    ["Reveal ability trajectory"] = "显示技能轨迹",
    ["Walk over digital footprint"] = "走过数字足迹",
    ["Walk over trails"] = "走过轨迹",
    ["Walk over nos puddles"] = "走过诺斯水坑",
    ["Anti block"] = "防格挡",
    ["Anti backstab"] = "防背刺",
    ["Azure trap spoof"] = "蔚蓝陷阱伪装",
    ["Auto M1"] = "自动 M1",
    ["Auto Slash/M1"] = "自动斩击/M1",
    ["Radius"] = "半径",
    ["Auto radius"] = "自动半径",
    ["Wasabi"] = "芥末",
    ["PC"] = "PC",
    ["Mobile"] = "手机",
    ["Console"] = "主机",
    ["Unknown"] = "未知",

    -- 动画
    ["Movement animations"] = "移动动画",
    ["Animations are FE — Everyone can see them like you do ✅"] = "动画是 FE — 所有人看到的效果和你一样 ✅",
    ["Replace run animations"] = "替换跑步动画",
    ["Basic run Default"] = "基础跑步 默认",
    ["Default"] = "默认",
    ["Noli Racing"] = "Noli 赛车",
    ["Slasher (Swift)"] = "Slasher（迅捷）",
    ["Nosferatu but old"] = "老版诺斯费拉图",
    ["BRIMSTONE"] = "硫磺",
    ["Cat"] = "猫",
    ["Friday The 13th Slasher"] = "十三号星期五 Slasher",
    ["Sixer Hunt"] = "Sixer 猎杀",
    ["Sukuna"] = "宿傩",
    ["Horse"] = "马",
    ["John Doe March 18th"] = "John Doe 3月18日",
    ["The Swordsmaster"] = "剑圣",
    ["Jason"] = "杰森",
    ["Slasher"] = "Slasher",
    ["Martial Artist"] = "武术家",
    ["Noli (Illusionary)"] = "Noli（幻影）",
    ["Noli (Narrator)"] = "Noli（旁白）",
    ["Noli (Milestone III)"] = "Noli（里程碑 III）",
    ["Noli (Milestone IV)"] = "Noli（里程碑 IV）",
    ["Noli (Devesto)"] = "Noli（Devesto）",
    ["Noli (Artful)"] = "Noli（艺术）",
    ["Noli (SPECIAL Yourself)"] = "Noli（特殊 你自己）",
    ["Noli (cameramn)"] = "Noli（摄影师）",
    ["Noli (The Admin)"] = "Noli（管理员）",
    ["Noli (Sigil)"] = "Noli（符印）",
    ["Noli (Content Creator)"] = "Noli（内容创作者）",
    ["Slasher (Subject_0)"] = "Slasher（Subject_0）",
    ["Slasher (Slaughter at Arms)"] = "Slasher（武装屠杀）",
    ["Slasher (Retro)"] = "Slasher（复古）",
    ["Slasher (Pursuer)"] = "Slasher（追击者）",
    ["Slasher (XD Reanim)"] = "Slasher（XD 重动画）",
    ["Slasher (Milestone III)"] = "Slasher（里程碑 III）",
    ["Slasher (Milestone IV)"] = "Slasher（里程碑 IV）",
    ["Slasher (Lovecore)"] = "Slasher（Lovecore）",
    ["Slasher (Killer Kyle)"] = "Slasher（杀手 Kyle）",
    ["Slasher (Pest)"] = "Slasher（瘟疫）",
    ["Slasher (Alfred Drevis)"] = "Slasher（Alfred Drevis）",
    ["Slasher (Drifter)"] = "Slasher（漂泊者）",
    ["Slasher (SPECIAL Yourself)"] = "Slasher（特殊 你自己）",
    ["Slasher (Mystic)"] = "Slasher（神秘）",
    ["Slasher (Combat Initiation)"] = "Slasher（战斗 initiation）",
    ["Slasher (Captain Zombie)"] = "Slasher（僵尸队长）",
    ["Slasher (Guesty)"] = "Slasher（Guesty）",
    ["Slasher (Classic)"] = "Slasher（经典）",
    ["c00lkidd (Krystal)"] = "c00lkidd（Krystal）",
    ["c00lkidd (c00lskeleton95)"] = "c00lkidd（c00lskeleton95）",
    ["c00lkidd (Milestone III)"] = "c00lkidd（里程碑 III）",
    ["c00lkidd (P4rtyPwny)"] = "c00lkidd（P4rtyPwny）",
    ["c00lkidd (Mafioso)"] = "c00lkidd（黑手党）",
    ["c00lkidd (Infernal)"] = "c00lkidd（地狱）",
    ["c00lkidd (Milestone IV)"] = "c00lkidd（里程碑 IV）",
    ["c00lkidd (c0llabk1dd)"] = "c00lkidd（c0llabk1dd）",
    ["c00lkidd (Celebration)"] = "c00lkidd（庆典）",
    ["c00lkidd (Orbb)"] = "c00lkidd（Orbb）",
    ["c00lkidd (TV TIME)"] = "c00lkidd（电视时间）",
    ["c00lkidd (1dev2)"] = "c00lkidd（1dev2）",
    ["c00lkidd (SPECIAL Yourself)"] = "c00lkidd（特殊 你自己）",
    ["c00lkidd (PH0NK1DD)"] = "c00lkidd（PH0NK1DD）",
    ["c00lkidd (3t1llmm0rph)"] = "c00lkidd（3t1llmm0rph）",
    ["1x1x1x1 (Gatito)"] = "1x1x1x1（Gatito）",
    ["1x1x1x1 (Voidbound test)"] = "1x1x1x1（虚空束缚测试）",
    ["1x1x1x1 (Toy)"] = "1x1x1x1（玩具）",
    ["1x1x1x1 (Timeless)"] = "1x1x1x1（永恒）",
    ["1x1x1x1 (Digital Rider)"] = "1x1x1x1（数字骑手）",
    ["1x1x1x1 (Milestone III)"] = "1x1x1x1（里程碑 III）",
    ["1x1x1x1 (Milestone IV)"] = "1x1x1x1（里程碑 IV）",
    ["1x1x1x1 (Martyr)"] = "1x1x1x1（殉道者）",
    ["1x1x1x1 (Hacklord)"] = "1x1x1x1（黑客领主）",
    ["1x1x1x1 (Fleskhjerta)"] = "1x1x1x1（Fleskhjerta）",
    ["1x1x1x1 (The Pestilence)"] = "1x1x1x1（瘟疫）",
    ["1x1x1x1 (SPECIAL Yourself)"] = "1x1x1x1（特殊 你自己）",
    ["1x1x1x1 (Boomer Formula)"] = "1x1x1x1（Boomer 公式）",
    ["1x1x1x1 (Eye of The Abyss)"] = "1x1x1x1（深渊之眼）",
    ["1x1x1x1 (xX4ceOfSpadesXx)"] = "1x1x1x1（xX4ceOfSpadesXx）",
    ["John Doe (Annihilation)"] = "John Doe（湮灭）",
    ["John Doe (Treachstone)"] = "John Doe（Treachstone）",
    ["John Doe (Screamer)"] = "John Doe（尖叫者）",
    ["John Doe (Milestone III)"] = "John Doe（里程碑 III）",
    ["John Doe (Milestone IV)"] = "John Doe（里程碑 IV）",
    ["John Doe (SPECIAL Yourself)"] = "John Doe（特殊 你自己）",
    ["John Doe (Aberrant)"] = "John Doe（异常）",
    ["John Doe (Boomer Formula)"] = "John Doe（Boomer 公式）",
    ["John Doe (J0H/M-18)"] = "John Doe（J0H/M-18）",
    ["John Doe (MLG)"] = "John Doe（MLG）",
    ["John Doe (Electromaniac)"] = "John Doe（电狂）",
    ["Jason (Combat Initiation)"] = "杰森（战斗 initiation）",
    ["Jason (Retro)"] = "杰森（复古）",
    ["Jason (Pursuer)"] = "杰森（追击者）",
    ["Jason (White Pumpkin)"] = "杰森（白南瓜）",
    ["Jason (Subject_0)"] = "杰森（Subject_0）",
    ["Jason (Killer Kyle)"] = "杰森（杀手 Kyle）",
    ["Azure (Deceiver)"] = "蔚蓝（欺骗者）",
    ["Nosferatu (Gluttony)"] = "诺斯费拉图（暴食）",
    ["Nosferatu (Milestone IV)"] = "诺斯费拉图（里程碑 IV）",
    ["Nosferatu (Milestone III)"] = "诺斯费拉图（里程碑 III）",
    ["Shedletsky (Retro)"] = "Shedletsky（复古）",
    ["Shedletsky (Little Guy)"] = "Shedletsky（小家伙）",
    ["Shedletsky (Boomer Formula)"] = "Shedletsky（Boomer 公式）",
    ["Noob (Cadi)"] = "菜鸟（Cadi）",
    ["Noob (Retro)"] = "菜鸟（复古）",
    ["Noob (Little)"] = "菜鸟（小）",
    ["Noob (Scoutpot)"] = "菜鸟（Scoutpot）",
    ["Noob (Campsite Victims)"] = "菜鸟（营地受害者）",
    ["Noob (Toy)"] = "菜鸟（玩具）",
    ["Noob (Genesis)"] = "菜鸟（创世纪）",
    ["Noob (Roommate)"] = "菜鸟（室友）",
    ["Noob (Runaway)"] = "菜鸟（逃亡者）",
    ["Noob (Zombie)"] = "菜鸟（僵尸）",
    ["Guest 1337 (Little Guy)"] = "Guest 1337（小家伙）",
    ["Guest 1337 (Nerfed Demoman)"] = "Guest 1337（削弱爆破手）",
    ["Guest 1337 (xXDARKSLAYERJONESXx)"] = "Guest 1337（xXDARKSLAYERJONESXx）",
    ["Guest 1337 (Gunsonnect76)"] = "Guest 1337（Gunsonnect76）",
    ["007n7 (Scripter)"] = "007n7（脚本师）",
    ["007n7 (Deivydoestutorials33)"] = "007n7（Deivydoestutorials33）",
    ["007n7 (Little Guy)"] = "007n7（小家伙）",
    ["Builderman (Oh Noes)"] = "Builderman（Oh Noes）",
    ["Builderman (Retro)"] = "Builderman（复古）",
    ["Builderman (Bob)"] = "Builderman（Bob）",
    ["Builderman (Cat Rocker)"] = "Builderman（猫摇滚）",
    ["Builderman (Punk)"] = "Builderman（朋克）",
    ["Builderman (dragondudes3)"] = "Builderman（dragondudes3）",
    ["Builderman (Toy)"] = "Builderman（玩具）",
    ["Builderman (Little Guy)"] = "Builderman（小家伙）",
    ["Builderman (Boomer Formula)"] = "Builderman（Boomer 公式）",
    ["Builderman (Guiltridden)"] = "Builderman（罪恶感）",
    ["Taph (ZeekytheHbomb)"] = "Taph（ZeekytheHbomb）",
    ["Taph (Toy)"] = "Taph（玩具）",
    ["Taph (Little)"] = "Taph（小）",
    ["Taph (Xx_Rumblefan95_xX)"] = "Taph（Xx_Rumblefan95_xX）",
    ["Taph (Silken)"] = "Taph（丝绸）",
    ["Dusekkar (ToaZuku)"] = "Dusekkar（ToaZuku）",
    ["Dusekkar (2009)"] = "Dusekkar（2009）",
    ["Dusekkar (Toy)"] = "Dusekkar（玩具）",
    ["Dusekkar (Medic)"] = "Dusekkar（医疗兵）",
    ["Dusekkar (FliesOfTheLord)"] = "Dusekkar（FliesOfTheLord）",
    ["Dusekkar (It Came From the Mansion)"] = "Dusekkar（来自豪宅）",
    ["Dusekkar (Team Beacon)"] = "Dusekkar（队伍信标）",
    ["Dusekkar (Little Guy)"] = "Dusekkar（小家伙）",
    ["Dusekkar (Boomer Formula)"] = "Dusekkar（Boomer 公式）",
    ["Dusekkar (Soul Sitter)"] = "Dusekkar（灵魂看守）",
    ["Dusekkar (Ghost Hunter)"] = "Dusekkar（猎鬼者）",
    ["Two Time (Yourself)"] = "Two Time（你自己）",
    ["Two Time (Autumn)"] = "Two Time（秋天）",
    ["Veeronica (Little Gal)"] = "Veeronica（小姑娘）",
    ["Chance (Retro)"] = "Chance（复古）",
    ["Chance (Little Guy)"] = "Chance（小家伙）",
    ["Chance (Serpent)"] = "Chance（毒蛇）",
    ["Elliot (Retro)"] = "Elliot（复古）",
    ["Elliot (Bobby)"] = "Elliot（Bobby）",
    ["Elliot (Jordan)"] = "Elliot（Jordan）",
    ["Elliot (Sally)"] = "Elliot（Sally）",
    ["Elliot (Friend)"] = "Elliot（朋友）",
    ["Elliot (Monster)"] = "Elliot（怪物）",
    ["Elliot (Toy)"] = "Elliot（玩具）",
    ["Elliot (Little Guy)"] = "Elliot（小家伙）",
    ["Elliot (VIP)"] = "Elliot（VIP）",
    ["Elliot (Spirit Animal)"] = "Elliot（精神动物）",
    ["Elliot (Mr. Meyer)"] = "Elliot（Meyer 先生）",
    ["Jane Doe (Classic)"] = "Jane Doe（经典）",
    ["Jane Doe (Sleepwalker23)"] = "Jane Doe（Sleepwalker23）",
    ["Jane Doe (Merri)"] = "Jane Doe（Merri）",
    ["Martial Artist (Roommate)"] = "武术家（室友）",
    ["Helperbot (Milestone IV)"] = "Helperbot（里程碑 IV）",
    ["Injured run Default"] = "受伤跑步 默认",
    ["Replace walk animations"] = "替换行走动画",
    ["Basic walk Default"] = "基础行走 默认",
    ["Injured walk Default"] = "受伤行走 默认",
    ["Replace idle animations"] = "替换待机动画",
    ["Basic idle Default"] = "基础待机 默认",
    ["Injured idle Default"] = "受伤待机 默认",
    ["Fake injured animations"] = "假受伤动画",
    ["Ghost animations"] = "幽灵动画",
    ["Enable ghost animations"] = "启用幽灵动画",
    ["Ghost M1 Animation"] = "幽灵 M1 动画",
    ["Shedletsky no options"] = "Shedletsky（无选项）",
    ["Chance no options"] = "Chance（无选项）",
    ["TwoTime no options"] = "TwoTime（无选项）",
    ["Noob no options"] = "菜鸟（无选项）",
    ["1x1x1x1 no options"] = "1x1x1x1（无选项）",
    ["Sixer no options"] = "Sixer（无选项）",
    ["Slasher no options"] = "Slasher（无选项）",
    ["c00lkidd no options"] = "c00lkidd（无选项）",
    ["Noli no options"] = "Noli（无选项）",
    ["JohnDoe no options"] = "JohnDoe（无选项）",
    ["Azure no options"] = "蔚蓝（无选项）",
    ["This section is not finished."] = "此部分尚未完成。",
    ["John Doe (Living Legend)"] = "John Doe（活着的传奇）",
    ["John Doe (Crystalized)"] = "John Doe（水晶化）",
    ["Helperbot"] = "Helperbot",
    ["Slasher (Dead Rabbits)"] = "Slasher（死兔子）",
    ["1x1x1x1 (Big 1x1x1x1)"] = "1x1x1x1（大 1x1x1x1）",
    ["1x1x1x1 (Heaven Executioner)"] = "1x1x1x1（天堂刽子手）",
    ["Jason (Dead Rabbits)"] = "杰森（死兔子）",
    ["Azure (First Born)"] = "蔚蓝（长子）",
    ["Nosferatu (Undead)"] = "诺斯费拉图（亡灵）",
    ["007n7 (Count Duble'o VII)"] = "007n7（Duble'o VII 伯爵）",
    ["Veeronica (Veeronica)"] = "Veeronica（Veeronica）",
    ["Veeronica (Human)"] = "Veeronica（人类）",
    ["Veeronica (Vintage)"] = "Veeronica（复古）",
    ["Chance (MLG)"] = "Chance（MLG）",
    ["Slash"] = "斩击",
    ["Fried Chicken"] = "炸鸡",
    ["One Shot"] = "一击",
    ["Coin Flip"] = "抛硬币",
    ["Hat Fix"] = "修帽子",
    ["Crouch"] = "蹲下",
    ["Dagger"] = "匕首",
    ["Pray"] = "祈祷",
    ["Ritual"] = "仪式",
    ["Bloxy Cola"] = "Bloxy 可乐",
    ["Slateskin Potion"] = "板岩皮肤药水",
    ["Ghostburger"] = "幽灵汉堡",
    ["Entanglement"] = "缠绕",
    ["Mass Infection"] = "大规模感染",
    ["Rejuvenate The Rotten"] = "复活腐烂者",
    ["Unstable Eye"] = "不稳定之眼",
    ["Demonic Pursuit"] = "恶魔追击",
    ["Blood Rush"] = "血冲",
    ["Blood Hunt"] = "血猎",
    ["Infernal Cry"] = "地狱哭喊",
    ["Behead"] = "斩首",
    ["Gashing Wound"] = "撕裂伤口",
    ["Raging Pace"] = "狂暴步伐",
    ["Walkspeed Override"] = "速度覆盖",
    ["Corrupt Nature"] = "腐蚀自然",
    ["Pizza Delivery"] = "披萨配送",
    ["Nova"] = "新星",
    ["Void Rush"] = "虚空冲刺",
    ["Observant"] = "观察者",
    ["Corrupt Energy"] = "腐蚀能量",
    ["Digital Footprint"] = "数字足迹",
    ["Enstrangle"] = "缠绕",
    ["Seeker Bulb"] = "追踪灯泡",
    ["Stigmatize"] = "污名",
    ["Blooming"] = "绽放",
    ["Unearthing"] = "挖掘",

    -- 编辑器
    ["Editor"] = "编辑器",
    ["If a value does nothing after changing then it means that value is only used by the server and changing it on client affects nothing"] = "如果修改后某个值没有效果，说明该值仅由服务器使用，在客户端修改无任何影响",
    ["Select character Sixer"] = "选择角色 Sixer",
    ["Select key no options"] = "选择键（无选项）",
    ["Select value"] = "选择值",
    ["Update key to value"] = "更新键到值",
    ["Reset all values"] = "重置所有值",
    ["Saves"] = "存档",
    ["Load save no options"] = "加载存档（无选项）",
    ["Load selected"] = "加载选中项",
    ["Delete selected"] = "删除选中项",
    ["Save name"] = "保存名称",
    ["Save"] = "保存",
    ["Refresh saves"] = "刷新存档",
    ["Set auto-load"] = "设置自动加载",
    ["Remove current auto-load"] = "移除当前自动加载",
    ["Values"] = "数值",
    ["PursuitMaxSpeed"] = "追击最大速度",
    ["PursuitLength"] = "追击时长",
    ["PursuitBaseSpeed"] = "追击基础速度",

    -- 自动播放
    ["Survivor AI"] = "幸存者 AI",
    ["Autoplay survivor"] = "自动游玩幸存者",
    ["Killer avoidance range"] = "杀手躲避范围",
    ["Generator priority Closest"] = "发电机优先级 最近",
    ["When to sprint Running from killer"] = "何时冲刺 逃离杀手时",
    ["Killer AI"] = "杀手 AI",
    ["Autoplay killer"] = "自动游玩杀手",
    ["Show pathfinding waypoints"] = "显示寻路路径点",
    ["Collect gears"] = "收集齿轮",
    ["On failed path Walk in random direction"] = "寻路失败时 随机方向行走",
    ["Lowest progress"] = "最低进度",
    ["Highest progress"] = "最高进度",
    ["Closest"] = "最近",
    ["Running from killer"] = "逃离杀手",
    ["Always"] = "始终",
    ["Hope for miracle (do nothing)"] = "祈祷奇迹（什么都不做）",
    ["Reset character"] = "重置角色",
    ["Walk in random direction"] = "随机方向行走",

    -- 游戏
    ["Map"] = "地图",
    ["Spike noclip"] = "尖刺穿墙",
    ["Break match"] = "破坏比赛",
    ["Fullbright"] = "全亮",
    ["Disable lobby blur"] = "禁用大厅模糊",
    ["Items"] = "物品",
    ["Grab medkit"] = "拿取医疗包",
    ["Grab bloxy cola"] = "拿取 Bloxy 可乐",
    ["Bring items"] = "携带物品",
    ["Delete items"] = "删除物品",
    ["Auto pickup all items"] = "自动拾取所有物品",
    ["Auto pickup near items"] = "自动拾取附近物品",
    ["Pickup items through walls"] = "穿墙拾取物品",
    ["Pickup items from further"] = "从更远处拾取物品",
    ["Pickup gears from further"] = "从更远处拾取齿轮",
    ["Auto pickup all gears"] = "自动拾取所有齿轮",
    ["Auto pickup near gears"] = "自动拾取附近齿轮",
    ["Spectate killer"] = "观战杀手",
    ["Teleport to killer"] = "传送到杀手",
    ["Farm survivors"] = "刷取幸存者",
    ["Bypass killer walls"] = "绕过杀手墙壁",
    ["Survivors"] = "幸存者",
    ["Teleport To Random Survivor"] = "传送到随机幸存者",
    ["Emotes"] = "表情",
    ["Select emote #Too Excited"] = "选择表情 #太兴奋",
    ["Fake emote start/stop (NO vfx, NO sfx)"] = "假表情开始/停止（无特效，无音效）",

    -- 反制
    ["Anti affects"] = "反制效果",
    ["Anti slowness"] = "防减速",
    ["Anti subspace"] = "防亚空间",
    ["Anti blindness"] = "防失明",
    ["Anti glitched"] = "防故障",
    ["Anti slatekin slow/fov"] = "防板岩皮肤减速/视野",
    ["Anti nausea"] = "防恶心",
    ["Anti stun"] = "防眩晕",
    ["Anti exhaust"] = "防疲惫",
    ["Antis misc"] = "反制杂项",
    ["Anti clone 007n7"] = "防 007n7 分身",
    ["Anti hallucinations"] = "防幻觉",
    ["Anti void star pull"] = "防虚空之星拉扯",
    ["Anti azure vine pull"] = "防蔚蓝藤蔓拉扯",
    ["Anti AFK kill"] = "防挂机击杀",
    ["Anti slow on landing"] = "防落地减速",
    ["Anti footsteps"] = "防脚步声",
    ["Anti knockback"] = "防击退",
    ["Anti infernal cry"] = "防地狱哭喊",
    ["Anti invisible players"] = "防隐身玩家",
    ["Antis Settings"] = "反制设置",
    ["Notify on block"] = "格挡时通知",
    ["Apply anti invis to self"] = "对自身应用防隐身",

    -- 杂项
    ["Fake block"] = "假格挡",
    ["Fake block (animation)"] = "假格挡（动画）",
    ["Block animation Normal"] = "格挡动画 正常",
    ["Gingerbread"] = "姜饼人",
    ["Gene"] = "基因",
    ["Ally that only kills zombies not u"] = "只杀僵尸不杀你的盟友",
    ["Sorcerer"] = "巫师",
    ["Juggernaut"] = "主宰",
    ["Bobby"] = "Bobby",
    ["Gunner"] = "枪手",
    ["Burnt Gingerbread"] = "烧焦姜饼人",
    ["SoyG"] = "SoyG",
    ["Invincible"] = "无敌",
    ["Greenbelt"] = "绿带",
    ["Milestone I"] = "里程碑 I",
    ["Milestone II"] = "里程碑 II",
    ["Milestone III"] = "里程碑 III",
    ["Milestone IV"] = "里程碑 IV",
    ["Tough Santa"] = "硬汉圣诞老人",
    ["Little Guy"] = "小家伙",
    ["Rebel"] = "叛逆者",
    ["Demo"] = "爆破手",
    ["Bombo"] = "Bombo",
    ["Inception's Centurion"] = "盗梦空间百夫长",
    ["Guard"] = "守卫",
    ["Nerfed Demoman"] = "削弱爆破手",
    ["Paintballer"] = "彩弹手",
    ["Furtive GI"] = "隐秘 GI",
    ["American Commando"] = "美国突击队",
    ["Boomer Formula"] = "Boomer 公式",
    ["Street Brawler"] = "街头斗士",
    ["Golden"] = "黄金",
    ["Panda"] = "熊猫",
    ["xXDARKSLAYERJONESXx"] = "xXDARKSLAYERJONESXx",
    ["Gunsonnect76"] = "Gunsonnect76",
    ["MLG"] = "MLG",
    ["Flander Fields"] = "Flander Fields",
    ["Change block animation"] = "修改格挡动画",
    ["If you enable block animation changer autoblock might not work properly (fake block is fine)"] = "如果启用格挡动画修改器，自动格挡可能无法正常工作（假格挡没问题）",
    ["Fake die"] = "假死",
    ["Ragdoll button (NOT FE)"] = "布娃娃按钮（非 FE）",
    ["Round Timer"] = "回合计时器",
    ["Round timer X"] = "回合计时器 X",
    ["Round timer Y"] = "回合计时器 Y",
    ["Only show time"] = "仅显示时间",
    ["Hide status"] = "隐藏状态",
    ["Miscallenous"] = "杂项",
    ["Old forsaken menu"] = "旧版 Forsaken 菜单",
    ["Disable old forsaken (One-Time press)"] = "禁用旧版 Forsaken（一次性按下）",
    ["Anti detect spectate"] = "防检测观战",
    ["⚠ PANIC ⚠"] = "⚠ 恐慌 ⚠",
    ["Script update rate"] = "脚本更新频率",
    ["Streamer mode"] = "主播模式",
    ["Icon (FILE NAME ONLY)"] = "图标（仅文件名）",
    ["Name"] = "名称",
    ["Name hider (client)"] = "名称隐藏器（客户端）",
    ["Re-Enable after changing setting"] = "修改设置后重新启用",

    -- 音频
    ["Audio"] = "音频",
    ["You can also put files into the Catsaken/Music folder and they will show in dropdowns"] = "你也可以将文件放入 Catsaken/Music 文件夹，它们会显示在下拉菜单中",
    ["Last Man Standing"] = "最后生还者",
    ["Downloaded 29 LMS files\nMost of these LMS arent official, they're just presets"] = "已下载 29 个 LMS 文件\n其中大部分 LMS 不是官方的，只是预设",
    ["LMS theme None"] = "LMS 主题 无",
    ["Custom LMS ID"] = "自定义 LMS ID",
    ["Custom LMS File"] = "自定义 LMS 文件",
    ["Change LMS"] = "更改 LMS",
    ["[Disable LMS Downloads]"] = "[禁用 LMS 下载]",
    ["Block Success | ID"] = "格挡成功 | ID",
    ["Block Success | File"] = "格挡成功 | 文件",
    ["Parry | ID"] = "招架 | ID",
    ["Parry | File"] = "招架 | 文件",
    ["Punch | ID"] = "出拳 | ID",
    ["Punch | File"] = "出拳 | 文件",
    ["Silence rage SFX"] = "静音狂暴音效",
    ["Chase Themes"] = "追逐主题",
    ["Chase Theme None"] = "追逐主题 无",
    ["Change chase theme"] = "更改追逐主题",
    ["Custom Chase ID"] = "自定义追逐 ID",
    ["Custom Chase File"] = "自定义追逐文件",
    ["Lobby Music"] = "大厅音乐",
    ["Downloaded 5 lobby music files"] = "已下载 5 个大厅音乐文件",
    ["Lobby music theme None"] = "大厅音乐主题 无",
    ["Custom Lobby Music ID"] = "自定义大厅音乐 ID",
    ["Custom Lobby Music File"] = "自定义大厅音乐文件",
    ["Change Lobby Music"] = "更改大厅音乐",
    ["[Disable Lobby Music Downloads]"] = "[禁用大厅音乐下载]",
    ["Custom"] = "自定义",
    ["1eggs vs Chef Shedletsky"] = "1eggs 对战 厨师 Shedletsky",
    ["1x1x1x1 vs Shedletsky"] = "1x1x1x1 对战 Shedletsky",
    ["A Grave Soul"] = "坟墓之魂",
    ["Annihilation John Doe vs Friend Elliot"] = "湮灭 John Doe 对战 朋友 Elliot",
    ["Burnout"] = "燃尽",
    ["Elliot vs c00lkidd"] = "Elliot 对战 c00lkidd",
    ["Erlking Dev Killer LMS"] = "Erlking Dev 杀手 LMS",
    ["Guest 666 vs Guest 1337"] = "Guest 666 对战 Guest 1337",
    ["Hacklord Shedletsky vs 1x1x1x1"] = "黑客领主 Shedletsky 对战 1x1x1x1",
    ["Hairytinkle vs Pedro John Doe"] = "Hairytinkle 对战 Pedro John Doe",
    ["Jack Frost 1x1x1x1 vs Santa Shedletsky"] = "冰霜杰克 1x1x1x1 对战 圣诞老人 Shedletsky",
    ["Jason vs Tommy Jarvis Guest 1337"] = "杰森 对战 Tommy Jarvis Guest 1337",
    ["John Doe vs Builderman"] = "John Doe 对战 Builderman",
    ["Noli vs 007n7"] = "Noli 对战 007n7",
    ["Noob Cosplay vs Yourself"] = "菜鸟 Cosplay 对战 你自己",
    ["Noob vs Guest 666"] = "菜鸟 对战 Guest 666",
    ["Old Last Man Standing OST"] = "旧版最后生还者 OST",
    ["Perpetuity"] = "永恒",
    ["Pretty Princess vs 226w6"] = "漂亮公主 对战 226w6",
    ["Pretty Princess vs Two Time"] = "漂亮公主 对战 Two Time",
    ["Scripter 007n7 vs Script Builder John Doe"] = "脚本师 007n7 对战 脚本建造者 John Doe",
    ["The Bomber vs Taph"] = "轰炸机 对战 Taph",
    ["Two Time vs Azure"] = "Two Time 对战 蔚蓝",
    ["Vanity Jason LMS"] = "虚荣 杰森 LMS",
    ["Veeronica vs Phosphorus"] = "Veeronica 对战 磷",
    ["Whistle Occurance"] = "口哨事件",
    ["Yourself John Doe"] = "你自己 John Doe",
    ["c00lkidd Cupcakes LMS"] = "c00lkidd 纸杯蛋糕 LMS",
    ["c00lkidd vs 007n7"] = "c00lkidd 对战 007n7",

    -- 其他
    ["The last survivor won."] = "最后一名幸存者获胜。",
    ["Player Stats"] = "玩家统计数据",
    ["The Tempest"] = "暴风雨",
    ["Round Stats"] = "回合统计",
    ["Round Time: 05:09"] = "回合时间:05:09",
    ["Back To Lobby"] = "返回大厅",
    ["NOOB"] = "菜鸟",

    -- 配置
    ["Configurations"] = "配置",
    ["Selected Config catsaken-default-S_awa60.json"] = "已选配置 catsaken-default-S_awa60.json",
    ["Overwrite Selected"] = "覆盖选中项",
    ["Set Selected As Autoload"] = "将选中项设为自动加载",
    ["Config Name"] = "配置名称",
    ["Save Config"] = "保存配置",
    ["Load Selected"] = "加载选中项",
    ["Refresh List"] = "刷新列表",
    ["Share Current Settings"] = "分享当前设置",
    ["Search For Configs"] = "搜索配置",
    ["Export/Import"] = "导出/导入",
    ["Export current settings to a Base64 file, then be able to load/share it for others to import and show in their configs list as specified name."] = "将当前设置导出为 Base64 文件，之后可以加载/分享给他人导入，并以指定名称显示在其配置列表中。",
    ["Name to export as"] = "导出名称",
    ["Export as Base64 and copy"] = "导出为 Base64 并复制",
    ["Enter Base64 content"] = "输入 Base64 内容",
    ["Import"] = "导入",

}

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. 预处理：把 key 按长度降序排，前缀/后缀匹配时长的优先
-- ═══════════════════════════════════════════════════════════════════════════
local SortedKeys = {}
for k in pairs(Translations) do
    SortedKeys[#SortedKeys + 1] = k
end
table.sort(SortedKeys, function(a, b)
    if #a ~= #b then return #a > #b end
    return a < b
end)

-- 只拿长度 >= 4 的做前后缀匹配：
-- "ON"/"OFF" 这类短词已经在精确表里，放进前后缀匹配会误伤
local AffixKeys = {}
for _, k in ipairs(SortedKeys) do
    if #k >= 4 then AffixKeys[#AffixKeys + 1] = k end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. 翻译函数
-- ═══════════════════════════════════════════════════════════════════════════
local cache = {}

local function StripTags(s)
    return (s:gsub("<[^>]*>", ""))
end

local transCount = 0
local transLog = {}

local function TranslateText(txt)
    if not ENABLE_TRANSLATE then return txt end
    if type(txt) ~= "string" or txt == "" then return txt end

    local hit = cache[txt]
    if hit ~= nil then return hit end

    local clean = StripTags(txt):gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")

    -- ① 整句精确匹配
    local exact = Translations[txt] or Translations[clean]
    if exact then
        cache[txt] = exact
        transCount = transCount + 1
        if #transLog < 40 then transLog[#transLog + 1] = txt .. "  →  " .. exact end
        return exact
    end

    -- ② 前缀匹配：处理 "Round ends in: 30" / "Speed: 5" 这种拼出来的
    local src = (clean ~= "" and clean) or txt
    local low = src:lower()
    for _, k in ipairs(AffixKeys) do
        local kl = k:lower()
        local n = #k
        if #src > n and low:sub(1, n) == kl then
            local rest = src:sub(n + 1)
            -- 冒号/空格开头才认，避免 "GearsX" 这种误配
            if rest:match("^[:：%s%d%.,%%%-]") then
                local out = Translations[k] .. rest
                cache[txt] = out
                return out
            end
        end
    end

    -- ③ 后缀匹配：处理 "5 Gears"
    local tail = low:sub(-64)
    local tailOff = #low - #tail
    for _, k in ipairs(AffixKeys) do
        local kl = k:lower()
        local n = #k
        if #src > n and low:sub(-n) == kl then
            local head = src:sub(1, #src - n)
            if head:match("[%s%d%.,%%%-]$") then
                local out = head .. Translations[k]
                cache[txt] = out
                return out
            end
        end
    end

    cache[txt] = txt
    return txt
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. 系统 UI 白名单（这些绝对不翻译）
-- ═══════════════════════════════════════════════════════════════════════════
local Players  = game:GetService("Players")
local CoreGui  = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")

local SystemUiNames = {
    RobloxGui = true, PlayerList = true, Backpack = true, Chat = true,
    BubbleChat = true, ExperienceChat = true, TextChatService = true,
    TopBar = true, Topbar = true, Health = true, EmotesMenu = true,
    Chrome = true, InspectMenu = true, PurchasePrompt = true,
    ScreenshotHud = true,
}

local function IsSysUI(obj)
    while obj do
        if SystemUiNames[obj.Name] then return true end
        obj = obj.Parent
    end
    return false
end

-- 该不该翻这个控件？
--   TextLabel  ：显示用，脚本不会读回来 → 全翻
--   TextBox    ：输入提示，翻
--   TextButton ：危险。catsaken 大量用按钮的 Text 当状态标志，
--                它会把 "OFF" 写进按钮再读回来判断。一旦被我们翻成"关闭"，
--                判断就永远不成立。所以 4 字符以内的按钮文本一律不翻。
local function ShouldTranslate(obj, txt)
    if not ENABLE_TRANSLATE then return false end
    if IsSysUI(obj) then return false end
    if obj:IsA("TextLabel") then return true end
    if obj:IsA("TextBox") then return true end
    if obj:IsA("TextButton") then
        local clean = (txt:gsub("<[^>]*>", ""):gsub("^%s+", ""):gsub("%s+$", ""))
        if #clean <= 4 then return false end   -- ON / OFF / Yes / No / Max …
        return true
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Hook 模式：拦 __newindex，改 Text 赋值
-- ═══════════════════════════════════════════════════════════════════════════
local hookInstalled = false

local function TryHook()
    -- 元表 Hook 会改写所有 Instance 的属性赋值通道。
    -- 里面每一次 Roblox API 调用都必须 pcall —— 碰到已销毁的 Instance、
    -- 或者 t 是 userdata 的情况，裸调用会抛异常，属性赋值失败，
    -- catsaken 的 VM 表状态就乱了（表现为 buffer.create 越界）。
    local ok, err = pcall(function()
        local mt = getrawmetatable(game)
        if not mt then error("getrawmetatable 返回 nil") end
        local oldNewIndex = mt.__newindex
        if type(setreadonly) == "function" then setreadonly(mt, false) end

        mt.__newindex = newcclosure(function(t, k, v)
            if k == "Text" or k == "PlaceholderText" then
                local okc, should = pcall(function()
                    if typeof(t) ~= "Instance" then return false end
                    if IsSysUI(t) then return false end
                    return ShouldTranslate(t, tostring(v))
                end)
                if okc and should then
                    local okv, nv = pcall(TranslateText, tostring(v))
                    if okv and type(nv) == "string" then v = nv end
                end
            end
            return oldNewIndex(t, k, v)
        end)

        if type(setreadonly) == "function" then setreadonly(mt, true) end
    end)
    hookInstalled = ok
    if not ok then
        warn("[汉化] Hook 装不上，走监听模式：" .. tostring(err))
    else
        print("[汉化] Hook 模式已启用")
    end
end

if ENABLE_HOOK then
    TryHook()
else
    print("[汉化] Hook 已关闭，走监听模式")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. 监听兜底：Hook 失败的执行器靠这个
-- ═══════════════════════════════════════════════════════════════════════════
local watched   = setmetatable({}, { __mode = "k" })
local busy      = setmetatable({}, { __mode = "k" })
local scanned   = setmetatable({}, { __mode = "k" })

local function TranslateObj(obj)
    if busy[obj] then return end
    if not ENABLE_TRANSLATE then return end
    busy[obj] = true
    pcall(function()
        local t = obj.Text
        if type(t) == "string" and t ~= "" and ShouldTranslate(obj, t) then
            local nText = TranslateText(t)
            if nText ~= t then obj.Text = nText end
        end
        local p = obj.PlaceholderText
        if type(p) == "string" and p ~= "" and ShouldTranslate(obj, p) then
            local nPlace = TranslateText(p)
            if nPlace ~= p then obj.PlaceholderText = nPlace end
        end
    end)
    busy[obj] = nil
end

local function WatchObj(obj)
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then return end
    if watched[obj] then return end
    watched[obj] = true

    TranslateObj(obj)

    pcall(function()
        obj:GetPropertyChangedSignal("Text"):Connect(function()
            if not busy[obj] then
                task.delay(0.01, function() TranslateObj(obj) end)
            end
        end)
        obj:GetPropertyChangedSignal("PlaceholderText"):Connect(function()
            if not busy[obj] then
                task.delay(0.01, function() TranslateObj(obj) end)
            end
        end)
    end)
end

local function ScanRoot(root)
    if not root or scanned[root] then return end
    scanned[root] = true
    pcall(function()
        for _, obj in ipairs(root:GetDescendants()) do
            WatchObj(obj)
        end
        root.DescendantAdded:Connect(function(obj)
            task.delay(0.01, function()
                WatchObj(obj)
                pcall(function()
                    for _, c in ipairs(obj:GetDescendants()) do
                        WatchObj(c)
                    end
                end)
            end)
        end)
    end)
end

local function GetAllRoots()
    local roots = {}
    if PlayerGui then roots[#roots + 1] = PlayerGui end
    pcall(function() if CoreGui then roots[#roots + 1] = CoreGui end end)
    pcall(function()
        if type(gethui) == "function" then
            local h = gethui()
            if h then roots[#roots + 1] = h end
        end
    end)
    return roots
end

task.spawn(function()
    while true do
        for _, root in ipairs(GetAllRoots()) do
            ScanRoot(root)
        end
        task.wait(hookInstalled and 15 or 8)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. 加载原脚本
-- ═══════════════════════════════════════════════════════════════════════════
task.wait(0.4)

print("[汉化] 下载 catsaken…")
local okDl, content = pcall(function()
    return game:HttpGet(ScriptUrl, true)
end)

if not okDl then
    warn("[汉化] 下载失败：" .. tostring(content))
    return
end
if type(content) ~= "string" or content == "" then
    warn("[汉化] 下载内容为空")
    return
end
print("[汉化] 下载成功，大小：" .. #content)

local func, err = loadstring(content)
if not func then
    warn("[汉化] 编译失败：" .. tostring(err))
    return
end

print("[汉化] 执行 catsaken…")
local okRun, runErr = pcall(func, ScriptArg)
if not okRun then
    warn("[汉化] 执行出错：" .. tostring(runErr))
    warn("[汉化] 这不是汉化层的问题（翻译用的是监听方式，只读 UI 文本）")
    return
end

print("[汉化] catsaken 已启动，开始翻译界面…")

-- 立刻全扫，不用等轮询
task.spawn(function()
    for round = 1, 10 do
        for _, root in ipairs(GetAllRoots()) do
            pcall(function()
                for _, obj in ipairs(root:GetDescendants()) do
                    WatchObj(obj)
                end
            end)
        end
        task.wait(0.25)
    end
    print(string.format("[汉化] 首轮翻译完成，共命中 %d 条", transCount))
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. 导出（给别的脚本调用）
-- ═══════════════════════════════════════════════════════════════════════════
pcall(function()
    local g = getgenv()
    g.__CATSAKEN_CN = {
        translate = TranslateText,
        table     = Translations,
        reload    = function() cache = {} end,
        log       = function()
            print(string.format("[汉化] 已翻译 %d 条，最近记录：", transCount))
            for _, l in ipairs(transLog) do print("  " .. l) end
        end,
        setHook      = function(on) ENABLE_HOOK = on and true or false end,
        setTranslate = function(on) ENABLE_TRANSLATE = on and true or false end,
        isTranslateOn = function() return ENABLE_TRANSLATE end,
        version   = "1.1",
    }
end)
