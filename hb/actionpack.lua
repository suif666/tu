--[[ 动作包（重写版 · 自实现）
     功能：动画选择播放 / 鬼畜抽搐 / 甩头 / 冻结动画 / 循环当前动画 / 刷新动画
     要点：所有循环只在开关打开时运行，关闭立刻退出
]]
if getgenv().__HB_ACTIONPACK_LOADED then return end
local Tab = (getgenv().Tabs and getgenv().Tabs.HBAnimTab) or getgenv().SutureHBAnimTab
if not Tab then warn("[动作包] 没拿到 HBAnimTab") return end
getgenv().__HB_ACTIONPACK_LOADED = true

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local WindUI = getgenv().HB_WindUI

local function notify(t, c, icon)
    if type(WindUI) == "table" then
        pcall(function()
            WindUI:Notify({ Title = tostring(t), Content = tostring(c or ""), Icon = icon or "check", Duration = 2 })
        end)
    end
    print(("[动作包] %s | %s"):format(tostring(t), tostring(c)))
end

local function getHum()
    local ch = LP.Character
    return ch and ch:FindFirstChildOfClass("Humanoid")
end
local function getAnimator()
    local h = getHum()
    return h and h:FindFirstChildOfClass("Animator")
end
local function tracks()
    local a = getAnimator()
    return a and a:GetPlayingAnimationTracks() or {}
end
local function setAllSpeed(v)
    for _, t in ipairs(tracks()) do pcall(function() t:AdjustSpeed(v) end) end
end
local function stopAll()
    for _, t in ipairs(tracks()) do pcall(function() t:Stop() end) end
end

local ACTIONS = {
    { name = "R15 待机",    id = "507766666" },
    { name = "R15 走",      id = "507777826" },
    { name = "R15 跑",      id = "507767714" },
    { name = "R15 跳",      id = "507765000" },
    { name = "R15 下落",    id = "507767968" },
    { name = "R6 待机",     id = "180435571" },
    { name = "R6 走",       id = "180435792" },
    { name = "R6 跑",       id = "180426354" },
    { name = "R6 跳",       id = "125750702" },
    { name = "摔倒",        id = "180436148" },
    { name = "坐下",        id = "2506281703" },
    { name = "Ninja 跑",    id = "750781874" },
}

local own = {}
local function play(id, looped)
    local a = getAnimator()
    if not a then notify("动作包", "角色未加载", "x") return end
    id = tostring(id or ""):gsub("%D", "")
    if id == "" then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. id
    local ok, tr = pcall(function() return a:LoadAnimation(anim) end)
    if not ok or not tr then notify("动作包", "ID 无效", "x") return end
    pcall(function()
        tr.Looped = looped and true or false
        tr:Play()
    end)
    table.insert(own, { tr = tr, anim = anim })
end

-- ── 鬼畜抽搐 ──
local twitch = { on = false, thread = nil, speed = 0.05 }
local function twitchLoop()
    while twitch.on do
        for _, t in ipairs(tracks()) do
            pcall(function() t:AdjustSpeed(0.2 + math.random() * 2.6) end)
        end
        local h = getHum()
        if h then
            pcall(function()
                h.CameraOffset = Vector3.new(
                    (math.random() - 0.5) * 0.12,
                    (math.random() - 0.5) * 0.12,
                    0
                )
            end)
        end
        task.wait(twitch.speed)
    end
    local h = getHum()
    if h then pcall(function() h.CameraOffset = Vector3.new(0, 0, 0) end) end
    setAllSpeed(1)
end

-- ── 甩头 ──
local headSpin = { on = false, thread = nil, speed = 0.03 }
local function headSpinLoop()
    while headSpin.on do
        local ch = LP.Character
        local head = ch and ch:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            pcall(function()
                head.CFrame = head.CFrame * CFrame.Angles(0, math.rad(35), math.rad(math.random(-25, 25)))
            end)
        end
        task.wait(headSpin.speed)
    end
end

-- ── 冻结动画 ──
local frozen = false
local function freeze()
    frozen = true
    setAllSpeed(0)
    notify("动作包", "动画已冻结（速度 0）", "check")
end
local function unfreeze()
    frozen = false
    setAllSpeed(1)
    notify("动作包", "动画已解冻", "check")
end

local sec = Tab:Section({ Title = "动画控制", Icon = "film", Opened = true })

