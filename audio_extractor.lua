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
-- 取执行器能拿到的 Roblox 登录 cookie。
-- 只用于向 assetdelivery.roblox.com（Roblox 自己的服务器）请求你自己游戏里的资源，
-- 和 Roblox 客户端做的事完全一样。绝不会打印、绝不会发往其它域名。
local function getCookie()
	local cands = {
		function() return getcookie and getcookie() end,
		function() return syn and syn.getcookie and syn.getcookie() end,
		function() return GetCookie and GetCookie() end,
		function() return getgenv and getgenv().getcookie and getgenv().getcookie() end,
	}
	for _, f in ipairs(cands) do
		local ok, c = pcall(f)
		if ok and type(c) == "string" and #c > 20 then
			return c
		end
	end
	return nil
end

local COOKIE = getCookie()

-- 统一的 HTTP GET
-- 返回 body, status, headers
local function httpRaw(url, useCookie)
	local req = { Url = url, Method = "GET" }
	if useCookie and COOKIE then
		req.Headers = { ["Cookie"] = ".ROBLOSECURITY=" .. COOKIE }
	end

	if type(request) == "function" then
		local ok, r = pcall(request, req)
		if ok and type(r) == "table" and r.Body ~= nil then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "request"
			return r.Body, r.StatusCode, r.Headers
		end
	end
	if type(http_request) == "function" then
		local ok, r = pcall(http_request, req)
		if ok and type(r) == "table" and r.Body ~= nil then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "http_request"
			return r.Body, r.StatusCode, r.Headers
		end
	end
	if syn and type(syn.request) == "function" then
		local ok, r = pcall(syn.request, req)
		if ok and type(r) == "table" and r.Body ~= nil then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "syn.request"
			return r.Body, r.StatusCode, r.Headers
		end
	end
	if http and type(http.request) == "function" then
		local ok, r = pcall(http.request, req)
		if ok and type(r) == "table" and r.Body ~= nil then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "http.request"
			return r.Body, r.StatusCode, r.Headers
		end
	end
	-- 兜底：game:HttpGet（走 Roblox 自己，通常自带客户端身份，但拿不到状态码）
	local ok, r = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and type(r) == "string" and #r > 0 then
		HTTP_METHOD_USED = HTTP_METHOD_USED or "game:HttpGet"
		return r, nil, nil
	end
	return nil, nil, nil
end

-- 自动跟随 302 跳转
local function httpGet(url, useCookie)
	local body, status, headers = httpRaw(url, useCookie)
	if headers then
		local loc = headers.Location or headers.location
		if type(loc) == "table" then loc = loc[1] end
		if type(loc) == "string" and loc ~= "" then
			local b2, s2 = httpRaw(loc, useCookie)
			if b2 and #b2 > 0 then
				return b2, s2, headers
			end
		end
	end
	return body, status, headers
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
	if head == "ftyp" or data:sub(5, 8) == "ftyp" then return "m4a" end
	if head:sub(1, 1) == "{" then return "json" end
	if head:sub(1, 1) == "<" then return "html" end
	return "bin"
end

-- 判断拿到的是不是真的音频
local function isAudio(data)
	if not data or #data < 256 then return false end
	local ext = detectExt(data)
	return ext ~= "json" and ext ~= "html" and ext ~= "bin"
end

