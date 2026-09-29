--[[
    黑白提取 · 远程模块：动作包
    动作包.lua

    本文件由脚本自己 game:HttpGet + loadstring 执行，是独立 chunk，
    看不到主脚本的局部变量，所以：
      页签   走 getgenv().Tabs.HB_actionTab
      共享环境 走 getgenv().HB_notify / HB_readInput / HB_onClose / HB_getChar / HB_getHum / HB_isR15
]]

if getgenv().__HB_ACTION_LOADED then
	return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.HB_actionTab) or getgenv().SutureHB_actionTab
if not Tab then
	warn("[动作包] 未找到页签（主脚本没赋值 HB_actionTab？）")
	return
end

-- 确认页签拿到后才标记已加载；构建失败时会在下面清掉，允许重试
getgenv().__HB_ACTION_LOADED = true

local notify    = getgenv().HB_notify
local readInput = getgenv().HB_readInput
local onClose   = getgenv().HB_onClose
local getChar   = getgenv().HB_getChar
local getHum    = getgenv().HB_getHum
local isR15     = getgenv().HB_isR15

if type(notify) ~= "function" then
	warn("[动作包] 主脚本共享环境未就绪（getgenv().HB_notify 缺失）")
	getgenv().__HB_ACTION_LOADED = nil
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
--==============================================================================
-- 动作包（从 黑白-MAIN.可运行版.lua 第 5960–6519 行 的 fn73 提取重写）
--  - 5963-6171：Tabs.Action「动画控制」分区 —— 130 条动作列表 + 下拉选择 + 播放/停止
--  - 6173-6518：Tabs.ActionV2「动作控制」分区 —— 鬼畜抽搐 / 甩头 / 定住解冻 /
--              循环当前动画 / 刷新动画 / 自定义动画包开关 / 说明
-- 与 黑白提取.lua 已实现的「随机跳舞、自定义动画、全局动画速度、停止所有动画」
-- 重复的部分不在此重复实现，只补动作包独有的逻辑。
--==============================================================================
return function(tab, ctx)
	local notify    = ctx.notify      -- function(title, content[, icon])
	local getChar   = ctx.getChar     -- function(player) -> Character or nil
	local getHum    = ctx.getHum      -- function(player) -> Humanoid or nil
	local readInput = ctx.readInput   -- function(element) -> string
	local isR15     = ctx.isR15       -- function(player) -> boolean
	local Players = game:GetService("Players")
	local LP = Players.LocalPlayer

	--==========================================================================
	-- 通用小工具：把人类身上的动画轨道全部找出来
	-- 源文件 fn77 走的是 FindFirstChildOfClass("Humanoid") 或 AnimationController；
	-- 这里额外优先用 Animator:GetPlayingAnimationTracks()（新版 API），
	-- 引擎上取不到再退回 Humanoid:GetPlayingAnimationTracks()（旧版 API）。
	--==========================================================================
	local function getAnimateOwner()
		local ch = getChar(LP)
		if not ch then
			return nil, nil
		end
		local animator = ch:FindFirstChildOfClass("Animator")
		return ch, animator
	end

	-- 取出「当前正在播放的所有动画轨道」（对应源文件里的 v13:GetPlayingAnimationTracks()）
	local function getPlayingTracks()
		local ch, animator = getAnimateOwner()
		if not ch then
			return {}
		end
		if animator then
			local ok, tracks = pcall(function()
				return animator:GetPlayingAnimationTracks()
			end)
			if ok and tracks then
				return tracks
			end
		end
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if hum then
			local ok, tracks = pcall(function()
				return hum:GetPlayingAnimationTracks()
			end)
			if ok and tracks then
				return tracks
			end
		end
		return {}
	end

	-- 通用：对当前所有在播动画做一件事（对应源文件到处出现的 for ... AdjustSpeed 循环）
	local function forEachPlayingTracks(fn)
		local n = 0
		for _, track in pairs(getPlayingTracks()) do
			local ok = pcall(function()
				fn(track)
			end)
			if ok then
				n = n + 1
			end
		end
		return n
	end

	--==========================================================================
	-- 动画控制：动作列表（源文件 5999-6126 行的 tbl9，130 条，ID 原样保留）
	-- 每项格式：{ 名称, 动画ID, 播放速度, 播放权重 }
	--==========================================================================
	local actionList = {
		{ "加州女孩", 124982597491660, 1, 0 },
		{ "直升机", 95301257497525, 1, 0 },
		{ "直升机2", 122951149300674, 1, 0 },
		{ "直升机3", 91257498644328, 1, 0 },
		{ "街头舞蹈", 108171959207138, 1, 0 },
		{ "街头跺脚", 115048845533448, 1.4, 0 },
		{ "扑腾的鱼", 79075971527754, 1, 0 },
		{ "江南Style", 100531289776679, 1, 0 },
		{ "苹果糖舞", 88315693621494, 1, 0 },
		{ "空中转圈", 94324173536622, 1, 0 },
		{ "比心(左)", 110936682778213, 0, 0 },
		{ "比心(右)", 84671941093489, 0, 0 },
		{ "狗狗", 78195344190486, 1, 0 },
		{ "MM2禅", 86872878957632, 1, 0 },
		{ "默认舞蹈", 88455578674030, 1, 0 },
		{ "坐下", 97185364700038, 1, 0 },
		{ "哥萨克踢", 119264600441310, 1, 0 },
		{ "战斗姿态", 116763940575803, 1, 0 },
		{ "你是谁", 81389876138766, 1, 0 },
		{ "摇摆坐", 130995344283026, 1, 0 },
		{ "摇摆坐2", 131836270858895, 1, 0 },
		{ "蠕虫舞", 90333292347820, 1, 0 },
		{ "蛇", 98476854035224, 1, 0 },
		{ "彼得死亡", 129787664584610, 1, 0 },
		{ "沃尔特场景", 113475147402830, 1, 0 },
		{ "可爱躺姿", 80754582835479, 1, 0 },
		{ "暗影迪奥", 92266904563270, 1, 0 },
		{ "承太郎姿势", 122120443600865, 1, 0 },
		{ "JOJO姿势", 120629563851640, 1, 0 },
		{ "漂浮躺", 77840765435893, 1, 0 },
		{ "圣经天使", 109873544976020, 1, 0 },
		{ "无头", 78837807518622, 1, 0 },
		{ "ME!ME!ME!", 103235915424832, 1, 0 },
		{ "飞机", 82135680487389, 1, 0 },
		{ "Xavier舞", 90802740360125, 1, 0 },
		{ "中国舞", 131758838511368, 1, 0 },
		{ "背头", 74288964113793, 1, 0 },
		{ "车辆1", 108747312576405, 1, 0 },
		{ "车辆2", 76503595759461, 1, 0 },
		{ "车辆3", 115245341767944, 1, 0 },
		{ "车辆4", 127805235430271, 1, 0 },
		{ "车辆5", 138003068153218, 1, 0 },
		{ "车辆6", 116772752010894, 1, 0 },
		{ "车辆7", 116625361313832, 1, 0 },
		{ "车辆8", 81388785824317, 1, 0 },
		{ "车辆9", 113181071290859, 1, 0 },
		{ "车辆10", 134681712937413, 1, 0 },
		{ "车辆11", 115260380433565, 1, 0 },
		{ "车辆12", 72382226286301, 1, 0 },
		{ "击败Koto", 93497729736287, 1, 0 },
		{ "坦克", 94915612757079, 1, 0 },
		{ "经典行走", 107806791584829, 1, 0 },
		{ "奇怪生物", 87025086742503, 1, 0 },
		{ "马桶人", 127154705636043, 1, 0 },
		{ "滚动哭宝", 129699431093711, 1, 0 },
		{ "思考", 127088545449493, 1, 0 },
		{ "假死", 88130117312312, 1, 0 },
		{ "迷幻", 135611169366768, 1, 0 },
		{ "穿搭检查", 81176957565811, 1, 0 },
		{ "投降", 100537772865440, 1, 0 },
		{ "假设", 91294374426630, 1, 0 },
		{ "Griddy舞", 121966805049108, 1, 0 },
		{ "认输", 78653596566468, 1, 0 },
		{ "篮球头转", 92854797386719, 1, 0 },
		{ "鹦鹉舞", 101810746304426, 1, 0 },
		{ "射击", 102691551292124, 1, 0 },
		{ "布娃娃", 136224735234038, 1, 0 },
		{ "悲伤坐", 100798804992348, 1, 0 },
		{ "汽水", 105459130960429, 1, 0 },
		{ "比利弹跳", 137501135905857, 1, 0 },
		{ "篮球", 119242308765484, 1, 0 },
		{ "打桩机", 91423662648449, 1, 0 },
		{ "怪物捣碎", 137883764619555, 1, 0 },
		{ "芙兰玩偶", 107217181254431, 1, 0 },
		{ "后空翻", 131205329995035, 1, 0 },
		{ "漂浮", 89523370947906, 1, 0 },
		{ "你好", 103041144411206, 1, 0 },
		{ "附身", 90708290447388, 1, 0 },
		{ "去你的!", 98289978017308, 1, 0 },
		{ "摸头", 85422671683973, 1, 0 },
		{ "上帝山羊漂浮", 100405715895755, 1, 0 },
		{ "直升机4", 115417853064013, 1, 0 },
		{ "网格舞", 85588129788692, 1, 0 },
		{ "破碎", 79757971761739, 1, 0 },
		{ "认输", 83265734904502, 1, 0 },
		{ "江南StyleV2", 129764254213842, 1, 0 },
		{ "180°翻转", 114400428765989, 1, 0 },
		{ "马桶舞", 128334204821841, 1, 0 },
		{ "吾乃天命唯一", 138433137191760, 1, 0 },
		{ "橙色正义", 110146282544198, 1, 0 },
		{ "牙线舞", 10714340543, 1, 0 },
		{ "三角符文舞蹈", 77984841414450, 1, 0 },
		{ "圣经级准确表情", 109873544976020, 1, 0 },
		{ "呃呃呃", 111251252458517, 1, 0 },
		{ "彼得不要啊", 84623954062978, 1, 0 },
		{ "我变成敞篷车了", 124756446017361, 1, 0 },
		{ "加里舞蹈", 93014787120483, 1, 0 },
		{ "IShowSpeed舞蹈", 92618727772186, 1, 0 },
		{ "光环农场", 99499783161907, 1, 0 },
		{ "雪天使", 80177289449617, 1, 0 },
		{ "被皮行者附身", 70432904702322, 1, 0 },
		{ "老鼠舞", 123916423751437, 1, 0 },
		{ "花生酱果冻时间", 129537633250603, 1, 0 },
		{ "撒尿狗", 130059214239749, 1, 0 },
		{ "玛卡雷娜", 91047682123297, 1, 0 },
		{ "严肃全能侠", 130019914905925, 1, 0 },
		{ "翻滚", 133612047483255, 1, 0 },
		{ "恐怖月份到啦", 99637983789946, 1, 0 },
		{ "怪物混搭", 88971195093161, 1, 0 },
		{ "无人机模式", 118592095684994, 1, 0 },
		{ "植物大战僵尸向日葵", 95894948496521, 1, 0 },
		{ "鱼类模式", 137969542385356, 1, 0 },
		{ "拉屎", 132399051509976, 1, 0 },
		{ "足球杂耍", 122583653807009, 1, 0 },
		{ "工程师舞蹈", 107355541549056, 1, 0 },
		{ "小鸡舞", 126960077574956, 1, 0 },
		{ "他掏出了鸡儿", 78347793265211, 1, 0 },
		{ "俄罗斯舞蹈", 97148848007002, 1, 0 },
		{ "爬行者模式", 114687548971893, 1, 0 },
		{ "灭霸舞蹈", 106389948045296, 1, 0 },
		{ "俯卧撑", 108313130500811, 1, 0 },
		{ "云端漂浮", 106022089542174, 1, 0 },
		{ "椅子模式2", 114140630538674, 1, 0 },
		{ "AI猫舞", 108865839239307, 1, 0 },
		{ "蔬菜舞蹈", 84352128203419, 1, 0 },
		{ "DJ哈立德", 82293338535013, 1, 0 },
	}

	-- 源文件 6128-6134 行：只取名称做成下拉框的 Values
	local actionNames = {}
	for _, entry in ipairs(actionList) do
		table.insert(actionNames, entry[1])
	end
	local selectedAction = actionNames[1] or ""

	--==========================================================================
	-- [动作控制 · 第一部分] 动作控制分区（源文件 5963-6171 行）
	--==========================================================================
	local actionSec = tab:Section({ Title = "动画控制", Opened = true })

	actionSec:Dropdown({
		Title = "选择动作",
		Desc = "共 " .. tostring(#actionList) .. " 个动作",
		Values = actionNames,
		Value = selectedAction,
		Callback = function(v)
			selectedAction = v
		end,
	})

	-- 对应源文件 6145-6161 行：按钮里遍历 tbl9 找到同名项，取 [2] ID、[3] 速度、[4] 权重
	-- 源文件这里的 fn75 是先停掉自己播的所有动画再播（looped = true），保持一致。
	local pkgTracks = {}

	local function stopActionPackageAnim()
		for _, track in ipairs(pkgTracks) do
			pcall(function()
				track:Stop()
			end)
		end
		pkgTracks = {}
	end

	local function playActionPackageAnim(id, speed, weight)
		-- 源文件 5979-5997 行 fn75 是 task.spawn 异步执行的，这里同样异步，
		-- 避免 LoadAnimation 在角色刚重生时阻塞界面。
		task.spawn(function()
			stopActionPackageAnim()
			local hum = getHum(LP)
			if not hum then
				return nil
			end
			-- 源文件用 Animator:LoadAnimation；没有 Animator 就补一个（新版引擎推荐做法）
			local animator = hum:FindFirstChildOfClass("Animator")
			if not animator then
				local ok, created = pcall(function()
					return Instance.new("Animator", hum)
				end)
				if not ok then
					animator = nil
				else
					animator = created
				end
			end

			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://" .. tostring(id)

			local track
			-- 有 Animator 用 Animator:LoadAnimation，否则退回 Humanoid:LoadAnimation
			local ok = pcall(function()
				if animator then
					track = animator:LoadAnimation(anim)
				else
					track = hum:LoadAnimation(anim)
				end
			end)
			if not ok or not track then
				return nil
			end

			track.Looped = true
			-- 源文件 5991 行：优先级固定为 Action，保证动作能盖住默认动画
			local okPrio = pcall(function()
				track.Priority = Enum.AnimationPriority.Action
			end)
			if not okPrio then
				pcall(function()
					track.Priority = Enum.AnimationPriority.Action2
				end)
			end

			track:Play(weight or 0, 1, 0)
			track:AdjustSpeed(speed or 1)
			table.insert(pkgTracks, track)
			return track
		end)
	end

	actionSec:Button({
		Title = "播放选中动作",
		Desc = "播放下拉框里选中的动作",
		Icon = "play",
		Callback = function()
			if not selectedAction or selectedAction == "" then
				notify("提示", "请先选择一个动作", "x")
				return
			end
			for _, entry in ipairs(actionList) do
				if entry[1] == selectedAction then
					playActionPackageAnim(entry[2], entry[3], entry[4])
					notify("动作包", "已播放：" .. tostring(selectedAction))
					return
				end
			end
			notify("错误", "列表里没有这个动作", "x")
		end,
	})

	actionSec:Button({
		Title = "停止所有动画",
		Desc = "停止本页动作包播放的动画",
		Icon = "square",
		Callback = function()
			task.spawn(stopActionPackageAnim)
			notify("动作", "已停止所有动画")
		end,
	})

	--==========================================================================
	-- [动作控制 · 第二部分] 动作控制分区（源文件 6173-6506 行）
	-- 随机跳舞 / 停止跳舞（源文件 6277-6278 行）、自定义动画 + 全局动画速度
	-- （源文件 6339-6376 行）在 黑白提取.lua 里已有实现，这里不重复。
	--==========================================================================
	tab:Divider()
	local v2Sec = tab:Section({ Title = "动作控制", Opened = true })

	----------------------------------------------------------------------------
	-- 鬼畜抽搐（源文件 6281-6320 行 fn83 / fn84）
	-- 仅 R6；ID 33796059，速度拉到 99，且**不参与** fn79 的轨道表
	----------------------------------------------------------------------------
	local twitchTrack = nil

	v2Sec:Button({
		Title = "鬼畜抽搐",
		Desc = "鬼畜抽搐动画（仅 R6）",
		Icon = "zap",
		Callback = function()
			if isR15(LP) then
				notify("鬼畜", "仅支持 R6 体形", "x")
				return
			end
			if twitchTrack then
				pcall(function()
					twitchTrack:Stop()
				end)
			end
			local hum = getHum(LP)
			if not hum then
				notify("错误", "角色未加载", "x")
				return
			end
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://33796059"
			local ok, track = pcall(function()
				return hum:LoadAnimation(anim)
			end)
			if not ok or not track then
				notify("错误", "鬼畜动画加载失败（可能被游戏禁止）", "x")
				return
			end
			twitchTrack = track
			track:Play()
			track:AdjustSpeed(99)
			notify("鬼畜", "鬼畜抽搐已开启")
		end,
	})

	v2Sec:Button({
		Title = "停止鬼畜",
		Desc = "停止鬼畜抽搐",
		Icon = "square",
		Callback = function()
			if twitchTrack then
				pcall(function()
					twitchTrack:Stop()
				end)
				twitchTrack = nil
			end
			notify("鬼畜", "已停止")
		end,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 甩头（源文件 6323-6336 行）ID 35154961，仅 R6，不循环
	----------------------------------------------------------------------------
	v2Sec:Button({
		Title = "甩头",
		Desc = "甩头动作（仅 R6）",
		Icon = "refresh-cw",
		Callback = function()
			if isR15(LP) then
				notify("甩头", "仅支持 R6 体形", "x")
				return
			end
			local hum = getHum(LP)
			if not hum then
				notify("错误", "角色未加载", "x")
				return
			end
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://35154961"
			local ok, track = pcall(function()
				return hum:LoadAnimation(anim)
			end)
			if not ok or not track then
				notify("错误", "甩头动画加载失败", "x")
				return
			end
			track.Looped = false
			track:Play(0, 1, 0)
			notify("甩头", "甩头动作已播放")
		end,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 定住 / 解冻所有动画（源文件 6380-6413 行 fn85 / fn86）
	-- 被冻住 / 解冻时记录一个状态标志，和源文件 flag6 一样
	----------------------------------------------------------------------------
	local frozen = false

	v2Sec:Button({
		Title = "定住动画",
		Desc = "冻结当前所有动画（速度设 0）",
		Icon = "snowflake",
		Callback = function()
			if not getHum(LP) and not getChar(LP) then
				return
			end
			frozen = true
			forEachPlayingTracks(function(track)
				track:AdjustSpeed(0)
			end)
			notify("动画", "已定住所有动画")
		end,
	})

	v2Sec:Button({
		Title = "解冻动画",
		Desc = "恢复所有动画速度（速度设 1）",
		Icon = "sun",
		Callback = function()
			if not getHum(LP) and not getChar(LP) then
				return
			end
			frozen = false
			forEachPlayingTracks(function(track)
				track:AdjustSpeed(1)
			end)
			notify("动画", "已解冻所有动画")
		end,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 循环当前动画（源文件 6416-6436 行）
	-- 源文件用 `n3 += 1`（Luau 语法），这里改成 n = n + 1
	----------------------------------------------------------------------------
	v2Sec:Button({
		Title = "循环当前动画",
		Desc = "把当前所有播放中的动画设为循环",
		Icon = "repeat",
		Callback = function()
			local n = forEachPlayingTracks(function(track)
				track.Looped = true
			end)
			notify("循环", "已设置 " .. tostring(n) .. " 条动画为循环")
		end,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 停止当前所有播放中的动画（源文件 6440-6449 行，跟上面只停自己的不同，这里停全部）
	----------------------------------------------------------------------------
	v2Sec:Button({
		Title = "停止当前全部动画",
		Desc = "停掉角色身上正在播放的所有动画",
		Icon = "square",
		Callback = function()
			forEachPlayingTracks(function(track)
				track:Stop()
			end)
			notify("动画", "已停止所有动画")
		end,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 刷新动画（源文件 6453-6473 行 fn87）
	-- 手法：把角色里的 Animate 脚本 Disabled = true -> 停掉所有轨道 -> 再 Disabled = false，
	-- 让 Animate 重新接管，默认行走/待机动画就回来了。fn87 也被下面「自定义动画包」复用。
	----------------------------------------------------------------------------
	local function refreshAnimate()
		local ch = getChar(LP)
		if not ch then
			notify("刷新", "角色未加载", "x")
			return false
		end
		local hum = ch:FindFirstChildOfClass("Humanoid")
		local animate = ch:FindFirstChild("Animate")
		if not hum or not animate then
			notify("刷新", "未找到 Animate/Humanoid", "x")
			return false
		end

		animate.Disabled = true
		for _, track in pairs(hum:GetPlayingAnimationTracks()) do
			pcall(function()
				track:Stop()
			end)
		end
		animate.Disabled = false
		notify("刷新", "动画已刷新")
		return true
	end

	v2Sec:Button({
		Title = "刷新动画",
		Desc = "重置 Animate 脚本，恢复默认动画",
		Icon = "refresh-cw",
		Callback = refreshAnimate,
	})

	v2Sec:Divider()

	----------------------------------------------------------------------------
	-- 自定义动画包（源文件 6476-6491 行）
	-- 源文件直接写 fn5("StarterPlayer").AllowCustomAnimations —— 这是**服务端属性**，
	-- 普通 LocalScript 没有权限改（会报权限错误），所以这里用 pcall 包住：
	-- 在客户端能达到的等价效果就是刷新一次 Animate，让自定义动画生效/失效。
	----------------------------------------------------------------------------
	v2Sec:Toggle({
		Title = "自定义动画包",
		Desc = "启用/禁用自定义动画包（需配合刷新）",
		Value = false,
		Callback = function(on)
			local ok = pcall(function()
				game:GetService("StarterPlayer").AllowCustomAnimations = on
			end)
			if not ok then
				notify("自定义动画", "客户端无权修改 StarterPlayer（服务端属性），已只做刷新", "x")
			end
			refreshAnimate()
			if on then
				notify("自定义动画", "已开启自定义动画包")
			else
				notify("自定义动画", "已关闭自定义动画包")
			end
		end,
	})

	----------------------------------------------------------------------------
	-- 说明（源文件 6493-6506 行 Paragraph，原文照搬）
	----------------------------------------------------------------------------
	v2Sec:Paragraph({
		Title = "说明",
		Desc = [[• 随机跳舞：自动适配 R6/R15
• 鬼畜/甩头：仅 R6 体形
• 自定义动画：输入 ID 和速度播放
• 全局速度调整：影响当前所有动画
• 定住/解冻：暂停/恢复所有动画
• 循环当前动画：将当前动画设为循环
• 刷新动画：重置 Animate 脚本
• 自定义动画包：开启后可使用自定义动画]],
		Image = "info",
		ImageSize = 16,
		Color = Color3.fromRGB(72, 72, 72),
	})

	----------------------------------------------------------------------------
	-- 窗口关闭清理（源文件 6508-6518 行 window:OnClose）
	-- 只做能确定生效的一步：停掉本页动作包自己播的动画。
	-- 源文件那儿还 Stop 了 v10（鬼畜轨道），这里一并处理。
	-- 关闭注册走 ctx.onClose（由调用方统一实现），为 nil 时静默跳过。
	--------------------------------------------------------------------------
	if ctx.onClose then
		ctx.onClose(function()
			stopActionPackageAnim()
			if twitchTrack then
				pcall(function()
					twitchTrack:Stop()
				end)
				twitchTrack = nil
			end
		end)
	end
end
end)()

-- 远程脚本是独立 chunk，出错必须显式暴露，否则就是静默白屏
local ok, err = pcall(build, Tab, ctx)
if not ok then
	warn("[动作包] 构建失败: " .. tostring(err))
	pcall(notify, "动作包", "构建失败: " .. tostring(err), "x")
	getgenv().__HB_ACTION_LOADED = nil   -- 清掉标志位，允许再点一次重试
else
	-- 成功也打一条到控制台，方便排查「页签是空的」这类问题
	print("[黑白提取] 远程模块已加载: 动作包 (" .. tostring(#Tab.Elements or 0) .. " 个元素)")
end
