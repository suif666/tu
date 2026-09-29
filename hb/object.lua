--[[
    黑白提取 · 远程模块：控制物体
    控制物体.lua

    本文件由脚本自己 game:HttpGet + loadstring 执行，是独立 chunk，
    看不到主脚本的局部变量，所以：
      页签   走 getgenv().Tabs.HB_objectTab
      共享环境 走 getgenv().HB_notify / HB_readInput / HB_onClose / HB_getChar / HB_getHum / HB_isR15
]]

if getgenv().__HB_OBJECT_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.HB_objectTab) or getgenv().SutureHB_objectTab
if not Tab then
	warn("[控制物体] 未找到页签（主脚本没赋值 HB_objectTab？）")
	return
end

-- 确认页签拿到后才标记已加载；构建失败时会在下面清掉，允许重试
getgenv().__HB_OBJECT_LOADED = true

local notify    = getgenv().HB_notify
local readInput = getgenv().HB_readInput
local onClose   = getgenv().HB_onClose
local getChar   = getgenv().HB_getChar
local getHum    = getgenv().HB_getHum
local isR15     = getgenv().HB_isR15

if type(notify) ~= "function" then
	warn("[控制物体] 主脚本共享环境未就绪（getgenv().HB_notify 缺失）")
	getgenv().__HB_OBJECT_LOADED = nil
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
    黑白提取 · 控制物体（ObjectCtrl）
    对应源 .tmp/黑白/黑白-MAIN.可运行版.lua 的 fn84，第 8353-8625 行

    ── 关于「纯本地」这件事 ──
    源里（以及之前这版）的做法是客户端直接改 part.CFrame，这属于「本地预测」：
    服务器不认，只有你自己屏幕上动，别人看不见，一松手还可能弹回去。

    要让别人也看见，必须让服务器承认这些部件由你模拟，也就是「抢网络所有权」。
    本机所有脚本里找到 4 种做法，都借鉴进来了：

    ① tplaysaddon-v2.4.0-v1.lua:5441  toggleNetworkOwner(bool)   —— 最彻底
          把自己 MaximumSimulationRadius / SimulationRadius 设成 1/0，
          把其他玩家的设成 0，并用 Heartbeat 持续维持；
          同时 settings().Physics.AllowSleep = false、
          LocalPlayer.ReplicationFocus = workspace。
          效果：全图未锚定部件都由你模拟，你移动它 = 服务器认账 = 别人看得见。

    ② Xa全源(剑客泛滥 打压缝合).lua:1432   LocalPlayer.SimulationRadius = math.huge
          同一个思路的简化版，只在 Heartbeat 里刷自己那一个属性。这里作为兜底。

    ③ Xa全源:98  canNetworkOwn(part)
          not part:IsGrounded() and not part.Anchored and part.ReceiveAge == 0
          用来判断一个部件当前能不能被接管。

    ④ .tmp/gh/tplays-testing.lua:120  isnetworkowner(part)
          gethiddenproperty(part, "NetworkOwnerV3") == -1 或 == 4
          （-1 = 本机，4 = 服务器）用来显示当前归属。

    另外两种「让东西动」的写法也吸收了：
      part:ApplyImpulse(force)   —— 亡命速递:1889 推开怪物用的
      part.Velocity = ...       —— Xa全源:1445 黑洞吸物用的
    这两条不改 CFrame，走物理，网络同步更自然。

    ── 两种模式（用户要的那个「选择」）──
      已固定物品：保留原来那套（场景里挑、本地改）——Anchored 部件只能这样
      未锚定物品：先抢网络所有权，再改，别人才看得见

    源里依赖的三个文件级共享帮助函数，各自做了等价实现：
      fn14()           取装饰器        -> getSelectionBox()，用 SelectionBox
      fn15(model, cb)  遍历目标所有部件 -> forEachPart(model, cb)
      fn16()           物体飞行的循环   -> 物体飞行那条 RenderStepped
]]

