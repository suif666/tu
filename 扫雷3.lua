print("汉化脚本 v3.3")

-- ===== 精确翻译表（整句完全匹配）=====
-- 请在此按 ["英文原文"] = "中文翻译" 格式添加
local Translations = {
    -- 示例: ["Home"] = "主页",
        ["Minesweeper"] = "扫雷",
        ["Solver"] = "解算器",
        ["Flags"] = "标记",
        ["ESP"] = "透视",
        ["Status"] = "状态",
        ["Halloween"] = "万圣节",
        ["Settings"] = "设置",
        ["MINESWEEPER, READY WHEN YOU ARE,"] = "扫雷，准备好了就开始",
        ["Free"] = "免费",
        ["Hide name"] = "隐藏名字",
        ["Hide avatar"] = "隐藏头像",
        ["PLAYERS"] = "玩家",
        ["EXECS"] = "执行器",
        ["SESSION"] = "会话",
        ["WORLD CLOCK"] = "世界时钟",
        ["Rejoin"] = "重新加入",
        ["Hop"] = "切换",
        ["Lowest"] = "最低",
        ["Job ID"] = "任务ID",
        ["LINKS"] = "链接",
        ["Feature list"] = "功能列表",
        ["Your executor is supported and fully compatible."] = "你的执行器受支持且完全兼容。",
        ["Tap the pill or"] = "点击胶囊或",
        ["TIP"] = "提示",
        ["Search in the sidebar's top box to jump to any feature in any tab."] = "在侧边栏顶部搜索框中搜索，可跳转到任意标签页的任意功能。",
        ["Solve"] = "解算",
        ["Movement"] = "移动",
        ["Auto solve"] = "自动解算",
        ["moves onto certain safe tiles, then the best guess"] = "移动到某些安全格，然后进行最佳猜测",
        ["Solver scan speed"] = "解算器扫描速度",
        ["Guessing"] = "猜测",
        ["Max guess risk"] = "最大猜测风险",
        ["Move by"] = "移动方式",
        ["Teleport (TP)"] = "传送（TP）",
        ["Teleport speed"] = "传送速度",
        ["TP speed"] = "TP速度",
        ["Tiles per scan"] = "每次扫描格数",
        ["Give up after"] = "放弃于",
        ["Walking"] = "行走",
        ["Walk speed"] = "行走速度",
        ["Longest walk"] = "最长行走",
        ["Waypoint timeout"] = "路径点超时",
        ["Walk"] = "行走",
        ["Auto flag"] = "自动标记",
        ["Auto flag mines"] = "自动标记地雷",
        ["clicks certain mines, works without auto solve"] = "点击特定地雷，无需自动解算也可工作",
        ["Flag delay"] = "标记延迟",
        ["Reach"] = "范围",
        ["Flag range"] = "标记范围",
        ["Marks"] = "标记",
        ["Colours"] = "颜色",
        ["Show"] = "显示",
        ["Show marks"] = "显示标记",
        ["runs on its own, no mode to pick"] = "独立运行，无需选择模式",
        ["Risk heat"] = "风险热力",
        ["colours unknown tiles next to numbers by mine chance"] = "根据雷概率给数字旁未知格上色",
        ["Best guess"] = "最佳猜测",
        ["marks the tile the solver would guess"] = "标记解算器会猜测的格子",
        ["ESP scan speed"] = "透视扫描速度",
        ["Distance and opacity"] = "距离和不透明度",
        ["Show distance"] = "显示距离",
        ["Opacity"] = "不透明度",
        ["Certain tiles"] = "确定格",
        ["Safe tile"] = "安全格",
        ["Mine tile"] = "地雷格",
        ["Low risk"] = "低风险",
        ["High risk"] = "高风险",
        ["Auto solve:"] = "自动解算：",
        ["Board"] = "棋盘",
        ["Paused"] = "已暂停",
        ["running"] = "运行中",
        ["Safe tiles"] = "安全格",
        ["Mines"] = "地雷",
        ["Solve time"] = "解算时间",
        ["Recent tiles"] = "最近格",
        ["MOVES"] = "移动",
        ["No moves yet"] = "暂无移动",
        ["Health"] = "生命值",
        ["Round"] = "回合",
        ["teleport"] = "传送",
        ["Flag state"] = "标记状态",
        ["Flags sent"] = "已发送标记",
        ["Errors"] = "错误",
        ["Last error"] = "最后错误",
        ["Exact"] = "精确",
        ["Rounds"] = "回合",
        ["Finished"] = "已完成",
        ["Last round"] = "上一回合",
        ["Fastest"] = "最快",
        ["Mines left"] = "剩余地雷",
        ["Opened"] = "已打开",
        ["Missed"] = "已错过",
        ["Vote popup"] = "投票弹窗",
        ["Halloween vote"] = "万圣节投票",
        ["auto answers the Halloween vote popup"] = "自动回答万圣节投票弹窗",
        ["Off"] = "关闭",
        ["Answer delay"] = "回答延迟",
        ["Vote"] = "投票",
        ["Answered"] = "已回答",
        ["Veto (No)"] = "否决（否）",
        ["Yes"] = "是",
        ["Interface"] = "界面",
        ["Toggle UI"] = "切换UI",
        ["Unload"] = "卸载",
}

