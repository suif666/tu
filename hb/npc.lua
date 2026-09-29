--[[
    黑白提取 · 远程模块：NPC交互
    NPC交互.lua

    本文件由脚本自己 game:HttpGet + loadstring 执行，是独立 chunk，
    看不到主脚本的局部变量，所以：
      页签   走 getgenv().Tabs.HB_npcTab
      共享环境 走 getgenv().HB_notify / HB_readInput / HB_onClose / HB_getChar / HB_getHum / HB_isR15
]]

if getgenv().__HB_NPC_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.HB_npcTab) or getgenv().SutureHB_npcTab
if not Tab then
	warn("[NPC交互] 未找到页签（主脚本没赋值 HB_npcTab？）")
	return
end

-- 确认页签拿到后才标记已加载；构建失败时会在下面清掉，允许重试
getgenv().__HB_NPC_LOADED = true

local notify    = getgenv().HB_notify
local readInput = getgenv().HB_readInput
local onClose   = getgenv().HB_onClose
local getChar   = getgenv().HB_getChar
local getHum    = getgenv().HB_getHum
local isR15     = getgenv().HB_isR15

if type(notify) ~= "function" then
	warn("[NPC交互] 主脚本共享环境未就绪（getgenv().HB_notify 缺失）")
	getgenv().__HB_NPC_LOADED = nil
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
--==============================================================
-- 黑白提取 · NPC交互
-- 对应源文件 .tmp/黑白/黑白-MAIN.可运行版.lua
--   UI 注册：7755-7780 行（local npc = arg.Tabs.NPC）
--   逻辑闭包：1867-2503 行（tbl6 状态表 1871-1878，工具函数 fn48-fn54 1907-1967，
--             NPC 功能 fn23-fn46 1969-2502）
--==============================================================
return function(tab, ctx)
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
	local myTab = tab   -- 页签由调用方建好（功能类 -> NPC交互）

	-- ---- 源 7756-7764：下拉框版选中 + 传送/拉取/视角/瞄准 ----
	local pickSec = myTab:Section({ Title = "选择与传送", Opened = true })

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
	local clickSec = myTab:Section({ Title = "点选NPC（高级操作）", Opened = true })

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

-- 远程脚本是独立 chunk，出错必须显式暴露，否则就是静默白屏
local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[NPC交互] 构建失败: " .. tostring(err))
	pcall(notify, "NPC交互", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_NPC_LOADED = nil   -- 清掉标志位，允许再点一次重试
else
	-- 成功也打一条到控制台，方便排查「页签是空的」这类问题
	print("[黑白提取] 远程模块已加载: NPC交互 (" .. tostring(#Tab.Elements or 0) .. " 个元素)")
end
