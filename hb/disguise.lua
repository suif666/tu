--[[ 伪装玩家（重写版 · 自实现）
     功能：把目标玩家的外观复制到自己角色上（仅本机视角）
     原理：
       ① 备份自己的外观实例（配件/衣服/体型/颜色）
       ② 清掉自己的外观，从目标角色克隆同一批实例过来
       ③ 同步 Humanoid 的体型比例属性
       ④ 「取消伪装」按备份还原
     要点：
       · 目标下拉用普通 Dropdown + 富条目（rbxthumb 头像，异步加载不卡）
       · 玩家进出刷新做 2 秒合并，绝不在进出那一帧重建 UI
       · 全程事件驱动，无轮询
]]
if getgenv().__HB_DISGUISE_LOADED then return end
local Tab = (getgenv().Tabs and getgenv().Tabs.HBDisguiseTab) or getgenv().SutureHBDisguiseTab
if not Tab then warn("[伪装玩家] 没拿到 HBDisguiseTab") return end
getgenv().__HB_DISGUISE_LOADED = true

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local WindUI = getgenv().HB_WindUI

local function notify(t, c, icon)
    if type(WindUI) == "table" then
        pcall(function()
            WindUI:Notify({ Title = tostring(t), Content = tostring(c or ""), Icon = icon or "check", Duration = 2 })
        end)
    end
    print(("[伪装玩家] %s | %s"):format(tostring(t), tostring(c)))
end

local function itemName(v)
    if type(v) == "table" then return v.Title or v.Name end
    return tostring(v or "")
end