local picked = ACTIONS[1].id
local function actionOptions()
    local out = {}
    for _, a in ipairs(ACTIONS) do
        out[#out + 1] = { Title = a.id, Desc = a.name }
    end
    return out
end

sec:Dropdown({
    Title = "选择动作",
    Desc = "常用动作，选中后点下面的播放",
    Values = actionOptions(),
    Value = nil,
    Callback = function(v)
        if type(v) == "table" then picked = v.Title or picked else picked = tostring(v or picked) end
    end,
})

sec:Button({
    Title = "播放选中动作",
    Desc = "循环播放选中的动作",
    Icon = "play",
    Callback = function()
        play(picked, true)
        notify("动作包", "播放 " .. tostring(picked), "check")
    end,
})

sec:Button({
    Title = "停止所有动画",
    Desc = "停掉当前所有动画轨道",
    Icon = "square",
    Callback = function()
        stopAll()
        notify("动作包", "已停止", "check")
    end,
})

local sec2 = Tab:Section({ Title = "动作控制", Icon = "activity", Opened = true })

sec2:Toggle({
    Title = "鬼畜抽搐",
    Desc = "随机抖动动画速度 + 镜头微晃",
    Value = false,
    Callback = function(v)
        twitch.on = v
        if v then
            if not twitch.thread or coroutine.status(twitch.thread) == "dead" then
                twitch.thread = task.spawn(twitchLoop)
            end
        end
    end,
})

sec2:Toggle({
    Title = "甩头",
    Desc = "每帧微旋头部（视觉抽搐）",
    Value = false,
    Callback = function(v)
        headSpin.on = v
        if v then
            if not headSpin.thread or coroutine.status(headSpin.thread) == "dead" then
                headSpin.thread = task.spawn(headSpinLoop)
            end
        end
    end,
})

sec2:Button({
    Title = "定住动画",
    Desc = "把所有动画速度设为 0（定格）",
    Icon = "pause",
    Callback = function() freeze() end,
})

sec2:Button({
    Title = "解冻动画",
    Desc = "恢复动画速度为 1",
    Icon = "play",
    Callback = function() unfreeze() end,
})

sec2:Button({
    Title = "循环当前动画",
    Desc = "把正在播放的动画全部设为循环",
    Icon = "repeat",
    Callback = function()
        local n = 0
        for _, t in ipairs(tracks()) do
            pcall(function()
                t.Looped = true
                if not t.IsPlaying then t:Play() end
                n = n + 1
            end)
        end
        notify("动作包", ("已设为循环 %d 条"):format(n), "check")
    end,
})

sec2:Button({
    Title = "刷新动画",
    Desc = "停止所有轨道后重新加载一次 Humanoid 默认动画",
    Icon = "refresh-cw",
    Callback = function()
        stopAll()
        local ch = LP.Character
        local animate = ch and ch:FindFirstChild("Animate")
        if animate then
            -- Animate 脚本自己有 Enabled 开关，关一下再开会重新挂载默认动画
            pcall(function()
                animate.Enabled = false
                task.wait(0.05)
                animate.Enabled = true
            end)
            notify("动作包", "动画已刷新", "check")
        else
            notify("动作包", "角色里没有 Animate 脚本", "x")
        end
    end,
})

sec2:Button({
    Title = "自定义动画包",
    Desc = "把一组常用动作一次性循环起来（跑 + 跳 + 待机）",
    Icon = "package",
    Callback = function()
        for _, id in ipairs({ "507767714", "507765000", "507766666" }) do
            play(id, true)
            task.wait(0.1)
        end
        notify("动作包", "已套用组合动作包", "check")
    end,
})

sec2:Paragraph({
    Title = "说明",
    Desc = "「鬼畜抽搐」「甩头」只在你打开时运行，关掉立即停止；冻结/解冻直接调 AdjustSpeed，不改任何游戏脚本。",
    Image = "info", ImageSize = 16, Color = Color3.fromRGB(120, 180, 255),
})

if getgenv().HB_win and type(getgenv().HB_win.OnClose) == "function" then
    pcall(function()
        getgenv().HB_win:OnClose(function()
            twitch.on = false
            headSpin.on = false
            setAllSpeed(1)
            stopAll()
        end)
    end)
end
print("[动作包] 已加载（自实现版）")
