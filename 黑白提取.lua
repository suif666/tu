--[[
    黑白脚本 · 功能提取（独立版）
    从「黑白全源」里把功能抠出来重写，不依赖 suif.lua，不依赖黑白那套框架。

    第一批（小件）：
      动作/动画类  自定义动画 / 全局动画速度 / 停止所有动画
      玩家类       伪装玩家 / 控制物体
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
-- 控制物体
--==============================================================
local selectedModel = nil
local savedPivots = {}
local selectionBox = nil
local pickConn = nil
local lockSelect = false
local objFlySpeed = 5
local objFlyConn = nil

local function getSelectionBox()
	if selectionBox and selectionBox.Parent then
		return selectionBox
	end
	local box = Instance.new("SelectionBox")
	box.Name = "HB_ObjectSelect"
	box.LineThickness = 0.05
	box.Color3 = Color3.fromRGB(0, 200, 255)
	box.Parent = game:GetService("CoreGui")
	selectionBox = box
	return box
end

local function setSelected(obj)
	selectedModel = obj
	getSelectionBox().Adornee = obj
end

local function copyToClipboard(text)
	local ok = pcall(function()
		setclipboard(tostring(text))
	end)
	return ok
end

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
-- [动作/动画类]
--==============================================================
local animTab = win:Tab({ Title = "动作/动画", Icon = "music" })
local animSec = animTab:Section({ Title = "自定义动画", Opened = true })

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

local quickSec = animTab:Section({ Title = "快捷动画", Opened = true })

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

local speedSec = animTab:Section({ Title = "全局动画速度", Opened = true })

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

--==============================================================
-- [玩家类]
--==============================================================
local playerTab = win:Tab({ Title = "玩家类", Icon = "user" })

-- ---- 伪装玩家 ----
local disguiseSec = playerTab:Section({ Title = "伪装玩家", Opened = true })

disguiseSec:Paragraph({
	Title = "把目标玩家的外观和名字改成另一个 Roblox 账号的样子",
	Desc = "先填要伪装成的 Roblox 用户名，再填要改的目标玩家名",
	Image = "info",
	ImageSize = 16,
	Color3.fromRGB(72, 72, 72),
})

local disguiseNameInput = disguiseSec:Input({
	Title = "伪装成（Roblox 用户名）",
	Placeholder = "例：Roblox",
	Value = "",
})

local disguiseTargetInput = disguiseSec:Input({
	Title = "目标玩家（当前服务器里的名字）",
	Placeholder = "例：Player1",
	Value = "",
})

-- 对应黑白的 fn80（子作用域那个）：按用户名查 userId
local function lookupUserId(name)
	local ok, result = pcall(function()
		return game:HttpGet("https://users.roblox.com/v1/users/search?keyword=" .. HttpService:UrlEncode(name), true)
	end)
	if not ok or not result then
		return nil
	end
	local ok2, data = pcall(function()
		return HttpService:JSONDecode(result)
	end)
	if not ok2 or not data or not data.data or #data.data == 0 then
		return nil
	end
	return data.data[1].id, data.data[1].name, data.data[1].displayName
end

-- 对应黑白的 fn81：把目标角色的外观替换掉
local function applyAppearance(character, userId)
	local ok, appearance = pcall(function()
		return Players:GetCharacterAppearanceAsync(userId)
	end)
	if not ok or not appearance then
		return false
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end

	for _, child in ipairs(appearance:GetChildren()) do
		if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("BodyColors") then
			child.Parent = character
		elseif child:IsA("Accessory") then
			local hum = character:FindFirstChildOfClass("Humanoid")
			if hum then
				pcall(function()
					hum:AddAccessory(child)
				end)
			end
		end
	end

	local head = character:FindFirstChild("Head")
	if head then
		local oldFace = head:FindFirstChild("face")
		if oldFace then
			oldFace:Destroy()
		end
		local newFace = appearance:FindFirstChild("face")
		if newFace then
			newFace.Parent = head
		else
			local decal = Instance.new("Decal")
			decal.Face = Enum.NormalId.Front
			decal.Name = "face"
			decal.Texture = "rbxasset://textures/face.png"
			decal.Transparency = 0
			decal.Parent = head
		end
	end

	-- 强制刷新一次外观
	local parent = character.Parent
	character.Parent = nil
	character.Parent = parent
	return true
end

disguiseSec:Button({
	Title = "伪装目标玩家",
	Desc = "把目标玩家的外观和名字改成上面那个账号的",
	Icon = "user-check",
	Callback = function()
		local wantName = tostring(readInput(disguiseNameInput) or "")
		local targetName = tostring(readInput(disguiseTargetInput) or "")
		if wantName == "" then
			notify("错误", "请先填要伪装成的用户名", "x")
			return
		end
		if targetName == "" then
			notify("错误", "请先填目标玩家名", "x")
			return
		end
		local target = Players:FindFirstChild(targetName)
		if not target then
			notify("错误", "目标玩家不存在或已离开", "x")
			return
		end
		local character = target.Character
		if not character or not character:FindFirstChildOfClass("Humanoid") then
			notify("错误", "目标玩家角色未加载", "x")
			return
		end

		local userId, userName, displayName = lookupUserId(wantName)
		if not userId then
			notify("错误", "查不到这个用户名", "x")
			return
		end

		local ok = applyAppearance(character, userId)
		if not ok then
			notify("错误", "获取外观失败", "x")
			return
		end

		pcall(function()
			character.Name = userName
		end)
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function()
				hum.DisplayName = displayName
			end)
		end

		notify("成功", string.format("已将 %s 的外观改为 %s", targetName, tostring(displayName)), "check")
	end,
})

-- ---- 控制物体 ----
local objectSec = playerTab:Section({ Title = "控制物体", Opened = true })

objectSec:Toggle({
	Title = "点击选择物体",
	Desc = "开启后鼠标左键点击场景物体即可选中",
	Value = false,
	Callback = function(on)
		if pickConn then
			pickConn:Disconnect()
			pickConn = nil
		end
		if not on then
			return
		end
		pickConn = LP:GetMouse().Button1Down:Connect(function()
			if lockSelect then
				return
			end
			local target = LP:GetMouse().Target
			if target then
				setSelected(target:FindFirstAncestorOfClass("Model") or target)
				notify("物体控制", "已选中: " .. tostring(selectedModel and selectedModel.Name))
			end
		end)
	end,
})

objectSec:Toggle({
	Title = "锁定选择",
	Desc = "锁定后点击不会改变已选中的物体",
	Value = false,
	Callback = function(on)
		lockSelect = on
	end,
})

objectSec:Button({
	Title = "复制选中物体名称",
	Icon = "clipboard",
	Callback = function()
		if not selectedModel then
			notify("错误", "还没选中物体", "x")
			return
		end
		if copyToClipboard(selectedModel.Name) then
			notify("物体控制", "已复制名称: " .. selectedModel.Name)
		else
			notify("错误", "当前环境不支持剪贴板", "x")
		end
	end,
})

objectSec:Button({
	Title = "保存位置",
	Icon = "save",
	Callback = function()
		if not selectedModel then
			notify("错误", "还没选中物体", "x")
			return
		end
		savedPivots[selectedModel] = selectedModel:GetPivot()
		notify("物体控制", "已保存位置")
	end,
})

objectSec:Button({
	Title = "加载位置",
	Icon = "rotate-ccw",
	Callback = function()
		if not selectedModel then
			notify("错误", "还没选中物体", "x")
			return
		end
		local pivot = savedPivots[selectedModel]
		if not pivot then
			notify("错误", "这个物体还没保存过位置", "x")
			return
		end
		pcall(function()
			selectedModel:PivotTo(pivot)
		end)
		notify("物体控制", "已回到保存的位置")
	end,
})

objectSec:Button({
	Title = "传送到物品",
	Icon = "navigation",
	Callback = function()
		if not selectedModel then
			notify("错误", "还没选中物体", "x")
			return
		end
		local character = getChar(LP)
		if not character then
			return
		end
		local basePart = selectedModel:IsA("BasePart") and selectedModel
			or selectedModel:FindFirstChildWhichIsA("BasePart")
		if not basePart then
			notify("错误", "这个物体里没有可用部件", "x")
			return
		end
		pcall(function()
			character:PivotTo(basePart.CFrame + Vector3.new(0, 3, 0))
		end)
		notify("物体控制", "已传送到 " .. selectedModel.Name)
	end,
})

objectSec:Button({
	Title = "传送物品到玩家",
	Icon = "move",
	Callback = function()
		if not selectedModel then
			notify("错误", "还没选中物体", "x")
			return
		end
		local character = getChar(LP)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local target = root.CFrame + root.CFrame.LookVector * 5
		local ok = pcall(function()
			if selectedModel:IsA("BasePart") then
				selectedModel.CFrame = target
			else
				selectedModel:PivotTo(target)
			end
		end)
		if ok then
			notify("物体控制", "已把物体拉到面前")
		else
			notify("错误", "移动失败", "x")
		end
	end,
})

objectSec:Toggle({
	Title = "物体飞行",
	Desc = "让选中的物体跟着鼠标跑",
	Value = false,
	Callback = function(on)
		if objFlyConn then
			objFlyConn:Disconnect()
			objFlyConn = nil
		end
		if not on then
			return
		end
		objFlyConn = RunService.RenderStepped:Connect(function()
			if not selectedModel then
				return
			end
			local mouse = LP:GetMouse()
			if not mouse.Hit then
				return
			end
			pcall(function()
				if selectedModel:IsA("BasePart") then
					selectedModel.CFrame = selectedModel.CFrame:Lerp(mouse.Hit + Vector3.new(0, 3, 0), 0.2)
				else
					selectedModel:PivotTo(selectedModel:GetPivot():Lerp(mouse.Hit + Vector3.new(0, 3, 0), 0.2))
				end
			end)
		end)
	end,
})

objectSec:Input({
	Title = "飞行速度",
	Placeholder = "数值",
	Value = "5",
	Callback = function(v)
		local n = tonumber(v)
		if n then
			objFlySpeed = n
		end
	end,
})

--==============================================================
-- [远程类] —— 上游是混淆脚本，这里保留原样远程加载
--==============================================================
local remoteTab = win:Tab({ Title = "远程类", Icon = "cloud" })
local remoteSec = remoteTab:Section({ Title = "上游混淆脚本", Opened = true })

remoteSec:Paragraph({
	Title = "以下两个上游是混淆代码，没法提取逻辑，只能原样远程加载",
	Desc = "解锁所有商城动画：MoonSec V3 混淆（约 553 KB）\n缓慢的快速跑：wearedevs 混淆（约 172 KB）",
	Image = "alert-triangle",
	ImageSize = 16,
	Color3.fromRGB(244, 201, 72),
})

local function runRemote(url, label)
	local ok, result = pcall(function()
		return loadstring(game:HttpGet(url))()
	end)
	if ok then
		notify(label, "已加载")
	else
		notify("错误", label .. " 加载失败: " .. tostring(result):sub(1, 60), "x")
	end
end

remoteSec:Button({
	Title = "解锁所有商城动画",
	Desc = "远程加载（MoonSec 混淆）",
	Icon = "unlock",
	Callback = function()
		runRemote("https://raw.githubusercontent.com/BS58dL/BS/refs/heads/main/%E8%A7%A3%E9%94%81%E6%89%80%E6%9C%89%E5%95%86%E5%9F%8E%E5%8A%A8%E7%94%BB.txt", "解锁所有商城动画")
	end,
})

remoteSec:Button({
	Title = "缓慢的快速跑",
	Desc = "远程加载（wearedevs 混淆）",
	Icon = "zap",
	Callback = function()
		runRemote("https://pastebin.com/raw/7fLqezjn", "缓慢的快速跑")
	end,
})

-- ===== 以下为提取出来的功能模块（自动合并，勿手改） =====

-- ── 动作包 ──
local buildActionPack = (function()
--==============================================================================
-- 动作包（从 黑白-MAIN.可运行版.lua 第 5960–6519 行 的 fn73 提取重写）
--  - 5963-6171：Tabs.Action「动画控制」分区 —— 130 条动作列表 + 下拉选择 + 播放/停止
--  - 6173-6518：Tabs.ActionV2「动作控制」分区 —— 鬼畜抽搐 / 甩头 / 定住解冻 /
--              循环当前动画 / 刷新动画 / 自定义动画包开关 / 说明
-- 与 黑白提取.lua 已实现的「随机跳舞、自定义动画、全局动画速度、停止所有动画」
-- 重复的部分不在此重复实现，只补动作包独有的逻辑。
--==============================================================================
return function(win, ctx)
	local notify    = ctx.notify      -- function(title, content[, icon])
	local getChar   = ctx.getChar     -- function(player) -> Character or nil
	local getHum    = ctx.getHum      -- function(player) -> Humanoid or nil
	local readInput = ctx.readInput   -- function(element) -> string
	local isR15     = ctx.isR15       -- function(player) -> boolean
	local Players = game:GetService("Players")
	local LP = Players.LocalPlayer

	local tab = win:Tab({ Title = "动作包", Icon = "music" })

	--==========================================================================
	-- 通用小工具：把人类身上的动画轨道全部找出来
	-- 源文件 fn77 走的是 FindFirstChildOfClass("Humanoid") 或 AnimationController；
	-- 这里额外优先用 Animator:GetPlayingAnimationTracks()（新版 API），
	-- 引擎上取不到再退回 Humanoid:GetPlayingAnimationTracks()（旧版 API）。
	--==========================================================================
	local function getAnimateOwner()
		local ch = getChar(LP)
		if not ch then
			return nil, nil
		end
		local animator = ch:FindFirstChildOfClass("Animator")
		return ch, animator
	end

	-- 取出「当前正在播放的所有动画轨道」（对应源文件里的 v13:GetPlayingAnimationTracks()）
	local function getPlayingTracks()
		local ch, animator = getAnimateOwner()
		if not ch then
			return {}
		end
		if animator then
			local ok, tracks = pcall(function()
				return animator:GetPlayingAnimationTracks()
			end)
			if ok and tracks then
				return tracks
			end
		end
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if hum then
			local ok, tracks = pcall(function()
				return hum:GetPlayingAnimationTracks()
			end)
			if ok and tracks then
				return tracks
			end
		end
		return {}
	end

	-- 通用：对当前所有在播动画做一件事（对应源文件到处出现的 for ... AdjustSpeed 循环）
	local function forEachPlayingTracks(fn)
		local n = 0
		for _, track in pairs(getPlayingTracks()) do
			local ok = pcall(function()
				fn(track)
			end)
			if ok then
				n = n + 1
			end
		end
		return n
	end

	--==========================================================================
	-- 动画控制：动作列表（源文件 5999-6126 行的 tbl9，130 条，ID 原样保留）
	-- 每项格式：{ 名称, 动画ID, 播放速度, 播放权重 }
	--==========================================================================
	local actionList = {
		{ "加州女孩", 124982597491660, 1, 0 },
		{ "直升机", 95301257497525, 1, 0 },
		{ "直升机2", 122951149300674, 1, 0 },
		{ "直升机3", 91257498644328, 1, 0 },
		{ "街头舞蹈", 108171959207138, 1, 0 },
		{ "街头跺脚", 115048845533448, 1.4, 0 },
		{ "扑腾的鱼", 79075971527754, 1, 0 },
		{ "江南Style", 100531289776679, 1, 0 },
		{ "苹果糖舞", 88315693621494, 1, 0 },
		{ "空中转圈", 94324173536622, 1, 0 },
		{ "比心(左)", 110936682778213, 0, 0 },
		{ "比心(右)", 84671941093489, 0, 0 },
		{ "狗狗", 78195344190486, 1, 0 },
		{ "MM2禅", 86872878957632, 1, 0 },
		{ "默认舞蹈", 88455578674030, 1, 0 },
		{ "坐下", 97185364700038, 1, 0 },
		{ "哥萨克踢", 119264600441310, 1, 0 },
		{ "战斗姿态", 116763940575803, 1, 0 },
		{ "你是谁", 81389876138766, 1, 0 },
		{ "摇摆坐", 130995344283026, 1, 0 },
		{ "摇摆坐2", 131836270858895, 1, 0 },
		{ "蠕虫舞", 90333292347820, 1, 0 },
		{ "蛇", 98476854035224, 1, 0 },
		{ "彼得死亡", 129787664584610, 1, 0 },
		{ "沃尔特场景", 113475147402830, 1, 0 },
		{ "可爱躺姿", 80754582835479, 1, 0 },
		{ "暗影迪奥", 92266904563270, 1, 0 },
		{ "承太郎姿势", 122120443600865, 1, 0 },
		{ "JOJO姿势", 120629563851640, 1, 0 },
		{ "漂浮躺", 77840765435893, 1, 0 },
		{ "圣经天使", 109873544976020, 1, 0 },
		{ "无头", 78837807518622, 1, 0 },
		{ "ME!ME!ME!", 103235915424832, 1, 0 },
		{ "飞机", 82135680487389, 1, 0 },
		{ "Xavier舞", 90802740360125, 1, 0 },
		{ "中国舞", 131758838511368, 1, 0 },
		{ "背头", 74288964113793, 1, 0 },
		{ "车辆1", 108747312576405, 1, 0 },
		{ "车辆2", 76503595759461, 1, 0 },
		{ "车辆3", 115245341767944, 1, 0 },
		{ "车辆4", 127805235430271, 1, 0 },
		{ "车辆5", 138003068153218, 1, 0 },
		{ "车辆6", 116772752010894, 1, 0 },
		{ "车辆7", 116625361313832, 1, 0 },
		{ "车辆8", 81388785824317, 1, 0 },
		{ "车辆9", 113181071290859, 1, 0 },
		{ "车辆10", 134681712937413, 1, 0 },
		{ "车辆11", 115260380433565, 1, 0 },
		{ "车辆12", 72382226286301, 1, 0 },
		{ "击败Koto", 93497729736287, 1, 0 },
		{ "坦克", 94915612757079, 1, 0 },
		{ "经典行走", 107806791584829, 1, 0 },
		{ "奇怪生物", 87025086742503, 1, 0 },
		{ "马桶人", 127154705636043, 1, 0 },
		{ "滚动哭宝", 129699431093711, 1, 0 },
		{ "思考", 127088545449493, 1, 0 },
		{ "假死", 88130117312312, 1, 0 },
		{ "迷幻", 135611169366768, 1, 0 },
		{ "穿搭检查", 81176957565811, 1, 0 },
		{ "投降", 100537772865440, 1, 0 },
		{ "假设", 91294374426630, 1, 0 },
		{ "Griddy舞", 121966805049108, 1, 0 },
		{ "认输", 78653596566468, 1, 0 },
		{ "篮球头转", 92854797386719, 1, 0 },
		{ "鹦鹉舞", 101810746304426, 1, 0 },
		{ "射击", 102691551292124, 1, 0 },
		{ "布娃娃", 136224735234038, 1, 0 },
		{ "悲伤坐", 100798804992348, 1, 0 },
		{ "汽水", 105459130960429, 1, 0 },
		{ "比利弹跳", 137501135905857, 1, 0 },
		{ "篮球", 119242308765484, 1, 0 },
		{ "打桩机", 91423662648449, 1, 0 },
		{ "怪物捣碎", 137883764619555, 1, 0 },
		{ "芙兰玩偶", 107217181254431, 1, 0 },
		{ "后空翻", 131205329995035, 1, 0 },
		{ "漂浮", 89523370947906, 1, 0 },
		{ "你好", 103041144411206, 1, 0 },
		{ "附身", 90708290447388, 1, 0 },
		{ "去你的!", 98289978017308, 1, 0 },
		{ "摸头", 85422671683973, 1, 0 },
		{ "上帝山羊漂浮", 100405715895755, 1, 0 },
		{ "直升机4", 115417853064013, 1, 0 },
		{ "网格舞", 85588129788692, 1, 0 },
		{ "破碎", 79757971761739, 1, 0 },
		{ "认输", 83265734904502, 1, 0 },
		{ "江南StyleV2", 129764254213842, 1, 0 },
		{ "180°翻转", 114400428765989, 1, 0 },
		{ "马桶舞", 128334204821841, 1, 0 },
		{ "吾乃天命唯一", 138433137191760, 1, 0 },
		{ "橙色正义", 110146282544198, 1, 0 },
		{ "牙线舞", 10714340543, 1, 0 },
		{ "三角符文舞蹈", 77984841414450, 1, 0 },
		{ "圣经级准确表情", 109873544976020, 1, 0 },
		{ "呃呃呃", 111251252458517, 1, 0 },
		{ "彼得不要啊", 84623954062978, 1, 0 },
		{ "我变成敞篷车了", 124756446017361, 1, 0 },
		{ "加里舞蹈", 93014787120483, 1, 0 },
		{ "IShowSpeed舞蹈", 92618727772186, 1, 0 },
		{ "光环农场", 99499783161907, 1, 0 },
		{ "雪天使", 80177289449617, 1, 0 },
		{ "被皮行者附身", 70432904702322, 1, 0 },
		{ "老鼠舞", 123916423751437, 1, 0 },
		{ "花生酱果冻时间", 129537633250603, 1, 0 },
		{ "撒尿狗", 130059214239749, 1, 0 },
		{ "玛卡雷娜", 91047682123297, 1, 0 },
		{ "严肃全能侠", 130019914905925, 1, 0 },
		{ "翻滚", 133612047483255, 1, 0 },
		{ "恐怖月份到啦", 99637983789946, 1, 0 },
		{ "怪物混搭", 88971195093161, 1, 0 },
		{ "无人机模式", 118592095684994, 1, 0 },
		{ "植物大战僵尸向日葵", 95894948496521, 1, 0 },
		{ "鱼类模式", 137969542385356, 1, 0 },
		{ "拉屎", 132399051509976, 1, 0 },
		{ "足球杂耍", 122583653807009, 1, 0 },
		{ "工程师舞蹈", 107355541549056, 1, 0 },
		{ "小鸡舞", 126960077574956, 1, 0 },
		{ "他掏出了鸡儿", 78347793265211, 1, 0 },
		{ "俄罗斯舞蹈", 97148848007002, 1, 0 },
		{ "爬行者模式", 114687548971893, 1, 0 },
		{ "灭霸舞蹈", 106389948045296, 1, 0 },
		{ "俯卧撑", 108313130500811, 1, 0 },
		{ "云端漂浮", 106022089542174, 1, 0 },
		{ "椅子模式2", 114140630538674, 1, 0 },
		{ "AI猫舞", 108865839239307, 1, 0 },
		{ "蔬菜舞蹈", 84352128203419, 1, 0 },
		{ "DJ哈立德", 82293338535013, 1, 0 },
	}

	-- 源文件 6128-6134 行：只取名称做成下拉框的 Values
	local actionNames = {}
	for _, entry in ipairs(actionList) do
		table.insert(actionNames, entry[1])
	end
	local selectedAction = actionNames[1] or ""

	--==========================================================================
	-- [动作控制 · 第一部分] 动作控制分区（源文件 5963-6171 行）
	--==========================================================================
	local actionSec = tab:Section({ Title = "动画控制", Opened = true })

	actionSec:Dropdown({
		Title = "选择动作",
		Desc = "共 " .. tostring(#actionList) .. " 个动作",
		Values = actionNames,
		Value = selectedAction,
		Callback = function(v)
			selectedAction = v
		end,
	})

	-- 对应源文件 6145-6161 行：按钮里遍历 tbl9 找到同名项，取 [2] ID、[3] 速度、[4] 权重
	-- 源文件这里的 fn75 是先停掉自己播的所有动画再播（looped = true），保持一致。
	local pkgTracks = {}

	local function stopActionPackageAnim()
		for _, track in ipairs(pkgTracks) do
			pcall(function()
				track:Stop()
			end)
		end
		pkgTracks = {}
	end

	local function playActionPackageAnim(id, speed, weight)
		-- 源文件 5979-5997 行 fn75 是 task.spawn 异步执行的，这里同样异步，
		-- 避免 LoadAnimation 在角色刚重生时阻塞界面。
		task.spawn(function()
			stopActionPackageAnim()
			local hum = getHum(LP)
			if not hum then
				return nil
			end
			-- 源文件用 Animator:LoadAnimation；没有 Animator 就补一个（新版引擎推荐做法）
			local animator = hum:FindFirstChildOfClass("Animator")
			if not animator then
				local ok, created = pcall(function()
					return Instance.new("Animator", hum)
				end)
				if not ok then
					animator = nil
				else
					animator = created
				end
			end

			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://" .. tostring(id)

			local track
			-- 有 Animator 用 Animator:LoadAnimation，否则退回 Humanoid:LoadAnimation
			local ok = pcall(function()
				if animator then
					track = animator:LoadAnimation(anim)
				else
					track = hum:LoadAnimation(anim)
				end
			end)
			if not ok or not track then
				return nil
			end

			track.Looped = true
			-- 源文件 5991 行：优先级固定为 Action，保证动作能盖住默认动画
			local okPrio = pcall(function()
				track.Priority = Enum.AnimationPriority.Action
			end)
			if not okPrio then
				pcall(function()
					track.Priority = Enum.AnimationPriority.Action2
				end)
			end

			track:Play(weight or 0, 1, 0)
			track:AdjustSpeed(speed or 1)
			table.insert(pkgTracks, track)
			return track
		end)
	end

	actionSec:Button({
		Title = "播放选中动作",
		Desc = "播放下拉框里选中的动作",
		Icon = "play",
		Callback = function()
			if not selectedAction or selectedAction == "" then
				notify("提示", "请先选择一个动作", "x")
				return
			end
			for _, entry in ipairs(actionList) do
				if entry[1] == selectedAction then
					playActionPackageAnim(entry[2], entry[3], entry[4])
					notify("动作包", "已播放：" .. tostring(selectedAction))
					return
				end
			end
			notify("错误", "列表里没有这个动作", "x")
		end,
	})

	actionSec:Button({
		Title = "停止所有动画",
		Desc = "停止本页动作包播放的动画",
		Icon = "square",
		Callback = function()
			task.spawn(stopActionPackageAnim)
			notify("动作", "已停止所有动画")
		end,
	})

	--==========================================================================
	-- [动作控制 · 第二部分] 动作控制分区（源文件 6173-6506 行）
	-- 随机跳舞 / 停止跳舞（源文件 6277-6278 行）、自定义动画 + 全局动画速度
	-- （源文件 6339-6376 行）在 黑白提取.lua 里已有实现，这里不重复。
	--==========================================================================
	tab:Divider()
	local v2Sec = tab:Section({ Title = "动作控制", Opened = true })

	----------------------------------------------------------------------------
	-- 鬼畜抽搐（源文件 6281-6320 行 fn83 / fn84）
	-- 仅 R6；ID 33796059，速度拉到 99，且**不参与** fn79 的轨道表
	----------------------------------------------------------------------------
	local twitchTrack = nil

	v2Sec:Button({
		Title = "鬼畜抽搐",
		Desc = "鬼畜抽搐动画（仅 R6）",
		Icon = "zap",
		Callback = function()
			if isR15(LP) then
				notify("鬼畜", "仅支持 R6 体形", "x")
				return
			end
			if twitchTrack then
				pcall(function()
					twitchTrack:Stop()
				end)
			end
			local hum = getHum(LP)
			if not hum then
				notify("错误", "角色未加载", "x")
				return
			end
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://33796059"
			local ok, track = pcall(function()
				return hum:LoadAnimation(anim)
			end)
			if not ok or not track then
				notify("错误", "鬼畜动画加载失败（可能被游戏禁止）", "x")
				return
			end
			twitchTrack = track
			track:Play()
			track:AdjustSpeed(99)
			notify("鬼畜", "鬼畜抽搐已开启")
		end,
	})

	v2Sec:Button({
		Title = "停止鬼畜",
		Desc = "停止鬼畜抽搐",
		Icon = "square",
		Callback = function()
			if twitchTrack then
				pcall(function()
					twitchTrack:Stop()
				end)
				twitchTrack = nil
			end
			notify("鬼畜", "已停止")
		end,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 甩头（源文件 6323-6336 行）ID 35154961，仅 R6，不循环
	----------------------------------------------------------------------------
	v2Sec:Button({
		Title = "甩头",
		Desc = "甩头动作（仅 R6）",
		Icon = "refresh-cw",
		Callback = function()
			if isR15(LP) then
				notify("甩头", "仅支持 R6 体形", "x")
				return
			end
			local hum = getHum(LP)
			if not hum then
				notify("错误", "角色未加载", "x")
				return
			end
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://35154961"
			local ok, track = pcall(function()
				return hum:LoadAnimation(anim)
			end)
			if not ok or not track then
				notify("错误", "甩头动画加载失败", "x")
				return
			end
			track.Looped = false
			track:Play(0, 1, 0)
			notify("甩头", "甩头动作已播放")
		end,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 定住 / 解冻所有动画（源文件 6380-6413 行 fn85 / fn86）
	-- 被冻住 / 解冻时记录一个状态标志，和源文件 flag6 一样
	----------------------------------------------------------------------------
	local frozen = false

	v2Sec:Button({
		Title = "定住动画",
		Desc = "冻结当前所有动画（速度设 0）",
		Icon = "snowflake",
		Callback = function()
			if not getHum(LP) and not getChar(LP) then
				return
			end
			frozen = true
			forEachPlayingTracks(function(track)
				track:AdjustSpeed(0)
			end)
			notify("动画", "已定住所有动画")
		end,
	})

	v2Sec:Button({
		Title = "解冻动画",
		Desc = "恢复所有动画速度（速度设 1）",
		Icon = "sun",
		Callback = function()
			if not getHum(LP) and not getChar(LP) then
				return
			end
			frozen = false
			forEachPlayingTracks(function(track)
				track:AdjustSpeed(1)
			end)
			notify("动画", "已解冻所有动画")
		end,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 循环当前动画（源文件 6416-6436 行）
	-- 源文件用 `n3 += 1`（Luau 语法），这里改成 n = n + 1
	----------------------------------------------------------------------------
	v2Sec:Button({
		Title = "循环当前动画",
		Desc = "把当前所有播放中的动画设为循环",
		Icon = "repeat",
		Callback = function()
			local n = forEachPlayingTracks(function(track)
				track.Looped = true
			end)
			notify("循环", "已设置 " .. tostring(n) .. " 条动画为循环")
		end,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 停止当前所有播放中的动画（源文件 6440-6449 行，跟上面只停自己的不同，这里停全部）
	----------------------------------------------------------------------------
	v2Sec:Button({
		Title = "停止当前全部动画",
		Desc = "停掉角色身上正在播放的所有动画",
		Icon = "square",
		Callback = function()
			forEachPlayingTracks(function(track)
				track:Stop()
			end)
			notify("动画", "已停止所有动画")
		end,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 刷新动画（源文件 6453-6473 行 fn87）
	-- 手法：把角色里的 Animate 脚本 Disabled = true -> 停掉所有轨道 -> 再 Disabled = false，
	-- 让 Animate 重新接管，默认行走/待机动画就回来了。fn87 也被下面「自定义动画包」复用。
	----------------------------------------------------------------------------
	local function refreshAnimate()
		local ch = getChar(LP)
		if not ch then
			notify("刷新", "角色未加载", "x")
			return false
		end
		local hum = ch:FindFirstChildOfClass("Humanoid")
		local animate = ch:FindFirstChild("Animate")
		if not hum or not animate then
			notify("刷新", "未找到 Animate/Humanoid", "x")
			return false
		end

		animate.Disabled = true
		for _, track in pairs(hum:GetPlayingAnimationTracks()) do
			pcall(function()
				track:Stop()
			end)
		end
		animate.Disabled = false
		notify("刷新", "动画已刷新")
		return true
	end

	v2Sec:Button({
		Title = "刷新动画",
		Desc = "重置 Animate 脚本，恢复默认动画",
		Icon = "refresh-cw",
		Callback = refreshAnimate,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 自定义动画包（源文件 6476-6491 行）
	-- 源文件直接写 fn5("StarterPlayer").AllowCustomAnimations —— 这是**服务端属性**，
	-- 普通 LocalScript 没有权限改（会报权限错误），所以这里用 pcall 包住：
	-- 在客户端能达到的等价效果就是刷新一次 Animate，让自定义动画生效/失效。
	----------------------------------------------------------------------------
	v2Sec:Toggle({
		Title = "自定义动画包",
		Desc = "启用/禁用自定义动画包（需配合刷新）",
		Value = false,
		Callback = function(on)
			local ok = pcall(function()
				game:GetService("StarterPlayer").AllowCustomAnimations = on
			end)
			if not ok then
				notify("自定义动画", "客户端无权修改 StarterPlayer（服务端属性），已只做刷新", "x")
			end
			refreshAnimate()
			if on then
				notify("自定义动画", "已开启自定义动画包")
			else
				notify("自定义动画", "已关闭自定义动画包")
			end
		end,
	})

	----------------------------------------------------------------------------
	-- 说明（源文件 6493-6506 行 Paragraph，原文照搬）
	----------------------------------------------------------------------------
	v2Sec:Paragraph({
		Title = "说明",
		Desc = [[• 随机跳舞：自动适配 R6/R15
• 鬼畜/甩头：仅 R6 体形
• 自定义动画：输入 ID 和速度播放
• 全局速度调整：影响当前所有动画
• 定住/解冻：暂停/恢复所有动画
• 循环当前动画：将当前动画设为循环
• 刷新动画：重置 Animate 脚本
• 自定义动画包：开启后可使用自定义动画]],
		Image = "info",
		ImageSize = 16,
		Color = Color3.fromRGB(72, 72, 72),
	})

	----------------------------------------------------------------------------
	-- 窗口关闭清理（源文件 6508-6518 行 window:OnClose）
	-- 只做能确定生效的一步：停掉本页动作包自己播的动画。
	-- 源文件那儿还 Stop 了 v10（鬼畜轨道），这里一并处理。
	-- 关闭注册走 ctx.onClose（由调用方统一实现），为 nil 时静默跳过。
	--------------------------------------------------------------------------
	if ctx.onClose then
		ctx.onClose(function()
			stopActionPackageAnim()
			if twitchTrack then
				pcall(function()
					twitchTrack:Stop()
				end)
				twitchTrack = nil
			end
		end)
	end
end
end)()

-- ── 动画包 ──
local buildAnimPack = (function()
return function(win, ctx)
	local notify    = ctx.notify      -- function(title, content[, icon])
	local getChar   = ctx.getChar     -- function(player) -> Character or nil
	local getHum    = ctx.getHum      -- function(player) -> Humanoid or nil
	local readInput = ctx.readInput   -- 本功能没有输入框，声明只为对齐 ctx 约定
	local Players = game:GetService("Players")
	local LP = Players.LocalPlayer

	-- 源 76485：{ key = "Animation", title = "动画包", icon = "user" }
	local tab = win:Tab({ Title = "动画包", Icon = "user" })

	--==============================================================
	-- 源 6523：arg.Tabs.Animation:Section({ Title = "动画控制", Opened = true })
	--==============================================================
	local sec = tab:Section({ Title = "动画控制", Opened = true })

	--==============================================================
	-- 源 6525-6558：fn75(arg2) —— 应用一套动画包
	--   参数形如 { ["idle.Animation1.AnimationId"] = "rbxassetid://891621366", ... }
	--   角色里的结构是：
	--     Animate(LocalScript) > idle / walk / run / jump / climb / fall / swim ...(StringValue)
	--                        > 每个姿态下面挂 Animation 实例
	--   所以 "idle.Animation1.AnimationId" 指的就是
	--     character.Animate.idle.Animation1.AnimationId
	--   也就是说：这套做法是「改写默认 Animate 脚本里各动画的 AnimationId」，
	--   不是挂自定义 Animation / 不是替换 Animate 脚本本身。
	--==============================================================
	local function applyPack(data)
		-- 源里就是 task.spawn 异步跑的，保持一致，避免写属性时卡 UI
		task.spawn(function()
			local char = (getChar and getChar(LP)) or LP.Character
			if not char then
				return
			end
			local animate = char:FindFirstChild("Animate")
			if not animate then
				return
			end

			for path, id in pairs(data) do
				-- 源 6539-6541：按 "." 把路径切开
				local parts = {}
				for seg in string.gmatch(path, "[^.]+") do
					table.insert(parts, seg)
				end

				-- 源 6543-6556：一层一层往下走；中间某一层不存在就整条跳过
				-- （源里用 continue/break 写的，这里等价改写）
				if #parts >= 2 then
					local node = animate
					local ok = true
					for i = 1, #parts - 1 do
						node = node[parts[i]]
						if not node then
							ok = false
							break
						end
					end

					-- 源 6554：v9[tbl8[#tbl8]] = v8
					-- 最后一段固定是 "AnimationId"，直接赋给 Animation 实例的属性
					if ok and node then
						pcall(function()
							node[parts[#parts]] = id
						end)
					end
				end
			end
		end)
	end

	--==============================================================
	-- 源 6560-6864：25 套动画包数据
	--   动画 ID 全部原样照抄，顺序、字段顺序、缺项（比如「无动画」没有 climb）
	--   都跟源文件一致。
	--==============================================================
	local packs = {
		{
			name = "宇航员",                                        -- 源 6562
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://891621366",
				["idle.Animation2.AnimationId"] = "rbxassetid://891633237",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://891667138",
				["run.RunAnim.AnimationId"] = "rbxassetid://891636393",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://891627522",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://891609353",
				["fall.FallAnim.AnimationId"] = "rbxassetid://891617961",
			},
		},
		{
			name = "泡状",                                          -- 源 6574
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://910004836",
				["idle.Animation2.AnimationId"] = "rbxassetid://910009958",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://910034870",
				["run.RunAnim.AnimationId"] = "rbxassetid://910025107",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://910016857",
				["fall.FallAnim.AnimationId"] = "rbxassetid://910001910",
				["swimidle.SwimIdle.AnimationId"] = "rbxassetid://910030921",
				["swim.Swim.AnimationId"] = "rbxassetid://910028158",
			},
		},
		{
			name = "卡通",                                          -- 源 6587
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://742637544",
				["idle.Animation2.AnimationId"] = "rbxassetid://742638445",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://742640026",
				["run.RunAnim.AnimationId"] = "rbxassetid://742638842",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://742637942",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://742636889",
				["fall.FallAnim.AnimationId"] = "rbxassetid://742637151",
			},
		},
		{
			name = "老人",                                          -- 源 6599
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://845397899",
				["idle.Animation2.AnimationId"] = "rbxassetid://845400520",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://845403856",
				["run.RunAnim.AnimationId"] = "rbxassetid://845386501",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://845398858",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://845392038",
				["fall.FallAnim.AnimationId"] = "rbxassetid://845396048",
			},
		},
		{
			name = "骑士",                                          -- 源 6611
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://657595757",
				["idle.Animation2.AnimationId"] = "rbxassetid://657568135",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://657552124",
				["run.RunAnim.AnimationId"] = "rbxassetid://657564596",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://658409194",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://658360781",
				["fall.FallAnim.AnimationId"] = "rbxassetid://657600338",
			},
		},
		{
			name = "悬浮",                                          -- 源 6623
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616006778",
				["idle.Animation2.AnimationId"] = "rbxassetid://616008087",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616013216",
				["run.RunAnim.AnimationId"] = "rbxassetid://616010382",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616008936",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://616003713",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616005863",
			},
		},
		{
			name = "法师",                                          -- 源 6635
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://707742142",
				["idle.Animation2.AnimationId"] = "rbxassetid://707855907",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://707897309",
				["run.RunAnim.AnimationId"] = "rbxassetid://707861613",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://707853694",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://707826056",
				["fall.FallAnim.AnimationId"] = "rbxassetid://707829716",
			},
		},
		{
			name = "忍者",                                          -- 源 6647
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://656117400",
				["idle.Animation2.AnimationId"] = "rbxassetid://656118341",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://656121766",
				["run.RunAnim.AnimationId"] = "rbxassetid://656118852",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://656117878",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://656114359",
				["fall.FallAnim.AnimationId"] = "rbxassetid://656115606",
			},
		},
		{
			name = "海盗",                                          -- 源 6659
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://750781874",
				["idle.Animation2.AnimationId"] = "rbxassetid://750782770",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://750785693",
				["run.RunAnim.AnimationId"] = "rbxassetid://750783738",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://750782230",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://750779899",
				["fall.FallAnim.AnimationId"] = "rbxassetid://750780242",
			},
		},
		{
			name = "机器人",                                        -- 源 6671
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616088211",
				["idle.Animation2.AnimationId"] = "rbxassetid://616089559",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616095330",
				["run.RunAnim.AnimationId"] = "rbxassetid://616091570",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616090535",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://616086039",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616087089",
			},
		},
		{
			name = "时尚",                                          -- 源 6683
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616136790",
				["idle.Animation2.AnimationId"] = "rbxassetid://616138447",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616146177",
				["run.RunAnim.AnimationId"] = "rbxassetid://616140816",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616139451",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://616133594",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616134815",
			},
		},
		{
			name = "超级英雄",                                      -- 源 6695
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616111295",
				["idle.Animation2.AnimationId"] = "rbxassetid://616113536",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616122287",
				["run.RunAnim.AnimationId"] = "rbxassetid://616117076",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616115533",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://616104706",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616108001",
			},
		},
		{
			name = "玩具",                                          -- 源 6707
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://782841498",
				["idle.Animation2.AnimationId"] = "rbxassetid://782845736",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://782843345",
				["run.RunAnim.AnimationId"] = "rbxassetid://782842708",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://782847020",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://782843869",
				["fall.FallAnim.AnimationId"] = "rbxassetid://782846423",
			},
		},
		{
			name = "吸血鬼",                                        -- 源 6719
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1083445855",
				["idle.Animation2.AnimationId"] = "rbxassetid://1083450166",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1083473930",
				["run.RunAnim.AnimationId"] = "rbxassetid://1083462077",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1083455352",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1083439238",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1083443587",
			},
		},
		{
			name = "狼人",                                          -- 源 6731
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1083195517",
				["idle.Animation2.AnimationId"] = "rbxassetid://1083214717",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1083178339",
				["run.RunAnim.AnimationId"] = "rbxassetid://1083216690",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1083218792",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1083182000",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1083189019",
			},
		},
		{
			name = "僵尸",                                          -- 源 6743
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616158929",
				["idle.Animation2.AnimationId"] = "rbxassetid://616160636",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616168032",
				["run.RunAnim.AnimationId"] = "rbxassetid://616163682",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616161997",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://616156119",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616157476",
			},
		},
		{
			name = "巡逻",                                          -- 源 6755
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1149612882",
				["idle.Animation2.AnimationId"] = "rbxassetid://1150842221",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1151231493",
				["run.RunAnim.AnimationId"] = "rbxassetid://1150967949",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1148811837",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1148811837",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1148863382",
			},
		},
		{
			name = "自信",                                          -- 源 6767
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1069977950",
				["idle.Animation2.AnimationId"] = "rbxassetid://1069987858",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1070017263",
				["run.RunAnim.AnimationId"] = "rbxassetid://1070001516",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1069984524",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1069946257",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1069973677",
			},
		},
		{
			name = "明星",                                          -- 源 6779
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1212900985",
				["idle.Animation2.AnimationId"] = "rbxassetid://1150842221",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1212980338",
				["run.RunAnim.AnimationId"] = "rbxassetid://1212980348",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1212954642",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1213044953",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1212900995",
			},
		},
		{
			name = "牛仔",                                          -- 源 6791
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1014390418",
				["idle.Animation2.AnimationId"] = "rbxassetid://1014398616",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1014421541",
				["run.RunAnim.AnimationId"] = "rbxassetid://1014401683",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1014394726",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1014380606",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1014384571",
			},
		},
		{
			name = "鬼",                                            -- 源 6803
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616006778",
				["idle.Animation2.AnimationId"] = "rbxassetid://616008087",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616013216",
				["run.RunAnim.AnimationId"] = "rbxassetid://616013216",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616008936",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616005863",
				["swimidle.SwimIdle.AnimationId"] = "rbxassetid://616012453",
				["swim.Swim.AnimationId"] = "rbxassetid://616011509",
			},
		},
		{
			name = "小偷",                                          -- 源 6816
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1132473842",
				["idle.Animation2.AnimationId"] = "rbxassetid://1132477671",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1132510133",
				["run.RunAnim.AnimationId"] = "rbxassetid://1132494274",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1132489853",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1132461372",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1132469004",
			},
		},
		{
			name = "公主",                                          -- 源 6828
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://941003647",
				["idle.Animation2.AnimationId"] = "rbxassetid://941013098",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://941028902",
				["run.RunAnim.AnimationId"] = "rbxassetid://941015281",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://941008832",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://940996062",
				["fall.FallAnim.AnimationId"] = "rbxassetid://941000007",
			},
		},
		{
			name = "无动画",                                        -- 源 6840（源里这套没有 climb）
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://0",
				["idle.Animation2.AnimationId"] = "rbxassetid://0",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://0",
				["run.RunAnim.AnimationId"] = "rbxassetid://0",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://0",
				["fall.FallAnim.AnimationId"] = "rbxassetid://0",
				["swimidle.SwimIdle.AnimationId"] = "rbxassetid://0",
				["swim.Swim.AnimationId"] = "rbxassetid://0",
			},
		},
		{
			name = "人类（预设）",                                  -- 源 6853
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://2510196951",
				["idle.Animation2.AnimationId"] = "rbxassetid://2510197257",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://2510202577",
				["run.RunAnim.AnimationId"] = "rbxassetid://2510198475",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://2510197830",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://2510192778",
				["fall.FallAnim.AnimationId"] = "rbxassetid://2510195892",
			},
		},
	}

	-- 源 6853 / 6906：恢复默认用的就是这一套
	local DEFAULT_PACK = "人类（预设）"

	-- 源 6866-6872：把每套的 name 抽出来当下拉列表
	local names = {}
	for _, pack in ipairs(packs) do
		table.insert(names, pack.name)
	end

	local selected = names[1] or ""

	--==============================================================
	-- 源 6874-6881：v7:Dropdown({ Title = "选择动画风格", Values = tbl9,
	--                            Value = str, Callback = function(arg2) str = arg2 end })
	--   列表是固定的 25 套，运行时不增删，所以用 Dropdown 而不是 Input。
	--==============================================================
	local styleDropdown = sec:Dropdown({
		Title = "选择动画风格",
		Values = names,
		Value = selected,
		Callback = function(v)
			selected = v
		end,
	})

	-- 源 6908：v8:SetValue("人类（预设）")
	--   黑白那套的 Dropdown 有 SetValue，Boreal 的元素上只有 Select
	--   （以及 DropdownMenu:Set），两个都会同步显示并触发 Callback，
	--   所以这里按 Boreal 实际提供的方法写。
	local function setDropdown(dd, value)
		if not dd then
			return
		end
		pcall(function()
			if dd.Select then
				dd:Select(value)
			elseif dd.DropdownMenu and dd.DropdownMenu.Set then
				dd.DropdownMenu:Set(value, true)
			end
		end)
	end

	local function findPack(name)
		for _, pack in ipairs(packs) do
			if pack.name == name then
				return pack
			end
		end
		return nil
	end

	--==============================================================
	-- 源 6883-6900：应用动画
	--   源里是遍历 tbl8 找同名项，找到就 fn75(v9.data) 然后提示；
	--   源 6894 的提示漏了动画名（fn13("动画", "已应用: ")），这里补上。
	--==============================================================
	sec:Button({
		Title = "应用动画",
		Desc = "把选中的动画风格写进角色的 Animate 脚本",
		Icon = "check",
		Callback = function()
			if selected == "" then
				notify("提示", "请先选择一个动画")
				return
			end

			-- 源里没有这层检查，补上是为了给出明确提示
			if not getChar(LP) or (getHum and not getHum(LP)) then
				notify("错误", "角色未加载，无法应用动画", "x")
				return
			end

			local pack = findPack(selected)
			if not pack then
				notify("错误", "找不到这套动画", "x")
				return
			end

			applyPack(pack.data)
			notify("动画", "已应用: " .. pack.name)
		end,
	})

	--==============================================================
	-- 源 6902-6917：恢复默认（人类）
	--   源里没有单独的「刷新动画」按钮；这个按钮同时做了两件事：
	--   1) 应用「人类（预设）」那套 ID
	--   2) v8:SetValue("人类（预设）") 把下拉框选中项拉回来（即刷新显示）
	--   注意：源和这里都不处理角色重生，重生后需要再点一次。
	--==============================================================
	sec:Button({
		Title = "恢复默认（人类）",
		Desc = "换回 Roblox 默认的人类动画",
		Icon = "undo",
		Variant = "Secondary",
		Callback = function()
			local pack = findPack(DEFAULT_PACK)
			if not pack then
				notify("错误", "缺少「人类（预设）」数据", "x")
				return
			end

			applyPack(pack.data)
			selected = DEFAULT_PACK
			setDropdown(styleDropdown, DEFAULT_PACK)
			notify("动画", "已恢复为默认人类动画")
		end,
	})

	notify("动画包", "已加载")