-- 把响应体变成一句人能看懂的说明
local function explain(body, status)
	if not body then return "无响应" end
	if #body == 0 then return "空响应" end
	if status then
		if status == 401 or status == 403 then
			return "HTTP " .. status .. " 鉴权被拒（需要登录态）"
		end
		if status == 404 then
			return "HTTP 404 资源不存在或无权访问"
		end
		if status == 429 then
			return "HTTP 429 请求太频繁被限流"
		end
	end
	local code = body:match('"code"%s*:%s*(%d+)')
	local msg = body:match('"message"%s*:%s*"([^"]+)"')
	if code or msg then
		return string.format("接口报错 code=%s %s", tostring(code), tostring(msg))
	end
	if body:sub(1, 1) == "<" then
		return "返回了 HTML 页面（不是音频）"
	end
	return string.format("响应 %d 字节，不是音频", #body)
end

-- 从诊断记录里挑出最有信息量的一条失败原因
local function shortReason(diag)
	if not diag or #diag == 0 then
		return nil
	end
	local best = nil
	for _, d in ipairs(diag) do
		if not d.ok then
			if not best then
				best = d
			end
			-- 鉴权类原因最有价值，优先展示
			local n = d.note or ""
			if n:find("鉴权", 1, true) or n:find("401", 1, true)
				or n:find("403", 1, true) or n:find("code=", 1, true) then
				best = d
			end
		end
	end
	if best then
		return string.format("%s: %s", best.method, best.note)
	end
	return nil
end

-- ═══════════════════ 下载 ═══════════════════
-- 按「最可能成功」的顺序逐个尝试，并记录每一步的结果
local function tryAll(assetId, collectDiag)
	local id = tostring(assetId)
	local diag = {}

	local function record(method, ok, note)
		if collectDiag then
			table.insert(diag, { method = method, ok = ok, note = note })
		end
	end

	local function accept(method, data, status)
		if isAudio(data) then
			record(method, true, string.format("%d 字节 %s", #data, detectExt(data)))
			return data, detectExt(data), method
		end
		record(method, false, explain(data, status))
		return nil
	end

	-- ① getcustomasset：走客户端自己的授权会话，对游戏内音频成功率最高
	if type(getcustomasset) == "function" and type(FS.readfile) == "function" then
		local ok, path = pcall(getcustomasset, "rbxassetid://" .. id)
		if ok and type(path) == "string" then
			local ok2, data = pcall(FS.readfile, path)
			if ok2 and type(data) == "string" then
				local d, e, m = accept("getcustomasset", data, nil)
				if d then return d, e, m, diag end
			else
				record("getcustomasset", false, "拿到路径但 readfile 读不了: " .. tostring(path):sub(1, 40))
			end
		else
			record("getcustomasset", false, "调用失败（执行器可能不支持音频）")
		end
	end

	-- ② 带 cookie 的 v1 直链
	local urls = {
		{ "v1+cookie", "https://assetdelivery.roblox.com/v1/asset/?id=" .. id, true },
		{ "v1+cookie(serverplaceid)", "https://assetdelivery.roblox.com/v1/asset/?id=" .. id .. "&serverplaceid=0", true },
		{ "v1", "https://assetdelivery.roblox.com/v1/asset/?id=" .. id, false },
		{ "v1(serverplaceid)", "https://assetdelivery.roblox.com/v1/asset/?id=" .. id .. "&serverplaceid=0", false },
	}
	for _, u in ipairs(urls) do
		local body, status = httpGet(u[2], u[3])
		local d, e, m = accept(u[1], body, status)
		if d then return d, e, m, diag end
	end

	-- ③ v2 拿 CDN 直链
	for _, useCookie in ipairs({ true, false }) do
		local tag = useCookie and "v2+cookie" or "v2"
		local v2body, v2status = httpGet("https://assetdelivery.roblox.com/v2/assetId/" .. id, useCookie)
		if v2body and #v2body > 0 then
			local loc = v2body:match('"location"%s*:%s*"([^"]+)"')
			if loc then
				local body, status = httpGet((loc:gsub("\\/", "/")), false)
				local d, e, m = accept(tag .. "-cdn", body, status)
				if d then return d, e, m, diag end
			else
				record(tag, false, explain(v2body, v2status))
			end
		else
			record(tag, false, explain(v2body, v2status))
		end
	end

	-- ④ game:HttpGet 单独再试一次。
	-- 它走 Roblox 自己的网络栈，通常自带客户端身份，和 request 的路径不一样，
	-- 所以即使 request 拿到了非音频响应，这一步也可能成功。
	for _, u in ipairs({
		"https://assetdelivery.roblox.com/v1/asset/?id=" .. id,
		"https://assetdelivery.roblox.com/v1/asset/?id=" .. id .. "&serverplaceid=0",
	}) do
		local ok, body = pcall(function()
			return game:HttpGet(u, true)
		end)
		if ok and type(body) == "string" then
			local d, e, m = accept("HttpGet", body, nil)
			if d then return d, e, m, diag end
		else
			record("HttpGet", false, "game:HttpGet 调用失败")
			break
		end
	end

	return nil, nil, "失败", diag
end

local function downloadOnce(assetId)
	local data, ext, how, diag = tryAll(assetId, false)
	return data, ext, how, diag
end

local function downloadAudio(assetId)
	local tries = math.max(1, CONFIG.RETRY)
	local how = "失败"
	local lastDiag = nil
	for _ = 1, tries do
		local data, ext, h, d = downloadOnce(assetId)
		if data then return data, ext, h end
		how = h
		lastDiag = d
		task.wait(0.15)
	end
	return nil, nil, how, lastDiag
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
-- 窗口尺寸：按视口算，默认只占屏幕一小块。右下角有拖拽手柄可调，尺寸会记住。
local function getViewport()
	local cam = workspace.CurrentCamera
	if cam then
		local ok, v = pcall(function() return cam.ViewportSize end)
		if ok and v then return v end
	end
	return Vector2.new(1280, 720)
end

local function loadRect()
	if type(isfile) ~= "function" or type(readfile) ~= "function" then return nil end
	local fp = CONFIG.OUT_DIR .. "/ui.txt"
	local ok, f = pcall(isfile, fp)
	if not ok or not f then return nil end
	local ok2, txt = pcall(readfile, fp)
	if not ok2 or type(txt) ~= "string" then return nil end
	local w, h, x, y = txt:match("(%d+),(%d+),(%-?%d+),(%-?%d+)")
	if w then return tonumber(w), tonumber(h), tonumber(x), tonumber(y) end
	return nil
end

local VP = getViewport()
local savedW, savedH, savedX, savedY = loadRect()

-- 默认只占屏幕一小块：宽约 42%、高约 50%
local defW = math.clamp(math.floor(VP.X * 0.42), 400, 620)
local defH = math.clamp(math.floor(VP.Y * 0.50), 300, 460)

-- 记住的尺寸也要夹回当前视口，否则换显示器/改分辨率后窗口会跑到屏幕外
local maxW = math.max(380, VP.X - 30)
local maxH = math.max(240, VP.Y - 30)
local sW = math.clamp(savedW or defW, 380, maxW)
local sH = math.clamp(savedH or defH, 240, maxH)
local sX = math.clamp(savedX or math.floor((VP.X - sW) / 2), 0, math.max(0, VP.X - sW))
local sY = math.clamp(savedY or math.floor((VP.Y - sH) / 3), 0, math.max(0, VP.Y - sH))

local win = Instance.new("Frame")
win.Size = UDim2.new(0, sW, 0, sH)
win.Position = UDim2.new(0, sX, 0, sY)
win.BackgroundColor3 = C.bg
win.BorderSizePixel = 0
win.Parent = gui
corner(win, 10)

-- 标题栏（可拖动）
local title = Instance.new("Frame")
title.Size = UDim2.new(1, 0, 0, 36)
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

local titleText = mkLabel(title, "  音频提取器", 14, UDim2.new(0, 0, 0, 0), C.text, true)
titleText.Size = UDim2.new(1, -60, 1, 0)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 34, 0, 26)
closeBtn.Position = UDim2.new(1, -38, 0.5, -12)
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
bar.Size = UDim2.new(1, -24, 0, 28)
bar.Position = UDim2.new(0, 12, 0, 42)
bar.BackgroundTransparency = 1
bar.Parent = win

-- 小窗下面板变窄，7 个按钮按像素排一行，字号缩到 12 保证不挤
local BTN = { { "重新扫描", 60, C.accent }, { "全选", 38 }, { "清空", 38 },
              { "下载选中", 60, C.ok }, { "停止", 38, C.bad },
              { "导出清单", 52 }, { "诊断下载", 52, C.warn } }
local bx = 0
local barBtns = {}
for i, d in ipairs(BTN) do
	local b = mkButton(bar, d[1], d[2], d[3])
	b.Size = UDim2.new(0, d[2], 1, 0)
	b.Position = UDim2.new(0, bx, 0, 0)
	b.TextSize = 12
	barBtns[i] = b
	bx = bx + d[2] + 5
end
local btnScan, btnSelAll, btnSelNone = barBtns[1], barBtns[2], barBtns[3]
local btnDownload, btnStop = barBtns[4], barBtns[5]
local btnExport, btnDiag = barBtns[6], barBtns[7]

-- 搜索框单独一行，占满宽度
local bar2 = Instance.new("Frame")
bar2.Size = UDim2.new(1, -24, 0, 26)
bar2.Position = UDim2.new(0, 12, 0, 74)
bar2.BackgroundTransparency = 1
bar2.Parent = win

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, 0, 1, 0)
searchBox.Position = UDim2.new(0, 0, 0, 0)
searchBox.BackgroundColor3 = C.panel2
searchBox.Text = ""
searchBox.PlaceholderText = "搜索名字 / AssetId / 路径"
searchBox.TextColor3 = C.text
searchBox.PlaceholderColor3 = C.dim
searchBox.TextSize = 12
searchBox.Font = Enum.Font.Gotham
searchBox.BorderSizePixel = 0
searchBox.ClearTextOnFocus = false
searchBox.Parent = bar2
corner(searchBox, 5)
pad(searchBox, 6)

-- 列表（表头 + 滚动区）
local header = Instance.new("Frame")
header.Size = UDim2.new(1, -24, 0, 20)
header.Position = UDim2.new(0, 12, 0, 104)
header.BackgroundColor3 = C.panel
header.BorderSizePixel = 0
header.Parent = win

-- 列宽：左边固定像素，右边从右往左贴边，中间「名字」占剩余宽度。
-- 这样窗口拉窄也不会把右边的按钮挤出去。
local COL = {
	chk  = { UDim2.new(0, 6),    UDim2.new(0, 18) },
	name = { UDim2.new(0, 28),   UDim2.new(1, -248) },
	len  = { UDim2.new(1, -216), UDim2.new(0, 40) },
	id   = { UDim2.new(1, -172), UDim2.new(0, 88) },
	play = { UDim2.new(1, -124), UDim2.new(0, 56) },
	down = { UDim2.new(1, -64),  UDim2.new(0, 56) },
}

local function headerCell(txt, spec, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = txt
	l.TextSize = 11
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = C.dim
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Size = spec[2]
	l.Position = spec[1]
	l.Parent = header
	return l
end
headerCell("选", COL.chk, Enum.TextXAlignment.Center)
headerCell("名字", COL.name)
headerCell("时长", COL.len)
headerCell("AssetId", COL.id, Enum.TextXAlignment.Right)
headerCell("操作", COL.down, Enum.TextXAlignment.Right)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -24, 1, -188)
scroll.Position = UDim2.new(0, 12, 0, 126)
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
footer.Size = UDim2.new(1, -24, 0, 50)
footer.Position = UDim2.new(0, 12, 1, -56)
footer.BackgroundColor3 = C.panel
footer.BorderSizePixel = 0
footer.Parent = win
corner(footer, 6)

local statusText = mkLabel(footer, "就绪。点「重新扫描」开始。", 11, UDim2.new(0, 6, 0, 2), C.text)
statusText.Size = UDim2.new(1, -86, 0, 16)
statusText.TextTruncate = Enum.TextTruncate.AtEnd

local countText = mkLabel(footer, "共 0 条 / 已选 0", 11, UDim2.new(0, 6, 0, 18), C.dim)
countText.Size = UDim2.new(1, -86, 0, 15)

local previewLabel = mkLabel(footer, "试听: 无", 10, UDim2.new(0, 6, 0, 33), C.dim)
previewLabel.Size = UDim2.new(1, -86, 0, 14)
previewLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- 试听控制
local btnPreviewStop = mkButton(footer, "停止试听", 74, C.warn)
btnPreviewStop.Size = UDim2.new(0, 74, 0, 22)
btnPreviewStop.Position = UDim2.new(1, -80, 0, 14)
btnPreviewStop.TextSize = 11
btnPreviewStop.Visible = false

-- 进度条
local progBg = Instance.new("Frame")
progBg.Size = UDim2.new(1, -40, 0, 4)
progBg.Position = UDim2.new(0, 12, 1, -6)
progBg.BackgroundColor3 = C.panel2
progBg.BorderSizePixel = 0
progBg.Parent = win
corner(progBg, 2)

-- 右下角拖拽缩放手柄：觉得窗小/窗大都直接拉
local grip = Instance.new("TextButton")
grip.Size = UDim2.new(0, 20, 0, 20)
grip.Position = UDim2.new(1, -22, 1, -22)
grip.BackgroundTransparency = 1
grip.Text = "◢"
grip.TextColor3 = C.dim
grip.TextSize = 12
grip.TextXAlignment = Enum.TextXAlignment.Right
grip.TextYAlignment = Enum.TextYAlignment.Bottom
grip.AutoButtonColor = false
grip.Parent = win

do
	local resizing, rStart, rW, rH = false, nil, 0, 0
	grip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			rStart = input.Position
			rW = win.AbsoluteSize.X
			rH = win.AbsoluteSize.Y
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
				end
			end)
		end
	end)
	grip.InputChanged:Connect(function(input)
		if not resizing then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - rStart
			local maxW = math.max(420, VP.X - 30)
			local maxH = math.max(300, VP.Y - 30)
			local nw = math.clamp(rW + d.X, 380, maxW)
			local nh = math.clamp(rH + d.Y, 240, maxH)
			win.Size = UDim2.new(0, nw, 0, nh)
		end
	end)
