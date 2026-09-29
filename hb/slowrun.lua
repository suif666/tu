--[[
    黑白提取 · 远程模块：缓慢的快速跑
    （源：缓慢的快速跑.lua，由 suif.lua 的 lazyLoad 拉取执行）

    契约（和 玩家类远程.lua 一致）：
        主脚本先 getgenv().Tabs.PlayerTab = 页签，再 lazyLoad(本文件, "缓慢的快速跑", 页签)

    本文件是独立 chunk，看不到主脚本的局部变量：
        页签    走 getgenv().Tabs.PlayerTab
        WindUI  走 getgenv().HB_WindUI
        win     走 getgenv().HB_win（用于 OnClose）
        notify / readInput / getChar / getHum / isR15 / onClose 在本文件里自己实现，
        不依赖主脚本导出，主脚本少给东西也不会挂。
]]

if getgenv().__HB_SLOWRUN_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.PlayerTab) or getgenv().SuturePlayerTab
if not Tab then
	warn("[缓慢的快速跑] 未找到页签（主脚本没赋值 getgenv().Tabs.PlayerTab？）")
	return
end

-- 确认页签拿到后才标记；构建失败会在末尾清掉，允许重试
getgenv().__HB_SLOWRUN_LOADED = true

local WindUI = getgenv().HB_WindUI
if type(WindUI) ~= "table" then
	warn("[缓慢的快速跑] getgenv().HB_WindUI 缺失，无法弹通知（功能仍会尝试构建）")
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
	print(string.format("[黑白提取][缓慢的快速跑] %s | %s", tostring(title), tostring(content)))
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
    黑白提取 · 缓慢的快速跑
    源：远程类页签里的一项（源 5563 行）

    上游 pastebin.com/raw/7fLqezjn 是 wearedevs 混淆过的 176,351 字节，
    没法提取逻辑，只能原样远程加载。
]]

return function(tab, ctx)
	local notify = ctx.notify

	local sec = tab:Section({ Title = "缓慢的快速跑（远程）", Opened = true })

	sec:Paragraph({
		Title = "上游是混淆代码，没法提取逻辑，只能原样远程加载",
		Desc = "缓慢的快速跑：wearedevs 混淆（约 172 KB）",
		Image = "alert-triangle",
		ImageSize = 16,
		Color = Color3.fromRGB(244, 201, 72),
	})

	sec:Button({
		Title = "加载缓慢的快速跑",
		Desc = "远程加载并执行（wearedevs 混淆）",
		Icon = "zap",
		Callback = function()
			local ok, result = pcall(function()
				return loadstring(game:HttpGet("https://pastebin.com/raw/7fLqezjn"))()
			end)
			if ok then
				notify("缓慢的快速跑", "已加载")
			else
				notify("错误", "加载失败: " .. tostring(result):sub(1, 60), "x")
			end
		end,
	})
end
end)()

local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[缓慢的快速跑] 构建失败: " .. tostring(err))
	pcall(notify, "缓慢的快速跑", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_SLOWRUN_LOADED = nil   -- 清掉标志位，允许重试
else
	print(string.format("[黑白提取] 远程模块已加载: 缓慢的快速跑 (%d 个元素)", #(Tab.Elements or {})))
end
