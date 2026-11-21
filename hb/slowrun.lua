--[[ 缓慢的快速跑（重写版 · 自实现，无远程混淆加载）
     原理：
       1. WalkSpeed 拉高 —— 人是真的跑得快
       2. 把角色「移动类动画」(Run/Walk) 的播放速度压低 —— 看起来是慢动作
       3. 新动画由 Animator.AnimationPlayed 事件补速度，全程事件驱动，零轮询
]]
if getgenv().__HB_SLOWRUN_LOADED then return end
local Tab = (getgenv().Tabs and getgenv().Tabs.PlayerTab) or getgenv().SuturePlayerTab
if not Tab then warn("[缓慢的快速跑] 没拿到 PlayerTab") return end
getgenv().__HB_SLOWRUN_LOADED = true

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local WindUI = getgenv().HB_WindUI

local function notify(t, c, icon)
    if type(WindUI) == "table" then
        pcall(function()
            WindUI:Notify({ Title = tostring(t), Content = tostring(c or ""), Icon = icon or "check", Duration = 2 })
        end)
    end
    print(("[缓慢的快速跑] %s | %s"):format(tostring(t), tostring(c)))
end

local S = {
    on = false,
    speed = 120,
    animSpeed = 0.35,
    baseSpeed = 16,
    conns = {},
}

local function getHum()
    local ch = LP.Character
    return ch and ch:FindFirstChildOfClass("Humanoid")
end
local function getAnimator()
    local hum = getHum()
    return hum and hum:FindFirstChildOfClass("Animator")
end

local function clearConns()
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    S.conns = {}
end

local function tuneTracks()
    local anim = getAnimator()
    if not anim then return end
    for _, t in ipairs(anim:GetPlayingAnimationTracks()) do
        pcall(function() t:AdjustSpeed(S.animSpeed) end)
    end
end

local function start()
    clearConns()
    local hum = getHum()
    if not hum then notify("缓慢的快速跑", "角色未加载", "x") return end
    S.baseSpeed = hum.WalkSpeed
    hum.WalkSpeed = S.speed
    tuneTracks()
    local anim = getAnimator()
    if anim then
        table.insert(S.conns, anim.AnimationPlayed:Connect(function(track)
            if not S.on then return end
            pcall(function() track:AdjustSpeed(S.animSpeed) end)
        end))
    end
    -- 角色重生后自动重新套用（一次连接，不轮询）
    table.insert(S.conns, LP.CharacterAdded:Connect(function()
        if not S.on then return end
        task.wait(0.6)
        local h = getHum()
        if h then h.WalkSpeed = S.speed end
        local a = getAnimator()
        if a then
            table.insert(S.conns, a.AnimationPlayed:Connect(function(track)
                if not S.on then return end
                pcall(function() track:AdjustSpeed(S.animSpeed) end)
            end))
        end
        tuneTracks()
    end))
end

local function stop()
    S.on = false
    clearConns()
    local hum = getHum()
    if hum then
        pcall(function() hum.WalkSpeed = (S.baseSpeed > 0 and S.baseSpeed) or 16 end)
    end
    local anim = getAnimator()
    if anim then
        for _, t in ipairs(anim:GetPlayingAnimationTracks()) do
            pcall(function() t:AdjustSpeed(1) end)
        end
    end
end

local sec = Tab:Section({ Title = "缓慢的快速跑", Icon = "footprints", Opened = true })

sec:Paragraph({
    Title = "慢动作外观 + 真实高速",
    Desc = "移动速度拉高，同时把跑步动画压成慢放，看起来慢其实飞快。全程事件驱动，不占帧。",
    Image = "info", ImageSize = 16, Color = Color3.fromRGB(120, 180, 255),
})

sec:Toggle({
    Title = "启用",
    Desc = "开启后角色移动动画会变成慢动作",
    Value = false,
    Callback = function(v)
        S.on = v
        if v then start() else stop() end
    end,
})

sec:Slider({
    Title = "移动速度",
    Desc = "真实的行走/奔跑速度",
    Value = 120, Min = 16, Max = 500, Rounding = 0,
    Callback = function(v)
        S.speed = v
        if S.on then
            local hum = getHum()
            if hum then hum.WalkSpeed = v end
        end
    end,
})

sec:Slider({
    Title = "动画慢放倍率",
    Desc = "越小越慢（0.1 = 慢十倍）",
    Value = 0.35, Min = 0.05, Max = 1, Rounding = 2,
    Callback = function(v)
        S.animSpeed = v
        if S.on then tuneTracks() end
    end,
})

sec:Button({
    Title = "立即套用一次",
    Desc = "改了速度又不想重开开关时点这个",
    Icon = "refresh-cw",
    Callback = function()
        if not S.on then notify("缓慢的快速跑", "先打开「启用」", "x") return end
        local hum = getHum()
        if hum then hum.WalkSpeed = S.speed end
        tuneTracks()
        notify("缓慢的快速跑", "已套用", "check")
    end,
})

if getgenv().HB_win and type(getgenv().HB_win.OnClose) == "function" then
    pcall(function() getgenv().HB_win:OnClose(function() stop() end) end)
end
print("[缓慢的快速跑] 已加载（自实现版）")
