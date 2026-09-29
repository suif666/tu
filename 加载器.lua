-- 加载器
local ... = ...

return (function(arg, ...)
	if game.Close ~= game.Close then
		return
	end
	local bindableEvent = Instance.new("BindableEvent")
	local n = nil

	task.defer(function()
		if n then
			n = 2
			bindableEvent:Fire()
		end
	end)

	n = 1
	bindableEvent.Event:Wait()
	if n ~= 2 then
		return
	end
	local flag = false
	local bindableFunction = Instance.new("BindableFunction")

	bindableFunction.OnInvoke = function(arg2, ...)
		if flag then
			if arg2 ~= 2 then
				return true
			end

			return setfenv(function(arg3, ...)
				return arg3.setfenv(function(...)
					return arg(...)
				end, arg3)(...)
			end, setmetatable({}, { __index = function(arg3, arg4)
				if arg4 == "BS_RANDOM_VARIABLE_NAME" then
					return function()
					end
				end
				return getfenv()[arg4]
			end }))(getfenv(), ...)
		end

		flag = true
		return nil
	end

	local v = bindableFunction:Invoke()
	if v then
		bindableFunction:Destroy()
		return v
	end

	local function fn(...)
		bindableFunction = bindableFunction:Destroy()
		return ...
	end

	return fn(bindableFunction:Invoke(2, ...))
end)(function()
	local function fn()
		local chunk = loadstring([[            local a = "hello"
            local b = 2
            return a - b
        ]])

		if not chunk then
			return false
		end
		return not pcall(chunk)
	end

	local function fn2()
		return not pcall(function()
			(nil)()
		end)
	end

	local function fn3()
		return pcall(function()
			if not isfolder("BS_script") then
				makefolder("BS_script")
			end

			if not isfolder("BS_script/Music") then
				makefolder("BS_script/Music")
			end
		end) and isfolder("BS_script/Music")
	end

	local function fn4()
		local CoreGui = game:GetService("CoreGui")
		local Players = game:GetService("Players")
		game:GetService("HttpService")
		game:GetService("RunService")
		local request_ = syn and syn.request or http and http.request or request
		local kick = Players.LocalPlayer.Kick
		local tbl = { "检测到抓包工具", "不要试图偷取数据", "Hook 检测生效", "System.Crash('检测到利用漏洞')" }

		local function fn5()
			task.spawn(function()
				local n = 0

				game:GetService("RunService").RenderStepped:Connect(function()
					n += 1
					local n2 = math.sin(n) * math.tan(n)
				end)
			end)

			for i = 1, 50 do
				task.spawn(function()
					while true do
						local tbl2 = {}

						for i2 = 1, 10000 do
							table.insert(tbl2, tostring(i2))
						end
					end
				end)
			end

			pcall(function()
				kick(Players.LocalPlayer, "Security Violation")
			end)

			while true do
			end
		end

		local function fn6(arg)
			pcall(function()
				if rconsoleprint then
					rconsoleprint("@@RED@@")
					rconsoleprint("\n[安全警告] " .. arg .. "\n")
				end

				local screenGui = Instance.new("ScreenGui")
				screenGui.IgnoreGuiInset = true
				screenGui.DisplayOrder = 999999
				screenGui.Parent = CoreGui
				local frame = Instance.new("Frame")
				frame.Size = UDim2.new(1, 0, 1, 0)
				frame.BackgroundColor3 = Color3.new(0, 0, 0)
				frame.Parent = screenGui
				local textLabel = Instance.new("TextLabel")
				textLabel.Text = arg .. "\n" .. tbl[math.random(1, #tbl)]
				textLabel.TextColor3 = Color3.new(1, 0, 0)
				textLabel.TextSize = 30
				textLabel.Size = UDim2.new(1, 0, 1, 0)
				textLabel.Parent = frame
			end)

			task.wait(1.5)
			fn5()
		end

		local function fn7()
			if getgenv().HttpSpy or getgenv().httppyspy then
				return "检测到全局 HttpSpy 变量"
			end

			for _, child in ipairs(CoreGui:GetChildren()) do
				local str = child.Name:lower()

				if str:find("spy") or str:find("http") then
					if child:FindFirstChild("Frame") or child:FindFirstChild("Main") then
						return "检测到非法调试 GUI: " .. child.Name
					end
				end
			end

			if request_ then
				if iscclosure and not iscclosure(request_) then
					return "Request 函数被篡改为 Lua Closure"
				end
				local v = debug.getinfo(request_)
				if v.source and (v.source:match("Spy") or v.what == "Lua") then
					return "Request 函数来源异常"
				end
			end

			return nil
		end

		local function fn8()
			task.spawn(function()
				local v

				while true do
					v = fn7()

					if v then
						break
					else
						task.wait(math.random(15, 30) / 10)
					end
				end

				fn6(v)
			end)

			local connection = nil

			connection = CoreGui.ChildAdded:Connect(function(child)
				local str = child.Name:lower()
				local pos = str:find("spy")
				local pos2

				if pos then
					pos2 = pos
				else
					pos2 = str:find("http") and str:find("gui")
				end

				if pos2 then
					connection:Disconnect()
					fn6("动态注入检测: " .. child.Name)
				end
			end)
		end

		fn8()

		local function fn9()
			pcall(function()
				game.Players.LocalPlayer:Kick()
			end)

			pcall(game.Shutdown, game)
		end

		local function fn10()
			return "a"
		end

		hookfunction(fn10, function()
			return "b"
		end)

		if not isfunctionhooked then
			fn9()
			return
		end

		if not isfunctionhooked(fn10) then
			fn9()
			return
		end
		local httpGet = game.HttpGet

		hookfunction(httpGet, function()
		end)

		if not isfunctionhooked(httpGet) then
			fn9()
			return
		end
		restorefunction(httpGet)
		if isfunctionhooked(httpGet) then
			fn9()
			return
		end
		local request_2 = request or http_request or syn and syn.request
		local request_3

		if request_2 then
			request_3 = request_2
		else
			request_3 = fluxus and fluxus.request
		end

		spawn(function()
			while task.wait(0.5) do
				pcall(function()
					if isfunctionhooked(game.HttpGet) then
						fn9()
					end

					if isfunctionhooked(game.HttpPost) then
						fn9()
					end

					if isfunctionhooked(tostring) then
						fn9()
					end

					if isfunctionhooked(setclipboard) then
						fn9()
					end

					if request_3 and isfunctionhooked(request_3) then
						fn9()
					end

					if isfolder("HttpGetFolder") or isfolder("WebhookFolder") or isfolder("RequestFolder") then
						fn9()
					end
				end)
			end
		end)

		for _, v in pairs({ "rconsoleprint", "rconsolewarn", "rconsoleinfo", "rconsoleerr", "rconsoletitle", "clonefunction" }) do
			getgenv()[v] = nil
		end

		game:GetService("StarterGui"):SetCore("SendNotification", { Title = "正在加载服务器脚本", Text = "请等待", Duration = 8, Callback = bindable })

		local function fn11(arg)
			return game:GetService(arg)
		end

		local placeId = game.PlaceId
		local localPlayer = game:GetService("Players").LocalPlayer

		local function fn12()
			local TweenService = fn11("TweenService")
			local screenGui = Instance.new("ScreenGui")
			screenGui.Name = "KongScriptPopup"
			screenGui.ResetOnSpawn = false
			screenGui.IgnoreGuiInset = true
			screenGui.DisplayOrder = 999

			local ok, result = pcall(function()
				return fn11("CoreGui")
			end)

			screenGui.Parent = ok and result or localPlayer:WaitForChild("PlayerGui")
			local frame = Instance.new("Frame")
			frame.Name = "PopupFrame"
			frame.Size = UDim2.new(0, 225, 0, 112.5)
			frame.Position = UDim2.new(1, 240, 0, 15)
			frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			frame.BorderSizePixel = 0
			frame.Parent = screenGui
			local uiCorner = Instance.new("UICorner")
			uiCorner.CornerRadius = UDim.new(0, 10.5)
			uiCorner.Parent = frame
			local textButton = Instance.new("TextButton")
			textButton.Name = "CloseBtn"
			textButton.Size = UDim2.new(0, 22.5, 0, 22.5)
			textButton.Position = UDim2.new(1, -27, 0, 4.5)
			textButton.BackgroundTransparency = 1
			textButton.Text = "X"
			textButton.TextColor3 = Color3.fromRGB(60, 60, 60)
			textButton.TextSize = 13.5
			textButton.Font = Enum.Font.SourceSansBold
			textButton.Parent = frame
			local textLabel = Instance.new("TextLabel")
			textLabel.Name = "TitleLabel"
			textLabel.Size = UDim2.new(1, -15, 0, 22.5)
			textLabel.Position = UDim2.new(0, 7.5, 0, 25.5)
			textLabel.BackgroundTransparency = 1
			textLabel.Text = "是否额外加载通用脚本"
			textLabel.TextColor3 = Color3.fromRGB(30, 30, 30)
			textLabel.TextSize = 12.75
			textLabel.Font = Enum.Font.SourceSansBold
			textLabel.Parent = frame
			local textLabel2 = Instance.new("TextLabel")
			textLabel2.Name = "TimeLabel"
			textLabel2.Size = UDim2.new(1, -15, 0, 18)
			textLabel2.Position = UDim2.new(0, 7.5, 0, 51)
			textLabel2.BackgroundTransparency = 1
			textLabel2.Text = "7:00"
			textLabel2.TextColor3 = Color3.fromRGB(120, 120, 120)
			textLabel2.TextSize = 11.25
			textLabel2.Font = Enum.Font.SourceSans
			textLabel2.Parent = frame
			local textButton2 = Instance.new("TextButton")
			textButton2.Name = "YesBtn"
			textButton2.Size = UDim2.new(0, 90, 0, 25.5)
			textButton2.Position = UDim2.new(0, 15, 1, -34.5)
			textButton2.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
			textButton2.Text = "是"
			textButton2.TextColor3 = Color3.fromRGB(30, 30, 30)
			textButton2.TextSize = 12
			textButton2.Font = Enum.Font.SourceSansBold
			textButton2.Parent = frame
			local uiCorner2 = Instance.new("UICorner")
			uiCorner2.CornerRadius = UDim.new(0, 7.5)
			uiCorner2.Parent = textButton2
			local textButton3 = Instance.new("TextButton")
			textButton3.Name = "NoBtn"
			textButton3.Size = UDim2.new(0, 90, 0, 25.5)
			textButton3.Position = UDim2.new(1, -105, 1, -34.5)
			textButton3.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
			textButton3.Text = "否"
			textButton3.TextColor3 = Color3.fromRGB(30, 30, 30)
			textButton3.TextSize = 12
			textButton3.Font = Enum.Font.SourceSansBold
			textButton3.Parent = frame
			local uiCorner3 = Instance.new("UICorner")
			uiCorner3.CornerRadius = UDim.new(0, 7.5)
			uiCorner3.Parent = textButton3
			TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.new(1, -240, 0, 15) }):Play()
			local flag = false
			local v = nil
			local bindableEvent = Instance.new("BindableEvent")

			local function fn13(arg)
				if flag then
					return
				end
				flag = true
				v = arg
				local tween

				if arg then
					tween = TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(1, -127.5, 0, 71.25) })
				else
					tween = TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Position = UDim2.new(1, 240, 0, 15) })
				end

				tween:Play()
				tween.Completed:Wait()
				screenGui:Destroy()
				bindableEvent:Fire()
			end

			textButton2.MouseButton1Click:Connect(function()
				task.spawn(fn13, true)
			end)

			textButton3.MouseButton1Click:Connect(function()
				task.spawn(fn13, false)
			end)

			textButton.MouseButton1Click:Connect(function()
				task.spawn(fn13, false)
			end)

			task.spawn(function()
				local n = 7

				while not flag and n > 0 do
					local n2 = math.max(0, math.floor(n * 100 + 0.5))
					textLabel2.Text = string.format("%d:%02d", math.floor(n2 / 100), n2 % 100)
					task.wait(0.01)
					n -= 0.01
				end

				if not flag then
					fn13(false)
				end
			end)

			bindableEvent.Event:Wait()
			return v
		end

		local tbl2 = {
			[126509999114328] = "https://pastefy.app/auGjJ13y/raw",
			[79546208627805] = "https://pastefy.app/auGjJ13y/raw",
			[6839171747] = "https://pastefy.app/Pfu16Dia/raw",
			[6516141723] = "https://pastefy.app/Pfu16Dia/raw",
			[8737602449] = "https://pastefy.app/XWxP8jgP/raw",
			[2474168535] = "https://pastefy.app/OBuLqneH/raw",
			[119570914951001] = "https://pastefy.app/ilKe52GH/raw",
			[14888386963] = "https://pastefy.app/ilKe52GH/raw",
			[14438406081] = "https://pastefy.app/g2kzrBNj/raw",
			[83645629621104] = "https://pastefy.app/YCqGrEjG/raw",
			[6331902150] = "https://pastefy.app/YCqGrEjG/raw",
			[103593441753340] = "https://pastefy.app/a80YC29L/raw",
			[8950496606] = "https://pastefy.app/fWjA2urK/raw",
			[125810438250765] = "https://pastefy.app/fWjA2urK/raw",
			[93044798454681] = "https://pastefy.app/fWjA2urK/raw",
			[120697797916670] = "https://pastefy.app/fWjA2urK/raw",
			[7008097940] = "https://pastefy.app/s1vmuIrL/raw",
			[155615604] = "https://pastefy.app/INfWc8aA/raw",
			[2753915549] = "https://pastefy.app/WytLShkw/raw",
			[10204250851] = "https://pastefy.app/FAmEa9Dw/raw",
			[13977939077] = "https://pastefy.app/FAmEa9Dw/raw",
			[16981421605] = "https://pastefy.app/EqkXwEjb/raw",
			[301549746] = "https://pastefy.app/dgBdfSse/raw",
			[4342047058] = "https://pastefy.app/XJ3SKq8E/raw",
			[12334109280] = "https://pastefy.app/XJ3SKq8E/raw",
			[85050171250159] = "https://pastefy.app/ET0yvqiW/raw",
			[115286378269814] = "https://pastefy.app/TaK0xd8G/raw",
			[118396261129211] = "https://pastefy.app/qPg1VeYr/raw",
			[95082159892680] = "https://pastefy.app/N0MAaHO7/raw",
			[3623096087] = "https://pastefy.app/lIDuT1BY/raw",
			[119048529960596] = "https://pastefy.app/F53tzQNA/raw",
			[83704201064817] = "https://pastefy.app/BGDQQKml/raw",
			[109652885385286] = "https://pastefy.app/BGDQQKml/raw",
			[7336302630] = "https://pastefy.app/3Jrhem0H/raw",
			[7541759836] = "https://pastefy.app/WLMwP38l/raw",
			[16044264830] = "https://pastefy.app/6X3Wyu6b/raw",
			[5985232436] = "https://pastefy.app/hrODbSGX/raw",
			[3351674303] = "https://pastefy.app/zAS3xApt/raw",
			[35397735] = "https://pastefy.app/OaMrpibc/raw",
			[119822977170203] = "https://pastefy.app/oIBhnrgF/raw",
			[121418861436763] = "https://pastefy.app/pbFPsYnZ/raw",
			[127380660530951] = "https://pastefy.app/pbFPsYnZ/raw",
			[10449761463] = "https://pastefy.app/nmRdg4oa/raw",
			[16732694052] = "https://pastefy.app/dp1u0rQr/raw",
			[93978595733734] = "https://pastefy.app/QJIsjeTj/raw",
			[18794863104] = "https://pastefy.app/PprW4FJI/raw",
			[18199615050] = "https://pastefy.app/PprW4FJI/raw",
			[136801880565837] = "https://pastefy.app/WNoQ63z2/raw",
			[286090429] = "https://pastefy.app/734YY297/raw",
			[131392929549794] = "https://pastefy.app/WLoXZyOY/raw",
			[104522435597696] = "https://pastefy.app/JIdIIjCL/raw",
			[78515283254292] = "https://pastefy.app/JIdIIjCL/raw",
			[102181577519757] = "https://pastefy.app/fWplMB2j/raw",
			[136431686349723] = "https://pastefy.app/fWplMB2j/raw",
			[96928626648264] = "https://pastefy.app/O13n9gi7/raw",
			[142823291] = "https://pastefy.app/cTT1XgL1/raw",
			[18519254033] = "https://pastefy.app/vgtO82ve/raw",
			[135739469505435] = "https://pastefy.app/wQfWfuCD/raw",
			[8767500166] = "https://pastefy.app/wQfWfuCD/raw",
			[99078474560152] = "https://pastefy.app/KQCRgTfv/raw",
			[98629859043211] = "https://pastefy.app/KQCRgTfv/raw",
			[12828227139] = "https://pastefy.app/TfzRZ9Bl/raw",
			[18879239467] = "https://pastefy.app/QzUhSabC/raw",
			[104841616983113] = "https://pastefy.app/LwkMOKjA/raw",
			[1537690962] = "https://pastefy.app/NTI1rSZ7/raw",
			[139802517550914] = "https://pastefy.app/rCBOUHCL/raw",
			[70411440483149] = "https://pastefy.app/rCBOUHCL/raw",
			[79327754502290] = "https://pastefy.app/3W4utQeO/raw",
			[86479448397834] = "https://pastefy.app/3W4utQeO/raw",
			[130594398886540] = "https://pastefy.app/Q23H3v1T/raw",
			[5256165620] = "https://pastefy.app/IAFzUQ7z/raw",
			[205224386] = "https://pastefy.app/ndDmdVSY/raw",
			[7711635737] = "https://pastefy.app/d4809d0u/raw",
			[6312753269] = "https://pastefy.app/WFOgvzcI/raw",
			[139769003880269] = "https://pastefy.app/yzvvL72z/raw",
			[77747658251236] = "https://pastefy.app/86DubIX7/raw",
			[70876832253163] = "https://pastefy.app/oTi9JK7L/raw",
			[116495829188952] = "https://pastefy.app/oTi9JK7L/raw",
			[189707] = "https://pastefy.app/OeM1aBm1/raw",
			[14438406081] = "https://pastefy.app/6fHKGH1W/raw",
			[9872472334] = "https://pastefy.app/hC2fRbfq/raw",
			[103854444055060] = "https://pastefy.app/xQuWRa9g/raw",
			[82966690358711] = "https://pastefy.app/zNW1N5cD/raw",
			[121425305223131] = "https://pastefy.app/yEk0uYJb/raw",
			[79268393072444] = "https://pastefy.app/lz2sWWcf/raw",
			[13822889] = "https://pastefy.app/W38E1YU6/raw",
			[73399811400782] = "https://pastefy.app/LaA5a95I/raw",
			[12118894416] = "https://pastefy.app/Zh3MQpSR/raw",
			[5777099015] = "https://pastefy.app/uRMwFIHo/raw",
			[123701320605975] = "https://pastefy.app/aFLqjI1Z/raw",
			[17122706530] = "https://pastefy.app/aFLqjI1Z/raw",
			[3145447020] = "https://pastefy.app/Yxfyfb0U/raw",
			[122160128185618] = "https://pastefy.app/LvqGt0Pc/raw",
			[1554960397] = "https://pastefy.app/2pOaQHWO/raw",
			[4399032158] = "https://pastefy.app/CjUKezHB/raw",
			[3956818381] = "https://pastefy.app/p2oHhd6s/raw",
			[8908228901] = "https://pastefy.app/vqqFrsIy/raw",
			[121308443347459] = "https://pastefy.app/fheqgcvs/raw",
			[17474746614] = "https://pastefy.app/fheqgcvs/raw",
			[4580204640] = "https://pastefy.app/iYtCfyAf/raw",
			[107802085750759] = "https://pastefy.app/xp304RNz/raw",
			[94141670851856] = "https://pastefy.app/xp304RNz/raw",
			[72167803024670] = "https://pastefy.app/6EhMcmMS/raw",
			[17391182236] = "https://pastefy.app/pEYtRxVa/raw",
			[15251574108] = "https://pastefy.app/pEYtRxVa/raw",
			[112279762578792] = "https://pastefy.app/qnGNdypd/raw",
			[5041144419] = "https://pastefy.app/2mJNX6mD/raw",
			[112281258506108] = "https://pastefy.app/XJKo6jTZ/raw",
			[135279186223423] = "https://pastefy.app/XJKo6jTZ/raw",
			[97463774278378] = "https://pastefy.app/cvnN2zSm/raw",
			[7239319209] = "https://pastefy.app/2V7wqFny/raw",
			[110333320616502] = "https://pastefy.app/ybjWQIGE/raw",
			[138837502355157] = "https://pastefy.app/ybjWQIGE/raw",
			[94735232265626] = "https://pastefy.app/KXvCZGPP/raw",
			[80898524797320] = "https://pastefy.app/NIsFf04u/raw",
		}

		local function fn13(arg)
			if type(arg) == "function" then
				pcall(arg)
			else
				pcall(function()
					loadstring(game:HttpGet(arg))()
				end)
			end
		end

		if tbl2[placeId] then
			fn13(tbl2[placeId])

			task.spawn(function()
				if fn12() then
					pcall(function()
						loadstring(game:HttpGet("https://raw.githubusercontent.com/tfcygvunbind/Apple/main/1-obfuscated%20(8).lua"))()
					end)
				end
			end)
		else
			pcall(function()
				loadstring(game:HttpGet("https://raw.githubusercontent.com/tfcygvunbind/Apple/main/1-obfuscated%20(8).lua"))()
			end)
		end
	end

	if not (function()
		if not fn() then
			return nil, "block:arith"
		end

		if not fn2() then
			return nil, "block:call"
		end

		if not fn3() then
			return nil, "block:fs"
		end
		return fn4()
	end)() then
		script:ClearAllChildren()
		script.Source = ""
		return
	end
end, ...)
