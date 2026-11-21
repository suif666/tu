--[[ 动作动画（重写版 · 自实现，无远程混淆加载）
     功能：自定义动画 ID 播放 / 快捷动画 / 停止 / 全局速度 / 直接播放商城 Emote 动画
     要点：所有动画通过 Animator:LoadAnimation 播放，全局速度用 AdjustSpeed，
           播放状态只维护一张 track 表，零轮询。
]]
if getgenv().__HB_ANIM_LOADED then return end
local Tab = (getgenv().Tabs and getgenv().Tabs.HBAnimTab) or getgenv().SutureHBAnimTab
if not Tab then warn("[动作动画] 没拿到 HBAnimTab") return end
getgenv().__HB_ANIM_LOADED = true

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local WindUI = getgenv().HB_WindUI

local function notify(t, c, icon)
    if type(WindUI) == "table" then
        pcall(function()
            WindUI:Notify({ Title = tostring(t), Content = tostring(c or ""), Icon = icon or "check", Duration = 2 })
        end)
    end
    print(("[动作动画] %s | %s"):format(tostring(t), tostring(c)))
end

-- 记录我们自己放出去的 track，方便统一停/调速
local own = {}
local globalSpeed = 1
local currentId = ""

local function getAnimator()
    local ch = LP.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    return hum and hum:FindFirstChildOfClass("Animator")
end

local function loadTrack(id)
    local animator = getAnimator()
    if not animator then return nil, "角色未加载" end
    id = tostring(id or ""):gsub("%D", "")
    if id == "" then return nil, "动画 ID 为空" end
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. id
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    if not ok or not track then
        anim:Destroy()
        return nil, "加载失败（ID 无效或被限制）"
    end
    return track, nil, anim
end

local function play(id, looped)
    local track, err, anim = loadTrack(id)
    if not track then notify("播放失败", err, "x") return false end
    pcall(function()
        track.Looped = looped and true or false
        track:AdjustSpeed(globalSpeed)
        track:Play()
    end)
    table.insert(own, { track = track, anim = anim })
    -- 清理已停止的，避免表无限增长
    for i = #own, 1, -1 do
        local e = own[i]
        if not e.track.IsPlaying then
            pcall(function() e.track:Stop() end)
            pcall(function() if e.anim then e.anim:Destroy() end end)
            table.remove(own, i)
        end
    end
    return true
end

local function stopAll()
    local animator = getAnimator()
    if animator then
        for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
            pcall(function() t:Stop() end)
        end
    end
    for _, e in ipairs(own) do
        pcall(function() e.track:Stop() end)
        pcall(function() if e.anim then e.anim:Destroy() end end)
    end
    own = {}
end

local function applySpeed(v)
    globalSpeed = v
    local animator = getAnimator()
    if animator then
        for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
            pcall(function() t:AdjustSpeed(v) end)
        end
    end
    for _, e in ipairs(own) do
        pcall(function() e.track:AdjustSpeed(v) end)
    end
end

-- ── 常用动画 ID（来自官方目录，不依赖任何远程脚本）──
local EMOTES = {
    { name = "R15 挥手 / Wave",   id = "128777973" },
    { name = "R15 鼓掌 / Clap",   id = "128746807" },
    { name = "R15 指点 / Point",  id = "128853357" },
    { name = "R15 嘲讽 / Dismiss", id = "128746807" },
    { name = "R15 慵懒躺 / Laugh", id = "129423131" },
    { name = "R15 复习 / Think",  id = "1519834271" },
    { name = "R6 跳舞 / Dance",   id = "180435792" },
    { name = "R15 踢踏舞 / Dance", id = "507771019" },
    { name = "R15 街舞 / HipHop", id = "507776043" },
    { name = "R15 机器人舞",       id = "507777826" },
    { name = "R15 大鹏展翅",       id = "507770818" },
    { name = "R6 Wave",           id = "128777973" },
}

