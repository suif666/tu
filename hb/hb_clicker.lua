--[[
    黑白提取 · 远程模块：自动连点器
    自动连点器.lua

    本文件由脚本自己 game:HttpGet + loadstring 执行，是独立 chunk，
    看不到主脚本的局部变量，所以：
      页签   走 getgenv().Tabs.HB_clickerTab
      共享环境 走 getgenv().HB_notify / HB_readInput / HB_onClose / HB_getChar / HB_getHum / HB_isR15
]]

if getgenv().__HB_CLICKER_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.HB_clickerTab) or getgenv().SutureHB_clickerTab
if not Tab then
	warn("[自动连点器] 未找到页签（主脚本没赋值 HB_clickerTab？）")
	return
end

-- 确认页签拿到后才标记已加载；构建失败时会在下面清掉，允许重试
getgenv().__HB_CLICKER_LOADED = true

local notify    = getgenv().HB_notify
local readInput = getgenv().HB_readInput
local onClose   = getgenv().HB_onClose
local getChar   = getgenv().HB_getChar
local getHum    = getgenv().HB_getHum
local isR15     = getgenv().HB_isR15

if type(notify) ~= "function" then
	warn("[自动连点器] 主脚本共享环境未就绪（getgenv().HB_notify 缺失）")
	getgenv().__HB_CLICKER_LOADED = nil
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
-- 黑白提取 · 自动连点器
-- 对应源文件 .tmp/黑白/黑白-MAIN.可运行版.lua（都在 fn84 里，fn84 = 8353-9048 行）
--   UI 注册：8623-8654 行（local clicker = arg.Tabs.Clicker）
--   参数设置：8624-8652 行（n3 点击间隔 0.5 / n4 按下时长 0.01）
--   悬浮面板：8659-9020 行（fn85，ScreenGui "AutoClicker_Classic" 见 8687）
--   关闭清理：9022-9034 行（fn86）
--   启动开关：9036-9047 行（Toggle "GUI 开关"）
-- 说明：该功能不是 loadstring(game:HttpGet(...))() 远程加载，是完整本地实现。
--==============================================================
return function(tab, ctx)
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

-- 远程脚本是独立 chunk，出错必须显式暴露，否则就是静默白屏
local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[自动连点器] 构建失败: " .. tostring(err))
	pcall(notify, "自动连点器", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_CLICKER_LOADED = nil   -- 清掉标志位，允许再点一次重试
end