end

local progFill = Instance.new("Frame")
progFill.Size = UDim2.new(0, 0, 1, 0)
progFill.BackgroundColor3 = C.accent
progFill.BorderSizePixel = 0
progFill.Parent = progBg
corner(progFill, 2)

-- ═══════════════════ 界面操作 ═══════════════════
local function setStatus(txt, color)
	statusText.Text = txt
	statusText.TextColor3 = color or C.text
end

local function setProgress(frac)
	progFill.Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0)
end

local function updateCount()
	local n = 0
	for _ in pairs(selected) do n = n + 1 end
	countText.Text = string.format("共 %d 条 / 已选 %d", #items, n)
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
	previewLabel.Text = "试听: 无"
end

local function playPreview(item)
	stopPreview()
	if item.playing and item.obj and item.obj.Parent then
		-- 游戏内正在播放的原声，直接用它的播放状态，不要新建也不要动它
		previewSound = item.obj
		previewOwned = false
		previewItem = item
		previewLabel.Text = "试听: " .. item.name .. "（游戏内正在播放）"
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
		previewLabel.Text = "试听: " .. item.name .. "  (id " .. item.numId .. ")"
		btnPreviewStop.Visible = true
	else
		local msg = "试听失败（资源可能不可访问）: " .. item.name
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
			row.Size = UDim2.new(1, -8, 0, 26)
			row.BackgroundColor3 = (shown % 2 == 0) and C.row1 or C.row2
			row.BorderSizePixel = 0
			row.LayoutOrder = shown
			row.Parent = scroll
			corner(row, 4)
			table.insert(rowRefs, row)

			-- 勾选
			local chk = Instance.new("TextButton")
			chk.Size = UDim2.new(0, 18, 0, 18)
			chk.Position = COL.chk[1] + UDim2.new(0, 0, 0.5, -9)
			chk.BackgroundColor3 = selected[item] and C.accent or C.panel2
			chk.Text = selected[item] and "✓" or ""
			chk.TextColor3 = Color3.new(1, 1, 1)
			chk.TextSize = 12
			chk.Font = Enum.Font.GothamBold
			chk.BorderSizePixel = 0
			chk.Parent = row
			corner(chk, 4)

			-- 名字（下载状态直接体现在这一列的颜色和前缀上，省掉一整列）
			local label = item.name
			if item.refs and item.refs > 1 then
				label = item.name .. "  ×" .. item.refs
			end
			local nameColor = C.text
			if item.file then
				label = "✓ " .. label
				nameColor = C.ok
			elseif item.err then
				nameColor = C.bad
			end
			local nm = mkLabel(row, label, 12, COL.name[1], nameColor)
			nm.Size = COL.name[2]
			nm.TextTruncate = Enum.TextTruncate.AtEnd

			-- 时长
			local ln = mkLabel(row, fmtLen(item.len), 11, COL.len[1], C.dim)
			ln.Size = COL.len[2]

			-- AssetId
			local idl = mkLabel(row, item.numId, 9, COL.id[1], C.dim)
			idl.Size = COL.id[2]
			idl.Font = Enum.Font.Code
			idl.TextXAlignment = Enum.TextXAlignment.Right

			-- 试听
			local bp = mkButton(row, "试听", 56, C.panel2)
			bp.Size = UDim2.new(0, 52, 0, 20)
			bp.Position = COL.play[1] + UDim2.new(0, 0, 0.5, -10)
			bp.TextSize = 11

			-- 下载这一个
			local bd = mkButton(row, "下载", 56, C.panel2)
			bd.Size = UDim2.new(0, 52, 0, 20)
			bd.Position = COL.down[1] + UDim2.new(0, 0, 0.5, -10)
			bd.TextSize = 11

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
						nm.TextColor3 = C.ok
						nm.Text = "✓ " .. nm.Text
					else
						nm.TextColor3 = C.bad
						setStatus((item.name .. " 失败: " .. (item.err or "未知")), C.bad)
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
		local failList = {}

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
				local data, ext, how, diag = downloadAudio(item.numId)
				if data then
					local safe = item.name:gsub("[\\/:*?\"<>|%%]", "_"):sub(1, 40)
					local fname = string.format("%s/%s_%s.%s", dir, safe, item.numId, ext)
					local ok = pcall(FS.writefile, fname, data)
					if ok then
						okN = okN + 1
						totalBytes = totalBytes + #data
						item.file = fname
						item.bytes = #data
						item.method = how
						if onEach then onEach(true, item) end
					else
						failN = failN + 1
						item.err = "写文件失败"
						table.insert(failList, item)
						if onEach then onEach(false, item) end
					end
				else
					failN = failN + 1
					-- 把最后一次尝试里最有信息量的失败原因带出来
					item.err = shortReason(diag) or how
					table.insert(failList, item)
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

		-- 失败时把原因打印出来，方便定位
		if failN > 0 then
			local seen = {}
			print("[音频提取] 失败原因汇总:")
			for _, it in ipairs(failList) do
				local r = it.err or "未知"
				seen[r] = (seen[r] or 0) + 1
			end
			for r, n in pairs(seen) do
				print(string.format("   %d 个: %s", n, r))
			end
			for i = 1, math.min(#failList, 5) do
				print(string.format("   例: %s  id=%s  %s",
					failList[i].name, failList[i].numId, failList[i].err or "未知"))
			end
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

-- ═══════════════════ 诊断 ═══════════════════
local function runDiagnose()
	if #items == 0 then
		setStatus("先扫描出音频再诊断", C.warn)
		return
	end
	-- 优先挑一个还没下载成功的
	local target = nil
	for _, it in ipairs(items) do
		if not it.file then
			target = it
			break
		end
	end
	target = target or items[1]

	setStatus("正在诊断 " .. target.name .. " …", C.text)

	task.spawn(function()
		local env = {}
		table.insert(env, "═══ 下载诊断 ═══")
		table.insert(env, "目标: " .. target.name .. "  id=" .. target.numId)
		table.insert(env, "执行器/环境:")
		table.insert(env, "  request            " .. tostring(type(request) == "function"))
		table.insert(env, "  http_request       " .. tostring(type(http_request) == "function"))
		table.insert(env, "  syn.request        " .. tostring(syn ~= nil and type(syn.request) == "function"))
		table.insert(env, "  http.request       " .. tostring(http ~= nil and type(http.request) == "function"))
		table.insert(env, "  getcustomasset     " .. tostring(type(getcustomasset) == "function"))
		table.insert(env, "  writefile          " .. tostring(type(writefile) == "function"))
		table.insert(env, "  能取到 cookie     " .. tostring(COOKIE ~= nil))
		table.insert(env, "")
		table.insert(env, "逐个方法尝试:")

		local data, ext, how, diag = tryAll(target.numId, true)
		if diag then
			for i, d in ipairs(diag) do
				table.insert(env, string.format("  %d) %-26s %s  %s",
					i, d.method, d.ok and "成功" or "失败", d.note or ""))
			end
		end
		table.insert(env, "")
		if data then
			table.insert(env, string.format("结论: 可用方法 = %s，拿到 %d 字节 (%s)", how, #data, ext))
		else
			table.insert(env, "结论: 所有方法都失败")
			table.insert(env, "常见原因:")
			table.insert(env, "  · 执行器没有带登录态的请求函数 -> 用不了 assetdelivery")
			table.insert(env, "  · 该音频是受限/付费资产，非所有者无法下载")
			table.insert(env, "  · 需要 .ROBLOSECURITY，但执行器不提供 getcookie")
		end

		for _, l in ipairs(env) do
			print("[诊断] " .. l)
		end

		local brief = data and ("可用: " .. tostring(how))
			or ((diag and diag[1] and diag[1].note) or "全部失败")
		setStatus("诊断完成: " .. tostring(brief) .. "  （完整结果见 F9 控制台）",
			data and C.ok or C.bad)

		if type(writefile) == "function" then
			pcall(makefolder, CONFIG.OUT_DIR)
			pcall(writefile, CONFIG.OUT_DIR .. "/diag.txt", table.concat(env, "\n"))
		end
	end)
end

btnExport.MouseButton1Click:Connect(exportIndex)
btnDiag.MouseButton1Click:Connect(runDiagnose)

btnPreviewStop.MouseButton1Click:Connect(function()
	stopPreview()
end)

closeBtn.MouseButton1Click:Connect(function()
	if type(writefile) == "function" then
		local ok = pcall(function()
			local sz = win.AbsoluteSize
			local ps = win.AbsolutePosition
			if type(makefolder) == "function" then
				pcall(makefolder, CONFIG.OUT_DIR)
			end
			writefile(CONFIG.OUT_DIR .. "/ui.txt",
				string.format("%d,%d,%d,%d",
					math.floor(sz.X), math.floor(sz.Y),
					math.floor(ps.X), math.floor(ps.Y)))
		end)
		if not ok then
			-- 记不住就算了，不影响关闭
		end
	end
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
