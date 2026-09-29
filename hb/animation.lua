--[[
    黑白提取 · 远程模块：动作动画
    动作动画.lua

    本文件由脚本自己 game:HttpGet + loadstring 执行，是独立 chunk，
    看不到主脚本的局部变量，所以：
      页签   走 getgenv().Tabs.HB_animTab
      共享环境 走 getgenv().HB_notify / HB_readInput / HB_onClose / HB_getChar / HB_getHum / HB_isR15
]]

if getgenv().__HB_ANIM_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.HB_animTab) or getgenv().SutureHB_animTab
if not Tab then
	warn("[动作动画] 未找到页签（主脚本没赋值 HB_animTab？）")
	return
end

-- 确认页签拿到后才标记已加载；构建失败时会在下面清掉，允许重试
getgenv().__HB_ANIM_LOADED = true

local notify    = getgenv().HB_notify
local readInput = getgenv().HB_readInput
local onClose   = getgenv().HB_onClose
local getChar   = getgenv().HB_getChar
local getHum    = getgenv().HB_getHum
local isR15     = getgenv().HB_isR15

if type(notify) ~= "function" then
	warn("[动作动画] 主脚本共享环境未就绪（getgenv().HB_notify 缺失）")
	getgenv().__HB_ANIM_LOADED = nil
	return
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
    黑白提取 · 动作/动画
    从主脚本的 v1 内联代码搬过来，改成一个接收 tab 的模块。

    内容：自定义动画 / 随机跳舞 / 停止所有动画 / 全局动画速度
    解锁所有商城动画（原来是远程类页签里的，属于动画功能，挪到这一节）
    动作包、动画包这两个模块由调用方塞进同一个 tab。
]]
return function(tab, ctx)
	local notify    = ctx.notify
	local readInput = ctx.readInput
	local isR15     = ctx.isR15
	local LP        = game:GetService("Players").LocalPlayer
	local getHum    = ctx.getHum
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
-- [动作/动画类]
--==============================================================

local animSec = tab:Section({ Title = "自定义动画", Opened = true })

local animIdInput = animSec:Input({
	Title = "动画 ID",
	Placeholder = "例：507771019",
	Value = "",
})

local animSpeedInput = animSec:Input({
	Title = "播放速度",
	Placeholder = "默认 1",
	Value = "1",
})

animSec:Button({
	Title = "播放自定义动画",
	Desc = "播放上面填的动画 ID",
	Icon = "play",
	Callback = function()
		local id = tostring(readInput(animIdInput) or "")
		if id == "" then
			notify("错误", "请先填动画 ID", "x")
			return
		end
		-- 支持直接粘 rbxassetid:// 或整段 URL
		id = id:gsub("rbxassetid://", ""):gsub(".*id=", ""):gsub("%D", "")
		if id == "" then
			notify("错误", "动画 ID 不合法", "x")
			return
		end
		local speed = tonumber(readInput(animSpeedInput)) or 1
		local track = playAnim(LP, id, speed, false, 0)
		if track then
			notify("自定义动画", "已播放 ID: " .. id)
		else
			notify("错误", "播放失败（动画 ID 可能无效）", "x")
		end
	end,
})

local quickSec = tab:Section({ Title = "快捷动画", Opened = true })

local function quickPlay(list, label, looped)
	local track = playAnim(LP, list[math.random(1, #list)], 1, looped or true, 0)
	if track then
		notify(label, "已启动（ID: " .. tostring(track.Animation.AnimationId):gsub("%D", "") .. "）")
	else
		notify("错误", label .. " 启动失败", "x")
	end
end

-- 对应黑白 fn81 / 动作包里的随机跳舞
quickSec:Button({
	Title = "随机跳舞",
	Desc = "自动适配 R6 / R15",
	Icon = "music",
	Callback = function()
		local list
		if isR15(LP) then
			list = {
				"3333432454", "4555808220", "4049037604", "4555782893",
				"10214311282", "10714010337", "10713981723", "10714372526",
				"10714076981", "10714392151", "11444443576",
			}
		else
			list = { "27789359", "30196114", "248263260", "45834924", "33796059", "28488254", "52155728" }
		end
		quickPlay(list, "跳舞")
	end,
})

quickSec:Button({
	Title = "停止所有动画",
	Desc = "停掉本脚本播放的动画",
	Icon = "square",
	Callback = function()
		stopAllAnim()
		notify("动作", "已停止所有动画")
	end,
})

local speedSec = tab:Section({ Title = "全局动画速度", Opened = true })

speedSec:Slider({
	Title = "全局动画速度",
	Desc = "调整当前所有正在播放的动画速度（默认 1）",
	Value = { Min = 0, Max = 10, Default = 1 },
	Step = 0.1,
	Callback = function(v)
		setGlobalAnimSpeed(v)
	end,
})

speedSec:Button({
	Title = "恢复速度 1",
	Icon = "rotate-ccw",
	Callback = function()
		setGlobalAnimSpeed(1)
		notify("动画速度", "已恢复为 1")
	end,
})

	--==========================================================
	-- 解锁所有商城动画（原来是「远程类」页签里的一项，按分类挪到动作/动画）
	-- 上游 MoonSec V3 混淆，约 553 KB，没法提取逻辑，只能原样远程加载
	--==========================================================
	local shopSec = tab:Section({ Title = "商城动画（远程）", Opened = false })

	shopSec:Paragraph({
		Title = "上游是混淆代码，没法提取逻辑，只能原样远程加载",
		Desc = "解锁所有商城动画：MoonSec V3 混淆（约 553 KB）",
		Image = "alert-triangle",
		ImageSize = 16,
		Color = Color3.fromRGB(244, 201, 72),
	})

	shopSec:Button({
		Title = "解锁所有商城动画",
		Desc = "远程加载并执行（MoonSec V3 混淆）",
		Icon = "unlock",
		Callback = function()
			local ok, result = pcall(function()
				return loadstring(game:HttpGet("https://raw.githubusercontent.com/BS58dL/BS/refs/heads/main/%E8%A7%A3%E9%94%81%E6%89%80%E6%9C%89%E5%95%86%E5%9F%8E%E5%8A%A8%E7%94%BB.txt"))()
			end)
			if ok then
				notify("解锁所有商城动画", "已加载")
			else
				notify("错误", "加载失败: " .. tostring(result):sub(1, 60), "x")
			end
		end,
	})

end
end)()

-- 远程脚本是独立 chunk，出错必须显式暴露，否则就是静默白屏
local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[动作动画] 构建失败: " .. tostring(err))
	pcall(notify, "动作动画", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_ANIM_LOADED = nil   -- 清掉标志位，允许再点一次重试
else
	-- 成功也打一条到控制台，方便排查「页签是空的」这类问题
	print("[黑白提取] 远程模块已加载: 动作动画 (" .. tostring(#Tab.Elements or 0) .. " 个元素)")
end