-- ===== 部分替换表（子串替换）=====
-- 请在此按 ["英文子串"] = "中文替换" 格式添加
-- 注意：会替换文本中所有匹配的子串，请谨慎使用
local PartialTranslations = {
    -- 示例: yes no 
    --["yes"] = "是",
   
}

-- ===== 选择模式（自建 GUI 按钮，手机/PC 都可靠；10 秒不选默认普通） =====
local function AskModeWithNotification()
    local choice = nil

    -- 自建选择 GUI：按钮点击是原生事件，一定能触发
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "HanHuaModeSelect"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() screenGui.Parent = game:GetService("CoreGui") end)

    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(0.86, 0.52)
    bg.Position = UDim2.fromScale(0.07, 0.24)
    bg.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
    bg.BackgroundTransparency = 0.05
    bg.BorderSizePixel = 0
    bg.Parent = screenGui
    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 14)
    bgCorner.Parent = bg
    local bgStroke = Instance.new("UIStroke")
    bgStroke.Thickness = 1
    bgStroke.Color = Color3.fromRGB(70, 130, 255)
    bgStroke.Parent = bg

    local title = Instance.new("TextLabel")
    title.Size = UDim2.fromScale(1, 0.22)
    title.BackgroundTransparency = 1
    title.Text = "汉化模式选择（10 秒后默认普通）"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 17
    title.Font = Enum.Font.GothamBold
    title.Parent = bg

    local btn1 = Instance.new("TextButton")
    btn1.Size = UDim2.fromScale(0.86, 0.3)
    btn1.Position = UDim2.fromScale(0.07, 0.32)
    btn1.BackgroundColor3 = Color3.fromRGB(70, 130, 255)
    btn1.Text = "Hook模式 (快速)"
    btn1.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn1.TextSize = 18
    btn1.Font = Enum.Font.GothamBold
    btn1.AutoButtonColor = true
    btn1.Parent = bg
    local btn1Corner = Instance.new("UICorner")
    btn1Corner.CornerRadius = UDim.new(0, 10)
    btn1Corner.Parent = btn1
    btn1.MouseButton1Click:Connect(function()
        choice = true
    end)

    local btn2 = Instance.new("TextButton")
    btn2.Size = UDim2.fromScale(0.86, 0.3)
    btn2.Position = UDim2.fromScale(0.07, 0.66)
    btn2.BackgroundColor3 = Color3.fromRGB(80, 85, 95)
    btn2.Text = "普通模式 (稳定)"
    btn2.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn2.TextSize = 18
    btn2.Font = Enum.Font.GothamBold
    btn2.AutoButtonColor = true
    btn2.Parent = bg
    local btn2Corner = Instance.new("UICorner")
    btn2Corner.CornerRadius = UDim.new(0, 10)
    btn2Corner.Parent = btn2
    btn2.MouseButton1Click:Connect(function()
        choice = false
    end)

    -- 用 tick()（墙钟）判断超时，wait 挂起期间也能正确计时
    local start = tick()
    repeat
        task.wait(0.1)
    until choice ~= nil or tick() - start > 10

    pcall(function() screenGui:Destroy() end)

    if choice == nil then
        print("[汉化] 未选择，默认使用普通模式（轮询）")
        return false
    end
    print("[汉化] 已选择:", choice and "Hook模式" or "普通模式")
    return choice
end
local UseHookTranslation = AskModeWithNotification()
print("最终使用模式:", UseHookTranslation and "Hook" or "普通监听")

-- ===== 翻译框架（监听模式为主）=====
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")

if not PlayerGui then
    warn("未找到 PlayerGui，汉化可能无法正常工作")
end

local SystemUiNames = {
    RobloxGui=true, PlayerList=true, Backpack=true, Chat=true, BubbleChat=true,
    ExperienceChat=true, TextChatService=true, TopBar=true, Topbar=true, Health=true,
    EmotesMenu=true, Chrome=true, InspectMenu=true, PurchasePrompt=true,
    ScreenshotHud=true
}

local WatchedRoots, WatchedObjects, TranslatingObjects = setmetatable({},{__mode="k"}), setmetatable({},{__mode="k"}), setmetatable({},{__mode="k"})

