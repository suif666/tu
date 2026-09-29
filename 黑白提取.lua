--[[
    黑白脚本 · 功能提取（独立版）
    从「黑白全源」里把功能抠出来重写，不依赖 suif.lua，不依赖黑白那套框架。

    第一批（小件）：
      动作/动画类  自定义动画 / 全局动画速度 / 停止所有动画
      玩家类       伪装玩家
      远程类       解锁所有商城动画 / 缓慢的快速跑

    UI：WindUI-Boreal（suif666/suif）
    说明：所有 :Notify 都走 WindUI，不用黑白自己的通知封装。
]]

local WINDUI_URL = "https://raw.githubusercontent.com/suif666/suif/refs/heads/main/WindUI-Boreal.lua"

--==============================================================
-- 基础
--==============================================================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local WindUI = loadstring(game:HttpGet(WINDUI_URL))()
if type(WindUI) ~= "table" then
	error("WindUI 加载失败")
end

local function notify(title, content, icon)
	WindUI:Notify({
		Title = tostring(title),
		Content = tostring(content or ""),
		Icon = icon or "check",
		Duration = 2,
	})
end

-- 取角色模型（不阻塞）
local function getChar(plr)
	plr = plr or LP
	return plr.Character
end

-- 取 Humanoid / AnimationController
local function getHum(plr)
	local ch = getChar(plr)
	if not ch then
		return nil
	end
	return ch:FindFirstChildOfClass("Humanoid") or ch:FindFirstChildOfClass("AnimationController")
end

local function isR15(plr)
	local ch = getChar(plr)
	return ch ~= nil and ch:FindFirstChild("UpperTorso") ~= nil
end

-- 读输入框的值。
-- 黑白那套 WindUI 用 el:Get()，Boreal 用 el.Value（它的存档模块就是读 .Value），
-- 两边都试一遍，避免猜错 API。
local function readInput(el)
	if not el then
		return ""
	end
	local ok, v = pcall(function()
		return el:Get()
	end)
	if ok and v ~= nil then
		return tostring(v)
	end
	return tostring(el.Value or "")
end

--==============================================================
-- 统一关闭回调注册
-- Boreal 的窗口对象上确实有 OnClose（源码里是 av.OnClose(C,F)，存到 OnCloseCallback
-- 字段，且它能访问 av.Topbar，说明挂在窗口对象上），但那是我从 379KB 源码里读出来的，
-- 不敢保证每个版本都一样。所以这里自己做一份回调表：注册照收，再 pcall 尝试挂到
-- 窗口的 OnClose 上；挂不上也不影响功能，只是窗口关闭时不会自动清理。
--==============================================================
local closeCallbacks = {}

local function onClose(fn)
	if type(fn) == "function" then
		table.insert(closeCallbacks, fn)
	end
end

local function runCloseCallbacks()
	local list = closeCallbacks
	closeCallbacks = {}
	for _, fn in ipairs(list) do
		pcall(fn)
	end
end

--==============================================================
-- 动画：播放 / 停止 / 全局速度
--==============================================================
local playingTracks = {}

local function stopAllAnim()
	for _, track in ipairs(playingTracks) do
		pcall(function()
			track:Stop()
		end)
	end
	playingTracks = {}
end