local function emoteOptions()
    local out = {}
    for _, e in ipairs(EMOTES) do
        out[#out + 1] = { Title = tostring(e.id), Desc = e.name }
    end
    return out
end

local sec = Tab:Section({ Title = "自定义动画", Icon = "play", Opened = true })

local idInput = ""
sec:Input({
    Title = "动画 ID",
    Desc = "rbxassetid 后面的那串数字，例如 507771019",
    Value = "",
    Callback = function(v) idInput = tostring(v or "") end,
})

sec:Slider({
    Title = "播放速度",
    Desc = "这条动画的倍速",
    Value = 1, Min = 0.1, Max = 5, Rounding = 2,
    Callback = function(v) globalSpeed = v end,
})

local loopToggle = false
sec:Toggle({
    Title = "循环播放",
    Desc = "打开后播放会一直循环",
    Value = false,
    Callback = function(v) loopToggle = v end,
})

sec:Button({
    Title = "播放自定义动画",
    Desc = "用上面的 ID 和速度播放",
    Icon = "play",
    Callback = function()
        if play(idInput, loopToggle) then
            notify("动作动画", "已播放 " .. tostring(idInput), "check")
        end
    end,
})

local sec2 = Tab:Section({ Title = "快捷动画", Icon = "zap", Opened = true })

sec2:Dropdown({
    Title = "选择动画",
    Desc = "常用 Emote，选中后点下面的播放",
    Values = emoteOptions(),
    Value = nil,
    Callback = function(v)
        if type(v) == "table" then currentId = v.Title or "" else currentId = tostring(v or "") end
    end,
})

sec2:Button({
    Title = "播放选中动画",
    Desc = "播放上面选中的 Emote，并循环",
    Icon = "play",
    Callback = function()
        if currentId == "" then notify("动作动画", "先选一个动画", "x") return end
        if play(currentId, true) then notify("动作动画", "播放 " .. currentId, "check") end
    end,
})

sec2:Button({
    Title = "随机跳舞",
    Desc = "从上面那批里随机挑一个循环播放",
    Icon = "shuffle",
    Callback = function()
        local id = EMOTES[math.random(#EMOTES)].id
        if play(id, true) then notify("动作动画", "随机播放 " .. id, "check") end
    end,
})

sec2:Button({
    Title = "停止所有动画",
    Desc = "停掉当前正在播的动画",
    Icon = "square",
    Callback = function()
        stopAll()
        notify("动作动画", "已停止", "check")
    end,
})

local sec3 = Tab:Section({ Title = "全局动画速度", Icon = "gauge", Opened = true })

sec3:Slider({
    Title = "全局动画速度",
    Desc = "影响所有正在播放的动画（1 = 原始速度）",
    Value = 1, Min = 0.1, Max = 5, Rounding = 2,
    Callback = function(v) applySpeed(v) end,
})

sec3:Button({
    Title = "恢复速度 1",
    Desc = "把所有动画速度重置为原始",
    Icon = "rotate-ccw",
    Callback = function()
        applySpeed(1)
        notify("动作动画", "速度已恢复 1", "check")
    end,
})

sec3:Paragraph({
    Title = "商城动画（已改为直接播放）",
    Desc = "原版靠远程加载混淆脚本去「解锁」，本质上还是往 Animator 里塞动画 ID。这里直接用官方目录的 ID 播放，不走任何远程代码。",
    Image = "info", ImageSize = 16, Color = Color3.fromRGB(120, 180, 255),
})

sec3:Button({
    Title = "解锁所有商城动画",
    Desc = "对角色身上的 Emote 逐个放一次（走本地目录，不远程）",
    Icon = "unlock",
    Callback = function()
        task.spawn(function()
            local n = 0
            for _, e in ipairs(EMOTES) do
                local track = loadTrack(e.id)
                if track then
                    pcall(function()
                        track.Looped = false
                        track:Play()
                        task.wait(0.15)
                        track:Stop()
                    end)
                    n = n + 1
                end
            end
            notify("动作动画", ("已逐一播放 %d 个 Emote"):format(n), "check")
        end)
    end,
})

if getgenv().HB_win and type(getgenv().HB_win.OnClose) == "function" then
    pcall(function() getgenv().HB_win:OnClose(function() stopAll() end) end)
end
print("[动作动画] 已加载（自实现版）")
