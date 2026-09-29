--[[
    黑白提取 · 远程模块：灾害预警
    （源：灾害预警.lua，由 suif.lua 的 lazyLoad 拉取执行）

    契约（和 玩家类远程.lua 一致）：
        主脚本先 getgenv().Tabs.HBDisasterTab = 页签，再 lazyLoad(本文件, "灾害预警", 页签)

    本文件是独立 chunk，看不到主脚本的局部变量：
        页签    走 getgenv().Tabs.HBDisasterTab
        WindUI  走 getgenv().HB_WindUI
        win     走 getgenv().HB_win（用于 OnClose）
        notify / readInput / getChar / getHum / isR15 / onClose 在本文件里自己实现，
        不依赖主脚本导出，主脚本少给东西也不会挂。
]]

if getgenv().__HB_DISASTER_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.HBDisasterTab) or getgenv().SutureHBHBDisasterTab
if not Tab then
	warn("[灾害预警] 未找到页签（主脚本没赋值 getgenv().Tabs.HBDisasterTab？）")
	return
end

-- 确认页签拿到后才标记；构建失败会在末尾清掉，允许重试
getgenv().__HB_DISASTER_LOADED = true

local WindUI = getgenv().HB_WindUI
if type(WindUI) ~= "table" then
	warn("[灾害预警] getgenv().HB_WindUI 缺失，无法弹通知（功能仍会尝试构建）")
end

-- ── 自带的 helper，不依赖主脚本 ──
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local function notify(title, content, icon)
	if type(WindUI) == "table" then
		pcall(function()
			WindUI:Notify({
				Title = tostring(title),
				Content = tostring(content or ""),
				Icon = icon or "check",
				Duration = 2,
			})
		end)
	end
	print(string.format("[黑白提取][灾害预警] %s | %s", tostring(title), tostring(content)))
end

-- 黑白那套 WindUI 用 el:Get()，Boreal 用 el.Value，两边都试一遍
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

local function getChar(plr)
	plr = plr or LP
	return plr.Character
end

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

-- 窗口关闭回调：主脚本导出了 win 就挂上去，没有就只记录
local closeCallbacks = {}
local function onClose(fn)
	if type(fn) == "function" then
		table.insert(closeCallbacks, fn)
	end
end
do
	local win = getgenv().HB_win
	if win then
		pcall(function()
			win:OnClose(function()
				local list = closeCallbacks
				closeCallbacks = {}
				for _, fn in ipairs(list) do
					pcall(fn)
				end
			end)
		end)
	end
end

local ctx = {
	notify = notify,
	readInput = readInput,
	onClose = onClose,
	getChar = getChar,
	getHum = getHum,
	isR15 = isR15,
}

