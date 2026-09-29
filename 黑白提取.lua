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
	Color = "Grey",
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
	Color = "Yellow",
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

notify("黑白提取", "已加载（第一批）", "check")