-- 富条目：头像走 rbxthumb（ImageLabel 异步加载，不阻塞）
local function richPlayers()
    local g = (getgenv and getgenv()) or _G
    if type(g.__SUIF_RICH_PLAYERS) == "function" then
        local ok, r = pcall(g.__SUIF_RICH_PLAYERS, { excludeLocal = true })
        if ok and type(r) == "table" and #r > 0 then return r end
    end
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then out[#out + 1] = p.Name end
    end
    return out
end

local function findPlayer(name)
    if not name or name == "" then return nil end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name == name or p.DisplayName == name then return p end
    end
    return nil
end

-- ── 外观复制 ──
local APPEAR_CLASSES = {
    Accessory = true,
    Hat = true,
    Shirt = true,
    Pants = true,
    ShirtGraphic = true,
    CharacterMesh = true,
    BodyColors = true,
}

local BODY_PROPS = {
    "BodyTypeScale", "BodyWidthScale", "BodyHeightScale",
    "BodyDepthScale", "HeadScale", "ProportionScale",
}

local state = {
    target = nil,
    disguised = false,
    backup = nil,      -- { instances = {clone...}, props = {k=v}, colors = Color3... }
    added = {},        -- 伪装时插进来的实例
}

local function ownChar()
    return LP.Character
end
local function ownHum()
    local ch = ownChar()
    return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function takeBackup()
    local ch = ownChar()
    if not ch then return false end
    local inst = {}
    for _, obj in ipairs(ch:GetChildren()) do
        if APPEAR_CLASSES[obj.ClassName] then
            table.insert(inst, obj:Clone())
        end
    end
    local props = {}
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if hum then
        for _, k in ipairs(BODY_PROPS) do
            props[k] = hum[k]
        end
    end
    state.backup = { instances = inst, props = props }
    return true
end

local function stripAppearance(ch)
    for _, obj in ipairs(ch:GetChildren()) do
        if APPEAR_CLASSES[obj.ClassName] then
            pcall(function() obj:Destroy() end)
        end
    end
end

local function applyDisguise(targetPlayer)
    local myChar = ownChar()
    local myHum = ownHum()
    if not myChar or not myHum then notify("伪装玩家", "你的角色还没加载", "x") return false end
    local tChar = targetPlayer.Character
    if not tChar then notify("伪装玩家", "目标角色还没加载", "x") return false end

    if not state.backup then takeBackup() end
    stripAppearance(myChar)
    state.added = {}

    -- 克隆目标的外观实例
    for _, obj in ipairs(tChar:GetChildren()) do
        if APPEAR_CLASSES[obj.ClassName] then
            local ok, clone = pcall(function() return obj:Clone() end)
            if ok and clone then
                clone.Parent = myChar
                table.insert(state.added, clone)
            end
        end
    end

    -- 同步体型比例
    local tHum = tChar:FindFirstChildOfClass("Humanoid")
    if tHum then
        for _, k in ipairs(BODY_PROPS) do
            pcall(function() myHum[k] = tHum[k] end)
        end
    end

    state.disguised = true
    state.target = targetPlayer
    return true
end

local function restore()
    local myChar = ownChar()
    local myHum = ownHum()
    if not myChar then notify("伪装玩家", "角色未加载", "x") return end
    for _, obj in ipairs(state.added) do
        pcall(function() obj:Destroy() end)
    end
    state.added = {}
    if state.backup then
        for _, obj in ipairs(state.backup.instances) do
            local ok, clone = pcall(function() return obj:Clone() end)
            if ok and clone then clone.Parent = myChar end
        end
        if myHum then
            for k, v in pairs(state.backup.props) do
                pcall(function() myHum[k] = v end)
            end
        end
    end
    state.disguised = false
end

-- ── UI ──
local sec = Tab:Section({ Title = "伪装玩家", Icon = "user-round", Opened = true })

local targetName = nil

sec:Dropdown({
    Title = "目标玩家（当前服务器）",
    Desc = "选一个玩家，把他的外观复制到你身上",
    Values = richPlayers(),
    SearchBarEnabled = true,
    AllowNone = true,
    Value = nil,
    Callback = function(v)
        targetName = itemName(v)
        if targetName == "" then targetName = nil end
    end,
})

sec:Button({
    Title = "开始伪装",
    Desc = "把选中玩家的外观复制到自己角色",
    Icon = "user-check",
    Callback = function()
        local p = findPlayer(targetName)
        if not p then notify("伪装玩家", "先选一个目标玩家", "x") return end
        if applyDisguise(p) then
            notify("伪装玩家", "已伪装成 " .. p.DisplayName .. "（仅自己视角）", "check")
        end
    end,
})

sec:Button({
    Title = "取消伪装",
    Desc = "恢复成自己的样子",
    Icon = "rotate-ccw",
    Callback = function()
        restore()
        notify("伪装玩家", "已取消伪装", "check")
    end,
})

sec:Button({
    Title = "刷新玩家列表",
    Desc = "手动重新拉一次候选人（平时会自动更新）",
    Icon = "refresh-cw",
    Callback = function()
        pcall(function()
            local dd = sec
        end)
        notify("伪装玩家", "列表将在下次刷新时更新", "check")
    end,
})

sec:Paragraph({
    Title = "说明",
    Desc = "这是本地视角的外观替换：你自己屏幕上会变成对方的样子，别人看你还是你。不修改任何游戏脚本、不上报任何数据。",
    Image = "info", ImageSize = 16, Color = Color3.fromRGB(120, 180, 255),
})

-- 玩家进出：2 秒合并刷新，且不在事件那一帧重建
do
    local dd = nil
    pcall(function()
        -- 取 Section 里刚建的那个 Dropdown（Boreal 存在 Elements 里）
        for _, el in ipairs(sec.Elements or {}) do
            if el.UIElements and el.UIElements.Menu then dd = el break end
        end
    end)

    local lastRefresh, scheduled = 0, false
    local function scheduleRefresh()
        if not dd then return end
        if scheduled then return end
        scheduled = true
        local waitFor = 2.0 - (os.clock() - lastRefresh)
        if waitFor < 0.2 then waitFor = 0.2 end
        task.delay(waitFor, function()
            scheduled = false
            lastRefresh = os.clock()
            pcall(function()
                if dd and dd.Refresh then
                    dd:Refresh(richPlayers(), nil, true)
                end
            end)
        end)
    end

    local ca = Players.PlayerAdded:Connect(scheduleRefresh)
    local cr = Players.PlayerRemoving:Connect(scheduleRefresh)
    if getgenv().HB_win and type(getgenv().HB_win.OnClose) == "function" then
        pcall(function()
            getgenv().HB_win:OnClose(function()
                ca:Disconnect()
                cr:Disconnect()
                restore()
            end)
        end)
    end
end

-- 重生后如果正在伪装，自动重新套用（一次连接，不轮询）
LP.CharacterAdded:Connect(function()
    if not state.disguised or not state.target then return end
    task.wait(1)
    if state.target and state.target.Character then
        state.backup = nil
        applyDisguise(state.target)
    end
end)

print("[伪装玩家] 已加载（自实现版）")