local build = (function()
--[[
	黑白提取 · 灾害预警（Natural Disaster Survival）

	来源：你提供的那段「预测灾难」代码 —— 它盯着 workspace 里的 SurvivalTag，
	读它的 StringValue，再用一张英文→中文表翻译。
	这里把那张表原样保留，并把「只在一开始查一次」补成常驻监听。

	源做法的问题：
	  1. 它只在 Toggle 回调里判断了一次，SurvivalTag 后面才出现就永远不报警；
	  2. 没有监听 Value 变化，同一局里换灾难不会提示；
	  3. 没处理的灾害名直接静默丢弃。
	这里都补上了，另外加了「未知灾害也提示」的开关，保证不会漏。

	Tag 位置不写死：workspace 下直接找，找不到再扫一层子容器，最后兜底 ReplicatedStorage。
]]

return function(tab, ctx)
	local notify = ctx.notify
	local onClose = ctx.onClose

	local Players = game:GetService("Players")

	--==========================================================
	-- 灾害名对照表（你给的那一份，原样保留）
	--==========================================================
	local DISASTERS = {
		["Blizzard"] = "暴风雪",
		["Sandstorm"] = "沙尘暴",
		["Tornado"] = "龙卷风",
		["Volcanic Eruption"] = "火山",
		["Flash Flood"] = "洪水",
		["Deadly Virus"] = "病毒",
		["Tsunami"] = "海啸",
		["Acid Rain"] = "酸雨",
		["Fire"] = "火焰",
		["Meteor Shower"] = "流星雨",
		["Earthquake"] = "地震",
		["Thunder Storm"] = "暴风雨",
		["Avalanche"] = "雪崩",
		["Lightning"] = "闪电",
	}

	-- 别名兜底：游戏不同版本写法有出入（有没有空格 / 单复数），
	-- 统一映射到上面的名字，避免因为一个空格就识别不出来。
	local ALIAS = {
		["Thunderstorm"] = "Thunder Storm",
		["MeteorShower"] = "Meteor Shower",
		["Volcano"] = "Volcanic Eruption",
		["Volcanic"] = "Volcanic Eruption",
		["Virus"] = "Deadly Virus",
		["Flood"] = "Flash Flood",
		["Lightening"] = "Lightning",
	}

	local TAG_NAME = "SurvivalTag"

	--==========================================================
	-- UI
	--==========================================================
	local sec = tab:Section({ Title = "灾害预警", Opened = true })

	sec:Paragraph({
		Title = "自然灾害生存 · 灾难提前播报",
		Desc = "开启后常驻监听 workspace 的 " .. TAG_NAME .. "，灾难一出现就弹通知",
		Image = "alert-triangle",
		ImageSize = 16,
		Color = Color3.fromRGB(244, 201, 72),
	})

	local cfg = {
		monitoring = false,
		unknown = true,
	}

	--==========================================================
	-- 找 Tag
	--==========================================================
	local function findTag()
		local ws = workspace
		local direct = ws:FindFirstChild(TAG_NAME)
		if direct then
			return direct
		end
		-- 扫一层子容器（有的版本把它塞在文件夹里）
		for _, child in ipairs(ws:GetChildren()) do
			if child:IsA("Folder") or child:IsA("Model") then
				local hit = child:FindFirstChild(TAG_NAME)
				if hit then
					return hit
				end
			end
		end
		-- 兜底
		local rs = game:GetService("ReplicatedStorage")
		return rs:FindFirstChild(TAG_NAME)
	end

	--==========================================================
	-- 播报
	--==========================================================
	local function report(raw)
		if raw == nil or raw == "" then
			return
		end
		raw = tostring(raw)
		local key = ALIAS[raw] or raw
		local cn = DISASTERS[key]
		if cn then
			notify("灾难预警", cn .. "（" .. key .. "）", "alert-triangle")
		elseif cfg.unknown then
			notify("灾难预警", "未知灾害：" .. raw, "alert-triangle")
		end
		print(string.format("[黑白提取][灾害预警] 当前灾害 = %s", raw))
	end

	--==========================================================
	-- 监听
	--==========================================================
	local conns = {}
	local boundTag = nil

	local function unbindTag()
		if boundTag then
			boundTag = nil
		end
	end

	local function bindTag(tag)
		if not tag then
			return
		end
		boundTag = tag
		-- 绑定瞬间先报一次当前值
		pcall(function()
			report(tag.Value)
		end)
		table.insert(conns, tag:GetPropertyChangedSignal("Value"):Connect(function()
			report(tag.Value)
		end))
	end

	local function startMonitor()
		if cfg.monitoring then
			return
		end
		cfg.monitoring = true

		bindTag(findTag())

		-- Tag 后面才生成 / 被换掉
		table.insert(conns, workspace.ChildAdded:Connect(function(c)
			if c.Name == TAG_NAME then
				bindTag(c)
			end
		end))
		table.insert(conns, workspace.ChildRemoved:Connect(function(c)
			if c == boundTag then
				unbindTag()
			end
		end))
	end

	local function stopMonitor()
		cfg.monitoring = false
		for _, c in ipairs(conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		conns = {}
		unbindTag()
	end

	--==========================================================
	-- 控件
	--==========================================================
	sec:Toggle({
		Title = "灾害预警",
		Desc = "常驻监听，灾难出现或切换时弹通知",
		Icon = "alert-triangle",
		Value = false,
		Callback = function(state)
			if state then
				startMonitor()
				local tag = findTag()
				if tag then
					notify("灾害预警", "已开启，当前灾害：" .. tostring(tag.Value), "check")
				else
					notify("灾害预警", "已开启，正在等待 " .. TAG_NAME .. " 出现", "check")
				end
			else
				stopMonitor()
				notify("灾害预警", "已关闭", "check")
			end
		end,
	})

	sec:Toggle({
		Title = "未知灾害也提示",
		Desc = "对照表里没有的名字，直接弹英文原名（保证不漏报）",
		Icon = "help-circle",
		Value = true,
		Callback = function(state)
			cfg.unknown = state
		end,
	})

	sec:Divider()

	sec:Button({
		Title = "立即检测一次",
		Desc = "不开启监听，也能马上看看现在是什么灾难",
		Icon = "search",
		Callback = function()
			local tag = findTag()
			if not tag then
				notify("灾害预警", "没找到 " .. TAG_NAME .. "（可能不在自然灾害生存里）", "x")
				return
			end
			report(tag.Value)
		end,
	})

	sec:Button({
		Title = "打印对照表",
		Desc = "把支持识别的灾难名输出到控制台（F9 查看）",
		Icon = "list",
		Callback = function()
			local names = {}
			for k, v in pairs(DISASTERS) do
				table.insert(names, k .. " = " .. v)
			end
			table.sort(names)
			print("[黑白提取][灾害预警] 对照表，共 " .. tostring(#names) .. " 条：")
			for _, line in ipairs(names) do
				print("    " .. line)
			end
			notify("灾害预警", "对照表已输出到控制台（" .. tostring(#names) .. " 条）", "check")
		end,
	})

	if onClose then
		onClose(function()
			stopMonitor()
		end)
	end
end
end)()

local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[灾害预警] 构建失败: " .. tostring(err))
	pcall(notify, "灾害预警", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_DISASTER_LOADED = nil   -- 清掉标志位，允许重试
else
	print(string.format("[黑白提取] 远程模块已加载: 灾害预警 (%d 个元素)", #(Tab.Elements or {})))
end
