--[[
	Roblox 音频提取器 —— GUI 版
	=============================
	先扫描，再由你决定下载哪些。支持试听、搜索、勾选、导出清单。

	相比上一版的优化：
	  · 扫描改成「分帧遍历 + 主动让出线程」，不再一次性 GetDescendants 卡死
	  · 不再自动全下。扫描完列出清单，你勾选哪些才下哪些
	  · 下载逐个进行，每个文件之间 task.wait 让出线程，可以随时停止
	  · 内置试听（直接播放 rbxassetid，不用先下载）
	  · 搜索过滤、导入导出、单个下载

	用法：
	  loadstring(game:HttpGet("..."))()
	  然后：扫描 -> 搜索/勾选 -> 试听确认 -> 下载选中
]]

-- ═══════════════════════════ 配置 ═══════════════════════════
local CONFIG = {
	OUT_DIR        = "提取的音频",
	SUB_DIR        = "音频",
	MAX_ROWS       = 400,     -- 列表最多渲染多少行（防卡）
	PREVIEW_VOLUME = 0.6,     -- 试听音量
	YIELD_EVERY    = 30,      -- 每遍历多少个实例让出一次线程
	RETRY          = 2,       -- 单个音频失败重试次数
}
-- ══════════════════════════════════════════════════════════════

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local LP = Players.LocalPlayer
local HTTP_METHOD_USED = nil

-- ═══════════════════ 文件系统 ═══════════════════
local FS = {
	writefile  = writefile,
	makefolder = makefolder,
	isfolder   = isfolder,
	readfile   = readfile,
}
local function hasFS()
	return type(FS.writefile) == "function" and type(FS.makefolder) == "function"
end

-- ═══════════════════ HTTP ═══════════════════
local function httpGet(url)
	if type(request) == "function" then
		local ok, r = pcall(request, { Url = url, Method = "GET" })
		if ok and type(r) == "table" and r.Body then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "request"
			return r.Body
		end
	end
	if type(http_request) == "function" then
		local ok, r = pcall(http_request, { Url = url, Method = "GET" })
		if ok and type(r) == "table" and r.Body then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "http_request"
			return r.Body
		end
	end
	if syn and type(syn.request) == "function" then
		local ok, r = pcall(syn.request, { Url = url, Method = "GET" })
		if ok and type(r) == "table" and r.Body then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "syn.request"
			return r.Body
		end
	end
	if http and type(http.request) == "function" then
		local ok, r = pcall(http.request, { Url = url, Method = "GET" })
		if ok and type(r) == "table" and r.Body then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "http.request"
			return r.Body
		end
	end
	local ok, r = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and type(r) == "string" and #r > 0 then
		HTTP_METHOD_USED = HTTP_METHOD_USED or "game:HttpGet"
		return r
	end
	return nil
end

-- ═══════════════════ 格式识别 ═══════════════════
local function detectExt(data)
	if not data or #data < 4 then
		return "bin"
	end
	local head = data:sub(1, 4)
	if head == "OggS" then return "ogg" end
	if head:sub(1, 3) == "ID3" then return "mp3" end
	local b1, b2 = data:byte(1), data:byte(2)
	if b1 == 255 and (b2 == 251 or b2 == 243 or b2 == 242) then return "mp3" end
	if head == "RIFF" then return "wav" end
	if head == "fLaC" then return "flac" end
	if head:sub(1, 1) == "{" then return "json" end
	return "bin"
end

