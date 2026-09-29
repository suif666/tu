--[[
	Roblox 音频提取器
	==================
	把游戏里的音频真正下载下来，以文件形式存到执行器的工作目录，并生成清单。

	用法：
	  1. 进游戏，等音频加载过一遍（音乐/音效都放一放，这样能拿到时长）
	  2. 需要的话改下面 CONFIG
	  3. 跑脚本，去执行器 workspace 里取文件

	输出：
	  <OUT_DIR>/音频/...            下载到的音频文件
	  <OUT_DIR>/index.txt           人看的清单
	  <OUT_DIR>/index.json          机器读的清单（AssetId 原样保留，可直接发我）
	  <OUT_DIR>/失败的.txt          没下下来的，方便重试

	说明：
	  · Roblox 里唯一承载音频的类就是 Sound，所以扫描 Sound 即穷尽。
	  · Sound.TimeLength 只有「加载过」才有值，没加载的会是 0，
	    默认不因此跳过（时长未知也照样下）。
	  · Roblox 音频源文件是 OGG Vorbis，存下来一般是 .ogg；
	    脚本会看魔数自动判断真实格式，不会写错后缀。
]]

-- ══════════════════════════ 配置 ══════════════════════════
local CONFIG = {
	OUT_DIR      = "提取的音频",   -- 输出目录（相对执行器 workspace）
	SUB_DIR      = "音频",         -- 音频文件放的子目录

	-- 过滤：默认全都要
	MIN_LEN      = 0,              -- 只要时长 >= 这个（秒），0 = 不限
	MAX_LEN      = 99999,          -- 只要时长 <= 这个（秒）
	NAME_FILTER  = "",             -- 只抓名字/路径含这个词的，留空 = 全部
	ONLY_PLAYING = false,          -- true = 只抓正在播放的

	-- 行为
	DOWNLOAD     = true,           -- false = 只生成清单，不下载
	MAX_COUNT    = 0,              -- 最多抓几个，0 = 不限
	WATCH_SECONDS = 8,             -- 额外监听 N 秒，抓扫描之后才创建的音频（0 = 不监听）
	RETRY        = 2,              -- 每个音频失败重试次数
}
-- ═══════════════════════════════════════════════════════════

local FS = {
	writefile  = writefile,
	makefolder = makefolder,
	isfolder   = isfolder,
	isfile     = isfile,
	readfile   = readfile,
	appendfile = appendfile,
}

local function hasFilesystem()
	return type(FS.writefile) == "function" and type(FS.makefolder) == "function"
end

-- ══════════════ HTTP：多路回退 ══════════════
local HTTP_METHOD_USED = nil

local function httpGet(url)
	if type(request) == "function" then
		local ok, r = pcall(request, { Url = url, Method = "GET" })
		if ok and type(r) == "table" and r.Body then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "request"
			return r.Body, r.StatusCode
		end
	end
	if type(http_request) == "function" then
		local ok, r = pcall(http_request, { Url = url, Method = "GET" })
		if ok and type(r) == "table" and r.Body then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "http_request"
			return r.Body, r.StatusCode
		end
	end
	if syn and type(syn.request) == "function" then
		local ok, r = pcall(syn.request, { Url = url, Method = "GET" })
		if ok and type(r) == "table" and r.Body then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "syn.request"
			return r.Body, r.StatusCode
		end
	end
	if http and type(http.request) == "function" then
		local ok, r = pcall(http.request, { Url = url, Method = "GET" })
		if ok and type(r) == "table" and r.Body then
			HTTP_METHOD_USED = HTTP_METHOD_USED or "http.request"
			return r.Body, r.StatusCode
		end
	end
	local ok, r = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and type(r) == "string" and #r > 0 then
		HTTP_METHOD_USED = HTTP_METHOD_USED or "game:HttpGet"
		return r, 200
	end
	return nil, nil
end

-- ══════════════ 真实格式识别 ══════════════
local function detectExt(data)
	if not data or #data < 4 then
		return "bin"
	end
	local head = data:sub(1, 4)
	if head == "OggS" then
		return "ogg"
	end
	if head:sub(1, 3) == "ID3" then
		return "mp3"
	end
	local b1, b2 = data:byte(1), data:byte(2)
	if b1 == 255 and (b2 == 251 or b2 == 243 or b2 == 242) then
		return "mp3"
	end
	if head == "RIFF" then
		return "wav"
	end
	if head == "fLaC" then
		return "flac"
	end
	if head:sub(1, 1) == "{" then
		return "json"
	end
	return "bin"
end