-- 对应黑白的 fn80
local function playAnim(plr, id, speed, looped, weight)
	local hum = getHum(plr)
	if not hum then
		return nil
	end
	stopAllAnim()
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(id)
	local track
	local ok = pcall(function()
		track = hum:LoadAnimation(anim)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = looped or false
	track:Play(weight or 0, 1, 0)
	track:AdjustSpeed(speed or 1)
	table.insert(playingTracks, track)
	return track
end

-- 对应黑白的 fn77 分支：调整所有正在播放的动画速度
local function setGlobalAnimSpeed(speed)
	local hum = getHum(LP)
	if not hum then
		return 0
	end
	local n = 0
	for _, track in pairs(hum:GetPlayingAnimationTracks()) do
		local ok = pcall(function()
			track:AdjustSpeed(speed)
		end)
		if ok then
			n = n + 1
		end
	end
	-- 本脚本自己播的那几条也一起调
	for _, track in ipairs(playingTracks) do
		pcall(function()
			track:AdjustSpeed(speed)
		end)
	end
	return n
end

--==============================================================
--==============================================================
--==============================================================
-- 窗口
--==============================================================
local win = WindUI:CreateWindow({
	Title = "黑白提取",
	Icon = "package",
	IconThemed = true,
	Author = "独立版",
	Folder = "HBExtract",
	Size = UDim2.fromOffset(520, 380),
	Transparent = true,
	Theme = "Dark",
	HideSearchBar = false,
	ScrollBarEnabled = true,
	Resizable = true,
})

-- 把上面积累的关闭回调挂到窗口上（挂不上也不影响，见 onClose 那段注释）
pcall(function()
	win:OnClose(runCloseCallbacks)
end)

--==============================================================
-- ctx：给下面各个功能模块用的运行环境
-- 每个模块都是 `return function(win, ctx) ... end` 的形式，只能通过这张表拿东西，
-- 不允许直接引用主脚本的局部变量，这样模块之间互不干扰、也能单独拿出去用。
--==============================================================
local ctx = {
	notify = notify,       -- function(标题, 内容[, 图标])
	getChar = getChar,     -- function(player) -> Character 或 nil
	getHum = getHum,       -- function(player) -> Humanoid 或 nil
	isR15 = isR15,         -- function(player) -> boolean
	readInput = readInput, -- function(输入框元素) -> string
	onClose = onClose,     -- function(fn) 注册窗口关闭时的清理回调
}

--==============================================================
-- 版本号（排查用：控制台会打出来，确认跑的是哪一版）
--==============================================================
local HB_VERSION = "远程脚本版 v2 · 扁平页签 + 瞬时加载"
print("[黑白提取] 启动 " .. HB_VERSION)

--==============================================================
-- 兼容层：getgenv 不一定存在
--==============================================================
local GENV = (type(getgenv) == "function") and getgenv() or _G

--==============================================================
-- 重跑清场
--
-- 远程脚本用 __HB_XXX_LOADED 防重复加载。不清掉的话，第二次执行主脚本
-- （不重进游戏）时远程脚本会直接 return，页签就是空的。
-- 只删 HB_ 开头的键，不动 Tabs 里其它脚本的页签。
--==============================================================
local HB_KEYS = {
	{ "Anim", "HB_AnimTab" }, { "Action", "HB_AnimTab" }, { "AnimPack", "HB_AnimTab" },
	{ "Disguise", "HB_DisguiseTab" }, { "SlowRun", "HB_SlowRunTab" },
	{ "Clicker", "HB_ClickerTab" }, { "NPC", "HB_NPCTab" },
	{ "Trigger", "HB_TriggerTab" }, { "Object", "HB_ObjectTab" },
}

for _, kv in ipairs(HB_KEYS) do
	GENV["__HB_" .. string.upper(kv[1]) .. "_LOADED"] = nil
end
if GENV.Tabs then
	for _, kv in ipairs(HB_KEYS) do
		GENV.Tabs[kv[2]] = nil
	end
end
do
	local oldWin = GENV.HB_win
	if oldWin then
		pcall(function()
			oldWin:Destroy()
		end)
		pcall(function()
			oldWin:Close()
		end)
	end
	GENV.HB_win = nil
end

--==============================================================
-- 建页签
--
-- ★ 之前用 win:Section({...}):Tab({...}) 做分类，在你的 Boreal 上会报错
--   （Boreal 里只有 av.Tab 是真正的页签工厂，av.Section 返回的对象没有 :Tab），
--   脚本在建页签这一步就中断了 —— 表现就是「什么都没有」。
--
--   现在改用已经验证可用的 win:Tab()，分类信息放进页签标题（侧栏一样看得清）。
--   如果你的 Boreal 版本确实支持 Section 分组，把 USE_SECTIONS 改成 true；
--   无论哪条路失败都会自动退回扁平页签，不会再让脚本中断。
--==============================================================
local USE_SECTIONS = false

local tabErrors = {}

local function makeSection(title, icon)
	if not USE_SECTIONS then
		return nil
	end
	local ok, sec = pcall(function()
		return win:Section({ Title = title, Icon = icon, Opened = true })
	end)
	return ok and sec or nil
end

local function makeTab(section, title, icon)
	if section then
		local ok, t = pcall(function()
			return section:Tab({ Title = title, Icon = icon, Locked = false })
		end)
		if ok and t then
			return t
		end
		table.insert(tabErrors, title .. "（分组页签失败，已退回扁平）")
	end
	local ok2, t2 = pcall(function()
		return win:Tab({ Title = title, Icon = icon, Locked = false })
	end)
	if ok2 and t2 then
		return t2
	end
	table.insert(tabErrors, title)
	warn("[黑白提取] 页签创建失败: " .. tostring(title))
	return nil
end

-- ── 视觉类 ──
local secShijue  = makeSection("视觉类", "palette")
local animTab     = makeTab(secShijue, "视觉类 · 动作/动画", "music")
local disguiseTab = makeTab(secShijue, "视觉类 · 伪装玩家", "user")

-- ── 玩家类 ──
local secWanjia = makeSection("玩家类", "user")
local runTab    = makeTab(secWanjia, "玩家类 · 缓慢的快速跑", "zap")

-- ── 工具类 ──
local secGongju  = makeSection("工具类", "wrench")
local clickerTab = makeTab(secGongju, "工具类 · 自动连点器", "mouse")

-- ── 功能类 ──
local secGongneng = makeSection("功能类", "folder")
local npcTab     = makeTab(secGongneng, "功能类 · NPC交互", "server")
local triggerTab = makeTab(secGongneng, "功能类 · 触发类", "zap")
local objectTab  = makeTab(secGongneng, "功能类 · 控制物体", "box")

print(string.format(
	"[黑白提取] 页签: 动作/动画=%s 伪装玩家=%s 缓慢跑=%s 连点器=%s NPC=%s 触发=%s 控制物体=%s",
	tostring(animTab ~= nil), tostring(disguiseTab ~= nil), tostring(runTab ~= nil),
	tostring(clickerTab ~= nil), tostring(npcTab ~= nil), tostring(triggerTab ~= nil),
	tostring(objectTab ~= nil)))

if #tabErrors > 0 then
	warn("[黑白提取] 有页签创建失败: " .. table.concat(tabErrors, ", "))
end

--==============================================================
-- 导出给远程脚本用的共享环境
-- 远程脚本是 loadstring 单独跑的独立 chunk，看不到主脚本的局部变量，
-- 所以统一挂到 getgenv()（没有则退到 _G）上，远程脚本按需取用。
--==============================================================
GENV.HB_WindUI    = WindUI
GENV.HB_notify    = notify
GENV.HB_readInput = readInput
GENV.HB_onClose   = onClose
GENV.HB_getChar   = getChar
GENV.HB_getHum    = getHum
GENV.HB_isR15     = isR15
GENV.HB_win       = win
GENV.HB_version   = HB_VERSION

GENV.Tabs = GENV.Tabs or {}
GENV.Tabs.HB_AnimTab     = animTab
GENV.Tabs.HB_DisguiseTab = disguiseTab
GENV.Tabs.HB_SlowRunTab  = runTab
GENV.Tabs.HB_ClickerTab  = clickerTab
GENV.Tabs.HB_NPCTab      = npcTab
GENV.Tabs.HB_TriggerTab  = triggerTab
GENV.Tabs.HB_ObjectTab   = objectTab

GENV.SutureHB_AnimTab     = animTab
GENV.SutureHB_DisguiseTab = disguiseTab
GENV.SutureHB_SlowRunTab  = runTab
GENV.SutureHB_ClickerTab  = clickerTab
GENV.SutureHB_NPCTab      = npcTab
GENV.SutureHB_TriggerTab  = triggerTab
GENV.SutureHB_ObjectTab   = objectTab

--==============================================================
-- 加载 9 个远程脚本
--
-- ★ 按你的要求改成「瞬时加载」：窗口建好就立刻依次拉取执行，
--   不做「点开页签才加载」。之前那版靠挂页签点击事件触发，
--   一旦挂不上就完全没有反应（表现就是什么都没有）。
--==============================================================
local HB_REMOTE_BASE = "https://raw.githubusercontent.com/suif666/tu/main/hb/"

-- 拉取并执行一个远程脚本。失败重试 3 次，返回 ok, err
local function loadRemote(url, desc)
	local lastErr
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			local src = game:HttpGet(url)
			local fn, compileErr = loadstring(src)
			if not fn then
				error(compileErr)
			end
			fn()
		end)
		if ok then
			return true
		end
		lastErr = err
		print(string.format("[黑白提取] %s 第 %d 次失败: %s", tostring(desc), attempt, tostring(err)))
		task.wait(0.5 * attempt)
	end
	return false, lastErr
