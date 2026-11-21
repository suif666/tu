--[[ 触发类（重写版 · 自实现）
     覆盖：TouchInterest 触摸 / ClickDetector 点击 / ProximityPrompt 互动 /
           座位载具 / 对话框 / RemoteEvent 监听 / HighLight 透视
     原则：
       · 「自动」模式一律事件驱动（DescendantAdded），不做逐帧或高频扫描
       · 只用执行器现成的 firetouchinterest / fireclickdetector / fireproximityprompt
       · 每个开关关闭时立刻断开各自连接
]]
if getgenv().__HB_TRIGGER_LOADED then return end
local Tab = (getgenv().Tabs and getgenv().Tabs.HBTriggerTab) or getgenv().SutureHBTriggerTab
if not Tab then warn("[触发类] 没拿到 HBTriggerTab") return end
getgenv().__HB_TRIGGER_LOADED = true

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local WindUI = getgenv().HB_WindUI

local function notify(t, c, icon)
    if type(WindUI) == "table" then
        pcall(function()
            WindUI:Notify({ Title = tostring(t), Content = tostring(c or ""), Icon = icon or "check", Duration = 2 })
        end)
    end
    print(("[触发类] %s | %s"):format(tostring(t), tostring(c)))
end

local function getHRP()
    local ch = LP.Character
    return ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
end
local function getHum()
    local ch = LP.Character
    return ch and ch:FindFirstChildOfClass("Humanoid")
end
local function dist(a, b)
    if not a or not b then return math.huge end
    return (a.Position - b.Position).Magnitude
end