-- ═══════════════════ 下载 ═══════════════════
local function downloadOnce(assetId)
	local id = tostring(assetId)

	for _, u in ipairs({
		"https://assetdelivery.roblox.com/v1/asset/?id=" .. id,
		"https://assetdelivery.roblox.com/v1/asset?id=" .. id,
	}) do
		local body = httpGet(u)
		if body and #body > 1024 then
			local ext = detectExt(body)
			if ext ~= "json" and ext ~= "bin" then
				return body, ext, "v1"
			end
		end
	end

	local v2 = httpGet("https://assetdelivery.roblox.com/v2/assetId/" .. id)
	if v2 and #v2 > 0 then
		local loc = v2:match('"location"%s*:%s*"([^"]+)"')
		if loc then
			local body = httpGet((loc:gsub("\\/", "/")))
			if body and #body > 1024 then
				local ext = detectExt(body)
				if ext ~= "json" and ext ~= "bin" then
					return body, ext, "v2-cdn"
				end
			end
		end
	end

	if type(getcustomasset) == "function" and type(FS.readfile) == "function" then
		local ok, path = pcall(getcustomasset, "rbxassetid://" .. id)
		if ok and type(path) == "string" then
			local ok2, data = pcall(FS.readfile, path)
			if ok2 and type(data) == "string" and #data > 1024 then
				local ext = detectExt(data)
				if ext ~= "json" and ext ~= "bin" then
					return data, ext, "customasset"
				end
			end
		end
	end

	return nil, nil, "失败"
end

local function downloadAudio(assetId)
	local tries = math.max(1, CONFIG.RETRY)
	local how = "失败"
	for _ = 1, tries do
		local data, ext, h = downloadOnce(assetId)
		if data then return data, ext, h end
		how = h
		task.wait(0.1)
	end
	return nil, nil, how
end

-- ═══════════════════ 状态 ═══════════════════
local items = {}          -- 扫描结果
local itemById = {}       -- AssetId -> item（去重、复用文件）
local selected = {}       -- item -> true
local previewSound = nil
local previewItem = nil
local downloading = false
local stopRequest = false
local scanned = false

-- ═══════════════════ 扫描（分帧，不卡） ═══════════════════
local function makeItem(s)
	local sid = s.SoundId
	if not sid or sid == "" then return nil end
	local id = tostring(sid):match("(%d+)")
	if not id then return nil end
	return {
		obj     = s,
		numId   = id,
		name    = s.Name or "?",
		len     = s.TimeLength or 0,
		playing = s.IsPlaying,
		looped  = s.Looped,
		parent  = (s.Parent and s.Parent:GetFullName()) or "?",
		file    = nil,
	}
end

