--[[
    黑白提取 · 远程模块：缓慢的快速跑
    缓慢的快速跑.lua

    本文件由脚本自己 game:HttpGet + loadstring 执行，是独立 chunk，
    看不到主脚本的局部变量，所以：
      页签   走 getgenv().Tabs.HB_slowrunTab
      共享环境 走 getgenv().HB_notify / HB_readInput / HB_onClose / HB_getChar / HB_getHum / HB_isR15
]]

if getgenv().__HB_SLOWRUN_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.HB_slowrunTab) or getgenv().SutureHB_slowrunTab
if not Tab then
	warn("[缓慢的快速跑] 未找到页签（主脚本没赋值 HB_slowrunTab？）")
	return
end

-- 确认页签拿到后才标记已加载；构建失败时会在下面清掉，允许重试
getgenv().__HB_SLOWRUN_LOADED = true

local notify    = getgenv().HB_notify
local readInput = getgenv().HB_readInput
local onClose   = getgenv().HB_onClose
local getChar   = getgenv().HB_getChar
local getHum    = getgenv().HB_getHum
local isR15     = getgenv().HB_isR15

if type(notify) ~= "function" then
	warn("[缓慢的快速跑] 主脚本共享环境未就绪（getgenv().HB_notify 缺失）")
	getgenv().__HB_SLOWRUN_LOADED = nil
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

-- 远程脚本是独立 chunk，出错必须显式暴露，否则就是静默白屏
local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[缓慢的快速跑] 构建失败: " .. tostring(err))
	pcall(notify, "缓慢的快速跑", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_SLOWRUN_LOADED = nil   -- 清掉标志位，允许再点一次重试
end
