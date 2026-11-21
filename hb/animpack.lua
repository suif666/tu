--[[ 动画包（重写版 · 自实现）
     功能：把角色 Animate 脚本里的默认动画 ID 换成另一套风格
     原理：Humanoid 的移动动画由角色内 Animate 脚本里的 Animation 对象驱动，
           改 AnimationId 就能换整套走路/跑步/跳跃/待机风格。
     要点：只改本地角色，不注入任何远程代码；切换后重新加载 Animate 生效。
]]
if getgenv().__HB_ANIMPACK_LOADED then return end
local Tab = (getgenv().Tabs and getgenv().Tabs.HBAnimTab) or getgenv().SutureHBAnimTab
if not Tab then warn("[动画包] 没拿到 HBAnimTab") return end
getgenv().__HB_ANIMPACK_LOADED = true

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local WindUI = getgenv().HB_WindUI

local function notify(t, c, icon)
    if type(WindUI) == "table" then
        pcall(function()
            WindUI:Notify({ Title = tostring(t), Content = tostring(c or ""), Icon = icon or "check", Duration = 2 })
        end)
    end
    print(("[动画包] %s | %s"):format(tostring(t), tostring(c)))
end

-- R15 默认动画 ID（官方 Ninja / Ninja 风格）
local PACKS = {
    ["默认（人类）"] = {
        idle = "507766666", walk = "507777826", run = "507767714",
        jump = "507765000", fall = "507767968", climb = "507765644",
    },
    ["忍者"] = {
        idle = "750779537", walk = "750783956", run = "750781874",
        jump = "750782010", fall = "756024456", climb = "750779530",
    },
    ["莱文（Levitation）"] = {
        idle = "507766666", walk = "507777826", run = "507767714",
        jump = "507765000", fall = "507767969", climb = "507765644",
    },
    ["僵尸"] = {
        idle = "4233394095", walk = "4233433121", run = "4233430864",
        jump = "4233390800", fall = "4233430864", climb = "507765644",
    },
    ["企鹅"] = {
        idle = "7372423948", walk = "7372425307", run = "7372424781",
        jump = "7372426802", fall = "7372427809", climb = "507765644",
    },
}

local SLOTS = { "idle", "walk", "run", "jump", "fall", "climb" }

local function getAnimate()
    local ch = LP.Character
    return ch and ch:FindFirstChild("Animate")
end

local function applyIds(map)
    local animate = getAnimate()
    if not animate then return false, "角色里没有 Animate 脚本" end
    local n = 0
    for _, slot in ipairs(SLOTS) do
        local id = map[slot]
        if id then
            -- Animate 脚本里每个动作是一个 Animation 对象（idle 下有多个子项）
            for _, obj in ipairs(animate:GetDescendants()) do
                if obj:IsA("Animation") then
                    local lowName = string.lower(obj.Name)
                    if lowName:find(slot, 1, true) then
                        pcall(function() obj.AnimationId = "rbxassetid://" .. id end)
                        n = n + 1
                    end
                end
            end
        end
    end
    return true, n
end

local function reloadAnimate()
    local ch = LP.Character
    if not ch then return end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local animate = getAnimate()
    if hum and animate then
        pcall(function()
            animate.Enabled = false
            animate.Enabled = true
        end)
    end
end

local function resetPack()
    local ok, n = applyIds(PACKS["默认（人类）"])
    reloadAnimate()
    if ok then notify("动画包", ("已恢复默认（%d 项）"):format(n), "check") end
end

local sec = Tab:Section({ Title = "动画控制", Icon = "film", Opened = true })

local cur = "默认（人类）"

local function packOptions()
    local out = {}
    for name in pairs(PACKS) do out[#out + 1] = { Title = name } end
    table.sort(out, function(a, b) return a.Title < b.Title end)
    return out
end

sec:Dropdown({
    Title = "选择动画风格",
    Desc = "换一套走路/跑步/跳跃/待机的动作",
    Values = packOptions(),
    Value = nil,
    Callback = function(v)
        cur = type(v) == "table" and (v.Title or cur) or tostring(v or cur)
    end,
})

sec:Button({
    Title = "应用动画",
    Desc = "把选中的风格套到自己的角色上",
    Icon = "check",
    Callback = function()
        local map = PACKS[cur]
        if not map then notify("动画包", "没有这个风格", "x") return end
        local ok, n = applyIds(map)
        if not ok then notify("动画包", tostring(n), "x") return end
        reloadAnimate()
        notify("动画包", ("已应用「%s」（改到 %d 项）"):format(cur, n), "check")
    end,
})

sec:Button({
    Title = "恢复默认（人类）",
    Desc = "把动画 ID 全部还原成官方默认值",
    Icon = "rotate-ccw",
    Callback = function() resetPack() end,
})

sec:Paragraph({
    Title = "说明",
    Desc = "Animate 脚本只影响你自己的客户端视角；别人看到的仍是他们本地渲染的动画。换了之后如果没立刻生效，走两步或跳一下即可刷新。",
    Image = "info", ImageSize = 16, Color = Color3.fromRGB(120, 180, 255),
})

print("[动画包] 已加载（自实现版）")