local function scanAsync(onProgress, onDone)
	local queue = { game }
	local qi = 1
	local visited = 0
	local seenInst = {}

	while qi <= #queue do
		local node = queue[qi]
		qi = qi + 1

		local okChildren, children = pcall(function()
			return node:GetChildren()
		end)
		if okChildren and children then
			for _, child in ipairs(children) do
				if not seenInst[child] then
					seenInst[child] = true
					visited = visited + 1
					if child:IsA("Sound") then
						local it = makeItem(child)
						if it then
							-- 同一 AssetId 只保留一条（记录引用数）
							local exist = itemById[it.numId]
							if exist then
								exist.refs = (exist.refs or 1) + 1
							else
								it.refs = 1
								itemById[it.numId] = it
								table.insert(items, it)
							end
						end
					end
					table.insert(queue, child)
				end
			end
		end

		if visited % CONFIG.YIELD_EVERY == 0 then
			if onProgress and visited % (CONFIG.YIELD_EVERY * 8) == 0 then
				onProgress(visited, #queue - qi + 1)
			end
			task.wait()
		end
	end

	table.sort(items, function(a, b)
		if a.len ~= b.len then return a.len > b.len end
		return a.name < b.name
	end)

	scanned = true
	if onDone then onDone(#items) end
end

-- ═══════════════════ GUI ═══════════════════
local C = {
	bg      = Color3.fromRGB(22, 22, 26),
	panel   = Color3.fromRGB(31, 31, 37),
	panel2  = Color3.fromRGB(38, 38, 45),
	row1    = Color3.fromRGB(28, 28, 33),
	row2    = Color3.fromRGB(33, 33, 39),
	accent  = Color3.fromRGB(88, 138, 255),
	text    = Color3.fromRGB(235, 235, 242),
	dim     = Color3.fromRGB(145, 145, 158),
	ok      = Color3.fromRGB(80, 200, 120),
	warn    = Color3.fromRGB(240, 180, 80),
	bad     = Color3.fromRGB(235, 95, 95),
}

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = p
	return c
end

local function pad(p, n)
	local u = Instance.new("UIPadding")
	u.PaddingTop = UDim.new(0, n)
	u.PaddingBottom = UDim.new(0, n)
	u.PaddingLeft = UDim.new(0, n)
	u.PaddingRight = UDim.new(0, n)
	u.Parent = p
	return u
end

local function mkLabel(parent, txt, size, pos, color, bold)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = txt
	l.TextSize = size or 13
	l.TextColor3 = color or C.text
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.new(1, 0, 1, 0)   -- 调用方一般会再覆盖 Size
	l.Position = pos or UDim2.new(0, 0, 0, 0)
	l.Parent = parent
	return l
end

local function mkButton(parent, txt, w, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 1, 0)
	b.BackgroundColor3 = color or C.panel2
	b.Text = txt
	b.TextColor3 = C.text
	b.TextSize = 13
	b.Font = Enum.Font.GothamMedium
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.Parent = parent
	corner(b, 5)
	return b
end

-- 父级容器
local function guiParent()
	local ok, cg = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and cg then return cg end
	if LP then return LP:WaitForChild("PlayerGui") end
	return nil
end

local parent = guiParent()
if not parent then
	warn("[音频提取] 找不到 GUI 容器")
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "AudioExtractorGUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent

-- 主窗
local win = Instance.new("Frame")
win.Size = UDim2.new(0, 760, 0, 520)
win.Position = UDim2.new(0.5, -380, 0.5, -260)
win.BackgroundColor3 = C.bg
win.BorderSizePixel = 0
win.Parent = gui
corner(win, 10)

-- 标题栏（可拖动）
local title = Instance.new("Frame")
title.Size = UDim2.new(1, 0, 0, 42)
title.BackgroundColor3 = C.panel
title.BorderSizePixel = 0
title.Active = true
title.Parent = win
corner(title, 10)

local titleFix = Instance.new("Frame")   -- 盖掉下方圆角
titleFix.Size = UDim2.new(1, 0, 0, 12)
titleFix.Position = UDim2.new(0, 0, 1, -12)
titleFix.BackgroundColor3 = C.panel
titleFix.BorderSizePixel = 0
titleFix.Parent = title

local titleText = mkLabel(title, "  音频提取器", 16, UDim2.new(0, 0, 0, 0), C.text, true)
titleText.Size = UDim2.new(1, -60, 1, 0)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 34, 0, 26)
closeBtn.Position = UDim2.new(1, -40, 0.5, -13)
closeBtn.BackgroundColor3 = C.bad
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.TextSize = 14
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
closeBtn.Parent = title
corner(closeBtn, 5)

-- 拖动
do
	local dragging, dragStart, startPos = false, nil, nil
	title.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = win.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	title.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - dragStart
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

-- 工具栏
local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, -24, 0, 36)
bar.Position = UDim2.new(0, 12, 0, 54)
bar.BackgroundTransparency = 1
bar.Parent = win

local btnScan = mkButton(bar, "重新扫描", 84, C.accent)
btnScan.Position = UDim2.new(0, 0, 0, 0)

local btnSelAll = mkButton(bar, "全选", 56)
btnSelAll.Position = UDim2.new(0, 90, 0, 0)

local btnSelNone = mkButton(bar, "清空", 56)
btnSelNone.Position = UDim2.new(0, 152, 0, 0)

local btnDownload = mkButton(bar, "下载选中", 84, C.ok)
btnDownload.Position = UDim2.new(0, 214, 0, 0)

local btnStop = mkButton(bar, "停止", 56, C.bad)
btnStop.Position = UDim2.new(0, 304, 0, 0)

local btnExport = mkButton(bar, "导出清单", 84)
btnExport.Position = UDim2.new(0, 366, 0, 0)

-- 搜索框
local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(0, 240, 0, 30)
searchBox.Position = UDim2.new(1, -246, 0, 3)
searchBox.BackgroundColor3 = C.panel2
searchBox.Text = ""
searchBox.PlaceholderText = "搜索名字 / AssetId / 路径"
searchBox.TextColor3 = C.text
searchBox.PlaceholderColor3 = C.dim
searchBox.TextSize = 13
searchBox.Font = Enum.Font.Gotham
searchBox.BorderSizePixel = 0
searchBox.ClearTextOnFocus = false
searchBox.Parent = bar
corner(searchBox, 5)
pad(searchBox, 6)