-- ══════════════ 下载单个音频 ══════════════
local function downloadOnce(assetId)
	local id = tostring(assetId)

	-- A: v1 直链
	local v1 = {
		"https://assetdelivery.roblox.com/v1/asset/?id=" .. id,
		"https://assetdelivery.roblox.com/v1/asset?id=" .. id,
	}
	for _, u in ipairs(v1) do
		local body = httpGet(u)
		if body and #body > 1024 then
			local ext = detectExt(body)
			if ext ~= "json" and ext ~= "bin" then
				return body, ext, "v1"
			end
		end
	end

	-- B: v2 拿 CDN 直链
	local v2 = httpGet("https://assetdelivery.roblox.com/v2/assetId/" .. id)
	if v2 and #v2 > 0 then
		local loc = v2:match('"location"%s*:%s*"([^"]+)"')
		if loc then
			loc = loc:gsub("\\/", "/")
			local body = httpGet(loc)
			if body and #body > 1024 then
				local ext = detectExt(body)
				if ext ~= "json" and ext ~= "bin" then
					return body, ext, "v2-cdn"
				end
			end
		end
	end

	-- C: getcustomasset 缓存
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
	local lastHow = "失败"
	for _ = 1, tries do
		local data, ext, how = downloadOnce(assetId)
		if data then
			return data, ext, how
		end
		lastHow = how
		task.wait(0.15)
	end
	return nil, nil, lastHow
end

-- ══════════════ 收集音频 ══════════════
local found = {}
local byInstance = {}

local function consider(s)
	if typeof(s) ~= "Instance" or not s:IsA("Sound") then
		return
	end
	local sid = s.SoundId
	if not sid or sid == "" then
		return
	end
	local id = tostring(sid):match("(%d+)")
	if not id then
		return
	end
	if byInstance[s] then
		return
	end
	byInstance[s] = true

	local name = s.Name or "?"
	local parent = (s.Parent and s.Parent:GetFullName()) or "?"

	if CONFIG.ONLY_PLAYING and not s.IsPlaying then
		return
	end
	local len = s.TimeLength or 0
	if len < CONFIG.MIN_LEN or len > CONFIG.MAX_LEN then
		return
	end
	if CONFIG.NAME_FILTER ~= "" then
		local f = CONFIG.NAME_FILTER:lower()
		if not (name:lower():find(f, 1, true) or parent:lower():find(f, 1, true)) then
			return
		end
	end

	table.insert(found, {
		obj     = s,
		numId   = id,
		soundId = sid,
		name    = name,
		len     = len,
		playing = s.IsPlaying,
		looped  = s.Looped,
		volume  = s.Volume,
		parent  = parent,
	})
end

local function collectAll()
	-- 1) 先全量扫一遍
	local n = 0
	for _, d in ipairs(game:GetDescendants()) do
		pcall(consider, d)
		n = n + 1
	end
	print(string.format("[提取] 扫描了 %d 个实例", n))

	-- 2) 再监听一会儿，抓扫描之后才创建的
	if CONFIG.WATCH_SECONDS and CONFIG.WATCH_SECONDS > 0 then
		print(string.format("[提取] 额外监听 %d 秒，捕捉后创建的音频…", CONFIG.WATCH_SECONDS))
		local conn = game.DescendantAdded:Connect(function(d)
			pcall(consider, d)
		end)
		task.wait(CONFIG.WATCH_SECONDS)
		pcall(function()
			conn:Disconnect()
		end)
	end

	-- 3) 排序：时长长的（歌曲）在前，同长按名字
	table.sort(found, function(a, b)
		if a.len ~= b.len then
			return a.len > b.len
		end
		return a.name < b.name
	end)
end

-- ══════════════════════════ 主流程 ══════════════════════════
print("===================================================")
print("[提取] Roblox 音频提取器")
print("===================================================")

if not hasFilesystem() and CONFIG.DOWNLOAD then
	warn("[提取] 当前执行器没有 writefile/makefolder，只能生成清单")
	CONFIG.DOWNLOAD = false
end

