--[[
    黑白提取 · 远程模块：伪装玩家
    （源：伪装玩家.lua，由 suif.lua 的 lazyLoad 拉取执行）

    契约（和 玩家类远程.lua 一致）：
        主脚本先 getgenv().Tabs.HBDisguiseTab = 页签，再 lazyLoad(本文件, "伪装玩家", 页签)

    本文件是独立 chunk，看不到主脚本的局部变量：
        页签    走 getgenv().Tabs.HBDisguiseTab
        WindUI  走 getgenv().HB_WindUI
        win     走 getgenv().HB_win（用于 OnClose）
        notify / readInput / getChar / getHum / isR15 / onClose 在本文件里自己实现，
        不依赖主脚本导出，主脚本少给东西也不会挂。
]]

if getgenv().__HB_DISGUISE_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.HBDisguiseTab) or getgenv().SutureHBHBDisguiseTab
if not Tab then
	warn("[伪装玩家] 未找到页签（主脚本没赋值 getgenv().Tabs.HBDisguiseTab？）")
	return
end

-- 确认页签拿到后才标记；构建失败会在末尾清掉，允许重试
getgenv().__HB_DISGUISE_LOADED = true

local WindUI = getgenv().HB_WindUI
if type(WindUI) ~= "table" then
	warn("[伪装玩家] getgenv().HB_WindUI 缺失，无法弹通知（功能仍会尝试构建）")
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
	print(string.format("[黑白提取][伪装玩家] %s | %s", tostring(title), tostring(content)))
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
    黑白提取 · 伪装玩家
    对应源 .tmp/黑白/黑白-MAIN.可运行版.lua 的 fn77（7249-8350 附近）

    源里的做法：
      fn79  改自己的 DisplayName（显示名）
      fn80  按用户名查 userId
      fn81  用 userId 拉外观并套到目标角色上

    这里保留「查用户名 -> 拉外观 -> 套用」这条主线，并按要求新增一个
    「目标玩家」单项下拉框，直接读取当前服务器里的人员，省得手打名字。

    Boreal 的 Dropdown 没有运行时替换 Values 的方法，所以「刷新」是把
    下拉框 Destroy 掉再在同一个 Section 里重建（跟 NPC交互 里一样的做法）。
]]

return function(tab, ctx)
	local notify = ctx.notify
	local readInput = ctx.readInput

	local Players = game:GetService("Players")
	local HttpService = game:GetService("HttpService")
	local LP = Players.LocalPlayer

	local sec = tab:Section({ Title = "伪装玩家", Opened = true })

	sec:Paragraph({
		Title = "把目标玩家的外观和名字改成另一个 Roblox 账号的样子",
		Desc = "从下拉框选目标玩家，再填要伪装成的 Roblox 用户名",
		Image = "info",
		ImageSize = 16,
		Color = Color3.fromRGB(72, 72, 72),
	})

	--==========================================================
	-- 服务器人员列表（下拉框 + 重建）
	--==========================================================
	local selectedTarget = nil

	local function listPlayerNames()
		local names = {}
		for _, p in ipairs(Players:GetPlayers()) do
			table.insert(names, p.Name)
		end
		table.sort(names, function(a, b)
			return a:lower() < b:lower()
		end)
		return names
	end

	local targetDropdown = sec:Dropdown({
		Title = "目标玩家（当前服务器）",
		Desc = "从服务器人员里单选一个作为伪装目标",
		Values = listPlayerNames(),
		Value = nil,
		Callback = function(v)
			selectedTarget = v
		end,
	})

	-- Boreal 重建下拉框只有一条路：Destroy 掉旧的，再在同一个 Section 里新建。
	local function rebuildTargetDropdown()
		local values = listPlayerNames()
		local ok = pcall(function()
			targetDropdown:Destroy()
		end)
		if not ok then
			notify("伪装玩家", "Dropdown:Destroy() 不可用，无法重建（当前 " .. tostring(#values) .. " 人）", "x")
			return
		end
		targetDropdown = sec:Dropdown({
			Title = "目标玩家（当前服务器）",
			Desc = "从服务器人员里单选一个作为伪装目标",
			Values = values,
			Value = selectedTarget,
			Callback = function(v)
				selectedTarget = v
			end,
		})
		notify("伪装玩家", "已刷新人员列表（" .. tostring(#values) .. " 人）")
	end

	sec:Button({
		Title = "刷新人员列表",
		Desc = "重新读取当前服务器里的玩家并重建下拉框",
		Icon = "refresh-cw",
		Callback = function()
			rebuildTargetDropdown()
		end,
	})

	-- 玩家进出服务器时，下拉框里的快照就旧了；这里顺手提示一下
	local joinConn = Players.PlayerAdded:Connect(function()
		notify("伪装玩家", "有玩家加入，点「刷新人员列表」更新下拉框")
	end)
	local leaveConn = Players.PlayerRemoving:Connect(function()
		notify("伪装玩家", "有玩家离开，点「刷新人员列表」更新下拉框")
	end)

	sec:Divider()

	--==========================================================
	-- 要伪装成的账号
	--==========================================================
	local disguiseNameInput = sec:Input({
		Title = "伪装成（Roblox 用户名）",
		Placeholder = "例：Roblox",
		Value = "",
	})

	--==========================================================
	-- 源 fn80 的等价：按用户名查 userId
	--==========================================================
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

	--==========================================================
	-- 源 fn81 的等价：把目标角色的外观替换掉
	--==========================================================
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

	--==========================================================
	-- 执行伪装
	--==========================================================
	sec:Button({
		Title = "伪装目标玩家",
		Desc = "把下拉框选中的目标玩家，改成上面那个账号的外观和名字",
		Icon = "user-check",
		Callback = function()
			local wantName = tostring(readInput(disguiseNameInput) or "")
			local targetName = selectedTarget

			if wantName == "" then
				notify("错误", "请先填要伪装成的用户名", "x")
				return
			end
			if not targetName or targetName == "" then
				notify("错误", "请先从下拉框选一个目标玩家", "x")
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
				notify("错误", "查不到这个用户名: " .. wantName, "x")
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

	--==========================================================
	-- 只改自己的显示名（源 fn79，7249 行）
	--==========================================================
	sec:Divider()

	local selfNameInput = sec:Input({
		Title = "改成自己的显示名",
		Placeholder = "留空则恢复成账号名",
		Value = "",
	})

	sec:Button({
		Title = "应用到自己",
		Desc = "只改你自己的 DisplayName（只在本机和别人客户端显示层生效）",
		Icon = "user",
		Callback = function()
			local ch = LP.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if not hum then
				notify("错误", "你自己的角色未加载", "x")
				return
			end
			local name = tostring(readInput(selfNameInput) or "")
			local ok, err = pcall(function()
				hum.DisplayName = (name == "") and LP.Name or name
			end)
			if ok then
				notify("成功", "已更新显示名", "check")
			else
				notify("错误", tostring(err), "x")
			end
		end,
	})

	if ctx.onClose then
		ctx.onClose(function()
			if joinConn then
				joinConn:Disconnect()
			end
			if leaveConn then
				leaveConn:Disconnect()
			end
		end)
	end
end
end)()

local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[伪装玩家] 构建失败: " .. tostring(err))
	pcall(notify, "伪装玩家", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_DISGUISE_LOADED = nil   -- 清掉标志位，允许重试
else
	print(string.format("[黑白提取] 远程模块已加载: 伪装玩家 (%d 个元素)", #(Tab.Elements or {})))
end