end

local HB_MODULES = {
	{ "animation.lua", "动作动画" },
	{ "actionpack.lua", "动作包" },
	{ "animpack.lua", "动画包" },
	{ "disguise.lua", "伪装玩家" },
	{ "slowrun.lua", "缓慢的快速跑" },
	{ "clicker.lua", "自动连点器" },
	{ "npc.lua", "NPC交互" },
	{ "trigger.lua", "触发类" },
	{ "object.lua", "控制物体" },
}

task.spawn(function()
	task.wait(0.2)
	local okCount, failList = 0, {}
	for i, m in ipairs(HB_MODULES) do
		print(string.format("[黑白提取] (%d/%d) 加载 %s ...", i, #HB_MODULES, m[2]))
		local ok, err = loadRemote(HB_REMOTE_BASE .. m[1], m[2])
		if ok then
			okCount = okCount + 1
		else
			table.insert(failList, m[2] .. " -> " .. tostring(err))
		end
		task.wait(0.15)
	end
	print(string.format("[黑白提取] 加载结束: 成功 %d / 共 %d", okCount, #HB_MODULES))
	if #failList == 0 then
		pcall(notify, "黑白提取", string.format("功能加载完成 (%d/%d)", okCount, #HB_MODULES), "check")
	else
		pcall(notify, "黑白提取", string.format("有 %d 个功能加载失败，详见控制台", #failList), "x")
		for _, f in ipairs(failList) do
			warn("[黑白提取] " .. f)
		end
	end
end)

pcall(notify, "黑白提取", "主脚本已启动（" .. tostring(HB_VERSION) .. "），正在加载功能...", "info")
