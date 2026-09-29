--[[
    黑白提取 · 远程模块：动画包
    动画包.lua

    本文件由脚本自己 game:HttpGet + loadstring 执行，是独立 chunk，
    看不到主脚本的局部变量，所以：
      页签   走 getgenv().Tabs.HB_animpackTab
      共享环境 走 getgenv().HB_notify / HB_readInput / HB_onClose / HB_getChar / HB_getHum / HB_isR15
]]

if getgenv().__HB_ANIMPACK_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.HB_animpackTab) or getgenv().SutureHB_animpackTab
if not Tab then
	warn("[动画包] 未找到页签（主脚本没赋值 HB_animpackTab？）")
	return
end

-- 确认页签拿到后才标记已加载；构建失败时会在下面清掉，允许重试
getgenv().__HB_ANIMPACK_LOADED = true

local notify    = getgenv().HB_notify
local readInput = getgenv().HB_readInput
local onClose   = getgenv().HB_onClose
local getChar   = getgenv().HB_getChar
local getHum    = getgenv().HB_getHum
local isR15     = getgenv().HB_isR15

if type(notify) ~= "function" then
	warn("[动画包] 主脚本共享环境未就绪（getgenv().HB_notify 缺失）")
	getgenv().__HB_ANIMPACK_LOADED = nil
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
return function(tab, ctx)
	local notify    = ctx.notify      -- function(title, content[, icon])
	local getChar   = ctx.getChar     -- function(player) -> Character or nil
	local getHum    = ctx.getHum      -- function(player) -> Humanoid or nil
	local readInput = ctx.readInput   -- 本功能没有输入框，声明只为对齐 ctx 约定
	local Players = game:GetService("Players")
	local LP = Players.LocalPlayer

	-- 源 76485：{ key = "Animation", title = "动画包", icon = "user" }

	--==============================================================
	-- 源 6523：arg.Tabs.Animation:Section({ Title = "动画控制", Opened = true })
	--==============================================================
	local sec = tab:Section({ Title = "动画控制", Opened = true })

	--==============================================================
	-- 源 6525-6558：fn75(arg2) —— 应用一套动画包
	--   参数形如 { ["idle.Animation1.AnimationId"] = "rbxassetid://891621366", ... }
	--   角色里的结构是：
	--     Animate(LocalScript) > idle / walk / run / jump / climb / fall / swim ...(StringValue)
	--                        > 每个姿态下面挂 Animation 实例
	--   所以 "idle.Animation1.AnimationId" 指的就是
	--     character.Animate.idle.Animation1.AnimationId
	--   也就是说：这套做法是「改写默认 Animate 脚本里各动画的 AnimationId」，
	--   不是挂自定义 Animation / 不是替换 Animate 脚本本身。
	--==============================================================
	local function applyPack(data)
		-- 源里就是 task.spawn 异步跑的，保持一致，避免写属性时卡 UI
		task.spawn(function()
			local char = (getChar and getChar(LP)) or LP.Character
			if not char then
				return
			end
			local animate = char:FindFirstChild("Animate")
			if not animate then
				return
			end

			for path, id in pairs(data) do
				-- 源 6539-6541：按 "." 把路径切开
				local parts = {}
				for seg in string.gmatch(path, "[^.]+") do
					table.insert(parts, seg)
				end

				-- 源 6543-6556：一层一层往下走；中间某一层不存在就整条跳过
				-- （源里用 continue/break 写的，这里等价改写）
				if #parts >= 2 then
					local node = animate
					local ok = true
					for i = 1, #parts - 1 do
						node = node[parts[i]]
						if not node then
							ok = false
							break
						end
					end

					-- 源 6554：v9[tbl8[#tbl8]] = v8
					-- 最后一段固定是 "AnimationId"，直接赋给 Animation 实例的属性
					if ok and node then
						pcall(function()
							node[parts[#parts]] = id
						end)
					end
				end
			end
		end)
	end

	--==============================================================
	-- 源 6560-6864：25 套动画包数据
	--   动画 ID 全部原样照抄，顺序、字段顺序、缺项（比如「无动画」没有 climb）
	--   都跟源文件一致。
	--==============================================================
	local packs = {
		{
			name = "宇航员",                                        -- 源 6562
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://891621366",
				["idle.Animation2.AnimationId"] = "rbxassetid://891633237",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://891667138",
				["run.RunAnim.AnimationId"] = "rbxassetid://891636393",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://891627522",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://891609353",
				["fall.FallAnim.AnimationId"] = "rbxassetid://891617961",
			},
		},
		{
			name = "泡状",                                          -- 源 6574
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://910004836",
				["idle.Animation2.AnimationId"] = "rbxassetid://910009958",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://910034870",
				["run.RunAnim.AnimationId"] = "rbxassetid://910025107",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://910016857",
				["fall.FallAnim.AnimationId"] = "rbxassetid://910001910",
				["swimidle.SwimIdle.AnimationId"] = "rbxassetid://910030921",
				["swim.Swim.AnimationId"] = "rbxassetid://910028158",
			},
		},
		{
			name = "卡通",                                          -- 源 6587
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://742637544",
				["idle.Animation2.AnimationId"] = "rbxassetid://742638445",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://742640026",
				["run.RunAnim.AnimationId"] = "rbxassetid://742638842",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://742637942",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://742636889",
				["fall.FallAnim.AnimationId"] = "rbxassetid://742637151",
			},
		},
		{
			name = "老人",                                          -- 源 6599
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://845397899",
				["idle.Animation2.AnimationId"] = "rbxassetid://845400520",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://845403856",
				["run.RunAnim.AnimationId"] = "rbxassetid://845386501",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://845398858",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://845392038",
				["fall.FallAnim.AnimationId"] = "rbxassetid://845396048",
			},
		},
		{
			name = "骑士",                                          -- 源 6611
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://657595757",
				["idle.Animation2.AnimationId"] = "rbxassetid://657568135",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://657552124",
				["run.RunAnim.AnimationId"] = "rbxassetid://657564596",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://658409194",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://658360781",
				["fall.FallAnim.AnimationId"] = "rbxassetid://657600338",
			},
		},
		{
			name = "悬浮",                                          -- 源 6623
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616006778",
				["idle.Animation2.AnimationId"] = "rbxassetid://616008087",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616013216",
				["run.RunAnim.AnimationId"] = "rbxassetid://616010382",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616008936",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://616003713",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616005863",
			},
		},
		{
			name = "法师",                                          -- 源 6635
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://707742142",
				["idle.Animation2.AnimationId"] = "rbxassetid://707855907",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://707897309",
				["run.RunAnim.AnimationId"] = "rbxassetid://707861613",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://707853694",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://707826056",
				["fall.FallAnim.AnimationId"] = "rbxassetid://707829716",
			},
		},
		{
			name = "忍者",                                          -- 源 6647
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://656117400",
				["idle.Animation2.AnimationId"] = "rbxassetid://656118341",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://656121766",
				["run.RunAnim.AnimationId"] = "rbxassetid://656118852",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://656117878",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://656114359",
				["fall.FallAnim.AnimationId"] = "rbxassetid://656115606",
			},
		},
		{
			name = "海盗",                                          -- 源 6659
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://750781874",
				["idle.Animation2.AnimationId"] = "rbxassetid://750782770",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://750785693",
				["run.RunAnim.AnimationId"] = "rbxassetid://750783738",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://750782230",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://750779899",
				["fall.FallAnim.AnimationId"] = "rbxassetid://750780242",
			},
		},
		{
			name = "机器人",                                        -- 源 6671
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616088211",
				["idle.Animation2.AnimationId"] = "rbxassetid://616089559",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616095330",
				["run.RunAnim.AnimationId"] = "rbxassetid://616091570",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616090535",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://616086039",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616087089",
			},
		},
		{
			name = "时尚",                                          -- 源 6683
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616136790",
				["idle.Animation2.AnimationId"] = "rbxassetid://616138447",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616146177",
				["run.RunAnim.AnimationId"] = "rbxassetid://616140816",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616139451",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://616133594",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616134815",
			},
		},
		{
			name = "超级英雄",                                      -- 源 6695
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616111295",
				["idle.Animation2.AnimationId"] = "rbxassetid://616113536",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616122287",
				["run.RunAnim.AnimationId"] = "rbxassetid://616117076",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616115533",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://616104706",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616108001",
			},
		},
		{
			name = "玩具",                                          -- 源 6707
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://782841498",
				["idle.Animation2.AnimationId"] = "rbxassetid://782845736",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://782843345",
				["run.RunAnim.AnimationId"] = "rbxassetid://782842708",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://782847020",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://782843869",
				["fall.FallAnim.AnimationId"] = "rbxassetid://782846423",
			},
		},
		{
			name = "吸血鬼",                                        -- 源 6719
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1083445855",
				["idle.Animation2.AnimationId"] = "rbxassetid://1083450166",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1083473930",
				["run.RunAnim.AnimationId"] = "rbxassetid://1083462077",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1083455352",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1083439238",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1083443587",
			},
		},
		{
			name = "狼人",                                          -- 源 6731
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1083195517",
				["idle.Animation2.AnimationId"] = "rbxassetid://1083214717",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1083178339",
				["run.RunAnim.AnimationId"] = "rbxassetid://1083216690",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1083218792",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1083182000",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1083189019",
			},
		},
		{
			name = "僵尸",                                          -- 源 6743
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616158929",
				["idle.Animation2.AnimationId"] = "rbxassetid://616160636",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616168032",
				["run.RunAnim.AnimationId"] = "rbxassetid://616163682",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616161997",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://616156119",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616157476",
			},
		},
		{
			name = "巡逻",                                          -- 源 6755
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1149612882",
				["idle.Animation2.AnimationId"] = "rbxassetid://1150842221",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1151231493",
				["run.RunAnim.AnimationId"] = "rbxassetid://1150967949",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1148811837",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1148811837",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1148863382",
			},
		},
		{
			name = "自信",                                          -- 源 6767
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1069977950",
				["idle.Animation2.AnimationId"] = "rbxassetid://1069987858",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1070017263",
				["run.RunAnim.AnimationId"] = "rbxassetid://1070001516",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1069984524",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1069946257",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1069973677",
			},
		},
		{
			name = "明星",                                          -- 源 6779
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1212900985",
				["idle.Animation2.AnimationId"] = "rbxassetid://1150842221",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1212980338",
				["run.RunAnim.AnimationId"] = "rbxassetid://1212980348",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1212954642",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1213044953",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1212900995",
			},
		},
		{
			name = "牛仔",                                          -- 源 6791
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1014390418",
				["idle.Animation2.AnimationId"] = "rbxassetid://1014398616",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1014421541",
				["run.RunAnim.AnimationId"] = "rbxassetid://1014401683",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1014394726",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1014380606",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1014384571",
			},
		},
		{
			name = "鬼",                                            -- 源 6803
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://616006778",
				["idle.Animation2.AnimationId"] = "rbxassetid://616008087",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://616013216",
				["run.RunAnim.AnimationId"] = "rbxassetid://616013216",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://616008936",
				["fall.FallAnim.AnimationId"] = "rbxassetid://616005863",
				["swimidle.SwimIdle.AnimationId"] = "rbxassetid://616012453",
				["swim.Swim.AnimationId"] = "rbxassetid://616011509",
			},
		},
		{
			name = "小偷",                                          -- 源 6816
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://1132473842",
				["idle.Animation2.AnimationId"] = "rbxassetid://1132477671",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://1132510133",
				["run.RunAnim.AnimationId"] = "rbxassetid://1132494274",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://1132489853",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://1132461372",
				["fall.FallAnim.AnimationId"] = "rbxassetid://1132469004",
			},
		},
		{
			name = "公主",                                          -- 源 6828
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://941003647",
				["idle.Animation2.AnimationId"] = "rbxassetid://941013098",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://941028902",
				["run.RunAnim.AnimationId"] = "rbxassetid://941015281",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://941008832",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://940996062",
				["fall.FallAnim.AnimationId"] = "rbxassetid://941000007",
			},
		},
		{
			name = "无动画",                                        -- 源 6840（源里这套没有 climb）
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://0",
				["idle.Animation2.AnimationId"] = "rbxassetid://0",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://0",
				["run.RunAnim.AnimationId"] = "rbxassetid://0",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://0",
				["fall.FallAnim.AnimationId"] = "rbxassetid://0",
				["swimidle.SwimIdle.AnimationId"] = "rbxassetid://0",
				["swim.Swim.AnimationId"] = "rbxassetid://0",
			},
		},
		{
			name = "人类（预设）",                                  -- 源 6853
			data = {
				["idle.Animation1.AnimationId"] = "rbxassetid://2510196951",
				["idle.Animation2.AnimationId"] = "rbxassetid://2510197257",
				["walk.WalkAnim.AnimationId"] = "rbxassetid://2510202577",
				["run.RunAnim.AnimationId"] = "rbxassetid://2510198475",
				["jump.JumpAnim.AnimationId"] = "rbxassetid://2510197830",
				["climb.ClimbAnim.AnimationId"] = "rbxassetid://2510192778",
				["fall.FallAnim.AnimationId"] = "rbxassetid://2510195892",
			},
		},
	}

	-- 源 6853 / 6906：恢复默认用的就是这一套
	local DEFAULT_PACK = "人类（预设）"

	-- 源 6866-6872：把每套的 name 抽出来当下拉列表
	local names = {}
	for _, pack in ipairs(packs) do
		table.insert(names, pack.name)
	end

	local selected = names[1] or ""

	--==============================================================
	-- 源 6874-6881：v7:Dropdown({ Title = "选择动画风格", Values = tbl9,
	--                            Value = str, Callback = function(arg2) str = arg2 end })
	--   列表是固定的 25 套，运行时不增删，所以用 Dropdown 而不是 Input。
	--==============================================================
	local styleDropdown = sec:Dropdown({
		Title = "选择动画风格",
		Values = names,
		Value = selected,
		Callback = function(v)
			selected = v
		end,
	})

	-- 源 6908：v8:SetValue("人类（预设）")
	--   黑白那套的 Dropdown 有 SetValue，Boreal 的元素上只有 Select
	--   （以及 DropdownMenu:Set），两个都会同步显示并触发 Callback，
	--   所以这里按 Boreal 实际提供的方法写。
	local function setDropdown(dd, value)
		if not dd then
			return
		end
		pcall(function()
			if dd.Select then
				dd:Select(value)
			elseif dd.DropdownMenu and dd.DropdownMenu.Set then
				dd.DropdownMenu:Set(value, true)
			end
		end)
	end

	local function findPack(name)
		for _, pack in ipairs(packs) do
			if pack.name == name then
				return pack
			end
		end
		return nil
	end

	--==============================================================
	-- 源 6883-6900：应用动画
	--   源里是遍历 tbl8 找同名项，找到就 fn75(v9.data) 然后提示；
	--   源 6894 的提示漏了动画名（fn13("动画", "已应用: ")），这里补上。
	--==============================================================
	sec:Button({
		Title = "应用动画",
		Desc = "把选中的动画风格写进角色的 Animate 脚本",
		Icon = "check",
		Callback = function()
			if selected == "" then
				notify("提示", "请先选择一个动画")
				return
			end

			-- 源里没有这层检查，补上是为了给出明确提示
			if not getChar(LP) or (getHum and not getHum(LP)) then
				notify("错误", "角色未加载，无法应用动画", "x")
				return
			end

			local pack = findPack(selected)
			if not pack then
				notify("错误", "找不到这套动画", "x")
				return
			end

			applyPack(pack.data)
			notify("动画", "已应用: " .. pack.name)
		end,
	})

	--==============================================================
	-- 源 6902-6917：恢复默认（人类）
	--   源里没有单独的「刷新动画」按钮；这个按钮同时做了两件事：
	--   1) 应用「人类（预设）」那套 ID
	--   2) v8:SetValue("人类（预设）") 把下拉框选中项拉回来（即刷新显示）
	--   注意：源和这里都不处理角色重生，重生后需要再点一次。
	--==============================================================
	sec:Button({
		Title = "恢复默认（人类）",
		Desc = "换回 Roblox 默认的人类动画",
		Icon = "undo",
		Variant = "Secondary",
		Callback = function()
			local pack = findPack(DEFAULT_PACK)
			if not pack then
				notify("错误", "缺少「人类（预设）」数据", "x")
				return
			end

			applyPack(pack.data)
			selected = DEFAULT_PACK
			setDropdown(styleDropdown, DEFAULT_PACK)
			notify("动画", "已恢复为默认人类动画")
		end,
	})

	notify("动画包", "已加载")
end
end)()

-- 远程脚本是独立 chunk，出错必须显式暴露，否则就是静默白屏
local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[动画包] 构建失败: " .. tostring(err))
	pcall(notify, "动画包", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_ANIMPACK_LOADED = nil   -- 清掉标志位，允许再点一次重试
end