collectAll()
print(string.format("[提取] 符合条件(%.0f~%.0f秒)的音频: %d 个",
	CONFIG.MIN_LEN, CONFIG.MAX_LEN, #found))

if #found == 0 then
	warn("[提取] 一个都没找到。放宽 MIN_LEN/MAX_LEN，或确认音频已加载")
	return
end

-- 建目录
local base = CONFIG.OUT_DIR
local dir = base .. "/" .. CONFIG.SUB_DIR
if CONFIG.DOWNLOAD then
	local ok = pcall(FS.makefolder, base)
	if ok then
		ok = pcall(FS.makefolder, dir)
	end
	if not ok then
		warn("[提取] 建目录失败，改用根目录")
		base, dir = ".", "."
	end
end

local index = {}
local okCount, failCount, skipCount = 0, 0, 0
local totalBytes = 0
local savedById = {}
local failed = {}

print("")
for i, s in ipairs(found) do
	if CONFIG.MAX_COUNT > 0 and (okCount + failCount) >= CONFIG.MAX_COUNT then
		print(string.format("[提取] 已达 MAX_COUNT=%d，停止", CONFIG.MAX_COUNT))
		break
	end

	local entry = {
		order   = i,
		name    = s.name,
		assetId = s.numId,   -- 保留字符串！Luau 的 tostring 会把 1e14 写成科学计数法
		length  = tonumber(string.format("%.2f", s.len)),
		looped  = s.looped,
		volume  = s.volume,
		playing = s.playing,
		path    = s.parent,
		file    = nil,
		bytes   = nil,
		method  = nil,
		note    = nil,
	}

	if savedById[s.numId] then
		entry.file = savedById[s.numId]
		entry.note = "同 AssetId 复用"
		skipCount = skipCount + 1
	elseif not CONFIG.DOWNLOAD then
		print(string.format("  [%d/%d] %-26s %8.2fs  id=%s",
			i, #found, s.name:sub(1, 26), s.len, s.numId))
	else
		local data, ext, how = downloadAudio(s.numId)
		if data then
			local safe = s.name:gsub("[\\/:*?\"<>|%%]", "_"):sub(1, 40)
			local fname = string.format("%s/%04d_%s_%s.%s", dir, i, safe, s.numId, ext)
			local ok, err = pcall(FS.writefile, fname, data)
			if ok then
				okCount = okCount + 1
				totalBytes = totalBytes + #data
				savedById[s.numId] = fname
				entry.file = fname
				entry.bytes = #data
				entry.method = how
				print(string.format("  [%d/%d] OK   %-24s %8.2fs  %8.1f KB  %s",
					i, #found, s.name:sub(1, 24), s.len, #data / 1024, ext))
			else
				failCount = failCount + 1
				entry.note = "写文件失败: " .. tostring(err)
				table.insert(failed, { name = s.name, id = s.numId, len = s.len, why = entry.note })
				warn(string.format("  [%d/%d] 写失败 %-22s %s", i, #found, s.name:sub(1, 22), tostring(err)))
			end
		else
			failCount = failCount + 1
			entry.note = how
			table.insert(failed, { name = s.name, id = s.numId, len = s.len, why = how })
			warn(string.format("  [%d/%d] 失败 %-24s %8.2fs  id=%s",
				i, #found, s.name:sub(1, 24), s.len, s.numId))
		end
	end

	table.insert(index, entry)
end

-- ══════════════ 写清单 ══════════════
if CONFIG.DOWNLOAD then
	-- 人看的
	local lines = {}
	table.insert(lines, "# 音频提取清单")
	table.insert(lines, string.format("# 共 %d 条，成功 %d，失败 %d", #index, okCount, failCount))
	table.insert(lines, "")
	table.insert(lines, string.format("%-6s %-28s %-10s %-18s %s", "序", "名字", "时长", "AssetId", "文件"))
	for _, e in ipairs(index) do
		table.insert(lines, string.format("%-6d %-28s %-10s %-18s %s",
			e.order, (e.name or ""):sub(1, 28), tostring(e.length) .. "s",
			tostring(e.assetId), e.file or ("(未提取: " .. tostring(e.note) .. ")")))
	end
	pcall(FS.writefile, base .. "/index.txt", table.concat(lines, "\n"))

	-- 机器读的（AssetId 带引号，避免科学计数法）
	local j = {}
	table.insert(j, "{")
	table.insert(j, string.format('  "total": %d,', #index))
	table.insert(j, string.format('  "extracted": %d,', okCount))
	table.insert(j, string.format('  "failed": %d,', failCount))
	table.insert(j, string.format('  "bytes": %d,', totalBytes))
	table.insert(j, '  "items": [')
	for k, e in ipairs(index) do
		local comma = (k < #index) and "," or ""
		table.insert(j, string.format(
			'    {"order":%d,"name":"%s","assetId":"%s","length":%s,"file":"%s","bytes":%s,"method":"%s","note":"%s"}%s',
			e.order, (e.name or ""):gsub('"', "'"), tostring(e.assetId),
			tostring(e.length), tostring(e.file), tostring(e.bytes),
			tostring(e.method), tostring(e.note or ""), comma))
	end
	table.insert(j, "  ]")
	table.insert(j, "}")
	pcall(FS.writefile, base .. "/index.json", table.concat(j, "\n"))

	-- 失败清单
	if #failed > 0 then
		local f = { "# 没提取成功的（AssetId 可查名字）", "" }
		for _, x in ipairs(failed) do
			table.insert(f, string.format("%-30s %8.2fs  id=%s  (%s)",
				x.name:sub(1, 30), x.len, x.id, x.why))
		end
		pcall(FS.writefile, base .. "/失败的.txt", table.concat(f, "\n"))
	end
end

print("")
print("===================================================")
print(string.format("[提取] 完成：成功 %d，失败 %d，复用 %d", okCount, failCount, skipCount))
if totalBytes > 0 then
	print(string.format("[提取] 总大小: %.2f MB", totalBytes / 1024 / 1024))
end
if HTTP_METHOD_USED then
	print("[提取] 生效的下载方式: " .. HTTP_METHOD_USED)
end
if CONFIG.DOWNLOAD then
	print("[提取] 目录: " .. dir)
	print("[提取] 清单: " .. base .. "/index.json")
end
print("===================================================")

if okCount == 0 and CONFIG.DOWNLOAD then
	warn("[提取] 一个都没下下来。原因通常是：")
	warn("  1. 执行器没有 request/http_request 这类能带登录态的请求函数")
	warn("  2. assetdelivery 需要 .ROBLOSECURITY，匿名会被拒")
	warn("  3. 音频是付费/私密资产")
	warn("  把 index.json 里的 AssetId 发我，我能查名字")
end