-- 转义 Lua pattern 特殊字符，让部分替换按字面匹配（用户填 [ % . 等不会崩）
local function EscapePattern(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

local function TranslateText(txt)
    if type(txt) ~= "string" or txt == "" then return txt end
    local clean = txt:gsub("<[^>]*>", ""):gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")

    -- 1. 精确匹配（整句）
    local exact = Translations[txt] or Translations[clean]
    if exact then return exact end

    -- 2. 部分替换（子串，字面匹配）
    local result = txt
    for original, translated in pairs(PartialTranslations) do
        result = result:gsub(EscapePattern(original), translated)
    end
    return result
end

local function IsSysUI(obj)
    while obj do
        if SystemUiNames[obj.Name] then return true end
        obj = obj.Parent
    end
    return false
end

local function TranslateObj(obj)
    if IsSysUI(obj) or TranslatingObjects[obj] then return end
    TranslatingObjects[obj] = true
    pcall(function()
        local nText = TranslateText(obj.Text)
        if nText ~= obj.Text then obj.Text = nText end
        local nPlace = TranslateText(obj.PlaceholderText)
        if nPlace ~= obj.PlaceholderText then obj.PlaceholderText = nPlace end
    end)
    TranslatingObjects[obj] = nil
end

local function WatchObj(obj)
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then return end
    if WatchedObjects[obj] then return end
    WatchedObjects[obj] = true

    TranslateObj(obj)

    local function onPropChange()
        if not TranslatingObjects[obj] then
            delay(0.03, function() TranslateObj(obj) end)
        end
    end

    pcall(function()
        obj:GetPropertyChangedSignal("Text"):Connect(onPropChange)
        obj:GetPropertyChangedSignal("PlaceholderText"):Connect(onPropChange)
    end)
end

local function GetRoots()
    local roots = {}
    if PlayerGui then table.insert(roots, PlayerGui) end
    pcall(function() table.insert(roots, CoreGui) end)
    pcall(function()
        if gethui then
            local hui = gethui()
            if hui then table.insert(roots, hui) end
        end
    end)
    return roots
end

local function ScanAndWatch(root)
    if not root or WatchedRoots[root] then return end
    WatchedRoots[root] = true

    pcall(function()
        for _, obj in ipairs(root:GetDescendants()) do
            WatchObj(obj)
        end
        root.DescendantAdded:Connect(function(obj)
            delay(0.05, function()
                WatchObj(obj)
                pcall(function()
                    for _, c in ipairs(obj:GetDescendants()) do
                        WatchObj(c)
                    end
                end)
            end)
        end)
    end)
end

-- ===== 如果用户选择了 Hook 模式，尝试安装 =====
local hookInstalled = false
if UseHookTranslation then
    local hookSuccess, hookErr = pcall(function()
        local mt = getrawmetatable(game)
        if not mt then error("getrawmetatable 失败") end
        local oldNewIndex = mt.__newindex
        setreadonly(mt, false)
        mt.__newindex = newcclosure(function(t, k, v)
            -- 只处理 Instance 上的 Text/PlaceholderText，避免非 Instance 调用 IsA 报错
            if (k == "Text" or k == "PlaceholderText") and typeof(t) == "Instance"
               and (t:IsA("TextLabel") or t:IsA("TextButton") or t:IsA("TextBox"))
               and not IsSysUI(t) then
                v = TranslateText(tostring(v))
            end
            return oldNewIndex(t, k, v)
        end)
        setreadonly(mt, true)
    end)
    if not hookSuccess then
        warn("[汉化] Hook安装失败，降级为监听模式:", hookErr)
        UseHookTranslation = false
        hookInstalled = false
    else
        print("[汉化] Hook模式已启用")
        hookInstalled = true
    end
else
    print("[汉化] 使用普通监听模式")
end

-- ===== 启动监听扫描（即使 Hook 成功也保留作为备用） =====
spawn(function()
    while true do
        for _, root in ipairs(GetRoots()) do
            ScanAndWatch(root)
            pcall(function()
                for _, obj in ipairs(root:GetDescendants()) do
                    WatchObj(obj)
                end
            end)
        end
        wait(hookInstalled and 20 or 12)
    end
end)

wait(0.5)

-- ===== 加载外部脚本 =====
local ScriptUrl = "https://pastefy.app/T5XIfiMo/raw'"
if ScriptUrl == "" then
    warn("[汉化] 外部脚本 URL 未填写，跳过外部脚本加载")
else
    print("[汉化] 开始下载外部脚本...")
    local ok, content = pcall(function()
        return game:HttpGet(ScriptUrl)
    end)

    if not ok then
        warn("[汉化] 下载失败：", content)
    elseif not content or content == "" then
        warn("[汉化] 内容为空")
    else
        print("[汉化] 下载成功，长度：", #content)
        local func, err = loadstring(content)
        if not func then
            warn("[汉化] 编译失败：", err)
        else
            print("[汉化] 编译成功，执行外部脚本...")
            local execOk, execErr = pcall(func)
            if not execOk then
                warn("[汉化] 执行失败：", execErr)
            else
                print("[汉化] 外部脚本执行成功")
            end
        end
    end
end

print("[汉化] 已加载")