-- 列表（表头 + 滚动区）
local header = Instance.new("Frame")
header.Size = UDim2.new(1, -24, 0, 24)
header.Position = UDim2.new(0, 12, 0, 96)
header.BackgroundColor3 = C.panel
header.BorderSizePixel = 0
header.Parent = win

local function headerCell(txt, x, w, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = txt
	l.TextSize = 12
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = C.dim
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Size = UDim2.new(0, w, 1, 0)
	l.Position = UDim2.new(0, x, 0, 0)
	l.Parent = header
	return l
end
headerCell("选中", 10, 44, Enum.TextXAlignment.Center)
headerCell("名字", 60, 210)
headerCell("时长", 274, 66)
headerCell("AssetId", 344, 130)
headerCell("操作", 484, 240, Enum.TextXAlignment.Center)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -24, 1, -206)
scroll.Position = UDim2.new(0, 12, 0, 122)
scroll.BackgroundColor3 = C.panel
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = C.accent
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = win
corner(scroll, 6)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 2)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

pad(scroll, 4)

-- 底部状态栏
local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, -24, 0, 68)
footer.Position = UDim2.new(0, 12, 1, -80)
footer.BackgroundColor3 = C.panel
footer.BorderSizePixel = 0
footer.Parent = win
corner(footer, 6)

local statusText = mkLabel(footer, "  就绪。点「重新扫描」开始。", 13, UDim2.new(0, 0, 0, 4), C.text)
statusText.Size = UDim2.new(1, -220, 0, 20)

local countText = mkLabel(footer, "  共 0 条 / 已选 0", 12, UDim2.new(0, 0, 0, 24), C.dim)
countText.Size = UDim2.new(1, -220, 0, 18)

-- 试听控制
local btnPreviewStop = mkButton(footer, "停止试听", 84, C.warn)
btnPreviewStop.Size = UDim2.new(0, 84, 0, 26)
btnPreviewStop.Position = UDim2.new(1, -96, 0, 6)
btnPreviewStop.Visible = false

local previewLabel = mkLabel(footer, "  试听: 无", 12, UDim2.new(0, 0, 0, 44), C.dim)
previewLabel.Size = UDim2.new(1, -220, 0, 18)

-- 进度条
local progBg = Instance.new("Frame")
progBg.Size = UDim2.new(1, -24, 0, 4)
progBg.Position = UDim2.new(0, 12, 1, -6)
progBg.BackgroundColor3 = C.panel2
progBg.BorderSizePixel = 0
progBg.Parent = win
corner(progBg, 2)

local progFill = Instance.new("Frame")
progFill.Size = UDim2.new(0, 0, 1, 0)
progFill.BackgroundColor3 = C.accent
progFill.BorderSizePixel = 0
progFill.Parent = progBg
corner(progFill, 2)

-- ═══════════════════ 界面操作 ═══════════════════
local function setStatus(txt, color)
	statusText.Text = "  " .. txt
	statusText.TextColor3 = color or C.text
end

local function setProgress(frac)
	progFill.Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0)
end

