--[[ 自动连点器（重写版 · 自实现）
     功能：按设定间隔连点鼠标左键 / 屏幕左侧悬浮面板实时开关
     要点：
       1. 执行器提供 mouse1press/mouse1release 就用它；否则退回 VirtualInputManager
       2. 点击循环只在开启时跑，关闭立刻退出（不常驻空转）
       3. 悬浮面板用 RunService.RenderStepped 之外的方式拖动（InputChanged + UserInputService）
          —— 不使用逐帧轮询
]]
if getgenv().__HB_CLICKER_LOADED then return end
local Tab = (getgenv().Tabs and getgenv().Tabs.ToolTab) or getgenv().SutureToolTab
if not Tab then warn("[自动连点器] 没拿到 ToolTab") return end
getgenv().__HB_CLICKER_LOADED = true

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")
local WindUI = getgenv().HB_WindUI

local function notify(t, c, icon)
    if type(WindUI) == "table" then
        pcall(function()
            WindUI:Notify({ Title = tostring(t), Content = tostring(c or ""), Icon = icon or "check", Duration = 2 })
        end)
    end
    print(("[自动连点器] %s | %s"):format(tostring(t), tostring(c)))
end

-- ── 点击后端 ──
local VIM = nil
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local function press()
    if type(mouse1press) == "function" then
        pcall(mouse1press)
    elseif VIM then
        pcall(function()
            VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        end)
    end
end
local function release()
    if type(mouse1release) == "function" then
        pcall(mouse1release)
    elseif VIM then
        pcall(function()
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
    end
end

local S = {
    on = false,
    interval = 0.05,
    hold = 0.01,
    thread = nil,
    guiOn = true,
}

local function loop()
    while S.on do
        press()
        if S.hold > 0 then task.wait(S.hold) end
        release()
        local wait = S.interval - S.hold
        if wait > 0 then task.wait(wait) end
    end
    release()
end

local function setOn(v)
    S.on = v
    if v then
        if not S.thread or coroutine.status(S.thread) == "dead" then
            S.thread = task.spawn(loop)
        end
    else
        release()
    end
    if clickerPanel then clickerPanel.refresh() end
end

-- ── 悬浮面板（左侧，可拖动）──
local clickerPanel = nil

local function buildPanel()
    if clickerPanel then
        if clickerPanel.gui then clickerPanel.gui.Enabled = S.guiOn end
        return
    end

    -- ★ 挂到主脚本导出的隐藏容器（gethui/CoreGui），不落 PlayerGui
    local g0 = (getgenv and getgenv()) or _G
    local gui
    if type(g0.__SUIF_HIDDEN_GUI) == "function" then
        local ok, r = pcall(g0.__SUIF_HIDDEN_GUI, "HB_ClickerPanel", 90)
        if ok and r then gui = r end
    end
    if not gui then
        gui = Instance.new("ScreenGui")
        gui.Name = "HB_ClickerPanel"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 90
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Parent = PlayerGui
        -- 有隐藏容器就搬过去
        if type(g0.__SUIF_HIDE_GUI) == "function" then
            pcall(g0.__SUIF_HIDE_GUI, gui)
        end
    end

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.AnchorPoint = Vector2.new(0, 0.5)
    frame.Position = UDim2.new(0, 18, 0.6, 0)
    frame.Size = UDim2.new(0, 150, 0, 92)
    frame.BackgroundColor3 = Color3.fromRGB(22, 24, 29)
    frame.BackgroundTransparency = 0.12
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60, 64, 74)
    stroke.Thickness = 1
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 22)
    title.Position = UDim2.new(0, 10, 0, 8)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamMedium
    title.TextSize = 13
    title.TextColor3 = Color3.fromRGB(235, 235, 240)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "自动连点器"
    title.Parent = frame

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.Size = UDim2.new(1, -20, 0, 16)
    status.Position = UDim2.new(0, 10, 0, 30)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.Gotham
    status.TextSize = 11
    status.TextColor3 = Color3.fromRGB(150, 155, 165)
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Text = "已停止"
    status.Parent = frame

    local btn = Instance.new("TextButton")
    btn.Name = "Toggle"
    btn.Size = UDim2.new(1, -20, 0, 30)
    btn.Position = UDim2.new(0, 10, 1, -42)
    btn.BackgroundColor3 = Color3.fromRGB(46, 50, 58)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = true
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 13
    btn.TextColor3 = Color3.fromRGB(235, 235, 240)
    btn.Text = "启动"
    btn.Parent = frame

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 6)
    bc.Parent = btn

    local function refresh()
        status.Text = S.on and ("连点中 · 每 %.2fs"):format(S.interval) or "已停止"
        status.TextColor3 = S.on and Color3.fromRGB(120, 220, 140) or Color3.fromRGB(150, 155, 165)
        btn.Text = S.on and "停止" or "启动"
        btn.BackgroundColor3 = S.on and Color3.fromRGB(190, 70, 70) or Color3.fromRGB(46, 50, 58)
    end

    btn.MouseButton1Click:Connect(function()
        setOn(not S.on)
    end)

    -- 拖动：只在按住时跟随（InputChanged，不是逐帧轮询）
    local dragging, dragStart, startPos = false, nil, nil
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    frame.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    clickerPanel = { gui = gui, frame = frame, refresh = refresh }
    refresh()
    gui.Enabled = S.guiOn
end

-- ── 主 UI ──
local sec = Tab:Section({ Title = "参数设置", Icon = "mouse-pointer-click", Opened = true })

sec:Slider({
    Title = "点击间隔延迟（秒）",
    Desc = "两次点击之间的间隔，越小越快",
    Value = 0.05, Min = 0.01, Max = 1, Rounding = 2,
    Callback = function(v)
        S.interval = v
        if clickerPanel then clickerPanel.refresh() end
    end,
})

sec:Slider({
    Title = "按下持续时间（秒）",
    Desc = "每次按下按住多久再松开",
    Value = 0.01, Min = 0, Max = 0.5, Rounding = 2,
    Callback = function(v) S.hold = v end,
})

sec:Toggle({
    Title = "启动",
    Desc = "开启后按设定间隔连续点鼠标左键",
    Value = false,
    Callback = function(v) setOn(v) end,
})

sec:Toggle({
    Title = "GUI 开关",
    Desc = "开启后屏幕左侧出现连点器悬浮面板",
    Value = true,
    Callback = function(v)
        S.guiOn = v
        if v then
            buildPanel()
            if clickerPanel then clickerPanel.gui.Enabled = true end
        elseif clickerPanel then
            clickerPanel.gui.Enabled = false
        end
    end,
})

sec:Button({
    Title = "显示悬浮面板",
    Desc = "在屏幕左侧重新显示连点器面板",
    Icon = "panel-left",
    Callback = function()
        S.guiOn = true
        buildPanel()
        if clickerPanel then clickerPanel.gui.Enabled = true end
        notify("自动连点器", "已显示悬浮面板", "check")
    end,
})

sec:Paragraph({
    Title = "说明",
    Desc = "连点循环只在「启动」打开时运行，关闭立即停下并松开按键，不会常驻占资源。",
    Image = "info", ImageSize = 16, Color = Color3.fromRGB(120, 180, 255),
})

task.defer(function()
    if S.guiOn then buildPanel() end
end)

if getgenv().HB_win and type(getgenv().HB_win.OnClose) == "function" then
    pcall(function()
        getgenv().HB_win:OnClose(function()
            S.on = false
            release()
        end)
    end)
end
print("[自动连点器] 已加载（自实现版）")