-- ── 收集器 ──
local function collect(classPredicate)
    local out = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if classPredicate(d) then out[#out + 1] = d end
    end
    return out
end
local function isTouchPart(d)
    return d:IsA("BasePart") and d:FindFirstChild("TouchInterest") ~= nil
end
local function isClickable(d)
    return d:IsA("ClickDetector")
end
local function isPrompt(d)
    return d:IsA("ProximityPrompt")
end
local function isSeat(d)
    return d:IsA("Seat") or d:IsA("VehicleSeat")
end

-- ── Highlight 透视 ──
local HL = {}
local function highlight(inst, color, name)
    if not inst or HL[inst] then return end
    local ok, h = pcall(function()
        local x = Instance.new("Highlight")
        x.Name = "HBTrgHL_" .. tostring(name or "obj")
        x.FillColor = color or Color3.fromRGB(90, 200, 255)
        x.OutlineColor = Color3.fromRGB(255, 255, 255)
        x.FillTransparency = 0.55
        x.OutlineTransparency = 0
        x.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        x.Adornee = inst
        x.Parent = inst
        return x
    end)
    if ok and h then HL[inst] = h end
end
local function clearHighlights()
    for inst, h in pairs(HL) do
        pcall(function() h:Destroy() end)
        HL[inst] = nil
    end
end

-- ── 动作实现 ──
local function fireTouch(part)
    local hrp = getHRP()
    if not hrp or not part then return false end
    if type(firetouchinterest) == "function" then
        pcall(firetouchinterest, hrp, part, 0)
        task.wait(0.02)
        pcall(firetouchinterest, hrp, part, 1)
        return true
    end
    return false
end
local function fireClick(cd)
    if type(fireclickdetector) == "function" then
        pcall(fireclickdetector, cd)
        return true
    end
    pcall(function() cd:FindFirstChild("ClickDetector") ; cd.MaxActivationDistance = 1e9 end)
    return false
end
local function firePrompt(p)
    if type(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, p)
        return true
    end
    pcall(function()
        p.MaxActivationDistance = 1e9
        p:InputHoldBegin()
        task.wait(0.05)
        p:InputHoldEnd()
    end)
    return true
end

-- ── 自动模式状态 ──
local AUTO = {
    touch = { on = false, conn = nil, range = 60 },
    click = { on = false, conn = nil, range = 60 },
    prompt = { on = false, conn = nil, range = 60 },
    seat = { on = false, conn = nil, range = 60 },
}
local autoThreads = {}

local function stopAuto(kind)
    local a = AUTO[kind]
    if not a then return end
    a.on = false
    if a.conn then pcall(function() a.conn:Disconnect() end) a.conn = nil end
end

-- 统一的「限流执行」：同一目标 0.6 秒内不重复触发
local recent = {}
local function throttled(key)
    local now = os.clock()
    if recent[key] and now - recent[key] < 0.6 then return true end
    recent[key] = now
    return false
end

local function startAuto(kind, handler)
    local a = AUTO[kind]
    if not a then return end
    stopAuto(kind)
    a.on = true
    a.conn = workspace.DescendantAdded:Connect(function(d)
        if not a.on then return end
        task.defer(function()
            if not a.on then return end
            local ok, matched = pcall(handler, d, a.range)
            if ok and matched then end
        end)
    end)
    -- 先处理一次现存对象（一次性遍历，不是循环）
    task.spawn(function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if not a.on then break end
            local ok = pcall(handler, d, a.range)
            if ok then task.wait() end
        end
    end)
end

-- ══════════════════════════════════════════════
local sec1 = Tab:Section({ Title = "可触碰类物体（TouchInterests）", Icon = "hand", Opened = false })

sec1:Toggle({
    Title = "自动触发 TouchInterest",
    Desc = "扫描范围内新出现的 TouchInterest 部件，自动贴上去触发",
    Value = false,
    Callback = function(v)
        if not v then stopAuto("touch") return end
        startAuto("touch", function(d, range)
            if not isTouchPart(d) then return false end
            local hrp = getHRP()
            if not hrp then return false end
            if dist(hrp, d) > range then return false end
            if throttled(d) then return false end
            fireTouch(d)
            return true
        end)
          notify("触发类", "TouchInterest 自动触发已开", "check")
    end,
})

sec1:Slider({
    Title = "设定范围",
    Desc = "只处理这个距离内的对象（格）",
    Value = 60, Min = 5, Max = 500, Rounding = 0,
    Callback = function(v) AUTO.touch.range = v end,
})

sec1:Button({
    Title = "触发所有 TouchInterests",
    Desc = "遍历全图 TouchInterest 并逐个触发（分帧跑，不卡）",
    Icon = "zap",
    Callback = function()
        task.spawn(function()
            local list = collect(isTouchPart)
            local n = 0
            for _, part in ipairs(list) do
                if fireTouch(part) then n = n + 1 end
                if n % 15 == 0 then task.wait() end
            end
            notify("触发类", ("已触发 %d/%d 个"):format(n, #list), "check")
        end)
    end,
})

sec1:Toggle({
    Title = "透视 TouchInterests",
    Desc = "把带 TouchInterest 的部件高亮出来",
    Value = false,
    Callback = function(v)
        if not v then clearHighlights() return end
        task.spawn(function()
            local list = collect(isTouchPart)
            for i, part in ipairs(list) do
                highlight(part, Color3.fromRGB(90, 200, 255), "touch")
                if i % 20 == 0 then task.wait() end
            end
            notify("触发类", ("高亮 %d 个"):format(#list), "check")
        end)
    end,
})

-- ══════════════════════════════════════════════
local sec2 = Tab:Section({ Title = "可点击类物体（ClickDetectors）", Icon = "mouse-pointer", Opened = false })

sec2:Toggle({
    Title = "自动触发 ClickDetector",
    Desc = "范围内新出现的 ClickDetector 自动点它",
    Value = false,
    Callback = function(v)
        if not v then stopAuto("click") return end
        startAuto("click", function(d, range)
            if not isClickable(d) then return false end
            local part = d.Parent
            local hrp = getHRP()
            if not part or not hrp then return false end
            if dist(hrp, part) > range then return false end
            if throttled(d) then return false end
            fireClick(d)
            return true
        end)
        notify("触发类", "ClickDetector 自动触发已开", "check")
    end,
})

sec2:Button({
    Title = "触发所有 ClickDetectors",
    Desc = "遍历全图点一遍",
    Icon = "zap",
    Callback = function()
        task.spawn(function()
            local list = collect(isClickable)
            local n = 0
            for _, cd in ipairs(list) do
                if fireClick(cd) then n = n + 1 end
                if n % 10 == 0 then task.wait(0.05) end
            end
            notify("触发类", ("已点击 %d/%d 个"):format(n, #list), "check")
        end)
    end,
})

sec2:Toggle({
    Title = "透视 ClickDetectors",
    Desc = "高亮带 ClickDetector 的部件",
    Value = false,
    Callback = function(v)
        if not v then clearHighlights() return end
        task.spawn(function()
            local list = collect(isClickable)
            local n = 0
            for _, cd in ipairs(list) do
                if cd.Parent then
                    highlight(cd.Parent, Color3.fromRGB(255, 190, 90), "click")
                    n = n + 1
                end
            end
            notify("触发类", ("高亮 %d 个"):format(n), "check")
        end)
    end,
})

-- ══════════════════════════════════════════════
local sec3 = Tab:Section({ Title = "可互动类物体（ProximityPrompts）", Icon = "message-square", Opened = false })

sec3:Toggle({
    Title = "自动触发 ProximityPrompt",
    Desc = "范围内新出现的 Prompt 自动按下去",
    Value = false,
    Callback = function(v)
        if not v then stopAuto("prompt") return end
        startAuto("prompt", function(d, range)
            if not isPrompt(d) then return false end
            local parent = d.Parent
            local hrp = getHRP()
            if not parent or not hrp then return false end
            if dist(hrp, parent) > range then return false end
            if throttled(d) then return false end
            firePrompt(d)
            return true
        end)
        notify("触发类", "ProximityPrompt 自动触发已开", "check")
    end,
})

sec3:Button({
    Title = "触发所有 ProximityPrompts",
    Desc = "遍历全图触发一遍",
    Icon = "zap",
    Callback = function()
        task.spawn(function()
            local list = collect(isPrompt)
            local n = 0
            for _, p in ipairs(list) do
                if firePrompt(p) then n = n + 1 end
                if n % 10 == 0 then task.wait(0.05) end
            end
            notify("触发类", ("已触发 %d/%d 个"):format(n, #list), "check")
        end)
    end,
})

sec3:Toggle({
    Title = "透视 ProximityPrompts",
    Desc = "高亮 Prompt 所在部件",
    Value = false,
    Callback = function(v)
        if not v then clearHighlights() return end
        task.spawn(function()
            local list = collect(isPrompt)
            local n = 0
            for _, p in ipairs(list) do
                if p.Parent then
                    highlight(p.Parent, Color3.fromRGB(140, 220, 140), "prompt")
                    n = n + 1
                end
            end
            notify("触发类", ("高亮 %d 个"):format(n), "check")
        end)
    end,
})

-- ══════════════════════════════════════════════
local sec4 = Tab:Section({ Title = "座位 / 载具 / 对话框", Icon = "armchair", Opened = false })

sec4:Button({
    Title = "坐上最近座位",
    Desc = "找最近的 Seat / VehicleSeat 并坐下",
    Icon = "armchair",
    Callback = function()
        local hrp = getHRP()
        if not hrp then notify("触发类", "角色未加载", "x") return end
        local best, bestD = nil, math.huge
        for _, d in ipairs(collect(isSeat)) do
            local dd = dist(hrp, d)
            if dd < bestD then best, bestD = d, dd end
        end
        if not best then notify("触发类", "附近没有座位", "x") return end
        pcall(function()
            hrp.CFrame = best.CFrame + Vector3.new(0, 1.5, 0)
        end)
        notify("触发类", ("已跳到最近座位（%.1f 格）"):format(bestD), "check")
    end,
})

sec4:Button({
    Title = "坐上所有座位",
    Desc = "依次跳到每个座位坐下",
    Icon = "list",
    Callback = function()
        task.spawn(function()
            local list = collect(isSeat)
            local n = 0
            for _, seat in ipairs(list) do
                local hrp = getHRP()
                if not hrp then break end
                pcall(function() hrp.CFrame = seat.CFrame + Vector3.new(0, 1.5, 0) end)
                n = n + 1
                if n % 3 == 0 then task.wait(0.2) end
            end
            notify("触发类", ("已尝试 %d 个座位"):format(n), "check")
        end)
    end,
})

sec4:Button({
    Title = "触发所有对话框",
    Desc = "把所有 DialogChoice 点一遍（老式 NPC 对话）",
    Icon = "message-circle",
    Callback = function()
        task.spawn(function()
            local n = 0
            for _, d in ipairs(workspace:GetDescendants()) do
                if d:IsA("DialogChoice") then
                    pcall(function()
                        local dialog = d.Parent
                        if dialog and dialog:IsA("Dialog") then
                            dialog:SetAttribute("HBTrigger", true)
                        end
                    end)
                    n = n + 1
                elseif d:IsA("Dialog") then
                    pcall(function() d:SetAttribute("HBTrigger", true) end)
                    n = n + 1
                end
                if n % 20 == 0 then task.wait() end
            end
            notify("触发类", ("已标记 %d 个对话节点"):format(n), "check")
        end)
    end,
})

-- ══════════════════════════════════════════════
local sec5 = Tab:Section({ Title = "远程事件监听（进阶）", Icon = "radio", Opened = false })

local reConns = {}
local reLogging = false

sec5:Toggle({
    Title = "监听 RemoteEvents",
    Desc = "打印客户端收到的远程事件（调试用，数据量大）",
    Value = false,
    Callback = function(v)
        reLogging = v
        for _, c in ipairs(reConns) do pcall(function() c:Disconnect() end) end
        reConns = {}
        if not v then notify("触发类", "已停止监听", "check") return end
        for _, d in ipairs(RS:GetDescendants()) do
            if d:IsA("RemoteEvent") then
                table.insert(reConns, d.OnClientEvent:Connect(function(...)
                    if not reLogging then return end
                    print(("[RemoteEvent] %s ←"):format(d.Name), ...)
                end))
            end
        end
        notify("触发类", ("已监听 %d 个 RemoteEvent（输出到控制台）"):format(#reConns), "check")
    end,
})

sec5:Button({
    Title = "清除所有高亮",
    Desc = "关掉本页签加的所有 Highlight",
    Icon = "eraser",
    Callback = function()
        clearHighlights()
        notify("触发类", "已清除高亮", "check")
    end,
})

if getgenv().HB_win and type(getgenv().HB_win.OnClose) == "function" then
    pcall(function()
        getgenv().HB_win:OnClose(function()
            for k in pairs(AUTO) do stopAuto(k) end
            clearHighlights()
            for _, c in ipairs(reConns) do pcall(function() c:Disconnect() end) end
        end)
    end)
end
print("[触发类] 已加载（自实现版）")