local function updateCount()
	local n = 0
	for _ in pairs(selected) do n = n + 1 end
	countText.Text = string.format("  共 %d 条 / 已选 %d", #items, n)
end

local function fmtLen(l)
	if not l or l <= 0 then return "未知" end
	return string.format("%.1fs", l)
end

-- 试听
-- previewOwned = true 表示这个 Sound 是我们自己建的，可以 Stop/Destroy；
-- false 表示是游戏原本的对象，只能断开引用，绝不能销毁。
local previewOwned = false

local function stopPreview()
	if previewSound and previewOwned then
		pcall(function()
			previewSound:Stop()
			previewSound:Destroy()
		end)
	end
	previewSound = nil
	previewOwned = false
	previewItem = nil
	btnPreviewStop.Visible = false
	previewLabel.Text = "  试听: 无"
end

local function playPreview(item)
	stopPreview()
	if item.playing and item.obj and item.obj.Parent then
		-- 游戏内正在播放的原声，直接用它的播放状态，不要新建也不要动它
		previewSound = item.obj
		previewOwned = false
		previewItem = item
		previewLabel.Text = "  试听: " .. item.name .. "（游戏内正在播放）"
		btnPreviewStop.Visible = true
		return
	end

	local s = Instance.new("Sound")
	s.Name = "HB_Preview"
	s.SoundId = "rbxassetid://" .. item.numId
	s.Volume = CONFIG.PREVIEW_VOLUME
	s.Parent = SoundService
	previewSound = s
	previewOwned = true
	previewItem = item

	s.Ended:Connect(function()
		if previewSound == s then
			stopPreview()
		end
	end)

	local ok = pcall(function()
		s:Play()
	end)
	if ok then
		previewLabel.Text = "  试听: " .. item.name .. "  (id " .. item.numId .. ")"
		btnPreviewStop.Visible = true
	else
		local msg = "  试听失败（资源可能不可访问）: " .. item.name
		stopPreview()
		previewLabel.Text = msg
	end
end

-- 前置声明：renderList 里每一行的「下载」按钮要用到它，
-- 而 renderList 定义在下载队列之前。不前置声明的话，
-- 闭包里引用到的会解析成全局变量（nil），点按钮直接报错。
local startDownload

-- ═══════════════════ 列表渲染 ═══════════════════
local rowRefs = {}

local function clearRows()
	for _, r in ipairs(rowRefs) do
		pcall(function() r:Destroy() end)
	end
	rowRefs = {}
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
end

local function matchFilter(item, q)
	if q == "" then return true end
	q = q:lower()
	return item.name:lower():find(q, 1, true) ~= nil
		or tostring(item.numId):find(q, 1, true) ~= nil
		or item.parent:lower():find(q, 1, true) ~= nil
end

local function renderList()
	clearRows()
	local q = searchBox.Text or ""
	local shown = 0

	for i, item in ipairs(items) do
		if matchFilter(item, q) then
			shown = shown + 1
			if shown > CONFIG.MAX_ROWS then
				break
			end

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 30)
			row.BackgroundColor3 = (shown % 2 == 0) and C.row1 or C.row2
			row.BorderSizePixel = 0
			row.LayoutOrder = shown
			row.Parent = scroll
			corner(row, 4)
			table.insert(rowRefs, row)

			-- 勾选
			local chk = Instance.new("TextButton")
			chk.Size = UDim2.new(0, 22, 0, 22)
			chk.Position = UDim2.new(0, 16, 0.5, -11)
			chk.BackgroundColor3 = selected[item] and C.accent or C.panel2
			chk.Text = selected[item] and "✓" or ""
			chk.TextColor3 = Color3.new(1, 1, 1)
			chk.TextSize = 14
			chk.Font = Enum.Font.GothamBold
			chk.BorderSizePixel = 0
			chk.Parent = row
			corner(chk, 4)

			-- 名字
			local nm = mkLabel(row, item.name, 13, UDim2.new(0, 60, 0, 0), C.text)
			nm.Size = UDim2.new(0, 210, 1, 0)
			nm.TextTruncate = Enum.TextTruncate.AtEnd
			if item.refs and item.refs > 1 then
				nm.Text = item.name .. "  ×" .. item.refs
			end

			-- 时长
			local ln = mkLabel(row, fmtLen(item.len), 12, UDim2.new(0, 274, 0, 0), C.dim)
			ln.Size = UDim2.new(0, 66, 1, 0)

			-- AssetId
			local idl = mkLabel(row, item.numId, 11, UDim2.new(0, 344, 0, 0), C.dim)
			idl.Size = UDim2.new(0, 130, 1, 0)
			idl.Font = Enum.Font.Code

			-- 试听
			local bp = mkButton(row, "试听", 56, C.panel2)
			bp.Size = UDim2.new(0, 56, 0, 22)
			bp.Position = UDim2.new(0, 484, 0.5, -11)

			-- 下载这一个
			local bd = mkButton(row, "下载", 56, C.panel2)
			bd.Size = UDim2.new(0, 56, 0, 22)
			bd.Position = UDim2.new(0, 546, 0.5, -11)

			-- 状态
			local st = mkLabel(row, item.file and "已保存" or "", 11,
				UDim2.new(0, 610, 0, 0), item.file and C.ok or C.dim)
			st.Size = UDim2.new(0, 120, 1, 0)
			st.TextTruncate = Enum.TextTruncate.AtEnd

			-- 事件
			chk.MouseButton1Click:Connect(function()
				selected[item] = (not selected[item]) or nil
				chk.BackgroundColor3 = selected[item] and C.accent or C.panel2
				chk.Text = selected[item] and "✓" or ""
				updateCount()
			end)

			bp.MouseButton1Click:Connect(function()
				if previewItem == item then
					stopPreview()
				else
					playPreview(item)
				end
			end)

			bd.MouseButton1Click:Connect(function()
				if downloading then
					setStatus("正在下载中，先点「停止」", C.warn)
					return
				end
				startDownload({ item }, function(ok)
					if ok then
						st.Text = "已保存"
						st.TextColor3 = C.ok
					else
						st.Text = "失败"
						st.TextColor3 = C.bad
					end
				end)
			end)
		end
	end

	scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
	updateCount()
	if shown > CONFIG.MAX_ROWS then
		setStatus(string.format("匹配 %d 条，只渲染前 %d 条，请用搜索缩小范围", shown, CONFIG.MAX_ROWS), C.warn)
	end

	-- AbsoluteContentSize 要等布局跑完才算准，刚插完行时可能还是旧值，
	-- 这里补一次延迟刷新，避免滚动条长度不对、滚不到底。
	task.spawn(function()
		task.wait(0.1)
		if scroll and scroll.Parent then
			scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
		end
	end)
