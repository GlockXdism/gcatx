getgenv().MailboxConfig = {
    MAIL_USERNAME = { "" },
    MAIL_ITEM_NAME = { 
        [""] = 0,
    },
    MAIL_NOTE = "",
    SEND_INTERVAL = 600,
    AUTO_SEND = false,
}

local C = getgenv().MailboxConfig or {}
local RS = game:GetService("ReplicatedStorage")
local Net = require(RS:WaitForChild("SharedModules"):WaitForChild("Networking"))
local PS = require(RS:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient"))
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

local STACK = {
    Sprinklers = 1, WateringCans = 1, Mushrooms = 1, Gnomes = 1, Raccoons = 1, Crates = 1,
    SeedPacks = 1, Trowels = 1, Props = 1, Seeds = 1, HarvestedFruits = 1, Flashbangs = 1, EmptyPots = 1,
}

local GUI_STATE = {
    isVisible = true,
    autoSendActive = false,
    statusMessage = "준비됨",
}

local function getInv()
    local ok, r = pcall(function() return PS:WaitForLocalReplica(5) end)
    return ok and r and r.Data and type(r.Data.Inventory) == "table" and r.Data.Inventory
end

local function buildBatch(inv, items)
    local out, max = {}, 20
    for name, amt in items do
        if #out >= max then break end
        local want = math.max(1, math.floor(tonumber(amt) or 1))
        if type(inv.Pets) == "table" then
            for key, p in inv.Pets do
                if want <= 0 or #out >= max then break end
                if type(p) == "table" and p.Id and not p.Equipped and tostring(p.Name) == name then
                    out[#out + 1] = { Category = "Pets", ItemKey = key, Count = 1 }
                    want -= 1
                end
            end
        end
        if want > 0 then
            for cat in STACK do
                local t = inv[cat]
                if type(t) == "table" and type(t[name]) == "number" and t[name] > 0 then
                    out[#out + 1] = { Category = cat, ItemKey = name, Count = math.min(want, t[name]) }
                    break
                end
            end
        end
    end
    return out
end

getgenv().mailboxSendOnce = function()
    local users, items = C.MAIL_USERNAME or {}, C.MAIL_ITEM_NAME or {}
    if #users == 0 or not next(items) then 
        GUI_STATE.statusMessage = "❌ 설정 오류"
        return warn("[Mailbox] empty config") 
    end
    local inv = getInv()
    if not inv then 
        GUI_STATE.statusMessage = "❌ 인벤토리 오류"
        return warn("[Mailbox] no inventory") 
    end
    local batch = buildBatch(inv, items)
    if #batch == 0 then 
        GUI_STATE.statusMessage = "❌ 보낼 아이템 없음"
        return warn("[Mailbox] nothing to send") 
    end
    local target = tostring(users[math.random(#users)])
    local ok, uid, err = pcall(function() return Net.Mailbox.LookupPlayer:Fire(target) end)
    if not ok or type(uid) ~= "number" or uid <= 0 then 
        GUI_STATE.statusMessage = "❌ 플레이어 찾기 실패"
        return warn("[Mailbox] lookup:", err) 
    end
    ok = pcall(function()
        Net.Mailbox.SendBatch:Fire(uid, batch, C.MAIL_NOTE or "")
    end)
    
    if ok then
        GUI_STATE.statusMessage = "✅ 전송 완료: " .. target
        print("[Mailbox] sent to " .. target)
        return true
    else
        GUI_STATE.statusMessage = "❌ 전송 실패"
        print("[Mailbox] send failed")
        return false
    end
end

local function createGUI()
    local player = Players.LocalPlayer
    if not player then
        warn("[Mailbox] No local player found")
        return
    end
    
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- 기존 GUI 제거
    local existingGui = playerGui:FindFirstChild("MailboxGUI")
    if existingGui then
        existingGui:Destroy()
    end
    
    -- 메인 화면
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MailboxGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Enabled = true
    screenGui.Parent = playerGui
    
    -- 메인 컨테이너
    local mainContainer = Instance.new("Frame")
    mainContainer.Name = "MainContainer"
    mainContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    mainContainer.BorderSizePixel = 0
    mainContainer.Size = UDim2.new(0, 300, 0, 450)
    mainContainer.Position = UDim2.new(1, -20, 0.5, -225)
    mainContainer.Parent = screenGui
    
    -- 코너 효과
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 15)
    corner.Parent = mainContainer
    
    -- 그림자 효과
    local shadow = Instance.new("UIStroke")
    shadow.Color = Color3.fromRGB(0, 150, 255)
    shadow.Thickness = 2
    shadow.Parent = mainContainer
    
    -- 헤더
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1, 0, 0, 50)
    header.Parent = mainContainer
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 15)
    headerCorner.Parent = header
    
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Text = "📬 메일박스"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 20
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -40, 1, 0)
    title.Position = UDim2.new(0, 15, 0, 0)
    title.Parent = header
    
    -- 닫기 버튼
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseBtn"
    closeBtn.Text = "✕"
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 18
    closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
    closeBtn.BackgroundTransparency = 0.7
    closeBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    closeBtn.BorderSizePixel = 0
    closeBtn.Size = UDim2.new(0, 35, 0, 35)
    closeBtn.Position = UDim2.new(1, -40, 0, 7)
    closeBtn.Parent = header
    
    local closeBtnCorner = Instance.new("UICorner")
    closeBtnCorner.CornerRadius = UDim.new(0, 8)
    closeBtnCorner.Parent = closeBtn
    
    closeBtn.MouseButton1Click:Connect(function()
        GUI_STATE.isVisible = false
        mainContainer:TweenSize(UDim2.new(0, 0, 0, 450), "Out", "Quad", 0.3, true)
        task.wait(0.3)
        mainContainer.Visible = false
    end)
    
    -- 상태 메시지
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Text = GUI_STATE.statusMessage
    statusLabel.Font = Enum.Font.GothamSemibold
    statusLabel.TextSize = 13
    statusLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
    statusLabel.BackgroundColor3 = Color3.fromRGB(30, 40, 50)
    statusLabel.BorderSizePixel = 0
    statusLabel.TextScaled = false
    statusLabel.TextWrapped = true
    statusLabel.Size = UDim2.new(1, -20, 0, 35)
    statusLabel.Position = UDim2.new(0, 10, 0, 60)
    statusLabel.Parent = mainContainer
    
    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0, 10)
    statusCorner.Parent = statusLabel
    
    -- 컨텐츠 스크롤
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "ScrollFrame"
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.Size = UDim2.new(1, -20, 0, 270)
    scrollFrame.Position = UDim2.new(0, 10, 0, 105)
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.ScrollBarThickness = 6
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(0, 150, 255)
    scrollFrame.Parent = mainContainer
    
    -- 설정 섹션
    local configLabel = Instance.new("TextLabel")
    configLabel.Name = "ConfigLabel"
    configLabel.Text = "⚙️ 설정"
    configLabel.Font = Enum.Font.GothamBold
    configLabel.TextSize = 14
    configLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    configLabel.BackgroundTransparency = 1
    configLabel.TextXAlignment = Enum.TextXAlignment.Left
    configLabel.Size = UDim2.new(1, -20, 0, 25)
    configLabel.Position = UDim2.new(0, 10, 0, 0)
    configLabel.Parent = scrollFrame
    
    -- 받는 사람 입력
    local usernameLabel = Instance.new("TextLabel")
    usernameLabel.Name = "UsernameLabel"
    usernameLabel.Text = "받는 사람:"
    usernameLabel.Font = Enum.Font.GothamSemibold
    usernameLabel.TextSize = 12
    usernameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    usernameLabel.BackgroundTransparency = 1
    usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
    usernameLabel.Size = UDim2.new(1, -20, 0, 20)
    usernameLabel.Position = UDim2.new(0, 10, 0, 30)
    usernameLabel.Parent = scrollFrame
    
    local usernameInput = Instance.new("TextBox")
    usernameInput.Name = "UsernameInput"
    usernameInput.Text = C.MAIL_USERNAME and C.MAIL_USERNAME[1] or ""
    usernameInput.Font = Enum.Font.Gotham
    usernameInput.TextSize = 12
    usernameInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    usernameInput.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
    usernameInput.PlaceholderText = "플레이어명 입력"
    usernameInput.BackgroundColor3 = Color3.fromRGB(40, 50, 60)
    usernameInput.BorderSizePixel = 0
    usernameInput.Size = UDim2.new(1, -20, 0, 30)
    usernameInput.Position = UDim2.new(0, 10, 0, 50)
    usernameInput.Parent = scrollFrame
    
    local usernameCorner = Instance.new("UICorner")
    usernameCorner.CornerRadius = UDim.new(0, 8)
    usernameCorner.Parent = usernameInput
    
    -- 메모
    local noteLabel = Instance.new("TextLabel")
    noteLabel.Name = "NoteLabel"
    noteLabel.Text = "메모:"
    noteLabel.Font = Enum.Font.GothamSemibold
    noteLabel.TextSize = 12
    noteLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    noteLabel.BackgroundTransparency = 1
    noteLabel.TextXAlignment = Enum.TextXAlignment.Left
    noteLabel.Size = UDim2.new(1, -20, 0, 20)
    noteLabel.Position = UDim2.new(0, 10, 0, 90)
    noteLabel.Parent = scrollFrame
    
    local noteInput = Instance.new("TextBox")
    noteInput.Name = "NoteInput"
    noteInput.Text = C.MAIL_NOTE or ""
    noteInput.Font = Enum.Font.Gotham
    noteInput.TextSize = 12
    noteInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    noteInput.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
    noteInput.PlaceholderText = "전송 메모 입력"
    noteInput.BackgroundColor3 = Color3.fromRGB(40, 50, 60)
    noteInput.BorderSizePixel = 0
    noteInput.Size = UDim2.new(1, -20, 0, 50)
    noteInput.Position = UDim2.new(0, 10, 0, 110)
    noteInput.TextWrapped = true
    noteInput.TextYAlignment = Enum.TextYAlignment.Top
    noteInput.Parent = scrollFrame
    
    local noteCorner = Instance.new("UICorner")
    noteCorner.CornerRadius = UDim.new(0, 8)
    noteCorner.Parent = noteInput
    
    -- 아이템 섹션
    local itemLabel = Instance.new("TextLabel")
    itemLabel.Name = "ItemLabel"
    itemLabel.Text = "📦 보낼 아이템"
    itemLabel.Font = Enum.Font.GothamBold
    itemLabel.TextSize = 14
    itemLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    itemLabel.BackgroundTransparency = 1
    itemLabel.TextXAlignment = Enum.TextXAlignment.Left
    itemLabel.Size = UDim2.new(1, -20, 0, 25)
    itemLabel.Position = UDim2.new(0, 10, 0, 170)
    itemLabel.Parent = scrollFrame
    
    -- 아이템 입력 (간단 버전)
    local itemCountLabel = Instance.new("TextLabel")
    itemCountLabel.Name = "ItemCountLabel"
    itemCountLabel.Text = "Super Watering Can: 2000"
    itemCountLabel.Font = Enum.Font.Gotham
    itemCountLabel.TextSize = 11
    itemCountLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
    itemCountLabel.BackgroundColor3 = Color3.fromRGB(40, 50, 60)
    itemCountLabel.BorderSizePixel = 0
    itemCountLabel.Size = UDim2.new(1, -20, 0, 30)
    itemCountLabel.Position = UDim2.new(0, 10, 0, 200)
    itemCountLabel.Parent = scrollFrame
    
    local itemCountCorner = Instance.new("UICorner")
    itemCountCorner.CornerRadius = UDim.new(0, 8)
    itemCountCorner.Parent = itemCountLabel
    
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 260)
    
    -- 하단 버튼들
    local buttonContainer = Instance.new("Frame")
    buttonContainer.Name = "ButtonContainer"
    buttonContainer.BackgroundTransparency = 1
    buttonContainer.BorderSizePixel = 0
    buttonContainer.Size = UDim2.new(1, -20, 0, 80)
    buttonContainer.Position = UDim2.new(0, 10, 1, -90)
    buttonContainer.Parent = mainContainer
    
    -- 한 번 전송 버튼
    local sendBtn = Instance.new("TextButton")
    sendBtn.Name = "SendBtn"
    sendBtn.Text = "🚀 지금 전송"
    sendBtn.Font = Enum.Font.GothamBold
    sendBtn.TextSize = 14
    sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    sendBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 100)
    sendBtn.BorderSizePixel = 0
    sendBtn.Size = UDim2.new(0.5, -5, 0, 35)
    sendBtn.Position = UDim2.new(0, 0, 0, 0)
    sendBtn.Parent = buttonContainer
    
    local sendBtnCorner = Instance.new("UICorner")
    sendBtnCorner.CornerRadius = UDim.new(0, 10)
    sendBtnCorner.Parent = sendBtn
    
    sendBtn.MouseButton1Click:Connect(function()
        GUI_STATE.statusMessage = "⏳ 전송 중..."
        if statusLabel and statusLabel.Parent then
            statusLabel.Text = GUI_STATE.statusMessage
        end
        
        -- 설정 업데이트
        if usernameInput.Text ~= "" then
            C.MAIL_USERNAME = { usernameInput.Text }
        end
        C.MAIL_NOTE = noteInput.Text
        
        task.spawn(function()
            pcall(getgenv().mailboxSendOnce)
            task.wait(1)
            if statusLabel and statusLabel.Parent then
                statusLabel.Text = GUI_STATE.statusMessage
            end
        end)
    end)
    
    -- 자동 전송 토글
    local autoBtn = Instance.new("TextButton")
    autoBtn.Name = "AutoBtn"
    autoBtn.Text = GUI_STATE.autoSendActive and "⏹️ 자동중" or "▶️ 자동전송"
    autoBtn.Font = Enum.Font.GothamBold
    autoBtn.TextSize = 14
    autoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    autoBtn.BackgroundColor3 = GUI_STATE.autoSendActive and Color3.fromRGB(150, 100, 0) or Color3.fromRGB(100, 100, 150)
    autoBtn.BorderSizePixel = 0
    autoBtn.Size = UDim2.new(0.5, -5, 0, 35)
    autoBtn.Position = UDim2.new(0.5, 5, 0, 0)
    autoBtn.Parent = buttonContainer
    
    local autoBtnCorner = Instance.new("UICorner")
    autoBtnCorner.CornerRadius = UDim.new(0, 10)
    autoBtnCorner.Parent = autoBtn
    
    autoBtn.MouseButton1Click:Connect(function()
        GUI_STATE.autoSendActive = not GUI_STATE.autoSendActive
        C.AUTO_SEND = GUI_STATE.autoSendActive
        autoBtn.Text = GUI_STATE.autoSendActive and "⏹️ 자동중" or "▶️ 자동전송"
        autoBtn.BackgroundColor3 = GUI_STATE.autoSendActive and Color3.fromRGB(150, 100, 0) or Color3.fromRGB(100, 100, 150)
        
        -- 설정 업데이트
        if usernameInput.Text ~= "" then
            C.MAIL_USERNAME = { usernameInput.Text }
        end
        C.MAIL_NOTE = noteInput.Text
        
        if GUI_STATE.autoSendActive then
            GUI_STATE.statusMessage = "✅ 자동 전송 시작"
            if statusLabel and statusLabel.Parent then
                statusLabel.Text = GUI_STATE.statusMessage
            end
            task.spawn(function()
                while GUI_STATE.autoSendActive and mainContainer.Parent do
                    pcall(getgenv().mailboxSendOnce)
                    task.wait(tonumber(C.SEND_INTERVAL) or 10)
                end
            end)
        else
            GUI_STATE.statusMessage = "⏹️ 자동 전송 중지"
            if statusLabel and statusLabel.Parent then
                statusLabel.Text = GUI_STATE.statusMessage
            end
        end
    end)
    
    -- 열기/닫기 버튼 (우측 하단)
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "ToggleBtn"
    toggleBtn.Text = "📬"
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 24
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Size = UDim2.new(0, 50, 0, 50)
    toggleBtn.Position = UDim2.new(1, -70, 1, -70)
    toggleBtn.Parent = screenGui
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 12)
    toggleCorner.Parent = toggleBtn
    
    toggleBtn.MouseButton1Click:Connect(function()
        if GUI_STATE.isVisible then
            GUI_STATE.isVisible = false
            mainContainer:TweenSize(UDim2.new(0, 0, 0, 450), "Out", "Quad", 0.3, true)
            task.wait(0.3)
            mainContainer.Visible = false
        else
            GUI_STATE.isVisible = true
            mainContainer.Visible = true
            mainContainer:TweenSize(UDim2.new(0, 300, 0, 450), "Out", "Quad", 0.3, true)
        end
    end)
    
    -- 키보드 단축키
    UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.M then
            if GUI_STATE.isVisible then
                GUI_STATE.isVisible = false
                if mainContainer and mainContainer.Parent then
                    mainContainer:TweenSize(UDim2.new(0, 0, 0, 450), "Out", "Quad", 0.3, true)
                    task.wait(0.3)
                    mainContainer.Visible = false
                end
            else
                GUI_STATE.isVisible = true
                if mainContainer and mainContainer.Parent then
                    mainContainer.Visible = true
                    mainContainer:TweenSize(UDim2.new(0, 300, 0, 450), "Out", "Quad", 0.3, true)
                end
            end
        end
    end)
    
    -- 상태 업데이트 루프
    task.spawn(function()
        while mainContainer and mainContainer.Parent do
            task.wait(0.5)
            if statusLabel and statusLabel.Parent then
                statusLabel.Text = GUI_STATE.statusMessage
            end
        end
    end)
    
    print("[Mailbox GUI] 로드 완료! M키로 열고 닫을 수 있습니다.")
end

-- GUI 생성
local guiSuccess = pcall(createGUI)
if not guiSuccess then
    warn("[Mailbox] GUI 생성 실패")
end

-- 자동 전송 초기화
if C.AUTO_SEND ~= false then
    GUI_STATE.autoSendActive = true
    task.spawn(function()
        while true do
            pcall(getgenv().mailboxSendOnce)
            task.wait(tonumber(C.SEND_INTERVAL) or 10)
        end
    end)
end
