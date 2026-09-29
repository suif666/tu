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
-- 分类与页签
-- Boreal 没有 TabGroup/Category，分类靠 win:Section() 建侧栏分组，
-- 分组对象上的 :Tab() 才是真正的页签（这就是 suif.lua 用的做法）。
--
--   视觉类 -> 动作/动画、伪装玩家
--   玩家类 -> 缓慢的快速跑
--   工具类 -> 自动连点器
--   功能类 -> NPC交互、触发类、控制物体
--==============================================================

-- ── 视觉类 ──
local secShijue = win:Section({ Title = "视觉类", Icon = "palette", Opened = true })
local animTab     = secShijue:Tab({ Title = "动作/动画", Icon = "music", Locked = false })
local disguiseTab = secShijue:Tab({ Title = "伪装玩家", Icon = "user",  Locked = false })

-- ── 玩家类 ──
local secWanjia = win:Section({ Title = "玩家类", Icon = "user", Opened = true })
local runTab    = secWanjia:Tab({ Title = "缓慢的快速跑", Icon = "zap", Locked = false })

-- ── 工具类 ──
local secGongju = win:Section({ Title = "工具类", Icon = "wrench", Opened = true })
local clickerTab = secGongju:Tab({ Title = "自动连点器", Icon = "mouse", Locked = false })

-- ── 功能类 ──
local secGongneng = win:Section({ Title = "功能类", Icon = "folder", Opened = true })
local npcTab     = secGongneng:Tab({ Title = "NPC交互",  Icon = "server", Locked = false })
local triggerTab = secGongneng:Tab({ Title = "触发类",   Icon = "zap",    Locked = false })
local objectTab  = secGongneng:Tab({ Title = "控制物体", Icon = "box",    Locked = false })

-- 各页签的归属：
--   动作/动画    <- 动作动画(v1内联) + 动作包 + 动画包 + 解锁所有商城动画
--   伪装玩家     <- 伪装玩家(含服务器人员下拉框)
--   缓慢的快速跑 <- 远程加载 wearedevs 混淆脚本
--   自动连点器 / NPC交互 / 触发类 / 控制物体 <- 各自独立模块

--==============================================================
-- 导出给远程脚本用的共享环境
-- 远程脚本是用 loadstring 单独跑的独立 chunk，看不到主脚本的局部变量，
-- 所以这里统一挂到 getgenv() 上，远程脚本按需取用。
-- 这也是 suif.lua 那套远程脚本的做法（getgenv().Tabs.XxxTab）。
--==============================================================
--==============================================================
-- 重跑清场（重要）
--
-- 远程脚本用 getgenv().__HB_XXX_LOADED 防重复加载。如果不在这里清掉，
-- 第二次执行主脚本（不重进游戏）时，远程脚本一进去就看到标志位是 true，
-- 直接 return —— 页签建出来了但里面是空的。
--
-- 另外把上一次留下的窗口和旧页签引用一起清掉，避免多窗口叠加、
-- 以及远程脚本拿到已经被销毁的旧页签对象。
-- 注意：只删 HB_ 开头的键，不动 getgenv().Tabs 里别的脚本的页签。
--==============================================================
local HB_KEYS = {
	{ "Anim",     "HB_AnimTab" },
	{ "Action",   "HB_AnimTab" },
	{ "AnimPack", "HB_AnimTab" },
	{ "Disguise", "HB_DisguiseTab" },
	{ "SlowRun",  "HB_SlowRunTab" },
	{ "Clicker",  "HB_ClickerTab" },
	{ "NPC",      "HB_NPCTab" },
	{ "Trigger",  "HB_TriggerTab" },
	{ "Object",   "HB_ObjectTab" },
}

for _, kv in ipairs(HB_KEYS) do
	getgenv()["__HB_" .. string.upper(kv[1]) .. "_LOADED"] = nil
end

if getgenv().Tabs then
	for _, kv in ipairs(HB_KEYS) do
		getgenv().Tabs[kv[2]] = nil
	end
end

do
	local oldWin = getgenv().HB_win
	if oldWin then
		pcall(function()
			oldWin:Destroy()
		end)
		pcall(function()
			oldWin:Close()
		end)
	end
	getgenv().HB_win = nil
end

getgenv().HB_WindUI   = WindUI
getgenv().HB_notify   = notify
getgenv().HB_readInput = readInput
getgenv().HB_onClose  = onClose
getgenv().HB_getChar  = getChar
getgenv().HB_getHum   = getHum
getgenv().HB_isR15    = isR15
getgenv().HB_win      = win

-- 页签挂到 getgenv().Tabs 上（远程脚本靠这个拿页签）
getgenv().Tabs = getgenv().Tabs or {}
getgenv().Tabs.HB_AnimTab     = animTab
getgenv().Tabs.HB_DisguiseTab = disguiseTab
getgenv().Tabs.HB_SlowRunTab  = runTab
getgenv().Tabs.HB_ClickerTab  = clickerTab
getgenv().Tabs.HB_NPCTab      = npcTab
getgenv().Tabs.HB_TriggerTab  = triggerTab
getgenv().Tabs.HB_ObjectTab   = objectTab