end

-- ═══════════════════ 下载队列 ═══════════════════
startDownload = function(list, onEach)
	if downloading then
		setStatus("已有下载任务在跑", C.warn)
		return
	end
	if not hasFS() then
		setStatus("执行器没有 writefile，无法保存文件", C.bad)
		return
	end
	if #list == 0 then
		setStatus("没有选中任何条目", C.warn)
		return
	end

	downloading = true
	stopRequest = false
	btnDownload.BackgroundColor3 = C.panel2

	local base = CONFIG.OUT_DIR
	local dir = base .. "/" .. CONFIG.SUB_DIR
	pcall(FS.makefolder, base)
	pcall(FS.makefolder, dir)

	task.spawn(function()
		local okN, failN, totalBytes = 0, 0, 0

		for i, item in ipairs(list) do
			if stopRequest then
				setStatus(string.format("已停止（完成 %d / %d）", i - 1, #list), C.warn)
				break
			end

			setProgress((i - 1) / #list)
			setStatus(string.format("下载中 %d/%d  %s", i, #list, item.name), C.text)

			-- 已经下过的直接复用
			if item.file then
				okN = okN + 1
				if onEach then onEach(true, item) end
			else
				local data, ext, how = downloadAudio(item.numId)
				if data then
					local safe = item.name:gsub("[\\/:*?\"<>|%%]", "_"):sub(1, 40)
					local fname = string.format("%s/%s_%s.%s", dir, safe, item.numId, ext)
					local ok = pcall(FS.writefile, fname, data)
					if ok then
						okN = okN + 1
						totalBytes = totalBytes + #data
						item.file = fname
						item.bytes = #data
						if onEach then onEach(true, item) end
					else
						failN = failN + 1
						if onEach then onEach(false, item) end
					end
				else
					failN = failN + 1
					item.err = how
					if onEach then onEach(false, item) end
				end
			end

			setProgress(i / #list)
			-- 关键：让出线程，避免连续同步请求把游戏卡死
			task.wait(0.05)
		end

		downloading = false
		stopRequest = false
		btnDownload.BackgroundColor3 = C.ok

		if totalBytes > 0 then
			setStatus(string.format("完成：成功 %d，失败 %d，共 %.2f MB",
				okN, failN, totalBytes / 1024 / 1024), C.ok)
		else
			setStatus(string.format("完成：成功 %d，失败 %d", okN, failN), okN > 0 and C.ok or C.bad)
		end
		renderList()
	end)
end

-- ═══════════════════ 导出清单 ═══════════════════
local function exportIndex()
	if not hasFS() then
		setStatus("执行器没有 writefile，无法导出", C.bad)
		return
	end
	local base = CONFIG.OUT_DIR
	pcall(FS.makefolder, base)

	local j = {}
	table.insert(j, "{")
	table.insert(j, string.format('  "total": %d,', #items))
	table.insert(j, '  "items": [')
	local saved = 0
	for k, it in ipairs(items) do
		if it.file then saved = saved + 1 end
		local comma = (k < #items) and "," or ""
		-- AssetId 必须带引号：Luau 的 tostring 会把 1e14 写成科学计数法
		table.insert(j, string.format(
			'    {"name":"%s","assetId":"%s","length":%.2f,"file":"%s","path":"%s"}%s',
			it.name:gsub('"', "'"), it.numId, it.len or 0,
			tostring(it.file), it.parent:gsub('"', "'"), comma))
	end
	table.insert(j, "  ]")
	table.insert(j, "}")

	pcall(FS.writefile, base .. "/index.json", table.concat(j, "\n"))

	local lines = { "# 音频扫描清单", string.format("# 共 %d 条，已保存 %d", #items, saved), "" }
	for i, it in ipairs(items) do
		table.insert(lines, string.format("%-4d %-30s %8.2fs  id=%s  %s",
			i, it.name:sub(1, 30), it.len or 0, it.numId,
			it.file and ("-> " .. it.file) or ""))
	end
	pcall(FS.writefile, base .. "/index.txt", table.concat(lines, "\n"))

	setStatus("清单已导出：" .. base .. "/index.json", C.ok)
end

-- ═══════════════════ 事件绑定 ═══════════════════
local function doScan()
	if downloading then
		setStatus("下载中，先停止再扫描", C.warn)
		return
	end
	stopPreview()
	items = {}
	itemById = {}
	selected = {}
	scanned = false
	clearRows()
	setProgress(0)
	setStatus("扫描中…", C.text)

	task.spawn(function()
		scanAsync(function(visited, remain)
			setStatus(string.format("扫描中… 已遍历 %d 个实例，队列剩 %d", visited, remain), C.text)
			-- 扫描进度无法精确预估，用队列消退做视觉反馈
			if remain > 0 then
				setProgress(1 - math.min(1, remain / (remain + visited + 1)))
			end
		end, function(n)
			setProgress(1)
			setStatus(string.format("扫描完成：找到 %d 个不同的音频", n), C.ok)
			renderList()
		end)
	end)
end

btnScan.MouseButton1Click:Connect(doScan)

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if scanned then
		renderList()
	end
end)

btnSelAll.MouseButton1Click:Connect(function()
	for _, it in ipairs(items) do
		selected[it] = true
	end
	renderList()
end)

btnSelNone.MouseButton1Click:Connect(function()
	selected = {}
	renderList()
end)

btnDownload.MouseButton1Click:Connect(function()
	local list = {}
	for _, it in ipairs(items) do
		if selected[it] then
			table.insert(list, it)
		end
	end
	startDownload(list)
end)

btnStop.MouseButton1Click:Connect(function()
	if downloading then
		stopRequest = true
		setStatus("正在停止…", C.warn)
	else
		stopPreview()
		setStatus("已停止试听", C.dim)
	end
end)

btnExport.MouseButton1Click:Connect(exportIndex)

btnPreviewStop.MouseButton1Click:Connect(function()
	stopPreview()
end)

closeBtn.MouseButton1Click:Connect(function()
	stopPreview()
	if previewSound then
		pcall(function() previewSound:Destroy() end)
	end
	gui:Destroy()
end)

-- ═══════════════════ 启动 ═══════════════════
setStatus("就绪。点「重新扫描」开始。", C.text)
setProgress(0)
updateCount()

-- 自动先扫一次
task.spawn(function()
	task.wait(0.3)
	doScan()
end)

print("[音频提取] GUI 已加载。窗口可拖动，右上角 X 关闭。")
