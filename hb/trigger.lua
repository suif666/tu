--[[
    黑白提取 · 远程模块：触发类
    触发类.lua

    本文件由脚本自己 game:HttpGet + loadstring 执行，是独立 chunk，
    看不到主脚本的局部变量，所以：
      页签   走 getgenv().Tabs.HB_triggerTab
      共享环境 走 getgenv().HB_notify / HB_readInput / HB_onClose / HB_getChar / HB_getHum / HB_isR15
]]

if getgenv().__HB_TRIGGER_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.HB_triggerTab) or getgenv().SutureHB_triggerTab
if not Tab then
	warn("[触发类] 未找到页签（主脚本没赋值 HB_triggerTab？）")
	return
end

-- 确认页签拿到后才标记已加载；构建失败时会在下面清掉，允许重试
getgenv().__HB_TRIGGER_LOADED = true

local notify    = getgenv().HB_notify
local readInput = getgenv().HB_readInput
local onClose   = getgenv().HB_onClose
local getChar   = getgenv().HB_getChar
local getHum    = getgenv().HB_getHum
local isR15     = getgenv().HB_isR15

if type(notify) ~= "function" then
	warn("[触发类] 主脚本共享环境未就绪（getgenv().HB_notify 缺失）")
	getgenv().__HB_TRIGGER_LOADED = nil
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
return function(tab, ctx)
	local notify    = ctx.notify      -- function(title, content[, icon])
	local getChar   = ctx.getChar     -- function(player) -> Character or nil
	local readInput = ctx.readInput   -- function(element) -> string

	local Players = game:GetService("Players")
	local ProximityPromptService = game:GetService("ProximityPromptService")
	local LP = Players.LocalPlayer

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

-- 远程脚本是独立 chunk，出错必须显式暴露，否则就是静默白屏
local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[触发类] 构建失败: " .. tostring(err))
	pcall(notify, "触发类", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_TRIGGER_LOADED = nil   -- 清掉标志位，允许再点一次重试
end