return function(tab, ctx)
	local notify = ctx.notify
	local readInput = ctx.readInput

	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local CoreGui = game:GetService("CoreGui")
	local LP = Players.LocalPlayer

	local MODE_ANCHORED   = "已固定物品（本地）"
	local MODE_UNANCHORED = "未锚定物品（抢网络所有权）"

	--==========================================================
	-- 状态
	--==========================================================
	local model = nil             -- 当前选中的物体
	local savedPivots = {}        -- 保存的位置
	local selectionBox = nil
	local pickConn = nil
	local flyConn = nil
	local lockSelect = false
	local objCtrlEnabled = false
	local flySpeed = 5
	local controlMode = MODE_ANCHORED
	local ownershipConn = nil     -- 抢所有权的心跳连接
	local ownsNetwork = false

	local function tip(msg, icon)
		notify("控制物体", msg, icon)
	end

	--==========================================================
	-- fn14 等价：选择框
	--==========================================================
	local function getSelectionBox()
		if selectionBox and selectionBox.Parent then
			return selectionBox
		end
		local box = Instance.new("SelectionBox")
		box.Name = "HB_ObjectSelect"
		box.LineThickness = 0.05
		box.Color3 = Color3.fromRGB(0, 200, 255)
		box.SurfaceTransparency = 1
		local ok = pcall(function()
			box.Parent = CoreGui
		end)
		if not ok or not box.Parent then
			box.Parent = LP:WaitForChild("PlayerGui")
		end
		selectionBox = box
		return box
	end

	local function setAdornee(obj)
		getSelectionBox().Adornee = obj
	end

	local function isAlive(obj)
		return obj ~= nil and obj.Parent ~= nil
	end

	--==========================================================
	-- fn15 等价：对目标本身 + 所有后代里的 BasePart 逐个应用
	--==========================================================
	local function forEachPart(target, fn)
		if not target then
			return 0
		end
		local n = 0
		local function apply(part)
			if part and part:IsA("BasePart") then
				local ok = pcall(fn, part)
				if ok then
					n = n + 1
				end
			end
		end
		apply(target)
		if target:IsA("Model") or target:IsA("Folder") then
			for _, d in ipairs(target:GetDescendants()) do
				apply(d)
			end
		end
		return n
	end

	local function firstPart(target)
		if not target then
			return nil
		end
		if target:IsA("BasePart") then
			return target
		end
		return target:FindFirstChildWhichIsA("BasePart")
	end

	--==========================================================
	-- ③ canNetworkOwn —— 借鉴 Xa全源:98
	--    能不能接管：没贴地、没锚定、没有网络延迟累积
	--    IsGrounded / ReceiveAge 不是所有版本都有，全部 pcall 保护
	--==========================================================
	local function canNetworkOwn(part)
		if not part or not part:IsA("BasePart") then
			return false
		end
		if part.Anchored then
			return false
		end
		local ok1, grounded = pcall(function()
			return part:IsGrounded()
		end)
		if ok1 and grounded then
			return false
		end
		local ok2, age = pcall(function()
			return part.ReceiveAge
		end)
		if ok2 and age ~= 0 then
			return false
		end
		return true
	end

	--==========================================================
	-- ④ isnetworkowner —— 借鉴 tplays-testing:120
	--    gethiddenproperty(part, "NetworkOwnerV3")：-1 = 本机，4 = 服务器
	--==========================================================
	local function networkOwnerOf(part)
		if type(gethiddenproperty) == "function" then
			local ok, val = pcall(gethiddenproperty, part, "NetworkOwnerV3")
			if ok and type(val) == "number" then
				if val == -1 then
					return "本机"
				elseif val == 4 then
					return "服务器"
				end
				return "其他客户端"
			end
		end
		return canNetworkOwn(part) and "可接管" or "不可接管"
	end

	--==========================================================
	-- ① 抢网络所有权 —— 借鉴 tplaysaddon:5441 toggleNetworkOwner
	--    把本机模拟半径拉满、其他玩家压成 0，并持续维持。
	--    这一步是「别人能不能看见」的关键。
	--==========================================================
	local savedPhysics = {}

	local function grabOwnership()
		if ownsNetwork then
			return true
		end

		local hasHidden = (type(gethiddenproperty) == "function") and (type(sethiddenproperty) == "function")
		local okPhys = pcall(function()
			savedPhysics.allowSleep = settings().Physics.AllowSleep
			settings().Physics.AllowSleep = false
		end)
		local okFocus = pcall(function()
			savedPhysics.replicaFocus = LP.ReplicationFocus
			LP.ReplicationFocus = workspace
		end)

		if not hasHidden and not okPhys and not okFocus then
			tip("当前执行器不支持 gethiddenproperty/sethiddenproperty，也改不了物理设置，无法抢网络所有权", "x")
			return false
		end

		if hasHidden then
			local ok1, v1 = pcall(gethiddenproperty, LP, "MaximumSimulationRadius")
			if ok1 then savedPhysics.maxSimRadius = v1 end
			local ok2, v2 = pcall(gethiddenproperty, LP, "SimulationRadius")
			if ok2 then savedPhysics.simRadius = v2 end
		end

		ownershipConn = RunService.Heartbeat:Connect(function()
			-- ② Xa全源:1432：公开属性直接拉满，作为兜底
			pcall(function()
				LP.SimulationRadius = math.huge
			end)

			if hasHidden then
				pcall(sethiddenproperty, LP, "MaximumSimulationRadius", 1 / 0)
				pcall(sethiddenproperty, LP, "SimulationRadius", 1 / 0)
				if replicatesignal then
					pcall(replicatesignal, LP.SimulationRadiusChanged, 1 / 0)
				end
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= LP then
						pcall(sethiddenproperty, plr, "MaxSimulationRadius", 0)
						pcall(sethiddenproperty, plr, "SimulationRadius", 0)
						if replicatesignal then
							pcall(replicatesignal, plr.SimulationRadiusChanged, 0)
						end
					end
				end
			end
		end)

		ownsNetwork = true
		return true
	end

	local function releaseOwnership()
		if not ownsNetwork then
			return
		end
		if ownershipConn then
			ownershipConn:Disconnect()
			ownershipConn = nil
		end
		pcall(function()
			if savedPhysics.allowSleep ~= nil then
				settings().Physics.AllowSleep = savedPhysics.allowSleep
			end
		end)
		pcall(function()
			if savedPhysics.replicaFocus ~= nil then
				LP.ReplicationFocus = savedPhysics.replicaFocus
			end
		end)
		if type(sethiddenproperty) == "function" then
			if savedPhysics.maxSimRadius ~= nil then
				pcall(sethiddenproperty, LP, "MaximumSimulationRadius", savedPhysics.maxSimRadius)
			end
			if savedPhysics.simRadius ~= nil then
				pcall(sethiddenproperty, LP, "SimulationRadius", savedPhysics.simRadius)
			end
		end
		ownsNetwork = false
	end

	--==========================================================
	-- 移动目标（按模式决定要不要先抢所有权）
	--==========================================================
	local function moveTarget(target, cframe)
		if not isAlive(target) then
			return false
		end
		if controlMode == MODE_UNANCHORED then
			if not ownsNetwork and not grabOwnership() then
				return false
			end
		end
		return (pcall(function()
			if target:IsA("BasePart") then
				target.CFrame = cframe
			else
				target:PivotTo(cframe)
			end
		end))
	end

	--==========================================================
	-- 模式选择（「选择」）
	--==========================================================
	local sec = tab:Section({ Title = "选择与控制模式", Opened = true })

	sec:Paragraph({
		Title = "两种模式的区别",
		Desc = "已固定物品：任意部件都能选，但只在你屏幕上动（本地预测），别人看不见。\n"
			.. "未锚定物品：先抢网络所有权再动，服务器认账，别人看得见；只对未锚定部件有效。",
		Image = "info",
		ImageSize = 16,
		Color = Color3.fromRGB(72, 72, 72),
	})

	sec:Dropdown({
		Title = "控制模式",
		Desc = "选「未锚定物品」会立刻开启抢网络所有权",
		Values = { MODE_ANCHORED, MODE_UNANCHORED },
		Value = MODE_ANCHORED,
		Callback = function(v)
			controlMode = v
			if v == MODE_UNANCHORED then
				if grabOwnership() then
					tip("已切到「未锚定物品」，网络所有权已抢到本机")
				else
					tip("抢网络所有权失败，仍会尝试移动，但别人可能看不见", "x")
				end
			else
				releaseOwnership()
				tip("已切回「已固定物品（本地）」")
			end
		end,
	})

	sec:Toggle({
		Title = "手动抢夺网络所有权",
		Desc = "开启后全图未锚定部件都归本机模拟，别人能看见你的移动",
		Value = false,
		Callback = function(on)
			if on then
				if grabOwnership() then
					local n = 0
					for _, d in ipairs(workspace:GetDescendants()) do
						if canNetworkOwn(d) then
							n = n + 1
						end
					end
					tip(string.format("已抢到网络所有权（可接管部件约 %d 个）", n))
				else
					tip("抢网络所有权失败", "x")
				end
			else
				releaseOwnership()
				tip("已释放网络所有权")
			end
		end,
	})

	--==========================================================
	-- 未锚定物品下拉框（读取场景）
	--==========================================================
	sec:Divider()

	local function listUnanchoredNames()
		local seen = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if canNetworkOwn(d) then
				local name = d.Name
				seen[name] = (seen[name] or 0) + 1
			end
		end
		local out = {}
		for name, count in pairs(seen) do
			table.insert(out, string.format("%s ×%d", name, count))
		end
		table.sort(out)
		return out
	end

	-- 按显示名找部件（"Name ×N" -> 第一个叫 Name 的可接管部件）
	local function findUnanchoredByLabel(label)
		if not label then
			return nil
		end
		local name = tostring(label):match("^(.-)%s*×%d+$") or tostring(label)
		for _, d in ipairs(workspace:GetDescendants()) do
			if d.Name == name and canNetworkOwn(d) then
				return d
			end
		end
		return nil
	end

	local function buildUnanchoredDropdown()
		return sec:Dropdown({
			Title = "未锚定物品（场景）",
			Desc = "只列未锚定的 BasePart，选中后可由本机模拟",
			Values = listUnanchoredNames(),
			Value = nil,
			Callback = function(v)
				local part = findUnanchoredByLabel(v)
				if not part then
					return
				end
				model = part
				setAdornee(part)
				tip("已选中: " .. tostring(part.Name) .. "（" .. networkOwnerOf(part) .. "）")
			end,
		})
	end

	local unanchoredDropdown = buildUnanchoredDropdown()

	sec:Button({
		Title = "刷新未锚定列表",
		Desc = "重新扫描 workspace 并重建下拉框",
		Icon = "refresh-cw",
		Callback = function()
			local values = listUnanchoredNames()
			local ok = pcall(function()
				unanchoredDropdown:Destroy()
			end)
			if not ok then
				tip("Dropdown:Destroy() 不可用，无法重建（当前 " .. tostring(#values) .. " 项）", "x")
				return
			end
			unanchoredDropdown = buildUnanchoredDropdown()
			tip("已刷新（" .. tostring(#values) .. " 项）")
		end,
	})

	--==========================================================
	-- 基础选择 / 基础控制
	--==========================================================
	local pickSec = tab:Section({ Title = "基础选择", Opened = true })

	pickSec:Toggle({
		Title = "点击选择物体",
		Desc = "开启后鼠标左键点击场景里的物体即可选中",
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
				if not target then
					return
				end
				if controlMode == MODE_UNANCHORED and target.Anchored then
					tip("这是已锚定部件，未锚定模式下动不了它（可先点「解除锚定」）", "x")
				end
				model = target:FindFirstAncestorOfClass("Model") or target
				setAdornee(model)
				tip("已选中: " .. tostring(model.Name) .. "（" .. networkOwnerOf(firstPart(model) or target) .. "）")
			end)
		end,
	})

	pickSec:Toggle({
		Title = "锁定选择",
		Desc = "锁定后点击不会改变已选中的物体",
		Value = false,
		Callback = function(on)
			lockSelect = on
		end,
	})

	local ctrlSec = tab:Section({ Title = "基础控制", Opened = true })

	ctrlSec:Button({
		Title = "复制物体名称",
		Icon = "clipboard",
		Callback = function()
			if not model then
				tip("还没选中物体", "x")
				return
			end
			local ok = pcall(function()
				setclipboard(tostring(model.Name))
			end)
			if ok then
				tip("已复制名称: " .. tostring(model.Name))
			else
				tip("当前环境不支持剪贴板", "x")
			end
		end,
	})

	ctrlSec:Toggle({
		Title = "启用物体控制",
		Desc = "允许修改选中物体的属性（关闭会取消选择框）",
		Value = false,
		Callback = function(on)
			objCtrlEnabled = on
			if not on then
				setAdornee(nil)
			elseif model then
				setAdornee(model)
			end
		end,
	})

	ctrlSec:Toggle({
		Title = "物体飞行",
		Desc = "让选中的物体跟着鼠标位置飞",
		Value = false,
		Callback = function(on)
			if flyConn then
				flyConn:Disconnect()
				flyConn = nil
			end
			if not on then
				return
			end
			if not model then
				tip("请先选中物体", "x")
				return
			end
			if controlMode == MODE_UNANCHORED then
				grabOwnership()
			end
			flyConn = RunService.RenderStepped:Connect(function()
				if not isAlive(model) then
					return
				end
				local mouse = LP:GetMouse()
				if not mouse or not mouse.Hit then
					return
				end
				local target = mouse.Hit + Vector3.new(0, 3, 0)
				local step = math.clamp((flySpeed or 5) / 100, 0.02, 0.8)
				local cur
				if model:IsA("BasePart") then
					cur = model.CFrame
				else
					cur = model:GetPivot()
				end
				moveTarget(model, cur:Lerp(target, step))
			end)
		end,
	})

	local flySpeedInput
	flySpeedInput = ctrlSec:Input({
		Title = "飞行速度",
		Placeholder = "数值",
		Value = "5",
		Callback = function(v)
			local n = tonumber(v) or tonumber(readInput(flySpeedInput))
			if n and n > 0 then
				flySpeed = n
			end
		end,
	})

	ctrlSec:Button({
		Title = "保存位置",
		Icon = "save",
		Callback = function()
			if not model then
				tip("还没选中物体", "x")
				return
			end
			savedPivots[model] = model:GetPivot()
			tip("已保存位置")
		end,
	})

	ctrlSec:Button({
		Title = "加载位置",
		Icon = "rotate-ccw",
		Callback = function()
			if not model then
				tip("还没选中物体", "x")
				return
			end
			local pivot = savedPivots[model]
			if not pivot then
				tip("这个物体还没保存过位置", "x")
				return
			end
			if moveTarget(model, pivot) then
				tip("已回到保存的位置")
			else
				tip("移动失败", "x")
			end
		end,
	})

	ctrlSec:Button({
		Title = "传送到物品",
		Icon = "navigation",
		Callback = function()
			if not model then
				tip("还没选中物体", "x")
				return
			end
			local ch = LP.Character
			local part = firstPart(model)
			if not ch or not part then
				tip("没有可用部件", "x")
				return
			end
			pcall(function()
				ch:PivotTo(part.CFrame + Vector3.new(0, 3, 0))
			end)
			tip("已传送到 " .. tostring(model.Name))
		end,
	})

	ctrlSec:Button({
		Title = "传送物品到玩家",
		Icon = "move",
		Callback = function()
			if not model then
				tip("还没选中物体", "x")
				return
			end
			local ch = LP.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if not root then
				return
			end
			if moveTarget(model, root.CFrame + root.CFrame.LookVector * 5) then
				tip("已把物体拉到面前")
			else
				tip("移动失败", "x")
			end
		end,
	})

	ctrlSec:Button({
		Title = "复制物品",
		Icon = "copy",
		Callback = function()
			if not model then
				tip("还没选中物体", "x")
				return
			end
			local ok, clone = pcall(function()
				return model:Clone()
			end)
			if not ok or not clone then
				tip("复制失败（该物体可能受保护）", "x")
				return
			end
			clone.Parent = workspace
			model = clone
			setAdornee(clone)
			tip("已复制并选中副本")
		end,
	})

	ctrlSec:Button({
		Title = "删除物品",
		Desc = "本地删除（只在你屏幕上消失）",
		Icon = "trash",
		Callback = function()
			if not model then
				tip("还没选中物体", "x")
				return
			end
			local name = tostring(model.Name)
			savedPivots[model] = nil
			pcall(function()
				model:Destroy()
			end)
			model = nil
			setAdornee(nil)
			tip("已删除: " .. name)
		end,
	})

	--==========================================================
	-- 网络所有权工具（借鉴来的实用项）
	--==========================================================
	local netSec = tab:Section({ Title = "网络所有权工具", Opened = true })

	netSec:Button({
		Title = "查看当前物体的所有权",
		Desc = "显示是本机 / 服务器 / 其他客户端",
		Icon = "search",
		Callback = function()
			local part = firstPart(model)
			if not part then
				tip("还没选中物体", "x")
				return
			end
			tip(tostring(part.Name) .. " 的所有权: " .. networkOwnerOf(part))
		end,
	})

	netSec:Button({
		Title = "解除锚定",
		Desc = "把选中物体设为 Anchored = false，之后才可能抢到所有权",
		Icon = "unlock",
		Callback = function()
			if not model then
				tip("还没选中物体", "x")
				return
			end
			local n = forEachPart(model, function(part)
				part.Anchored = false
			end)
			tip(string.format("已解除 %d 个部件的锚定", n))
		end,
	})

	netSec:Button({
		Title = "尝试直接指定所有权",
		Desc = "对选中部件调用 SetNetworkOwner（客户端通常无权限，失败是正常的）",
		Icon = "wifi",
		Callback = function()
			local part = firstPart(model)
			if not part then
				tip("还没选中物体", "x")
				return
			end
			local ok, err = pcall(function()
				part:SetNetworkOwner(LP)
			end)
			if ok then
				tip("已指定给本机（当前: " .. networkOwnerOf(part) .. "）")
			else
				tip("SetNetworkOwner 失败: " .. tostring(err):sub(1, 50), "x")
			end
		end,
	})

	netSec:Button({
		Title = "推一下选中物体",
		Desc = "用 ApplyImpulse 给一个力，走物理同步（借鉴亡命速递）",
		Icon = "move",
		Callback = function()
			local part = firstPart(model)
			if not part then
				tip("还没选中物体", "x")
				return
			end
			if controlMode == MODE_UNANCHORED and not ownsNetwork then
				grabOwnership()
			end
			local ch = LP.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local dir = root and (part.Position - root.Position).Unit or Vector3.new(0, 1, 0)
			local ok = pcall(function()
				part:ApplyImpulse(dir * 2000 + Vector3.new(0, 200, 0))
			end)
			if ok then
				tip("已施加推力")
			else
				tip("施加推力失败（部件可能已锚定）", "x")
			end
		end,
	})

	--==========================================================
	-- 视觉与物理
	--==========================================================
	local visSec = tab:Section({ Title = "视觉与物理", Opened = true })

	visSec:Toggle({
		Title = "物体透明化",
		Desc = "把选中物体及其部件设为半透明",
		Value = false,
		Callback = function(on)
			local n = forEachPart(model, function(part)
				part.Transparency = on and 0.5 or 0
			end)
			if n == 0 then
				tip("还没选中物体", "x")
			end
		end,
	})

	visSec:Toggle({
		Title = "禁用碰撞",
		Desc = "关闭选中物体的 CanCollide",
		Value = false,
		Callback = function(on)
			local n = forEachPart(model, function(part)
				part.CanCollide = not on
			end)
			if n == 0 then
				tip("还没选中物体", "x")
			end
		end,
	})

	visSec:Toggle({
		Title = "固定物体",
		Desc = "把选中物体锚定在空中",
		Value = false,
		Callback = function(on)
			local n = forEachPart(model, function(part)
				part.Anchored = on
			end)
			if n == 0 then
				tip("还没选中物体", "x")
			end
		end,
	})

	visSec:Toggle({
		Title = "启用反射",
		Desc = "把选中物体的 Reflectance 设为 0.5",
		Value = false,
		Callback = function(on)
			local n = forEachPart(model, function(part)
				part.Reflectance = on and 0.5 or 0
			end)
			if n == 0 then
				tip("还没选中物体", "x")
			end
		end,
	})

	visSec:Button({
		Title = "放大物体",
		Desc = "尺寸 ×1.2",
		Icon = "maximize",
		Callback = function()
			local n = forEachPart(model, function(part)
				part.Size = part.Size * 1.2
			end)
			if n == 0 then
				tip("还没选中物体", "x")
			else
				tip(string.format("已放大 %d 个部件", n))
			end
		end,
	})

	visSec:Button({
		Title = "缩小物体",
		Desc = "尺寸 ×0.8",
		Icon = "minimize",
		Callback = function()
			local n = forEachPart(model, function(part)
				part.Size = part.Size * 0.8
			end)
			if n == 0 then
				tip("还没选中物体", "x")
			else
				tip(string.format("已缩小 %d 个部件", n))
			end
		end,
	})

	visSec:Button({
		Title = "随机颜色",
		Desc = "给选中物体随机上色",
		Icon = "palette",
		Callback = function()
			local n = forEachPart(model, function(part)
				part.BrickColor = BrickColor.random()
			end)
			if n == 0 then
				tip("还没选中物体", "x")
			else
				tip(string.format("已给 %d 个部件随机上色", n))
			end
		end,
	})

	--==========================================================
	-- 关闭清理（源 8597-8625 的 window:OnClose 里写的是 (nil):Disconnect()，
	-- 那是反混淆残留；这里按实际意图断开并释放所有权）
	--==========================================================
	if ctx.onClose then
		ctx.onClose(function()
			if pickConn then
				pickConn:Disconnect()
				pickConn = nil
			end
			if flyConn then
				flyConn:Disconnect()
				flyConn = nil
			end
			releaseOwnership()
			if selectionBox then
				pcall(function()
					selectionBox:Destroy()
				end)
				selectionBox = nil
			end
		end)
	end
end
end)()

-- 远程脚本是独立 chunk，出错必须显式暴露，否则就是静默白屏
local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[控制物体] 构建失败: " .. tostring(err))
	pcall(notify, "控制物体", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_OBJECT_LOADED = nil   -- 清掉标志位，允许再点一次重试
else
	-- 成功也打一条到控制台，方便排查「页签是空的」这类问题
	print("[黑白提取] 远程模块已加载: 控制物体 (" .. tostring(#Tab.Elements or 0) .. " 个元素)")
end