end
end)()

-- ── 自动连点器 ──
local buildAutoClicker = (function()
--==============================================================
-- 黑白提取 · 自动连点器
-- 对应源文件 .tmp/黑白/黑白-MAIN.可运行版.lua（都在 fn84 里，fn84 = 8353-9048 行）
--   UI 注册：8623-8654 行（local clicker = arg.Tabs.Clicker）
--   参数设置：8624-8652 行（n3 点击间隔 0.5 / n4 按下时长 0.01）
--   悬浮面板：8659-9020 行（fn85，ScreenGui "AutoClicker_Classic" 见 8687）
--   关闭清理：9022-9034 行（fn86）
--   启动开关：9036-9047 行（Toggle "GUI 开关"）
-- 说明：该功能不是 loadstring(game:HttpGet(...))() 远程加载，是完整本地实现。
--==============================================================
return function(win, ctx)
	local notify    = ctx.notify    -- function(title, content[, icon])
	local readInput = ctx.readInput -- function(element) -> string
	local Players   = game:GetService("Players")
	local LP        = Players.LocalPlayer
	-- 连点器只跟鼠标/输入有关，用不到 ctx.getChar / ctx.getHum

	local VirtualInputManager = game:GetService("VirtualInputManager")
	local UserInputService    = game:GetService("UserInputService")
	local HttpService         = game:GetService("HttpService")
	local CoreGui             = game:GetService("CoreGui")

	local unpackFn = table.unpack or unpack

	--==============================================================
	-- 参数：对应源文件 8625-8626 行（local n3 = 0.5 / local n4 = 0.01）
	--==============================================================
	local clickInterval = 0.5  -- n3：两次点击之间的间隔（秒）
	local pressDuration = 0.01 -- n4：每次按下保持的时间（秒）

	-- 源 8858-8859 行给点击坐标硬编码了 +35 / +50，那是为了补偿
	-- CoreGui 顶栏内缩（它的 ScreenGui 没开 IgnoreGuiInset）。
	-- 这里让 ScreenGui 开 IgnoreGuiInset，AbsolutePosition 就直接等于
	-- VirtualInputManager 需要的视口坐标，偏移留 0；若在你的执行器里
	-- 点击位置整体偏了，改这两个常量即可。
	local CLICK_OFFSET_X = 0
	local CLICK_OFFSET_Y = 0

	local PANEL_TRANSPARENCY = 0.2 -- 源 8671 行 backgroundTransparency
	local DOT_TRANSPARENCY   = 0.9 -- 源 8672 行 backgroundTransparency2

	-- 源 8674-8684 行 tbl10：悬浮面板用到的图标资源 id
	local ICONS = {
		Remove   = "rbxassetid://122610572797061",
		Start    = "rbxassetid://128832474920642",
		Stop     = "rbxassetid://113047868752296",
		Add      = "rbxassetid://80871366492449",
		Show     = "rbxassetid://89558029527587",
		Hidden   = "rbxassetid://82900330630483",
		Drag     = "rbxassetid://139381026962112",
		Delete   = "rbxassetid://105775511743927",
		Settings = "rbxassetid://70541424009556",
	}

	-- 源 8980-8990 行用的执行器文件 API，路径同源文件
	local SAVE_FOLDER = "黑白脚本"
	local SAVE_FILE   = SAVE_FOLDER .. "/自动点击器.txt"

	local function fileExists(path)
		return type(isfile) == "function" and isfile(path)
	end

	-- 源 8860 / 8862 行：VirtualInputManager:SendMouseButtonEvent
	-- 部分执行器屏蔽了 VirtualInputManager，用鼠标函数兜底
	local function sendClick(x, y, isDown)
		local ok = pcall(function()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, isDown, game, 1)
		end)
		if ok then
			return true
		end
		if isDown then
			if type(mousemoveabs) == "function" then
				pcall(mousemoveabs, x, y)
			end
			if type(mouse1down) == "function" then
				pcall(mouse1down)
			end
		else
			if type(mouse1up) == "function" then
				pcall(mouse1up)
			end
		end
		return false
	end

	--==============================================================
	-- UI 骨架：Tab -> 参数设置 / 启动
	--==============================================================
	local tab = win:Tab({ Title = "自动连点器", Icon = "mouse" })

	-- 对应源 8624-8652 行：clicker:Section({Title = "参数设置"}) 里的两个 Input
	local paramSec = tab:Section({ Title = "参数设置", Opened = true })

	local intervalInput, durationInput -- 先声明，下面的 Callback 才能安全闭包引用

	intervalInput = paramSec:Input({
		Title = "点击间隔延迟（秒）",
		Placeholder = "0.5",
		Value = "0.5",
		Callback = function(v)
			-- 源 8632-8638：local num = tonumber(arg2); if num and num > 0 then n3 = num end
			local num = tonumber(v) or tonumber(readInput(intervalInput))
			if num and num > 0 then
				clickInterval = num
			end
		end,
	})

	durationInput = paramSec:Input({
		Title = "按下持续时间（秒）",
		Placeholder = "0.01",
		Value = "0.01",
		Callback = function(v)
			-- 源 8645-8651：local num = tonumber(arg2); if num and num >= 0 then n4 = num end
			local num = tonumber(v) or tonumber(readInput(durationInput))
			if num and num >= 0 then
				pressDuration = num
			end
		end,
	})

	tab:Divider()

	-- 对应源 8654 行：clicker:Section({Title = "启动"})
	local startSec = tab:Section({ Title = "启动", Opened = true })

	startSec:Paragraph({
		Title = "开启后屏幕左侧出现连点器悬浮面板",
		Desc = "加号=添加点位，减号=删除最后一个点位，垃圾桶=关闭面板；\n圆点可以直接拖动到要连点的位置。",
		Image = "mouse-pointer-click",
		ImageSize = 16,
		Color = Color3.fromRGB(72, 72, 72),
	})

	--==============================================================
	-- 悬浮面板状态
	--   screenGui   <- 源 v9
	--   dragConns   <- 源 tbl8（所有拖拽连接）
	--   dots        <- 源 tbl9（所有点位）
	--   running     <- 源 flag7（是否正在连点）
	--==============================================================
	local screenGui   = nil
	local dragConns   = {}
	local dots        = {}
	local running     = false
	local dotsVisible = true -- 源 8670 行 visible

	-- 对应源 8659-9020 行的 fn85()：建出整个悬浮连点面板
	local function buildPanel()
		if screenGui then
			return -- 源 8660-8662：已经建过就直接返回
		end

		local gui = Instance.new("ScreenGui")
		gui.Name = "AutoClicker_Classic" -- 源 8687
		gui.ResetOnSpawn = false         -- 源 8688
		gui.IgnoreGuiInset = true        -- 见上面 CLICK_OFFSET 注释（源里没写，靠 +35/+50 硬补）

		pcall(function()
			gui.Parent = CoreGui -- 源 8690-8692
		end)
		if not gui.Parent then
			gui.Parent = LP:WaitForChild("PlayerGui") -- 源 8694-8696
		end

		screenGui = gui
		dots = {}
		dragConns = {}
		dotsVisible = true

		-- 源 8699-8714：左侧竖条工具面板 MainPanel
		local mainPanel = Instance.new("Frame")
		mainPanel.Name = "MainPanel"
		mainPanel.Parent = gui
		mainPanel.BackgroundColor3 = Color3.new(1, 1, 1)
		mainPanel.BackgroundTransparency = PANEL_TRANSPARENCY
		mainPanel.Position = UDim2.new(0, 16, 0, 34)
		mainPanel.Size = UDim2.new(0, 30, 0, 204)
		mainPanel.BorderSizePixel = 0
		local corner1 = Instance.new("UICorner")
		corner1.CornerRadius = UDim.new(0, 2)
		corner1.Parent = mainPanel
		local layout1 = Instance.new("UIListLayout")
		layout1.Parent = mainPanel
		layout1.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout1.Padding = UDim.new(0, 2)
		layout1.SortOrder = Enum.SortOrder.LayoutOrder

		-- 源 8715-8731：设置小窗 SettingsUI（保存/清空保存）
		local settingsPanel = Instance.new("Frame")
		settingsPanel.Name = "SettingsUI"
		settingsPanel.Parent = gui
		settingsPanel.BackgroundColor3 = Color3.new(1, 1, 1)
		settingsPanel.BackgroundTransparency = PANEL_TRANSPARENCY
		settingsPanel.Position = UDim2.new(0.5, -100, 0.5, -75)
		settingsPanel.Size = UDim2.new(0, 200, 0, 150)
		settingsPanel.Visible = false
		settingsPanel.BorderSizePixel = 0
		local corner2 = Instance.new("UICorner")
		corner2.CornerRadius = UDim.new(0, 2)
		corner2.Parent = settingsPanel
		local layout2 = Instance.new("UIListLayout")
		layout2.Parent = settingsPanel
		layout2.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout2.Padding = UDim.new(0, 10)
		layout2.SortOrder = Enum.SortOrder.LayoutOrder

		-- 对应源 8733-8762 行的 fn86(arg2, arg3)：给 GuiObject 加鼠标/触摸拖拽
		-- 源里把同一个连接重复插入了两次（8756-8761），这里只连一次
		local function makeDraggable(target, handle)
			handle = handle or target
			local states = {} -- 源 tbl11：按输入对象记录拖拽起点

			local function onBegan(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					states[input] = {
						object = target,
						startPos = target.Position,
						dragStart = input.Position,
						isDragging = true,
					}
				end
			end

			local function onEnded(input)
				if states[input] and states[input].object == target then
					states[input] = nil
				end
			end

			local function onChanged(input)
				local s = states[input]
				if s and s.isDragging then
					local delta = input.Position - s.dragStart
					target.Position = UDim2.new(
						s.startPos.X.Scale, s.startPos.X.Offset + delta.X,
						s.startPos.Y.Scale, s.startPos.Y.Offset + delta.Y
					)
				end
			end

			table.insert(dragConns, handle.InputBegan:Connect(onBegan))
			table.insert(dragConns, handle.InputEnded:Connect(onEnded))
			table.insert(dragConns, UserInputService.InputChanged:Connect(onChanged))
		end

		makeDraggable(settingsPanel) -- 源 8764
		makeDraggable(mainPanel)     -- 源 8765

		-- 对应源 8767-8778 行的 createImageButton
		local function createImageButton(name, image, layoutOrder, scale)
			local btn = Instance.new("ImageButton")
			btn.Name = name
			btn.Parent = mainPanel
			btn.BackgroundTransparency = 1
			btn.Image = image
			btn.ImageColor3 = Color3.new(0, 0, 0)
			btn.LayoutOrder = layoutOrder
			local size = (name == "EyeBtn" and 20 or 24) * (scale or 1)
			btn.Size = UDim2.new(0, size, 0, size)
			return btn
		end

		-- 对应源 8780-8787 行的 fn87：工具条里的间距占位
		local function createSpacer(height, layoutOrder)
			local spacer = Instance.new("Frame")
			spacer.Name = "Spacer"
			spacer.Parent = mainPanel
			spacer.BackgroundTransparency = 1
			spacer.Size = UDim2.new(0, 24, 0, height)
			spacer.LayoutOrder = layoutOrder
			return spacer
		end

		-- 源 8789-8799：工具条按钮（DragBtn 源里只是个拖拽手柄图标，没接事件，
		-- 因为整条面板本身已经可以拖了，这里保持一致）
		local PlayBtn = createImageButton("PlayBtn", ICONS.Start, 1, 1)
		local AddBtn = createImageButton("AddBtn", ICONS.Add, 2, 1)
		local RemoveBtn = createImageButton("RemoveBtn", ICONS.Remove, 3, 1)
		createSpacer(6, 4)
		local SettingsBtn = createImageButton("SettingsBtn", ICONS.Settings, 5, 0.6)
		createSpacer(6, 6)
		local EyeBtn = createImageButton("EyeBtn", ICONS.Show, 7, 1)
		createSpacer(6, 8)
		createImageButton("DragBtn", ICONS.Drag, 9, 0.6)
		createSpacer(6, 10)
		local DeleteBtn = createImageButton("DeleteBtn", ICONS.Delete, 11, 0.5)

		-- 对应源 8801-8837 行的 createImageLabel(index, pos)：一个可拖动的点击点位
		local function createDot(index, savedPos)
			local dot = Instance.new("ImageLabel")
			dot.Name = "ClickDot"
			dot.Parent = gui
			dot.BackgroundColor3 = Color3.new(1, 1, 1)
			dot.BackgroundTransparency = DOT_TRANSPARENCY
			dot.Size = UDim2.new(0, 20, 0, 20)
			dot.Visible = dotsVisible
			dot.Active = false
			local corner3 = Instance.new("UICorner")
			corner3.CornerRadius = UDim.new(1, 0)
			corner3.Parent = dot

			local icon = Instance.new("ImageLabel")
			icon.Name = "Icon"
			icon.Parent = dot
			icon.Image = "rbxassetid://110626268563466"
			icon.Size = UDim2.new(0, 30, 0, 30)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.BackgroundTransparency = 1

			local label = Instance.new("TextLabel")
			label.Parent = dot
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.Text = tostring(index)
			label.Font = Enum.Font.GothamBold
			label.TextSize = 16

			if savedPos then
				-- 源 8829-8830：存档里的位置
				dot.Position = UDim2.new(unpackFn(savedPos))
			else
				-- 源 8832：默认在屏幕中间按 5 个一行排开
				dot.Position = UDim2.new(
					0.5, (index - 1) % 5 * 40 - 80,
					0.5, math.floor((index - 1) / 5) * 40 - 40
				)
			end

			makeDraggable(dot) -- 源 8835
			return dot
		end

		-- 复位工具条外观（源 8877-8885 / 8889-8895 两处重复的收尾逻辑）
		local function resetPanelLook()
			if not mainPanel.Parent then
				return
			end
			mainPanel.BackgroundColor3 = Color3.new(1, 1, 1)
			mainPanel.BackgroundTransparency = PANEL_TRANSPARENCY
			PlayBtn.Image = ICONS.Start
			for _, dot in ipairs(dots) do
				dot.BackgroundTransparency = DOT_TRANSPARENCY
			end
		end

		-- 对应源 8839-8897 行：PlayBtn 开始/停止连点
		PlayBtn.MouseButton1Click:Connect(function()
			running = not running -- 源 8840

			if running then
				mainPanel.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
				mainPanel.BackgroundTransparency = PANEL_TRANSPARENCY + 0.5
				PlayBtn.Image = ICONS.Stop

				for _, dot in ipairs(dots) do
					dot.BackgroundTransparency = DOT_TRANSPARENCY + 0.2
				end

				task.spawn(function()
					-- 对应源 8851-8875 行的 while flag7 do ... end
					-- 源里用了 continue / break（Luau 语法），这里改写成等价的普通循环
					while running do
						if #dots == 0 then
							break
						end
						for _, dot in ipairs(dots) do
							if not running then
								break
							end
							local absPos = dot.AbsolutePosition
							local absSize = dot.AbsoluteSize
							local x = absPos.X + absSize.X / 2 + CLICK_OFFSET_X
							local y = absPos.Y + absSize.Y / 2 + CLICK_OFFSET_Y
							sendClick(x, y, true)
							task.wait(pressDuration)
							sendClick(x, y, false)
							task.wait(clickInterval)
						end
						if running then
							task.wait()
						end
					end

					resetPanelLook() -- 源 8877-8885
					running = false
				end)
			else
				resetPanelLook() -- 源 8887-8896
			end
		end)

		-- 源 8899-8902：添加点位
		AddBtn.MouseButton1Click:Connect(function()
			local dot = createDot(#dots + 1)
			table.insert(dots, dot)
		end)

		-- 源 8904-8910：删除最后一个点位
		RemoveBtn.MouseButton1Click:Connect(function()
			local dot = table.remove(dots)
			if dot then
				dot:Destroy()
			end
		end)

		-- 源 8912-8914：展开/收起设置小窗
		SettingsBtn.MouseButton1Click:Connect(function()
			settingsPanel.Visible = not settingsPanel.Visible
		end)

		-- 源 8916-8935：清空全部并关掉面板
		DeleteBtn.MouseButton1Click:Connect(function()
			running = false
			for i = #dots, 1, -1 do
				if dots[i] then
					dots[i]:Destroy()
					table.remove(dots, i)
				end
			end
			dots = {}
			gui:Destroy()
			for _, conn in ipairs(dragConns) do
				conn:Disconnect()
			end
			dragConns = {}
			screenGui = nil
		end)

		-- 源 8937-8944：显示/隐藏所有点位
		EyeBtn.MouseButton1Click:Connect(function()
			dotsVisible = not dotsVisible
			EyeBtn.Image = dotsVisible and ICONS.Show or ICONS.Hidden
			for _, dot in ipairs(dots) do
				dot.Visible = dotsVisible
			end
		end)

		-- 对应源 8946-8963 行的 createTextButton
		local function createTextButton(name, layoutOrder, callback)
			local btn = Instance.new("TextButton")
			btn.Name = name
			btn.Parent = settingsPanel
			btn.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
			btn.BackgroundTransparency = 0.1
			btn.Size = UDim2.new(0, 180, 0, 40)
			btn.Font = Enum.Font.GothamSemibold
			btn.Text = name
			btn.TextSize = 14
			btn.TextColor3 = Color3.new(0, 0, 0)
			btn.LayoutOrder = layoutOrder
			local corner4 = Instance.new("UICorner")
			corner4.CornerRadius = UDim.new(0, 2)
			corner4.Parent = btn
			btn.MouseButton1Click:Connect(callback)
			return btn
		end

		-- 源 8965-8985：把面板位置 + 所有点位位置存到执行器文件
		createTextButton("保存位置", 1, function()
			if type(writefile) ~= "function" then
				notify("自动连点器", "当前执行器不支持 writefile，无法保存", "x")
				return
			end
			local dotData = {}
			for i, dot in ipairs(dots) do
				dotData[i] = {
					Position = {
						dot.Position.X.Scale, dot.Position.X.Offset,
						dot.Position.Y.Scale, dot.Position.Y.Offset,
					},
				}
			end
			local payload = {
				panelPosition = {
					mainPanel.Position.X.Scale, mainPanel.Position.X.Offset,
					mainPanel.Position.Y.Scale, mainPanel.Position.Y.Offset,
				},
				settingsPosition = {
					settingsPanel.Position.X.Scale, settingsPanel.Position.X.Offset,
					settingsPanel.Position.Y.Scale, settingsPanel.Position.Y.Offset,
				},
				dotData = dotData,
			}
			local ok = pcall(function()
				if type(isfolder) == "function" and not isfolder(SAVE_FOLDER) then
					makefolder(SAVE_FOLDER) -- 源 8980-8982
				end
				writefile(SAVE_FILE, HttpService:JSONEncode(payload)) -- 源 8984
			end)
			if ok then
				notify("自动连点器", "已保存 " .. tostring(#dots) .. " 个点位", "check")
			else
				notify("自动连点器", "保存失败（执行器文件 API 不可用）", "x")
			end
		end)

		-- 源 8987-8991：清空存档
		createTextButton("清空保存", 2, function()
			if fileExists(SAVE_FILE) and type(delfile) == "function" then
				pcall(delfile, SAVE_FILE)
				notify("自动连点器", "已清空保存", "check")
			else
				notify("自动连点器", "没有可清空的存档", "x")
			end
		end)

		-- 对应源 8993-9016 行的 fn88()：读存档，还原面板/点位位置
		local function loadSaved()
			if not fileExists(SAVE_FILE) or type(readfile) ~= "function" then
				return
			end
			local ok, data = pcall(function()
				return HttpService:JSONDecode(readfile(SAVE_FILE))
			end)
			if not ok or type(data) ~= "table" then
				return
			end
			if data.panelPosition then
				mainPanel.Position = UDim2.new(unpackFn(data.panelPosition)) -- 源 9000-9002
			end
			if data.settingsPosition then
				settingsPanel.Position = UDim2.new(unpackFn(data.settingsPosition)) -- 源 9004-9006
			end
			if data.dotData then
				for i, info in ipairs(data.dotData) do -- 源 9008-9013
					table.insert(dots, createDot(i, info.Position))
				end
			end
		end

		loadSaved()        -- 源 9018
		gui.Enabled = true -- 源 9019
	end

	-- 对应源 9022-9034 行的 fn86()：关闭悬浮面板并清理连接
	local function destroyPanel()
		if not screenGui then
			return
		end
		running = false
		for _, conn in ipairs(dragConns) do
			pcall(function()
				conn:Disconnect()
			end)
		end
		dragConns = {}
		for _, dot in ipairs(dots) do
			pcall(function()
				dot:Destroy()
			end)
		end
		dots = {}
		screenGui:Destroy()
		screenGui = nil
	end

	-- 对应源 9036-9047 行的 Toggle "GUI 开关"
	startSec:Toggle({
		Title = "GUI 开关",
		Desc = "显示/隐藏自动连点器界面",
		Value = false,
		Callback = function(on)
			if on then
				buildPanel()
				if screenGui then
					notify("自动连点器", "面板已开启：拖动圆点选位置，点绿色三角开始连点", "check")
				else
					notify("自动连点器", "面板创建失败", "x")
				end
			else
				destroyPanel()
				notify("自动连点器", "已关闭连点器面板")
			end
		end,
	})

	--==========================================================
	-- 关闭清理：源 8597-8621 行的 window:OnClose 只收掉了 ObjectCtrl 的东西，
	-- 悬浮连点器没人管；这里统一交给 ctx.onClose（由调用方实现，nil 时静默跳过）。
	--==========================================================
	-- 关面板时顺手把悬浮连点器也收掉，避免窗口关了它还在屏幕上
	if ctx.onClose then
		ctx.onClose(destroyPanel)
	end
end
end)()

-- ── NPC交互 ──
local buildNPC = (function()
--==============================================================
-- 黑白提取 · NPC交互
-- 对应源文件 .tmp/黑白/黑白-MAIN.可运行版.lua
--   UI 注册：7755-7780 行（local npc = arg.Tabs.NPC）
--   逻辑闭包：1867-2503 行（tbl6 状态表 1871-1878，工具函数 fn48-fn54 1907-1967，
--             NPC 功能 fn23-fn46 1969-2502）
--==============================================================
return function(win, ctx)
	local notify = ctx.notify -- function(title, content[, icon])
	local getChar = ctx.getChar -- function(player) -> Character or nil
	local readInput = ctx.readInput -- function(element) -> string
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local Workspace = game:GetService("Workspace")
	local LP = Players.LocalPlayer

	local cam = Workspace.CurrentCamera
	local playerGui = LP:WaitForChild("PlayerGui")

	--==========================================================
	-- 状态表：对应源 1871-1878 的 tbl6 + 1880-1883 的 flag6/v6/flag7/highlight2
	--==========================================================
	local state = {
		selected = nil, -- 源 tbl6.selected：下拉框选中的 NPC 名字
		loopTp = false, -- 源 tbl6.loopTp
		loopTpToMe = false, -- 源 tbl6.loopTpToMe
		loopAll = false, -- 源 tbl6.loopAll
		lookNPC = false, -- 源 tbl6.lookNPC
		aimbot = false, -- 源 tbl6.aimbot
		clickSelect = false, -- 源 flag6
		lockSelect = false, -- 源 flag7
	}

	local clickedNPC = nil -- 源 v6：鼠标点中的 NPC 模型（第二套选中状态）
	local highlight = nil -- 源 highlight2（fn47 创建）
	local savedChar = nil -- 源 character：控制NPC 前的自己角色

	local conn = {} -- 统一存放所有连接，方便关闭时断开
	local function put(c)
		table.insert(conn, c)
		return c
	end

	--==========================================================
	-- 工具函数：对应源 fn48-fn54（1907-1967）
	--==========================================================

	-- 源 fn48：NPC 判定 —— Model + 不是玩家角色 + 有存活 Humanoid + 有 Head/HumanoidRootPart/PrimaryPart
	local function isNPC(model)
		if not model or not model:IsA("Model") then
			return false
		end
		if Players:GetPlayerFromCharacter(model) then
			return false
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not (hum and hum.Health > 0) then
			return false
		end
		return (model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) ~= nil
	end

	-- 源 fn49：给 NPC 起个展示名（Humanoid.DisplayName 优先）
	local function npcName(model)
		if not model then
			return "未知NPC"
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.DisplayName ~= "" then
			return hum.DisplayName
		end
		return model.Name
	end

	-- 源 fn50：通知（源里是 v:Notify）
	local function tip(msg)
		notify("NPC交互", msg)
	end

	-- 源 fn51：收集当前场景所有 NPC 的名字
	local function listNPCNames()
		local names = {}
		for _, d in ipairs(Workspace:GetDescendants()) do
			if isNPC(d) then
				table.insert(names, d.Name)
			end
		end
		return names
	end

	-- 源 fn52：按名字在 workspace 里找 NPC（源只返回第一个匹配）
	local function findNPCByName(name)
		if not name or name == "" then
			return nil
		end
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d.Name == name and isNPC(d) then
				return d
			end
		end
		return nil
	end

	-- 源 fn53：自己的 HumanoidRootPart
	local function myRoot()
		local ch = getChar(LP)
		return ch and ch:FindFirstChild("HumanoidRootPart") or nil
	end

	-- 源 fn54：取 NPC 的可操作部件（HumanoidRootPart 优先，其次 PrimaryPart）
	local function npcPart(model)
		if not model then
			return nil
		end
		return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	end

	-- 源 fn47（1885-1895）：给选中的 NPC 加一个绿色描边高亮（源挂在 PlayerGui，这里照旧）
	local function getHighlight()
		if highlight and highlight.Parent then
			return highlight
		end
		highlight = Instance.new("Highlight")
		highlight.Name = "NPCControlHighlight_" .. tostring(tick())
		highlight.FillTransparency = 1
		highlight.OutlineColor = Color3.fromRGB(0, 255, 0)
		highlight.Parent = playerGui
		return highlight
	end

	-- 源 fn32 里的选中逻辑（2154-2160）
	local function selectClicked(model)
		clickedNPC = model
		getHighlight().Adornee = model
		tip("已选择: " .. npcName(model))
	end

	-- 统一取「当前操作的 NPC」：优先鼠标点中的，其次下拉框/输入框选中的（源里这两套是分开的）
	local function currentNPC()
		if clickedNPC and clickedNPC.Parent and isNPC(clickedNPC) then
			return clickedNPC
		end
		return findNPCByName(state.selected)
	end

	--==========================================================
	-- 循环/连接管理（源里是 task.spawn + while tbl6.xxx do，这里改成可关的 while state.xxx do）
	--==========================================================
	local loopTpJob, loopTpToMeJob, loopAllJob, aimJob = nil, nil, nil, nil
	local connClick, connPull, connTpHead, connCtrl, connFollow, connKillAura, connFreezeAura = nil, nil, nil, nil, nil, nil, nil

	local function stopAll()
		for _, c in ipairs(conn) do
			pcall(function()
				c:Disconnect()
			end)
		end
		conn = {}
		loopTpJob, loopTpToMeJob, loopAllJob, aimJob = nil, nil, nil, nil
		connClick, connPull, connTpHead, connCtrl, connFollow, connKillAura, connFreezeAura = nil, nil, nil, nil, nil, nil, nil
		state.loopTp, state.loopTpToMe, state.loopAll, state.lookNPC, state.aimbot = false, false, false, false, false
		if highlight then
			pcall(function()
				highlight:Destroy()
			end)
			highlight = nil
		end
		-- 恢复视角与角色（源里关闭窗口时没有做这一步，属于补强：见 8033-8035 只清了碰撞箱）
		if cam then
			local hum = getChar(LP) and getChar(LP):FindFirstChildOfClass("Humanoid")
			if hum then
				cam.CameraSubject = hum
			end
		end
	end

	--==========================================================
	-- UI
	--==========================================================
	local npcTab = win:Tab({ Title = "NPC交互", Icon = "server" })

	-- ---- 源 7756-7764：下拉框版选中 + 传送/拉取/视角/瞄准 ----
	local pickSec = npcTab:Section({ Title = "选择与传送", Opened = true })

	-- 源 7756：npc:Dropdown({Title="选择NPC", Callback=fn23})
	-- Boreal 的 Dropdown 没有运行时替换 Values 的方法（源 7757「刷新NPC列表」用的是 SetValues），
	-- 所以这里 Value 列表是建面板那一刻的快照；要重新扫描请点下面「重建下拉框」。
	local npcDropdown = pickSec:Dropdown({
		Title = "选择NPC",
		Values = listNPCNames(),
		Value = nil,
		Callback = function(v)
			-- 源 fn23（1969-1972）
			state.selected = v
			tip("已选择: " .. tostring(v))
		end,
	})

	-- 源 7757：npc:Button({Title="刷新NPC列表", Callback=fn24})
	-- 【等价改写】Boreal 没有 SetValues/Refresh，改成：Input 填名字 + 重建下拉框
	local npcNameInput = pickSec:Input({
		Title = "NPC 名字（替代下拉框）",
		Placeholder = "例：Dummy",
		Value = "",
	})

	pickSec:Button({
		Title = "使用输入框的NPC",
		Desc = "把输入框里的名字设为当前选中的NPC",
		Icon = "check",
		Callback = function()
			local name = tostring(readInput(npcNameInput) or "")
			if name == "" then
				tip("请先填 NPC 名字")
				return
			end
			if not findNPCByName(name) then
				tip("找不到这个NPC: " .. name)
				return
			end
			state.selected = name
			tip("已选择: " .. name)
		end,
	})

	-- Boreal 重建下拉框只有一条路：把旧的 Destroy 掉再在同一个 Section 里新建一个。
	-- 下面是明确的「重建」实现（源 fn24 的等价物），重建后重新绑定 Callback。
	local function rebuildDropdown()
		local values = listNPCNames()
		local ok = pcall(function()
			npcDropdown:Destroy()
		end)
		if not ok then
			-- 万一 Destroy 不可用，就只提示，避免报错中断
			tip("Dropdown:Destroy() 不可用，无法重建（当前共 " .. tostring(#values) .. " 个NPC）")
			return
		end
		npcDropdown = pickSec:Dropdown({
			Title = "选择NPC",
			Values = values,
			Value = state.selected,
			Callback = function(v)
				state.selected = v
				tip("已选择: " .. tostring(v))
			end,
		})
		tip("NPC列表已刷新（" .. tostring(#values) .. " 个）")
	end

	pickSec:Button({
		Title = "刷新NPC列表",
		Desc = "重新扫描 workspace 并重建下拉框",
		Icon = "refresh-cw",
		Callback = function()
			rebuildDropdown()
		end,
	})

	pickSec:Divider()

	-- 源 7758：npc:Button({Title="传送到NPC", Callback=fn25})
	pickSec:Button({
		Title = "传送到NPC",
		Desc = "传送到下拉框/输入框选中的NPC身旁",
		Icon = "arrow-right-to-bracket",
		Callback = function()
			-- 源 fn25（1998-2009）
			local me = myRoot()
			local part = npcPart(findNPCByName(state.selected))
			if me and part then
				me.CFrame = part.CFrame + Vector3.new(0, 3, 0)
				tip("传送成功")
			else
				tip("无效NPC")
			end
		end,
	})

	-- 源 7759：npc:Toggle({Title="循环传送至NPC", Value=tbl6.loopTp, Callback=fn26})
	-- 源 2015-2029 是 while tbl6.loopTp do 的常驻协程，这里改成 Toggle 控制的可关闭循环
	pickSec:Toggle({
		Title = "循环传送至NPC",
		Desc = "持续把自己传送到选中NPC身旁",
		Value = false,
		Callback = function(on)
			state.loopTp = on
			tip("循环传送" .. (on and "开启" or "关闭"))
			if on then
				if loopTpJob then
					return
				end
				loopTpJob = task.spawn(function()
					while state.loopTp do
						local me = myRoot()
						local part = npcPart(findNPCByName(state.selected))
						if me and part then
							me.CFrame = part.CFrame + Vector3.new(0, 3, 0)
						end
						task.wait(0.05)
					end
					loopTpJob = nil
				end)
			end
		end,
	})

	-- 源 7760：npc:Button({Title="NPC传送到我", Callback=fn27})
	pickSec:Button({
		Title = "NPC传送到我",
		Desc = "把选中的NPC拉到自己身旁",
		Icon = "arrow-left-to-bracket",
		Callback = function()
			-- 源 fn27（2032-2043）
			local me = myRoot()
			local part = npcPart(findNPCByName(state.selected))
			if me and part then
				part.CFrame = me.CFrame + Vector3.new(0, 3, 0)
				tip("已拉取NPC")
			else
				tip("无效NPC")
			end
		end,
	})

	-- 源 7761：npc:Toggle({Title="循环拉取NPC", Value=tbl6.loopTpToMe, Callback=fn28})
	pickSec:Toggle({
		Title = "循环拉取NPC",
		Desc = "持续把选中NPC拉到自己身旁",
		Value = false,
		Callback = function(on)
			state.loopTpToMe = on
			tip("循环拉取" .. (on and "开启" or "关闭"))
			if on then
				if loopTpToMeJob then
					return
				end
				loopTpToMeJob = task.spawn(function()
					while state.loopTpToMe do
						local me = myRoot()
						local part = npcPart(findNPCByName(state.selected))
						if me and part then
							part.CFrame = me.CFrame + Vector3.new(0, 3, 0)
						end
						task.wait(0.05)
					end
					loopTpToMeJob = nil
				end)
			end
		end,
	})

	-- 源 7762：npc:Toggle({Title="吸全部NPC", Value=tbl6.loopAll, Callback=fn29})
	pickSec:Toggle({
		Title = "吸全部NPC",
		Desc = "把所有NPC吸到自己身前",
		Icon = "users",
		Value = false,
		Callback = function(on)
			state.loopAll = on
			tip("吸全部NPC" .. (on and "开启" or "关闭"))
			if on then
				if loopAllJob then
					return
				end
				loopAllJob = task.spawn(function()
					while state.loopAll do
						local me = myRoot()
						if me then
							-- 源 2078-2086：遍历 workspace 全量后代做判定
							for _, d in ipairs(Workspace:GetDescendants()) do
								if isNPC(d) then
									local part = npcPart(d)
									if part then
										part.CFrame = me.CFrame * CFrame.new(0, 0, -4)
									end
								end
							end
							task.wait(0.2)
						else
							task.wait(0.05)
						end
					end
					loopAllJob = nil
				end)
			end
		end,
	})

	-- 源 7763：npc:Toggle({Title="查看NPC视角", Callback=fn30})
	-- 注：源里「查看NPC视角」有两个重复 Toggle（7763 用 fn30/下拉框目标，7776 用 fn42/点击目标，且 fn42 传的是
	-- Model 而不是 Humanoid，源本身有 bug）。这里合并成一个，按 Humanoid 取 CameraSubject。
	pickSec:Toggle({
		Title = "查看NPC视角",
		Desc = "把摄像机切到选中的NPC身上（源里重复定义，已合并）",
		Icon = "eye",
		Value = false,
		Callback = function(on)
			-- 源 fn30（2095-2114）
			state.lookNPC = on
			if on then
				local model = currentNPC()
				local hum = model and model:FindFirstChildOfClass("Humanoid")
				if hum then
					cam.CameraSubject = hum
					tip("已切换视角")
				else
					tip("无效NPC")
				end
			else
				local ch = getChar(LP)
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if hum then
					cam.CameraSubject = hum
					tip("视角恢复")
				end
			end
		end,
	})

	-- 源 7764：npc:Toggle({Title="自动瞄准NPC", Callback=fn31})
	-- 注：源 2116-2134 就是「每帧把摄像机朝向目标」的自瞄，和玩家自瞄同构；这里保留为 NPC 专用锁头。
	pickSec:Toggle({
		Title = "自动瞄准NPC",
		Desc = "摄像机始终朝向选中的NPC（与通用自瞄重复，可只用其一）",
		Icon = "crosshair",
		Value = false,
		Callback = function(on)
			state.aimbot = on
			tip("自动瞄准" .. (on and "开启" or "关闭"))
			if on then
				if aimJob then
					return
				end
				aimJob = task.spawn(function()
					while state.aimbot do
						local part = npcPart(currentNPC())
						if part then
							cam.CFrame = CFrame.new(cam.CFrame.Position, part.Position)
						end
						task.wait(0.03)
					end
					aimJob = nil
				end)
			end
		end,
	})

	-- ---- 源 7766-7780：鼠标点选版（第二套选中状态，对应源 v6）----
	local clickSec = npcTab:Section({ Title = "点选NPC（高级操作）", Opened = true })

	clickSec:Paragraph({
		Title = "下面这组操作作用在「鼠标点选的NPC」上",
		Desc = "源脚本里下拉框选中(tbl6.selected)和鼠标点选(v6)是两套独立状态，这里保持原样：先开「点击选择NPC」再点场景里的NPC即可。",
		Image = "info",
		ImageSize = 16,
		Color = Color3.fromRGB(72, 72, 72),
	})

	-- 源 7766：npc:Toggle({Title="点击选择NPC", Callback=fn32})
	clickSec:Toggle({
		Title = "点击选择NPC",
		Desc = "开启后鼠标左键点击NPC即可选中（带绿色描边）",
		Value = false,
		Callback = function(on)
			-- 源 fn32（2136-2166）
			state.clickSelect = on
			if connClick then
				connClick:Disconnect()
				connClick = nil
			end
			if not on then
				return
			end
			local mouse = LP:GetMouse()
			connClick = put(mouse.Button1Down:Connect(function()
				if state.lockSelect then
					return
				end
				local target = mouse.Target
				if not target then
					return
				end
				local model = target:FindFirstAncestorOfClass("Model")
				if isNPC(model) then
					selectClicked(model)
				end
			end))
		end,
	})

	-- 源 7767：npc:Toggle({Title="锁定选择", Callback=fn33})
	clickSec:Toggle({
		Title = "锁定选择",
		Desc = "锁定后点击不会改变已选中的NPC",
		Value = false,
		Callback = function(on)
			-- 源 fn33（2168-2170）
			state.lockSelect = on
		end,
	})

	-- 源 7768：npc:Toggle({Title="循环拉取当前NPC", Callback=fn34})
	clickSec:Toggle({
		Title = "循环拉取当前NPC",
		Desc = "持续将选中的NPC拉到自己面前",
		Value = false,
		Callback = function(on)
			-- 源 fn34（2172-2199）：源用 RunService.Heartbeat
			if connPull then
				connPull:Disconnect()
				connPull = nil
			end
			if not on then
				tip("循环拉取当前NPC已关闭")
				return
			end
			connPull = put(RunService.Heartbeat:Connect(function()
				local me = myRoot()
				local part = npcPart(clickedNPC)
				if me and part then
					part.CFrame = me.CFrame + Vector3.new(0, 3, 0)
				end
			end))
			tip("循环拉取当前NPC已开启")
		end,
	})

	-- 源 7769：npc:Toggle({Title="循环传送到NPC头上", Callback=fn35})
	clickSec:Toggle({
		Title = "循环传送到NPC头上",
		Desc = "持续将自己传送到选中的NPC头顶",
		Value = false,
		Callback = function(on)
			-- 源 fn35（2201-2228）
			if connTpHead then
				connTpHead:Disconnect()
				connTpHead = nil
			end
			if not on then
				tip("循环传送头上已关闭")
				return
			end
			connTpHead = put(RunService.Heartbeat:Connect(function()
				local me = myRoot()
				local part = npcPart(clickedNPC)
				if me and part then
					me.CFrame = part.CFrame + Vector3.new(0, 3, 0)
				end
			end))
			tip("循环传送头上已开启")
		end,
	})

	-- 源 7770：npc:Button({Title="杀死NPC", Callback=fn36})
	clickSec:Button({
		Title = "杀死NPC",
		Desc = "把选中NPC的 Humanoid.Health 置 0",
		Icon = "skull",
		Callback = function()
			-- 源 fn36（2230-2240）
			local hum = clickedNPC and clickedNPC:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = 0
				tip("已击杀NPC")
			end
		end,
	})

	-- 源 7771：npc:Button({Title="传送到NPC", Callback=fn37})
	clickSec:Button({
		Title = "传送到NPC",
		Desc = "传送到选中NPC的右侧",
		Callback = function()
			-- 源 fn37（2242-2250）
			local me = myRoot()
			local part = npcPart(clickedNPC)
			if me and part then
				me.CFrame = part.CFrame + Vector3.new(3, 0, 0)
				tip("传送成功")
			end
		end,
	})

	-- 源 7772：npc:Button({Title="传送NPC到玩家", Callback=fn38})
	clickSec:Button({
		Title = "传送NPC到玩家",
		Desc = "把整个NPC模型搬到自己右侧",
		Callback = function()
			-- 源 fn38（2252-2265）：SetPrimaryPartCFrame 在新版已废弃但保留兼容分支
			local me = myRoot()
			if not me or not clickedNPC then
				return
			end
			local target = CFrame.new(me.Position + Vector3.new(3, 0, 0))
			if clickedNPC.PrimaryPart then
				pcall(function()
					clickedNPC:SetPrimaryPartCFrame(target)
				end)
			else
				pcall(function()
					clickedNPC:PivotTo(target)
				end)
			end
			tip("已拉取NPC")
		end,
	})

	-- 源 7773：npc:Toggle({Title="控制NPC", Callback=fn39})
	clickSec:Toggle({
		Title = "控制NPC",
		Desc = "把自己挂到选中的NPC身上（客户端 Character 替换，本地可见）",
		Value = false,
		Callback = function(on)
			-- 源 fn39（2267-2309）
			if on then
				local part = npcPart(clickedNPC)
				local hum = clickedNPC and clickedNPC:FindFirstChildOfClass("Humanoid")
				if part and hum then
					savedChar = getChar(LP)
					LP.Character = clickedNPC
					cam.CameraSubject = hum
					-- 源用 PreSimulation 里交替 ±0.01 的 Y 抖动来保持「被引擎认作角色」
					local n = 0.01
					connCtrl = put(RunService.PreSimulation:Connect(function()
						local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
						if h and h.RootPart then
							local root = h.RootPart
							root.CFrame = root.CFrame + Vector3.new(0, n, 0)
							n = -n
						elseif connCtrl then
							connCtrl:Disconnect()
							connCtrl = nil
						end
					end))
					getHighlight().OutlineColor = Color3.fromRGB(0, 255, 0)
					tip("已接管NPC控制")
				else
					tip("无效NPC")
				end
			elseif savedChar then
				LP.Character = savedChar
				local hum = savedChar:FindFirstChildOfClass("Humanoid")
				if hum then
					cam.CameraSubject = hum
				end
				if connCtrl then
					connCtrl:Disconnect()
					connCtrl = nil
				end
				tip("已恢复控制")
			end
		end,
	})

	-- 源 7774：npc:Button({Title="切换坐下状态", Callback=fn40})
	clickSec:Button({
		Title = "切换坐下状态",
		Desc = "切换选中NPC的 Humanoid.Sit",
		Callback = function()
			-- 源 fn40（2311-2321）
			local hum = clickedNPC and clickedNPC:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Sit = not hum.Sit
				tip("坐下状态已切换")
			end
		end,
	})

	-- 源 7775：npc:Toggle({Title="NPC跟随玩家", Callback=fn41})
	clickSec:Toggle({
		Title = "NPC跟随玩家",
		Desc = "让选中NPC用 Humanoid:MoveTo 跟着你",
		Value = false,
		Callback = function(on)
			-- 源 fn41（2323-2355）
			if connFollow then
				connFollow:Disconnect()
				connFollow = nil
			end
			if not on then
				tip("NPC跟随已关闭")
				return
			end
			local part = npcPart(clickedNPC)
			local hum = clickedNPC and clickedNPC:FindFirstChildOfClass("Humanoid")
			if not (part and hum) then
				tip("无效NPC")
				return
			end
			connFollow = put(RunService.Heartbeat:Connect(function()
				local me = myRoot()
				if not me or not clickedNPC then
					if connFollow then
						connFollow:Disconnect()
						connFollow = nil
					end
					return
				end
				hum:MoveTo(me.Position + Vector3.new(-4, 0, 0))
			end))
			getHighlight().OutlineColor = Color3.fromRGB(0, 255, 0)
			tip("NPC跟随已开启")
		end,
	})

	-- 源 7777：npc:Toggle({Title="冻结NPC", Callback=fn43})
	clickSec:Toggle({
		Title = "冻结NPC",
		Desc = "把选中NPC的 HumanoidRootPart 设为 Anchored",
		Value = false,
		Callback = function(on)
			-- 源 fn43（2374-2382）：注意源冻结的是 RootPart.Anchored，不是 PlatformStand
			local part = npcPart(clickedNPC)
			if part then
				part.Anchored = on
				getHighlight().OutlineColor = on and Color3.fromRGB(135, 206, 235) or Color3.fromRGB(0, 255, 0)
				tip("NPC冻结" .. (on and "开启" or "关闭"))
			end
		end,
	})

	-- 源 7778：npc:Toggle({Title="自动杀死NPC", Callback=fn44})
	clickSec:Toggle({
		Title = "自动杀死NPC",
		Desc = "每 0.1 秒击杀 13 格半径内的所有NPC",
		Value = false,
		Callback = function(on)
			-- 源 fn44（2384-2422）
			if connKillAura then
				connKillAura:Disconnect()
				connKillAura = nil
			end
			if not on then
				tip("击杀光环已关闭")
				return
			end
			local last = 0
			connKillAura = put(RunService.Stepped:Connect(function()
				local now = tick()
				if now - last < 0.1 then
					return
				end
				last = now
				local me = myRoot()
				if not me then
					return
				end
				-- 源用 GetPartBoundsInRadius(位置, 13)，需要与 OverlapParams 一起调用才合法，这里补上
				local parts = Workspace:GetPartBoundsInRadius(me.Position, 13, OverlapParams.new())
				for _, p in pairs(parts) do
					local model = p:FindFirstAncestorOfClass("Model")
					if isNPC(model) then
						local hum = model:FindFirstChildOfClass("Humanoid")
						if hum then
							hum.Health = 0
						end
					end
				end
			end))
			tip("击杀光环已开启")
		end,
	})

	-- 源 7779：npc:Button({Title="NPC跳跃", Callback=fn45})
	clickSec:Button({
		Title = "NPC跳跃",
		Desc = "让 13 格半径内的所有NPC起跳",
		Callback = function()
			-- 源 fn45（2424-2444）
			local me = myRoot()
			if not me then
				return
			end
			local parts = Workspace:GetPartBoundsInRadius(me.Position, 13, OverlapParams.new())
			for _, p in pairs(parts) do
				local model = p:FindFirstAncestorOfClass("Model")
				if isNPC(model) then
					local hum = model:FindFirstChildOfClass("Humanoid")
					if hum then
						pcall(function()
							hum:ChangeState(Enum.HumanoidStateType.Jumping)
						end)
					end
				end
			end
			tip("已触发NPC跳跃")
		end,
	})

	-- 源 7780：npc:Toggle({Title="NPC冻结光环", Callback=fn46})
	clickSec:Toggle({
		Title = "NPC冻结光环",
		Desc = "每 0.1 秒把 13 格半径内的NPC Anchored（关闭时解锁）",
		Value = false,
		Callback = function(on)
			-- 源 fn46（2446-2502）
			if connFreezeAura then
				connFreezeAura:Disconnect()
				connFreezeAura = nil
			end
			if on then
				local last = 0
				connFreezeAura = put(RunService.Stepped:Connect(function()
					local now = tick()
					if now - last < 0.1 then
						return
					end
					last = now
					local me = myRoot()
					if not me then
						return
					end
					local parts = Workspace:GetPartBoundsInRadius(me.Position, 13, OverlapParams.new())
					for _, p in pairs(parts) do
						local model = p:FindFirstAncestorOfClass("Model")
						if isNPC(model) then
							local part = npcPart(model)
							if part then
								part.Anchored = true
							end
						end
					end
				end))
				tip("冻结光环已开启")
			else
				-- 关闭时把半径内的解冻一次（源 2482-2498 同）
				local me = myRoot()
				if me then
					local parts = Workspace:GetPartBoundsInRadius(me.Position, 13, OverlapParams.new())
					for _, p in pairs(parts) do
						local model = p:FindFirstAncestorOfClass("Model")
						if isNPC(model) then
							local part = npcPart(model)
							if part then
								part.Anchored = false
							end
						end
					end
				end
				tip("冻结光环已关闭")
			end
		end,
	})

	--==========================================================
	-- 关闭清理：源在 window:OnClose 只清了碰撞箱（8033-8035），NPC 这些循环没人管；
	-- 这里把 NPC 相关的连接统一断开，避免关面板后还在传。
	-- 统一走 ctx.onClose（由调用方实现）；ctx.onClose 为 nil 时静默跳过。
	--==========================================================
	if ctx.onClose then
		ctx.onClose(stopAll)
	end
end
end)()

-- ── 触发类 ──
local buildTrigger = (function()
--[[
    黑白脚本 · 触发类（独立提取版）
    ------------------------------------------------------------
    来源：黑白-MAIN.可运行版.lua 第 9050 ~ 10029 行
          （原 fn85 里 arg.Tabs.Trigger 那一段，标志行 9053 local trigger = arg.Tabs.Trigger）

    对应关系：
      源 fn5("服务名")    -> game:GetService("服务名")
      源 fn13(标题, 内容) -> notify(标题, 内容)
      源 tbl9（9115~9143）-> 本文件 S 表
      源 fn86 / fn87      -> espTag / espClearDefault（透视标记，我自己用 Highlight + BillboardGui 重写）
      源 fn88 ~ fn116     -> 本文件 scanXxx / autoStart 系列
      源 fn117            -> espScanClass（批量挂透视的封装）

    改写说明：
      1. 源里所有「自动 / 循环」都是 while 标志位 do ... end。这里统一交给
         autoStart / autoStop 管理：Toggle 关掉 = 标志位清空，循环下一轮自行退出，
         不会留下无法关闭的死循环。
      2. firetouchinterest / fireclickdetector / fireproximityprompt / firesignal /
         getrawmetatable / setreadonly / newcclosure 都是执行器函数，全部 pcall 包住；
         环境里没有时只提示、不报错。
      3. 源里 tbl9.InteractDistance / IgnoreDistanceLimit / IgnoreCooldown / SmartDelay
         这几项只赋值、从没被用过（死代码），这里给它们补上了真实作用（见各处注释）。
      4. 透视 / 高亮 GUI / 范围圈三种可视化都是我重写的，源里只有一份写死的实现。
      5. 源文件里 window:OnClose 的清理逻辑（10013 ~ 10029 行）照搬，关窗注册统一走
         ctx.onClose（由调用方实现，为 nil 时静默跳过）。
]]
return function(win, ctx)
	local notify    = ctx.notify      -- function(title, content[, icon])
	local getChar   = ctx.getChar     -- function(player) -> Character or nil
	local readInput = ctx.readInput   -- function(element) -> string

	local Players = game:GetService("Players")
	local ProximityPromptService = game:GetService("ProximityPromptService")
	local LP = Players.LocalPlayer

	local tab = win:Tab({ Title = "触发类", Icon = "zap" })

	--==========================================================
	-- 0. 执行器能力检测
	--    源文件里 firetouchinterest 等都是裸调用（9168 / 9195 / 9218 / 9337 / 9369 行），
	--    这里统一检测一次，缺什么就在 UI 上提示什么。
	--==========================================================
	local hasFireTouch  = type(firetouchinterest) == "function"
	local hasFireClick  = type(fireclickdetector) == "function"
	local hasFirePrompt = type(fireproximityprompt) == "function"
	local hasFireSignal = type(firesignal) == "function"
	local hasRawMeta    = type(getrawmetatable) == "function"
	local hasSetRO      = type(setreadonly) == "function"
	local hasNewC       = type(newcclosure) == "function"

	--==========================================================
	-- 1. 基础工具（源文件里到处是 Players4.LocalPlayer.Character）
	--==========================================================
	local function localChar()
		if getChar then
			local ok, ch = pcall(getChar, LP)
			if ok and ch then
				return ch
			end
		end
		return LP.Character
	end

	local function localRoot()
		local ch = localChar()
		if ch then
			return ch:FindFirstChild("HumanoidRootPart")
		end
		return nil
	end

	local function say(title, content, icon)
		if notify then
			local ok = pcall(notify, title, content, icon)
			if ok then
				return
			end
		end
		print(string.format("[%s] %s", tostring(title), tostring(content)))
	end

	--==========================================================
	-- 2. 运行状态：对应源文件 tbl9（9115 ~ 9143 行）
	--==========================================================
	local S = {
		IgnoreDistanceLimit = false,  -- 自动触发无视交互距离限制
		IgnoreCooldown      = false,  -- 自动忽略冷却时间
		ShowTriggerInfo     = true,   -- 显示触发信息
		ShowRangeCircle     = false,  -- 显示触发范围圈
		SmartDelay          = true,   -- 智能延迟
		GlobalDelay         = 0.5,    -- 全局触发延迟
		TouchTriggerRange   = 20,     -- 可触碰范围 / 直接 Touched 范围
		InteractDistance    = 10,     -- 交互距离（ProximityPrompt）
		VehicleRange        = 30,     -- 载具触发范围
		DialogRange         = 20,     -- 对话范围
		SpyRemotes          = false,  -- 监听 RemoteEvent
	}

	local inputTouchRange, inputInteractDist, inputVehicleRange, inputDialogRange

	local auto        = {}  -- 自动循环开关：auto[key] == true 表示继续跑
	local espOn       = {}  -- 透视循环开关
	local espSets     = {}  -- 透视已标记对象：espSets[key][对象] = true
	local espClearFns = {}  -- 自定义清理函数（GUI 高亮用）

	-- 范围判定：源里到处是 (a.Position - b.Position).Magnitude <= range
	-- 「无视交互距离限制」打开时直接放行（源里这个开关只存不用，这里补上作用）
	local function inRange(a, b, range)
		if S.IgnoreDistanceLimit then
			return true
		end
		range = tonumber(range) or 0
		if range <= 0 then
			return true
		end
		return (a - b).Magnitude <= range
	end

	--==========================================================
	-- 3. 自动循环管理
	--    源里 fn89 / fn92 / fn95 / fn99 / fn103 / fn106 / fn109 / fn114 是 8 个
	--    while 标志位循环，这里合并成一个可关闭的调度器。
	--    floor  = 该功能自身的下限间隔（源里的写死等待值：0.5 / 0.25 / 0.3 / 1）
	--    GlobalDelay = UI 上的「全局触发延迟」，取两者较大值
	--    SmartDelay  = 智能延迟：本轮没扫到东西就多歇 0.5 秒（源里只存不用，这里补上）
	--==========================================================
	local lastInfo = 0

	local function autoStart(key, label, scan, floor)
		if auto[key] then
			return
		end
		auto[key] = true
		floor = floor or 0.1
		task.spawn(function()
			while auto[key] do
				local ok, res = pcall(scan)
				local n = 0
				if ok then
					if type(res) == "number" then
						n = res
					end
				else
					-- 扫描里真出错了就自动停掉，避免无限刷错误
					auto[key] = nil
					say("触发", tostring(label) .. " 自动任务出错已停止：" .. tostring(res):sub(1, 60), "x")
					break
				end

				if n > 0 and S.ShowTriggerInfo and (os.clock() - lastInfo) > 3 then
					lastInfo = os.clock()
					say("触发", string.format("%s：本轮触发 %d 个", tostring(label), n))
				end

				local d = math.max(floor, tonumber(S.GlobalDelay) or 0.5)
				if S.SmartDelay and n == 0 then
					d = d + 0.5
				end
				task.wait(d)
			end
		end)
	end

	local function autoStop(key)
		auto[key] = nil
	end

	local function stopAllAuto()
		local keys = {}
		for k in pairs(auto) do
			table.insert(keys, k)
		end
		for _, k in ipairs(keys) do
			auto[k] = nil
		end
	end

	--==========================================================
	-- 4. 透视（源 fn86 / fn87 / fn117，9068 ~ 9113 与 9585 ~ 9611 行）
	--    源里所有透视共用一个 tbl8.Objects，一开一关会互相清掉；
	--    这里按 key 分开存，互不干扰；子对象名字也带 key，避免冲突。
	--==========================================================
	local function espTag(key, obj, text, color)
		if not obj or not obj:IsA("BasePart") then
			return
		end
		if obj:FindFirstChild("BS_ESP_" .. key) then
			return
		end

		local hl = Instance.new("Highlight")
		hl.Name = "BS_ESP_" .. key
		hl.FillColor = color or Color3.fromRGB(255, 255, 0)
		hl.OutlineColor = color or Color3.fromRGB(255, 255, 0)
		hl.FillTransparency = 0.7
		hl.OutlineTransparency = 0.3
		hl.Parent = obj

		local bb = Instance.new("BillboardGui")
		bb.Name = "BS_ESPText_" .. key
		bb.Size = UDim2.new(0, 120, 0, 30)
		bb.AlwaysOnTop = true
		bb.Adornee = obj
		bb.Parent = obj

		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.new(1, 0, 1, 0)
		tl.BackgroundTransparency = 1
		tl.TextColor3 = Color3.fromRGB(255, 255, 255)
		tl.TextScaled = true
		tl.Text = text or ""
		tl.Parent = bb

		espSets[key] = espSets[key] or {}
		espSets[key][obj] = true
	end

	local function espClearDefault(key)
		local set = espSets[key]
		if not set then
			return
		end
		for obj in pairs(set) do
			pcall(function()
				if obj then
					local a = obj:FindFirstChild("BS_ESP_" .. key)
					if a then
						a:Destroy()
					end
					local b = obj:FindFirstChild("BS_ESPText_" .. key)
					if b then
						b:Destroy()
					end
				end
			end)
		end
		espSets[key] = {}
	end

	local function espDoClear(key)
		local fn = espClearFns[key]
		if fn then
			pcall(fn)
		else
			espClearDefault(key)
		end
	end

	local function espStart(key, scan, clearFn)
		if espOn[key] then
			return
		end
		espOn[key] = true
		espSets[key] = {}
		if clearFn then
			espClearFns[key] = clearFn
		end
		task.spawn(function()
			while espOn[key] do
				espDoClear(key)
				pcall(scan)
				task.wait(1)
			end
			espDoClear(key)
		end)
	end

	local function espFree(key)
		espOn[key] = nil
		espDoClear(key)
	end

	local function stopAllEsp()
		local keys = {}
		for k in pairs(espOn) do
			table.insert(keys, k)
		end
		for _, k in ipairs(keys) do
			espFree(k)
		end
	end

	-- 源 fn117：按类名批量挂透视（可触碰 / 可点击 / 可互动 / Touched 部件共用）
	local function espScanClass(key, label, className, color)
		local root = localRoot()
		for _, d in ipairs(workspace:GetDescendants()) do
			local hit = false
			pcall(function()
				hit = d:IsA(className)
			end)
			if not hit and className == "TouchTransmitter" and d.Name == "TouchInterest" then
				hit = true
			end
			if hit then
				local part = d
				if not part:IsA("BasePart") then
					part = part.Parent
				end
				if part and part:IsA("BasePart") then
					local text = label
					if S.ShowTriggerInfo and root then
						-- 「显示触发信息」打开时，标签上带距离（我自己加的）
						text = string.format("%s %dm", label, math.floor((root.Position - part.Position).Magnitude))
					end
					espTag(key, part, text, color)
				end
			end
		end
	end

	--==========================================================
	-- 5. 各功能扫描 / 触发本体
	--==========================================================

	-- 源 fn88（9145 ~ 9175）：触发所有 TouchInterest
	local function scanTouchInterests()
		local root = localRoot()
		if not root then
			return 0
		end
		if not hasFireTouch then
			return 0
		end
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("TouchTransmitter") or d.Name == "TouchInterest" then
				local part = d.Parent
				if part and part:IsA("BasePart") and inRange(root.Position, part.Position, S.TouchTriggerRange) then
					pcall(function()
						firetouchinterest(part, root, 0)
						firetouchinterest(part, root, 1)
					end)
					n = n + 1
				end
			end
		end
		return n
	end

	-- 源 fn91（9192 ~ 9198）：触发所有 ClickDetector
	local function scanClickDetectors()
		if not hasFireClick then
			return 0
		end
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ClickDetector") then
				local ok = pcall(fireclickdetector, d)
				if ok then
					n = n + 1
				end
			end
		end
		return n
	end

	-- 源 fn94（9215 ~ 9221）：触发所有 ProximityPrompt
	-- 源里完全没做距离判定；这里用「交互距离」做上限（源里该值只存不用），
	-- 打开「无视交互距离限制」后即恢复成全部触发。
	local function scanPrompts()
		local root = localRoot()
		if not hasFirePrompt then
			return 0
		end
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				local part = d.Parent
				local pass = true
				if root and part and part:IsA("BasePart") then
					pass = inRange(root.Position, part.Position, S.InteractDistance)
				end
				if pass then
					if S.IgnoreCooldown then
						-- 源里 IgnoreCooldown 只存不用；这里补上：清零长按时间并强制可用
						pcall(function()
							d.HoldDuration = 0
							d.Enabled = true
						end)
					end
					local ok = pcall(fireproximityprompt, d)
					if ok then
						n = n + 1
					end
				end
			end
		end
		return n
	end

	-- 源 fn97（9238 ~ 9252）：快速互动，把所有 Prompt 的 HoldDuration 变 0
	local promptHoldConn = nil
	local function quickInteract()
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				local ok = pcall(function()
					d.HoldDuration = 0
				end)
				if ok then
					n = n + 1
				end
			end
		end
		-- 源里每点一次就多连一条信号（会泄漏）；这里改成只保留一条
		if promptHoldConn then
			pcall(function()
				promptHoldConn:Disconnect()
			end)
			promptHoldConn = nil
		end
		local ok, conn = pcall(function()
			return ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
				pcall(function()
					prompt.HoldDuration = 0
				end)
			end)
		end)
		if ok then
			promptHoldConn = conn
		end
		return n
	end

	-- 源 fn98（9254 ~ 9277）：触发所有 BasePart 的 Touched 事件
	-- 注意源里用的是 TouchTriggerRange（不是交互距离）
	local function scanTouchedParts()
		local ch = localChar()
		local root = localRoot()
		if not ch or not root then
			return 0
		end
		if not hasFireTouch then
			return 0
		end
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d ~= root and not d:IsDescendantOf(ch) then
				if inRange(root.Position, d.Position, S.TouchTriggerRange) then
					pcall(function()
						firetouchinterest(d, root, 0)
						firetouchinterest(d, root, 1)
					end)
					n = n + 1
				end
			end
		end
		return n
	end

	-- 源 fn101（9294 ~ 9326）：阻挡 Touch 事件
	-- 源里关闭时会把全图 CanTouch==false 的部件全改成 true（会动到别人改过的部件），
	-- 这里改成只还原「自己设过 false」的部件。
	local touchBlocked = {}
	local function touchBlockRestore()
		for part in pairs(touchBlocked) do
			pcall(function()
				if part and part.Parent then
					part.CanTouch = true
				end
			end)
		end
		touchBlocked = {}
	end

	local function scanTouchBlock()
		local ch = localChar()
		local root = localRoot()
		if not root then
			return 0
		end
		local n = 0
		local parts = workspace:GetPartBoundsInRadius(root.Position, 10)
		for _, part in ipairs(parts) do
			local mine = ch ~= nil and part:IsDescendantOf(ch)
			if part:IsA("BasePart") and not mine and part.CanTouch then
				local ok = pcall(function()
					part.CanTouch = false
				end)
				if ok then
					touchBlocked[part] = true
					n = n + 1
				end
			end
		end
		return n
	end

	-- 源 fn102（9328 ~ 9342）：触发所有 GUI 按钮
	local function scanGuiButtons()
		if not hasFireSignal then
			return 0
		end
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		if not pg then
			return 0
		end
		local n = 0
		for _, d in ipairs(pg:GetDescendants()) do
			if d:IsA("TextButton") or d:IsA("ImageButton") then
				local ok = pcall(function()
					firesignal(d.MouseButton1Click)
					firesignal(d.Activated)
				end)
				if ok then
					n = n + 1
				end
			end
		end
		return n
	end

	-- GUI 高亮（源 9768 ~ 9809，原来往按钮里塞一个绝对坐标的 TextLabel）
	-- 这里改成给按钮加黄色 UIStroke，位置永远跟着按钮走，是我自己重写的可视化。
	local GUI_ESP_TAG = "BS_GUIESP"

	local function guiEspSkip(obj)
		local p = obj
		while p do
			if p:IsA("ScreenGui") and p.Name:match("^WindUI") then
				return true   -- 不给我们自己的菜单描边
			end
			p = p.Parent
		end
		return false
	end

	local function guiEspClear()
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		if not pg then
			return
		end
		for _, d in ipairs(pg:GetDescendants()) do
			local old = d:FindFirstChild(GUI_ESP_TAG)
			if old then
				pcall(function()
					old:Destroy()
				end)
			end
		end
	end

	local function guiEspScan()
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		if not pg then
			return 0
		end
		local n = 0
		for _, d in ipairs(pg:GetDescendants()) do
			if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Visible and not guiEspSkip(d) then
				if not d:FindFirstChild(GUI_ESP_TAG) then
					local stroke = Instance.new("UIStroke")
					stroke.Name = GUI_ESP_TAG
					stroke.Color = Color3.fromRGB(255, 255, 0)
					stroke.Thickness = 2
					stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					stroke.Parent = d
				end
				n = n + 1
			end
		end
		return n
	end

	-- 源 fn105（9359 ~ 9377）：坐上所有座位
	local function sitAllSeats()
		local root = localRoot()
		if not root then
			return 0
		end
		if not hasFireTouch then
			return 0
		end
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				local ok = pcall(function()
					firetouchinterest(root, d, 0)
					task.wait()
					firetouchinterest(root, d, 1)
				end)
				if ok then
					n = n + 1
				end
			end
		end
		return n
	end

	-- 源 fn106（9379 ~ 9409）：自动上载具
	local function scanAutoVehicle()
		local ch = localChar()
		local root = localRoot()
		if not ch or not root then
			return 0
		end
		if not hasFireTouch then
			return 0
		end
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if not hum or hum.SeatPart ~= nil then
			return 0
		end
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if (d:IsA("Seat") or d:IsA("VehicleSeat")) and d.Occupant == nil then
				if inRange(root.Position, d.Position, S.VehicleRange) then
					pcall(function()
						firetouchinterest(root, d, 0)
						task.wait()
						firetouchinterest(root, d, 1)
					end)
					n = n + 1
				end
			end
		end
		return n
	end

	-- 源 fn108（9415 ~ 9440）：触发所有对话框（自动选第一个选项）
	local function scanDialogs()
		local ch = localChar()
		local root = localRoot()
		if not ch or not root then
			return 0
		end
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if not hum then
			return 0
		end
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("Dialog") then
				local part = d.Parent
				if part and part:IsA("BasePart") and inRange(root.Position, part.Position, S.DialogRange) then
					local ok = pcall(function()
						local choices = d:GetDialogChoices()
						if choices and #choices > 0 then
							d:SignalDialogChoiceSelected(hum, choices[1])
						end
					end)
					if ok then
						n = n + 1
					end
				end
			end
		end
		return n
	end

	-- 源 fn111 / fn112（9457 ~ 9492）：监听 RemoteEvent（需要执行器的元表函数）
	local remoteLog = {}
	local originalNamecall = nil

	local function spyStop()
		S.SpyRemotes = false
		if not hasRawMeta then
			return
		end
		pcall(function()
			local mt = getrawmetatable(game)
			if not mt then
				return
			end
			if hasSetRO then
				setreadonly(mt, false)
			end
			if originalNamecall then
				mt.__namecall = originalNamecall
				originalNamecall = nil
			end
			if hasSetRO then
				setreadonly(mt, true)
			end
		end)
	end

	local function spyStart()
		if S.SpyRemotes then
			return true
		end
		if not hasRawMeta then
			return false
		end
		S.SpyRemotes = true

		local ok = pcall(function()
			local mt = getrawmetatable(game)
			if not mt then
				error("getrawmetatable 返回空")
			end
			originalNamecall = mt.__namecall
			if hasSetRO then
				setreadonly(mt, false)
			end
			local wrap = hasNewC and newcclosure or function(f)
				return f
			end
			mt.__namecall = wrap(function(self, ...)
				local packed = table.pack(...)
				if S.SpyRemotes then
					pcall(function()
						if typeof(self) == "Instance" and self:IsA("RemoteEvent") then
							table.insert(remoteLog, {
								Name = self:GetFullName(),
								Args = packed,
								Time = tick(),
							})
							while #remoteLog > 300 do
								table.remove(remoteLog, 1)
							end
							if S.ShowTriggerInfo then
								print(string.format("[远程监听] %s 已触发", self:GetFullName()))
							end
						end
					end)
				end
				return originalNamecall(self, table.unpack(packed, 1, packed.n))
			end)
			if hasSetRO then
				setreadonly(mt, true)
			end
		end)

		if not ok then
			S.SpyRemotes = false
			return false
		end
		return true
	end

	-- 源 fn113（9494 ~ 9508）：把捕获到的远程事件打到控制台
	local function dumpRemotes()
		for i, rec in ipairs(remoteLog) do
			local parts = {}
			for i2 = 1, (rec.Args and rec.Args.n or 0) do
				table.insert(parts, tostring(rec.Args[i2]))
			end
			print(string.format("[%d] %s - 参数: %s", i, tostring(rec.Name), table.concat(parts, ", ")))
		end
		return #remoteLog
	end

	-- 源 fn114（9510 ~ 9535）：自动重放最后一条远程事件
	-- 用 string.gmatch 手写切分路径（源里用的是 Luau 专有的 split 扩展，不是标准 Lua 5.1）
	local function scanReplayRemote()
		if #remoteLog == 0 then
			return 0
		end
		local rec = remoteLog[#remoteLog]
		local n = 0
		pcall(function()
			local node = game
			for seg in string.gmatch(rec.Name, "[^.]+") do
				node = node and node:FindFirstChild(seg)
			end
			if node and node:IsA("RemoteEvent") then
				node:FireServer(table.unpack(rec.Args, 1, rec.Args.n))
				n = 1
			end
		end)
		return n
	end

	-- 源 fn116（9543 ~ 9583）：显示触发范围圈
	-- 源里那个球没设 CanTouch / CanQuery，自己会被碰到也会挡鼠标，这里补上。
	local rangePart = nil

	local function stopRangeCircle()
		S.ShowRangeCircle = false
		if rangePart then
			pcall(function()
				rangePart:Destroy()
			end)
			rangePart = nil
		end
	end

	local function setRangeCircle(on)
		if not on then
			stopRangeCircle()
			return
		end
		if rangePart then
			pcall(function()
				rangePart:Destroy()
			end)
			rangePart = nil
		end

		local p = Instance.new("Part")
		p.Name = "BS_RangeCircle"
		p.Shape = Enum.PartType.Ball
		p.Transparency = 0.75
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(0, 170, 255)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Parent = workspace
		rangePart = p
		S.ShowRangeCircle = true

		task.spawn(function()
			while rangePart == p and S.ShowRangeCircle do
				local root = localRoot()
				if root then
					local r = tonumber(S.TouchTriggerRange) or 20
					p.Position = root.Position
					p.Size = Vector3.new(r * 2, r * 2, r * 2)
				end
				task.wait(0.1)
			end
			if rangePart == p then
				pcall(function()
					p:Destroy()
				end)
				rangePart = nil
			end
		end)
	end

	--==========================================================
	-- 6. 输入框 → S 表同步
	--    Input 一律用 ctx.readInput 取值（源 9635 / 9701 / 9833 / 9894 行的 4 个输入框）
	--==========================================================
	local function syncSettings()
		pcall(function()
			local n

			n = tonumber(readInput(inputTouchRange))
			if n and n > 0 then
				S.TouchTriggerRange = n
			end

			n = tonumber(readInput(inputInteractDist))
			if n and n > 0 then
				S.InteractDistance = n
			end

			n = tonumber(readInput(inputVehicleRange))
			if n and n > 0 then
				S.VehicleRange = n
			end

			n = tonumber(readInput(inputDialogRange))
			if n and n > 0 then
				S.DialogRange = n
			end
		end)
	end

	--==========================================================
	-- 7. UI
	--==========================================================
	local secTouch = tab:Section({ Title = "可触碰类物体（TouchInterests）", Opened = true })  -- 源 9613（源里是折叠的）

	-- 源 9615
	secTouch:Button({
		Title = "触发所有 TouchInterests",
		Desc = "遍历全图 TouchInterest / TouchTransmitter 并调用 firetouchinterest",
		Icon = "hand",
		Callback = function()
			if not hasFireTouch then
				say("触发", "当前执行器没有 firetouchinterest，无法触发", "x")
				return
			end
			syncSettings()
			local n = scanTouchInterests()
			say("触发", string.format("已触发 %d 个 TouchInterests", n))
		end,
	})

	-- 源 9623（fn89 / fn90）
	secTouch:Toggle({
		Title = "自动触发 TouchInterest",
		Desc = "循环扫描触发，关掉立即停止",
		Value = false,
		Callback = function(on)
			if on then
				if not hasFireTouch then
					say("触发", "当前执行器没有 firetouchinterest，自动触发不会生效", "x")
					return
				end
				autoStart("touch", "自动触发 TouchInterest", scanTouchInterests, 0.05)
				say("触发", "自动触发 TouchInterest 已开启")
			else
				autoStop("touch")
				say("触发", "自动触发 TouchInterest 已停止")
			end
		end,
	})

	-- 源 9635
	inputTouchRange = secTouch:Input({
		Title = "设定范围",
		Placeholder = "输入范围值（0 = 不限）",
		Value = "20",
		Callback = function(v)
			local n = tonumber(v) or tonumber(readInput(inputTouchRange))
			if n and n > 0 then
				S.TouchTriggerRange = n
			end
		end,
	})

	-- 源 9645 fn117(v7, "TouchInterests", ...)
	secTouch:Toggle({
		Title = "透视 TouchInterests",
		Desc = "用 Highlight + BillboardGui 高亮可触碰物体（自己重写）",
		Value = false,
		Callback = function(on)
			if on then
				espStart("touch", function()
					espScanClass("touch", "TouchInterest", "TouchTransmitter", Color3.fromRGB(255, 0, 255))
				end)
			else
				espFree("touch")
			end
		end,
	})

	local secClick = tab:Section({ Title = "可点击类物体（ClickDetectors）", Opened = false })  -- 源 9646

	-- 源 9648
	secClick:Button({
		Title = "触发所有 ClickDetectors",
		Desc = "遍历全图 ClickDetector 并调用 fireclickdetector",
		Icon = "mouse-pointer-click",
		Callback = function()
			if not hasFireClick then
				say("触发", "当前执行器没有 fireclickdetector，无法触发", "x")
				return
			end
			local n = scanClickDetectors()
			say("触发", string.format("已触发 %d 个 ClickDetectors", n))
		end,
	})

	-- 源 9656（fn92 / fn93）
	secClick:Toggle({
		Title = "自动触发 ClickDetector",
		Desc = "源里固定 0.5 秒一轮",
		Value = false,
		Callback = function(on)
			if on then
				if not hasFireClick then
					say("触发", "当前执行器没有 fireclickdetector，自动触发不会生效", "x")
					return
				end
				autoStart("click", "自动触发 ClickDetector", scanClickDetectors, 0.5)
				say("触发", "自动触发 ClickDetector 已开启")
			else
				autoStop("click")
				say("触发", "自动触发 ClickDetector 已停止")
			end
		end,
	})

	-- 源 9668 fn117(v8, "ClickDetectors", ...)
	secClick:Toggle({
		Title = "透视 ClickDetectors",
		Desc = "高亮所有可点击物体（自己重写）",
		Value = false,
		Callback = function(on)
			if on then
				espStart("click", function()
					espScanClass("click", "ClickDetector", "ClickDetector", Color3.fromRGB(0, 255, 0))
				end)
			else
				espFree("click")
			end
		end,
	})

	local secPrompt = tab:Section({ Title = "可互动类物体（ProximityPrompts）", Opened = false })  -- 源 9669

	-- 源 9671
	secPrompt:Button({
		Title = "触发所有 ProximityPrompts",
		Desc = "遍历全图 ProximityPrompt 并调用 fireproximityprompt",
		Icon = "zap",
		Callback = function()
			if not hasFirePrompt then
				say("触发", "当前执行器没有 fireproximityprompt，无法触发", "x")
				return
			end
			syncSettings()
			local n = scanPrompts()
			say("触发", string.format("已触发 %d 个 ProximityPrompts", n))
		end,
	})

	-- 源 9679（fn95 / fn96）
	secPrompt:Toggle({
		Title = "自动触发 ProximityPrompt",
		Desc = "源里固定 0.25 秒一轮",
		Value = false,
		Callback = function(on)
			if on then
				if not hasFirePrompt then
					say("触发", "当前执行器没有 fireproximityprompt，自动触发不会生效", "x")
					return
				end
				autoStart("prompt", "自动触发 ProximityPrompt", scanPrompts, 0.25)
				say("触发", "自动触发 ProximityPrompt 已开启")
			else
				autoStop("prompt")
				say("触发", "自动触发 ProximityPrompt 已停止")
			end
		end,
	})

	-- 源 9691 fn117(v9, "ProximityPrompts", ...)
	secPrompt:Toggle({
		Title = "透视 ProximityPrompts",
		Desc = "高亮所有可互动物体（自己重写）",
		Value = false,
		Callback = function(on)
			if on then
				espStart("prompt", function()
					espScanClass("prompt", "ProximityPrompt", "ProximityPrompt", Color3.fromRGB(0, 150, 255))
				end)
			else
				espFree("prompt")
			end
		end,
	})

	-- 源 9693（fn97）
	secPrompt:Button({
		Title = "快速互动",
		Desc = "把所有 ProximityPrompt 的 HoldDuration 设为 0",
		Icon = "timer",
		Callback = function()
			local n = quickInteract()
			say("快速互动", string.format("已将 %d 个 Prompt 的 HoldDuration 设为 0", n))
		end,
	})

	-- 源 9701
	inputInteractDist = secPrompt:Input({
		Title = "交互距离",
		Desc = "自动触发 ProximityPrompt 的距离上限（源里该值没被使用）",
		Placeholder = "输入距离值（0 = 不限）",
		Value = "10",
		Callback = function(v)
			local n = tonumber(v) or tonumber(readInput(inputInteractDist))
			if n and n > 0 then
				S.InteractDistance = n
			end
		end,
	})

	local secTouched = tab:Section({ Title = "直接触碰事件（Touched）", Opened = false })  -- 源 9714

	-- 源 9716
	secTouched:Button({
		Title = "触发所有Touched事件",
		Desc = "对范围内所有 BasePart 触发 Touched（用 TouchTriggerRange）",
		Icon = "hand",
		Callback = function()
			if not hasFireTouch then
				say("触发", "当前执行器没有 firetouchinterest，无法触发", "x")
				return
			end
			syncSettings()
			local n = scanTouchedParts()
			say("触发", string.format("已触发 %d 个 Touched 部件", n))
		end,
	})

	-- 源 9724（fn99 / fn100）
	secTouched:Toggle({
		Title = "自动触发Touched事件",
		Desc = "源里固定 0.3 秒一轮",
		Value = false,
		Callback = function(on)
			if on then
				if not hasFireTouch then
					say("触发", "当前执行器没有 firetouchinterest，自动触发不会生效", "x")
					return
				end
				autoStart("touched", "自动触发 Touched", scanTouchedParts, 0.3)
				say("触发", "自动触发 Touched 已开启")
			else
				autoStop("touched")
				say("触发", "自动触发 Touched 已停止")
			end
		end,
	})

	-- 源 9736 fn117(v10, "Touched部件", ...)
	secTouched:Toggle({
		Title = "透视 Touched部件",
		Desc = "高亮全图 BasePart（自己重写，数量多时可能卡）",
		Value = false,
		Callback = function(on)
			if on then
				espStart("touched", function()
					espScanClass("touched", "Touched", "BasePart", Color3.fromRGB(255, 128, 0))
				end)
			else
				espFree("touched")
			end
		end,
	})

	-- 源 9738（fn101）
	secTouched:Toggle({
		Title = "阻挡Touch事件",
		Desc = "把身边 10 格内部件的 CanTouch 关掉，关闭时只还原自己改过的",
		Value = false,
		Callback = function(on)
			if on then
				autoStart("touchblock", "阻挡Touch", scanTouchBlock, 0.1)
				say("触发", "阻挡Touch 已开启")
			else
				autoStop("touchblock")
				touchBlockRestore()
				say("触发", "阻挡Touch 已关闭，CanTouch 已还原")
			end
		end,
	})

	local secGui = tab:Section({ Title = "GUI按钮触发", Opened = false })  -- 源 9746

	-- 源 9748
	secGui:Button({
		Title = "触发所有GUI按钮",
		Desc = "对 PlayerGui 里所有 TextButton / ImageButton 调用 firesignal",
		Icon = "square-mouse-pointer",
		Callback = function()
			if not hasFireSignal then
				say("触发", "当前执行器没有 firesignal，无法触发 GUI 按钮", "x")
				return
			end
			local n = scanGuiButtons()
			say("触发", string.format("已触发 %d 个 GUI 按钮", n))
		end,
	})

	-- 源 9756（fn103 / fn104）
	secGui:Toggle({
		Title = "自动点击GUI按钮",
		Desc = "源里固定 1 秒一轮",
		Value = false,
		Callback = function(on)
			if on then
				if not hasFireSignal then
					say("触发", "当前执行器没有 firesignal，自动点击不会生效", "x")
					return
				end
				autoStart("gui", "自动点击GUI按钮", scanGuiButtons, 1)
				say("触发", "自动点击GUI按钮 已开启")
			else
				autoStop("gui")
				say("触发", "自动点击GUI按钮 已停止")
			end
		end,
	})

	-- 源 9768（原来的绝对坐标 TextLabel，这里改成 UIStroke）
	secGui:Toggle({
		Title = "高亮可点击GUI",
		Desc = "给可点击按钮加黄框（自己重写，不框我们自己的菜单）",
		Value = false,
		Callback = function(on)
			if on then
				espStart("gui", guiEspScan, guiEspClear)
				say("触发", "GUI 高亮已开启")
			else
				espFree("gui")
				say("触发", "GUI 高亮已关闭")
			end
		end,
	})

	local secSeat = tab:Section({ Title = "座位/载具触发", Opened = false })  -- 源 9811

	-- 源 9813（fn105）
	secSeat:Button({
		Title = "坐上所有座位",
		Desc = "对全图 Seat / VehicleSeat 触发一次 touch",
		Icon = "armchair",
		Callback = function()
			if not hasFireTouch then
				say("载具", "当前执行器没有 firetouchinterest，无法上座", "x")
				return
			end
			local n = sitAllSeats()
			say("载具", string.format("已尝试坐上 %d 个座位", n))
		end,
	})

	-- 源 9821（fn106 / fn107）
	secSeat:Toggle({
		Title = "自动上载具",
		Desc = "自己没坐下时，自动触碰范围内的空座位（源里 0.5 秒一轮）",
		Value = false,
		Callback = function(on)
			if on then
				if not hasFireTouch then
					say("载具", "当前执行器没有 firetouchinterest，自动上载具不会生效", "x")
					return
				end
				autoStart("vehicle", "自动上载具", scanAutoVehicle, 0.5)
				say("载具", "自动上载具 已开启")
			else
				autoStop("vehicle")
				say("载具", "自动上载具 已停止")
			end
		end,
	})

	-- 源 9833
	inputVehicleRange = secSeat:Input({
		Title = "载具触发范围",
		Placeholder = "输入范围值（0 = 不限）",
		Value = "30",
		Callback = function(v)
			local n = tonumber(v) or tonumber(readInput(inputVehicleRange))
			if n and n > 0 then
				S.VehicleRange = n
			end
		end,
	})

	-- 源 9846（透视空座位）
	secSeat:Toggle({
		Title = "透视空座位",
		Desc = "高亮 Occupant 为空的 Seat / VehicleSeat（自己重写）",
		Value = false,
		Callback = function(on)
			if on then
				espStart("seat", function()
					local root = localRoot()
					for _, d in ipairs(workspace:GetDescendants()) do
						if (d:IsA("Seat") or d:IsA("VehicleSeat")) and d.Occupant == nil then
							local text = "座位"
							if S.ShowTriggerInfo and root then
								text = string.format("座位 %dm", math.floor((root.Position - d.Position).Magnitude))
							end
							espTag("seat", d, text, Color3.fromRGB(255, 255, 0))
						end
					end
				end)
			else
				espFree("seat")
			end
		end,
	})

	local secDialog = tab:Section({ Title = "对话框触发", Opened = false })  -- 源 9872

	-- 源 9874（fn108）
	secDialog:Button({
		Title = "触发所有对话框",
		Desc = "对范围内 Dialog 自动选中第一个选项",
		Icon = "message-square",
		Callback = function()
			syncSettings()
			local n = scanDialogs()
			say("对话", string.format("已触发 %d 个对话框", n))
		end,
	})

	-- 源 9882（fn109 / fn110）
	secDialog:Toggle({
		Title = "自动对话",
		Desc = "源里固定 1 秒一轮",
		Value = false,
		Callback = function(on)
			if on then
				autoStart("dialog", "自动对话", scanDialogs, 1)
				say("对话", "自动对话 已开启")
			else
				autoStop("dialog")
				say("对话", "自动对话 已停止")
			end
		end,
	})

	-- 源 9894
	inputDialogRange = secDialog:Input({
		Title = "对话范围",
		Placeholder = "输入范围值（0 = 不限）",
		Value = "20",
		Callback = function(v)
			local n = tonumber(v) or tonumber(readInput(inputDialogRange))
			if n and n > 0 then
				S.DialogRange = n
			end
		end,
	})

	local secRemote = tab:Section({ Title = "远程事件(进阶)", Opened = false })  -- 源 9907

	-- 源 9909（fn111 / fn112）
	secRemote:Toggle({
		Title = "监听RemoteEvents",
		Desc = "Hook __namecall 记录 RemoteEvent 调用（需要 getrawmetatable）",
		Value = false,
		Callback = function(on)
			if on then
				if spyStart() then
					say("远程", "已开始监听 RemoteEvent")
				else
					say("远程", "当前执行器不支持 getrawmetatable / setreadonly，无法监听", "x")
				end
			else
				spyStop()
				say("远程", "已停止监听 RemoteEvent")
			end
		end,
	})

	-- 源 9921（fn113）
	secRemote:Button({
		Title = "显示捕获的远程事件",
		Desc = "把记录打印到控制台（F9）",
		Icon = "terminal",
		Callback = function()
			local n = dumpRemotes()
			say("远程", string.format("已输出 %d 条记录到控制台", n))
		end,
	})

	-- 源 9929（fn114 / fn115）
	secRemote:Toggle({
		Title = "自动重放远程事件",
		Desc = "每轮重放最新捕获的那一条（源里 1 秒一轮）",
		Value = false,
		Callback = function(on)
			if on then
				autoStart("replay", "自动重放远程事件", scanReplayRemote, 1)
				say("远程", "自动重放远程事件 已开启")
			else
				autoStop("replay")
				say("远程", "自动重放远程事件 已停止")
			end
		end,
	})

	local secSet = tab:Section({ Title = "设置", Opened = false })  -- 源 9941

	-- 源 9943（源里只存不用，这里真的会跳过距离判定）
	secSet:Toggle({
		Title = "自动触发无视交互距离限制",
		Desc = "开启后所有范围判定直接放行（源里该开关是死代码）",
		Value = false,
		Callback = function(on)
			S.IgnoreDistanceLimit = on and true or false
			say("设置", "无视交互距离限制：" .. (on and "开" or "关"))
		end,
	})

	-- 源 9951（源里只存不用，这里用于清零 HoldDuration 并强制 Enabled）
	secSet:Toggle({
		Title = "自动忽略冷却时间",
		Desc = "触发 ProximityPrompt 前把 HoldDuration 清零并强制 Enabled",
		Value = false,
		Callback = function(on)
			S.IgnoreCooldown = on and true or false
			say("设置", "忽略冷却时间：" .. (on and "开" or "关"))
		end,
	})

	-- 源 9959
	secSet:Toggle({
		Title = "显示触发信息",
		Desc = "自动触发的反馈、透视标签上的距离、远程监听打印",
		Value = true,
		Callback = function(on)
			S.ShowTriggerInfo = on and true or false
		end,
	})

	-- 源 9967（fn116）
	secSet:Toggle({
		Title = "显示触发范围圈",
		Desc = "脚下画一个半透明球形显示当前可触碰范围（自己重写）",
		Value = false,
		Callback = function(on)
			setRangeCircle(on)
		end,
	})

	-- 源 9975（源里只存不用，这里表现为：扫不到东西时自动多歇 0.5 秒）
	secSet:Toggle({
		Title = "智能延迟",
		Desc = "没有可触发对象时自动放慢循环，省性能",
		Value = true,
		Callback = function(on)
			S.SmartDelay = on and true or false
		end,
	})

	-- 源 9983
	secSet:Slider({
		Title = "全局触发延迟",
		Desc = "所有自动触发循环的基础间隔（源里只有 Touch 循环用到了它）",
		Value = { Min = 0.1, Max = 5, Default = 0.5 },
		Step = 0.1,
		Callback = function(v)
			local n = tonumber(v)
			if n then
				S.GlobalDelay = n
			end
			syncSettings()
		end,
	})

	-- 源里没有这个按钮；加一个总闸，避免用户一个个去关（UI 开关不会自动归位）
	secSet:Button({
		Title = "停止所有自动触发",
		Desc = "关掉全部自动循环 + 透视 + 范围圈 + 远程监听（开关按钮需要手动关）",
		Icon = "square",
		Callback = function()
			stopAllAuto()
			stopAllEsp()
			spyStop()
			touchBlockRestore()
			stopRangeCircle()
			say("设置", "已停止所有自动触发 / 透视 / 监听")
		end,
	})

	local secInfo = tab:Section({ Title = "说明区", Opened = true })  -- 源 9992

	-- 源 9994 ~ 10011 的 14 条说明，原文照搬
	for _, line in ipairs({
		"• TouchInterests: 可触碰类物体（如按钮、机关等）",
		"• ClickDetectors: 可点击类物体（如可点击的部件）",
		"• ProximityPrompts: 可互动类物体（NPC对话、收集品等）",
		"• 直接Touched: 无TouchInterest的触摸事件",
		"• GUI按钮: 自动点击玩家界面的按钮",
		"• 座位/载具: 自动上座和进入载具",
		"• 对话框: 自动与NPC对话交互",
		"• 远程事件: 监听和重放网络事件（进阶）",
		"• 自动功能开启后会持续检测并触发",
		"• 快速互动可立即设置HoldDuration为0",
		"• 无视交互距离限制：自动触发时忽略距离检测",
		"• 忽略冷却时间：跳过所有交互冷却时间",
		"• 透视功能可高亮显示可互动对象位置",
		"• 触发范围圈可视化显示影响范围",
	}) do
		secInfo:Paragraph({ Title = "", Desc = line, Image = "info", ImageSize = 14, Color = Color3.fromRGB(72, 72, 72) })
	end

	-- 执行器缺函数时给一条醒目提示
	local missing = {}
	if not hasFireTouch then
		table.insert(missing, "firetouchinterest")
	end
	if not hasFireClick then
		table.insert(missing, "fireclickdetector")
	end
	if not hasFirePrompt then
		table.insert(missing, "fireproximityprompt")
	end
	if not hasFireSignal then
		table.insert(missing, "firesignal")
	end
	if not hasRawMeta then
		table.insert(missing, "getrawmetatable")
	end

	if #missing > 0 then
		local secEnv = tab:Section({ Title = "运行环境提示", Opened = true })
		secEnv:Paragraph({
			Title = "缺少执行器函数",
			Desc = "当前环境没有：" .. table.concat(missing, "、") .. "。相关按钮点了只会提示，不会报错。",
			Image = "alert-triangle",
			ImageSize = 16,
			Color = Color3.fromRGB(244, 201, 72),
		})
	end

	--==========================================================
	-- 8. 关窗清理（源 10013 ~ 10029 的 window:OnClose）
	--    统一走 ctx.onClose（由调用方实现）；ctx.onClose 为 nil 时静默跳过。
	--==========================================================
	if ctx.onClose then
		ctx.onClose(function()
			stopAllAuto()
			stopAllEsp()
			spyStop()
			touchBlockRestore()
			stopRangeCircle()
			if promptHoldConn then
				pcall(function()
					promptHoldConn:Disconnect()
				end)
				promptHoldConn = nil
			end
		end)
	end

	say("触发类", "已加载（黑白 · 触发类提取版）", "check")
end
end)()

-- 统一实例化各模块

-- 每个模块都单独 pcall：某一节出错只弹一条通知，不会连累后面的页签
-- （之前 Color = "Yellow" 那种错误会直接中断整个脚本，导致后面的页签全都不出现）
local function loadModule(name, fn)
	local ok, err = pcall(fn, win, ctx)
	if not ok then
		pcall(notify, "模块加载失败", name .. "：" .. tostring(err), "x")
		print(string.format("[黑白提取] 模块 %s 加载失败: %s", name, tostring(err)))
	end
	return ok
end

loadModule("动作包", buildActionPack)
loadModule("动画包", buildAnimPack)
loadModule("自动连点器", buildAutoClicker)
loadModule("NPC交互", buildNPC)
loadModule("触发类", buildTrigger)

notify("黑白提取", "已加载（动作包 / 动画包 / 自动连点器 / NPC交互 / 触发类）", "check")
