--[[ 灾害预警（重写版 · 自实现）
     自然灾害生存：读 workspace 里的 SurvivalTag(StringValue) → 翻译 → 播报
     要点：事件驱动（Attribute/Value 变化 + ChildAdded），不轮询
]]
if getgenv().__HB_DISASTER_LOADED then return end
local Tab = (getgenv().Tabs and getgenv().Tabs.ZRZHTab) or getgenv().SutureZRZHTab
if not Tab then warn("[灾害预警] 没拿到 ZRZHTab") return end
getgenv().__HB_DISASTER_LOADED = true

local Players = game:GetService("Players")
local WindUI = getgenv().HB_WindUI
local TAG_NAME = "SurvivalTag"

local function notify(t, c, icon)
    if type(WindUI) == "table" then
        pcall(function()
            WindUI:Notify({ Title = tostring(t), Content = tostring(c or ""), Icon = icon or "alert-triangle", Duration = 4 })
        end)
    end
    print(("[灾害预警] %s | %s"):format(tostring(t), tostring(c)))
end

local DISASTERS = {
    ["Blizzard"] = "暴风雪",
    ["Sandstorm"] = "沙尘暴",
    ["Tornado"] = "龙卷风",
    ["Volcanic Eruption"] = "火山喷发",
    ["Flash Flood"] = "洪水",
    ["Deadly Virus"] = "致命病毒",
    ["Tsunami"] = "海啸",
    ["Acid Rain"] = "酸雨",
    ["Fire"] = "大火",
    ["Meteor Shower"] = "流星雨",
    ["Earthquake"] = "地震",
    ["Thunder Storm"] = "雷暴",
    ["Avalanche"] = "雪崩",
    ["Lightning"] = "闪电",
}
local ALIAS = {
    ["Thunderstorm"] = "Thunder Storm",
    ["MeteorShower"] = "Meteor Shower",
    ["Volcano"] = "Volcanic Eruption",
    ["Volcanic"] = "Volcanic Eruption",
    ["Virus"] = "Deadly Virus",
    ["Flood"] = "Flash Flood",
    ["Lightening"] = "Lightning",
}

local S = { on = false, unknown = true, conns = {}, last = "" }

local function translate(raw)
    if not raw or raw == "" then return nil end
    local key = ALIAS[raw] or raw
    return DISASTERS[key], key
end

local function announce(raw)
    if raw == S.last then return end
    S.last = raw
    local cn, key = translate(raw)
    if cn then
        notify("灾害预警 · " .. cn, "即将来临：" .. cn .. "（" .. tostring(key) .. "）", "alert-triangle")
    elseif S.unknown then
        notify("灾害预警 · 未知", "未收录的灾害：" .. tostring(raw), "alert-triangle")
    end
end

local function findTag()
    local function scan(root, depth)
        if depth > 2 then return nil end
        for _, v in ipairs(root:GetChildren()) do
            if v.Name == TAG_NAME then return v end
        end
        for _, v in ipairs(root:GetChildren()) do
            local r = scan(v, depth + 1)
            if r then return r end
        end
        return nil
    end
    return scan(workspace, 0) or scan(game:GetService("ReplicatedStorage"), 0)
end

local function watch()
    local tag = findTag()
    if tag then
        announce(tostring(tag.Value))
        table.insert(S.conns, tag.Changed:Connect(function(p)
            if p == "Value" then announce(tostring(tag.Value)) end
        end))
    end
    -- 新一局会重建 tag：事件驱动，不轮询
    table.insert(S.conns, workspace.DescendantAdded:Connect(function(d)
        if not S.on then return end
        if d.Name == TAG_NAME and d:IsA("StringValue") then
            task.defer(function()
                announce(tostring(d.Value))
                table.insert(S.conns, d.Changed:Connect(function(p)
                    if p == "Value" then announce(tostring(d.Value)) end
                end))
            end)
        end
    end))
end

local function stop()
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    S.conns = {}
    S.last = ""
end

local sec = Tab:Section({ Title = "灾害预警", Icon = "triangle-alert", Opened = true })

sec:Paragraph({
    Title = "自然灾害生存 · 灾难提前播报",
    Desc = "盯着 workspace 里的 SurvivalTag，名称一变就弹提示。只在有变化时触发，不循环扫描。",
    Image = "info", ImageSize = 16, Color = Color3.fromRGB(120, 180, 255),
})

sec:Toggle({
    Title = "灾害预警",
    Desc = "开启后监控当前灾害，变化时播报中文名",
    Value = false,
    Callback = function(v)
        S.on = v
        if v then
            watch()
            notify("灾害预警", "已开启", "check")
        else
            stop()
            notify("灾害预警", "已关闭", "check")
        end
    end,
})

sec:Toggle({
    Title = "未知灾害也提示",
    Desc = "对照表里没有的名字，直接弹英文原名（不漏报）",
    Value = true,
    Callback = function(v) S.unknown = v end,
})

sec:Button({
    Title = "立即检测一次",
    Desc = "手动找一次 SurvivalTag 并播报当前灾害",
    Icon = "search",
    Callback = function()
        local tag = findTag()
        if tag then
            S.last = ""
            announce(tostring(tag.Value))
        else
            notify("灾害预警", "没找到 " .. TAG_NAME .. "（可能不在自然灾害生存里）", "x")
        end
    end,
})

sec:Button({
    Title = "打印对照表",
    Desc = "把已收录的灾害名和中文翻译打到控制台",
    Icon = "list",
    Callback = function()
        print("──── 灾害名对照表 ────")
        local list = {}
        for k, v in pairs(DISASTERS) do table.insert(list, { k, v }) end
        table.sort(list, function(a, b) return a[1] < b[1] end)
        for _, e in ipairs(list) do print(("%-22s → %s"):format(e[1], e[2])) end
        print(("共 %d 条（另有 %d 条别名）"):format(#list, (function() local n = 0 for _ in pairs(ALIAS) do n = n + 1 end return n end)()))
        notify("灾害预警", "对照表已打印到控制台", "check")
    end,
})

if getgenv().HB_win and type(getgenv().HB_win.OnClose) == "function" then
    pcall(function() getgenv().HB_win:OnClose(function() stop() end) end)
end
print("[灾害预警] 已加载（自实现版）")