-- 同时给一份 Suture* 别名，方便沿用你原来的命名习惯
getgenv().SutureHB_AnimTab     = animTab
getgenv().SutureHB_DisguiseTab = disguiseTab
getgenv().SutureHB_SlowRunTab  = runTab
getgenv().SutureHB_ClickerTab  = clickerTab
getgenv().SutureHB_NPCTab      = npcTab
getgenv().SutureHB_TriggerTab  = triggerTab
getgenv().SutureHB_ObjectTab   = objectTab

--==============================================================
-- 远程脚本登记
-- 主脚本只负责建页签；每个功能都是一个独立远程脚本，
-- 点开对应页签时才去拉取并执行（避免启动时一次性拉 9 个文件卡顿）。
--==============================================================
local HB_REMOTE_BASE = "https://raw.githubusercontent.com/suif666/tu/main/hb/"

-- 拉取并执行一个远程脚本。失败重试 3 次，仍失败就明确提示。
local function loadRemote(url, desc, onSuccess, onFail)
	task.spawn(function()
		local ok, err
		for attempt = 1, 3 do
			ok, err = pcall(function()
				local src = game:HttpGet(url)
				local fn, compileErr = loadstring(src)
				if not fn then
					error(compileErr)
				end
				fn()
			end)
			if ok then
				if onSuccess then
					pcall(onSuccess)
				end
				return
			end
			task.wait(0.5 * attempt)
		end
		warn((desc or "远程脚本") .. " 加载失败: " .. tostring(err))
		pcall(notify, desc or "远程脚本", "加载失败：" .. tostring(err), "x")
		if onFail then
			pcall(onFail)
		end
	end)
end

-- 登记表：状态机 pending / loading / done / failed
local lazyTabs = {}
local lazyOrder = {}

local function startLoad(item)
	if item.state == "loading" or item.state == "done" then
		return
	end
	item.state = "loading"
	loadRemote(item.url, item.desc,
		function()
			item.state = "done"
		end,
		function()
			item.state = "failed"
		end)
end

-- 登记一个页签对应的远程脚本；点击该页签时才加载
local function lazyLoad(url, desc, tab)
	if not (tab and tab.Index) then
		warn("[黑白提取] lazyLoad 拿不到页签: " .. tostring(desc))
		return
	end
	local item = { url = url, desc = desc, state = "pending" }
	lazyTabs[tab.Index] = item
	lazyOrder[#lazyOrder + 1] = item

	-- 挂页签的点击事件。普通 Tab 的点击对象是 tab.UIElements.Main，
	-- TabItem 只有 Dropdown 型 Tab 才用，挂它点不动（suif.lua 里踩过的坑）。
	task.spawn(function()
		for _ = 1, 20 do
			local btn = tab.UIElements and tab.UIElements.Main
			if btn and btn.MouseButton1Click then
				pcall(function()
					btn.MouseButton1Click:Connect(function()
						if item.state == "pending" or item.state == "failed" then
							startLoad(item)
						end
					end)
				end)
				return
			end
			task.wait(0.1)
		end
		warn("[黑白提取] 挂不上页签点击事件: " .. tostring(desc))
	end)
end

-- ── 各页签对应的远程脚本 ──
lazyLoad(HB_REMOTE_BASE .. "animation.lua", "动作动画", animTab)
lazyLoad(HB_REMOTE_BASE .. "actionpack.lua", "动作包", animTab)
lazyLoad(HB_REMOTE_BASE .. "animpack.lua", "动画包", animTab)
lazyLoad(HB_REMOTE_BASE .. "disguise.lua", "伪装玩家", disguiseTab)
lazyLoad(HB_REMOTE_BASE .. "slowrun.lua", "缓慢的快速跑", runTab)
lazyLoad(HB_REMOTE_BASE .. "clicker.lua", "自动连点器", clickerTab)
lazyLoad(HB_REMOTE_BASE .. "npc.lua", "NPC交互", npcTab)
lazyLoad(HB_REMOTE_BASE .. "trigger.lua", "触发类", triggerTab)
lazyLoad(HB_REMOTE_BASE .. "object.lua", "控制物体", objectTab)

-- 兜底：万一某个页签的点击事件没挂上，3 秒后把这些还没加载的也拉下来，
-- 保证功能一定可用（只是失去了「点了才加载」的省流量效果）。
task.spawn(function()
	task.wait(3)
	for _, item in ipairs(lazyOrder) do
		if item.state == "pending" then
			startLoad(item)
			task.wait(0.4)
		end
	end
end)

notify("黑白提取", "主脚本已就绪：视觉类 / 玩家类 / 工具类 / 功能类（点开页签自动加载功能）", "check")
