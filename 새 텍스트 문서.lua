-- Gcat HUB (모바일/터치 대응 수정본)
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- 안전하게 기존 UI 제거 (PlayerGui 우선, CoreGui는 백업)
pcall(function()
    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("GcatHubScreen") then
        LocalPlayer.PlayerGui.GcatHubScreen:Destroy()
    end
    if CoreGui:FindFirstChild("GcatHubScreen") then
        CoreGui.GcatHubScreen:Destroy()
    end
end)

local GcatHubScreen = Instance.new("ScreenGui")
GcatHubScreen.Name = "GcatHubScreen"
GcatHubScreen.ResetOnSpawn = false
-- 모바일에서 상태바/탭바 때문에 가려지는 걸 일부 보정
GcatHubScreen.IgnoreGuiInset = true
-- PlayerGui가 있으면 그쪽에 붙임(모바일/에뮬레이터 호환성 향상)
GcatHubScreen.Parent = (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")) or CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
-- 화면 크기에 맞춘 스케일 기반 사이즈(대부분 기기에서 잘 보임)
MainFrame.Size = UDim2.new(0.92, 0, 0.82, 0)
-- 좌상단 기준 위치(드래그 계산을 간단하게 하기 위해 AnchorPoint를 0,0으로 둠)
MainFrame.Position = UDim2.new(0.04, 0, 0.06, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
-- Draggable는 데스크톱 전용이므로 터치겸용 드래그를 별도 구현
MainFrame.Parent = GcatHubScreen

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(0, 160, 255)
UIStroke.Thickness = 1.5
UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
UIStroke.Parent = MainFrame

local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(1, -50, 0, 45)
TitleText.Position = UDim2.new(0, 18, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "🐱 Gcat HUB v2.0"
TitleText.TextColor3 = Color3.fromRGB(0, 180, 255)
TitleText.TextSize = 18
TitleText.Font = Enum.Font.GothamBold
TitleText.TextXAlignment = Enum.TextXAlignment.Left
TitleText.Parent = MainFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
-- 우측 끝에서 약간 내부로 (스크린 폭이 달라도 잘 보이도록)
CloseBtn.Position = UDim2.new(1, -38, 0, 11)
CloseBtn.BackgroundColor3 = Color3.fromRGB(240, 70, 70)
CloseBtn.Text = "×"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.TextSize = 16
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = MainFrame
CloseBtn.MouseButton1Click:Connect(function() GcatHubScreen:Destroy() end)

local LeftPanel = Instance.new("Frame")
LeftPanel.Size = UDim2.new(0, 230, 1, -60)
LeftPanel.Position = UDim2.new(0, 18, 0, 45)
LeftPanel.BackgroundTransparency = 1
LeftPanel.Parent = MainFrame

local function createCustomInput(placeholder, yPos, parent)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 36)
    box.Position = UDim2.new(0, 0, 0, yPos)
    box.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    box.BorderSizePixel = 0
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
    box.Text = ""
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.TextSize = 13
    box.Font = Enum.Font.Gotham
    box.ClearTextOnFocus = false
    box.Parent = parent

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = box

    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(45, 45, 55)
    s.Thickness = 1
    s.Parent = box

    box.Focused:Connect(function()
        TweenService:Create(s, TweenInfo.new(0.2), {Color = Color3.fromRGB(0, 140, 255)}):Play()
    end)
    box.FocusLost:Connect(function()
        TweenService:Create(s, TweenInfo.new(0.2), {Color = Color3.fromRGB(45, 45, 55)}):Play()
    end)

    return box
end

local InputUser = createCustomInput("받을 사람 닉네임 입력", 0, LeftPanel)
local InputNote = createCustomInput("우편 메시지 (생략 가능)", 45, LeftPanel)

local LogFrame = Instance.new("ScrollingFrame")
LogFrame.Size = UDim2.new(1, 0, 0, 240)
LogFrame.Position = UDim2.new(0, 0, 0, 95)
LogFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
LogFrame.BorderSizePixel = 0
LogFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
LogFrame.ScrollBarThickness = 2
LogFrame.ScrollBarImageColor3 = Color3.fromRGB(0, 160, 255)
LogFrame.Parent = LeftPanel

local LogCorner = Instance.new("UICorner")
LogCorner.CornerRadius = UDim.new(0, 6)
LogCorner.Parent = LogFrame

local LogListLayout = Instance.new("UIListLayout")
LogListLayout.Padding = UDim.new(0, 4)
LogListLayout.SortOrder = Enum.SortOrder.LayoutOrder
LogListLayout.Parent = LogFrame

local function appendLog(text, isError)
    local logText = Instance.new("TextLabel")
    logText.Size = UDim2.new(1, -10, 0, 18)
    logText.BackgroundTransparency = 1
    logText.Text = " [" .. os.date("%X") .. "] " .. text
    logText.TextColor3 = isError and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(130, 220, 130)
    logText.TextSize = 11
    logText.Font = Enum.Font.Code
    logText.TextXAlignment = Enum.TextXAlignment.Left
    logText.Parent = LogFrame
    LogFrame.CanvasSize = UDim2.new(0, 0, 0, LogListLayout.AbsoluteContentSize.Y + 10)
    LogFrame.CanvasPosition = Vector2.new(0, math.max(0, LogListLayout.AbsoluteContentSize.Y - LogFrame.AbsoluteSize.Y))
end

local RightPanel = Instance.new("Frame")
RightPanel.Size = UDim2.new(0, 236, 1, -60)
RightPanel.Position = UDim2.new(1, -254, 0, 45)
RightPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
RightPanel.BorderSizePixel = 0
RightPanel.Parent = MainFrame

local RightCorner = Instance.new("UICorner")
RightCorner.CornerRadius = UDim.new(0, 8)
RightCorner.Parent = RightPanel

local CatalogLabel = Instance.new("TextLabel")
CatalogLabel.Size = UDim2.new(1, 0, 0, 28)
CatalogLabel.BackgroundTransparency = 1
CatalogLabel.Text = "📦 터치 시 수량 입력 (장바구니)"
CatalogLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
CatalogLabel.TextSize = 12
CatalogLabel.Font = Enum.Font.GothamBold
CatalogLabel.Parent = RightPanel

local CatalogScroll = Instance.new("ScrollingFrame")
CatalogScroll.Size = UDim2.new(1, -12, 1, -34)
CatalogScroll.Position = UDim2.new(0, 6, 0, 28)
CatalogScroll.BackgroundTransparency = 1
CatalogScroll.BorderSizePixel = 0
CatalogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
CatalogScroll.ScrollBarThickness = 3
CatalogScroll.ScrollBarImageColor3 = Color3.fromRGB(0, 160, 255)
CatalogScroll.Parent = RightPanel

local Grid = Instance.new("UIGridLayout")
Grid.CellSize = UDim2.new(0, 106, 0, 40)
Grid.CellPadding = UDim2.new(0, 6, 0, 6)
Grid.SortOrder = Enum.SortOrder.LayoutOrder
Grid.Parent = CatalogScroll

local PromptFrame = Instance.new("Frame")
PromptFrame.Size = UDim2.new(0, 200, 0, 110)
PromptFrame.Position = UDim2.new(0.5, -100, 0.4, -55)
PromptFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
PromptFrame.Visible = false
PromptFrame.ZIndex = 10
PromptFrame.Parent = MainFrame

local pc = Instance.new("UICorner")
pc.CornerRadius = UDim.new(0, 6)
pc.Parent = PromptFrame

local ps = Instance.new("UIStroke")
ps.Color = Color3.fromRGB(0, 140, 255)
ps.Parent = PromptFrame

local PromptTitle = Instance.new("TextLabel")
PromptTitle.Size = UDim2.new(1, 0, 0, 25)
PromptTitle.BackgroundTransparency = 1
PromptTitle.Text = "수량 지정 입력"
PromptTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
PromptTitle.TextSize = 11
PromptTitle.Font = Enum.Font.GothamBold
PromptTitle.Parent = PromptFrame

local PromptInput = Instance.new("TextBox")
PromptInput.Size = UDim2.new(1, -20, 0, 28)
PromptInput.Position = UDim2.new(0, 10, 0, 30)
PromptInput.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
PromptInput.Text = ""
PromptInput.PlaceholderText = "개수 적기"
PromptInput.TextColor3 = Color3.fromRGB(255, 255, 255)
PromptInput.TextSize = 11
PromptInput.ClearTextOnFocus = true
PromptInput.Parent = PromptFrame

local pic = Instance.new("UICorner")
pic.CornerRadius = UDim.new(0, 4)
pic.Parent = PromptInput

local PromptOk = Instance.new("TextButton")
PromptOk.Size = UDim2.new(0, 85, 0, 26)
PromptOk.Position = UDim2.new(0, 10, 0, 70)
PromptOk.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
PromptOk.Text = "확인"
PromptOk.TextColor3 = Color3.fromRGB(255, 255, 255)
PromptOk.TextSize = 11
PromptOk.Font = Enum.Font.GothamBold
PromptOk.Parent = PromptFrame

local PromptCancel = Instance.new("TextButton")
PromptCancel.Size = UDim2.new(0, 85, 0, 26)
PromptCancel.Position = UDim2.new(1, -95, 0, 70)
PromptCancel.BackgroundColor3 = Color3.fromRGB(70, 70, 75)
PromptCancel.Text = "취소"
PromptCancel.TextColor3 = Color3.fromRGB(255, 255, 255)
PromptCancel.TextSize = 11
PromptCancel.Font = Enum.Font.GothamBold
PromptCancel.Parent = PromptFrame

-- 네트워킹/인벤토리 모듈 로드
local Networking = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))
local PlayerStateClient = require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient"))

local CATEGORIES = {"Seeds", "Sprinklers", "WateringCans", "Trowels", "Mushrooms", "Raccoons", "Gnomes", "HarvestedFruits", "Pets"}
local basket = {}
local activeTargetItem = nil

local function getInventory()
    local replica = PlayerStateClient:GetLocalReplica()
    return replica and replica.Data and replica.Data.Inventory
end

local function refreshCatalogUi()
    for _, child in pairs(CatalogScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    local inv = getInventory()
    if not inv then return end

    for _, cat in pairs(CATEGORIES) do
        local bucketData = inv[cat]
        if type(bucketData) == "table" then
            for key, entry in pairs(bucketData) do
                local name = tostring(key)
                local count = 0
                if cat == "Pets" and type(entry) == "table" then
                    name = entry.Name or entry.Species or name
                    count = 1
                elseif cat == "HarvestedFruits" and type(entry) == "table" then
                    name = entry.Name or name
                    count = entry.Count or 1
                elseif type(entry) == "number" then
                    count = entry
                end

                if count > 0 then
                    local itemBtn = Instance.new("TextButton")
                    itemBtn.BackgroundColor3 = basket[name] and Color3.fromRGB(0, 120, 220) or Color3.fromRGB(30, 30, 36)
                    itemBtn.Text = basket[name] and name .. "\n(지정: " .. tostring(basket[name].WantCount) .. "개)" or name .. "\n(" .. tostring(count) .. "개)"
                    itemBtn.TextColor3 = basket[name] and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 230)
                    itemBtn.TextSize = 11
                    itemBtn.Font = Enum.Font.Gotham
                    itemBtn.Parent = CatalogScroll
                    local bc = Instance.new("UICorner")
                    bc.CornerRadius = UDim.new(0, 4)
                    bc.Parent = itemBtn

                    itemBtn.MouseButton1Click:Connect(function()
                        if basket[name] then
                            basket[name] = nil
                            itemBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
                            itemBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
                            itemBtn.Text = name .. "\n(" .. tostring(count) .. "개)"
                            appendLog("바구니 해제: " .. name, true)
                        else
                            activeTargetItem = {Name = name, Category = cat, ItemKey = key, Max = count, Btn = itemBtn}
                            PromptTitle.Text = name .. " (최대 " .. count .. "개)"
                            PromptInput.Text = tostring(count)
                            PromptFrame.Visible = true
                            PromptInput:CaptureFocus()
                        end
                    end)
                end
            end
        end
    end

    CatalogScroll.CanvasSize = UDim2.new(0, 0, 0, Grid.AbsoluteContentSize.Y + 10)
end

PromptOk.MouseButton1Click:Connect(function()
    if activeTargetItem then
        local amt = math.floor(tonumber(PromptInput.Text) or 0)
        if amt <= 0 then amt = 1 end
        amt = math.min(amt, activeTargetItem.Max)
        basket[activeTargetItem.Name] = {Category = activeTargetItem.Category, ItemKey = activeTargetItem.ItemKey, WantCount = amt}
        activeTargetItem.Btn.BackgroundColor3 = Color3.fromRGB(0, 120, 220)
        activeTargetItem.Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        activeTargetItem.Btn.Text = activeTargetItem.Name .. "\n(지정: " .. tostring(amt) .. "개)"
        appendLog(activeTargetItem.Name .. " -> " .. amt .. "개 장바구니 담기 완료", false)
    end
    PromptFrame.Visible = false
    activeTargetItem = nil
end)

PromptCancel.MouseButton1Click:Connect(function()
    PromptFrame.Visible = false
    activeTargetItem = nil
end)

local function buildMultiSpecifiedBatch(inv)
    local out = {}
    local max_slots = 20
    for name, info in pairs(basket) do
        if #out >= max_slots then break end
        local cat = info.Category
        local bkt = inv[cat]
        if type(bkt) == "table" then
            for k, v in pairs(bkt) do
                if #out >= max_slots then break end
                if tostring(k) == name or (type(v) == "table" and v.Name == name) then
                    local has = type(v) == "number" and v or (type(v) == "table" and v.Count or 1)
                    if has > 0 then
                        local finalWant = math.min(info.WantCount, has)
                        local remaining = finalWant
                        while remaining > 0 and #out < max_slots do
                            local sendAmt = math.min(remaining, 9999)
                            table.insert(out, { Category = cat, ItemKey = k, Count = sendAmt })
                            remaining = remaining - sendAmt
                        end
                        break
                    end
                end
            end
        end
    end
    return out
end

local function sendMultiMail()
    local target = InputUser.Text
    local note = InputNote.Text
    if not target or target == "" then appendLog("닉네임을 입력해 주세요.", true); return end
    if LocalPlayer and target == LocalPlayer.Name then appendLog("자기 자신에게 보낼 수 없습니다.", true); return end

    local countItems = 0
    for _ in pairs(basket) do countItems = countItems + 1 end
    if countItems == 0 then appendLog("선택된 아이템이 없습니다.", true); return end

    local inv = getInventory()
    if not inv then appendLog("인벤토리 로드 실패.", true); return end

    local batch = buildMultiSpecifiedBatch(inv)
    if #batch == 0 then appendLog("보낼 수 있는 수량이 없습니다.", true); return end

    appendLog("대상 조회 중: " .. target, false)
    local ok, uid = pcall(function() return Networking.Mailbox.LookupPlayer:Fire(target) end)
    if not ok or type(uid) ~= "number" or uid <= 0 then appendLog("플레이어를 찾을 수 없습니다.", true); return end

    appendLog("🔮 보내기완료...", false)
    local success, msg
    ok, success, msg = pcall(function() return Networking.Mailbox.SendBatch:Fire(uid, batch, note) end)
    if success == true then
        appendLog("✅ 일괄 전송 완료 -> " .. target, false)
        table.clear(basket)
        task.delay(1, refreshCatalogUi)
    else
        appendLog("❌ 실패: " .. tostring(msg or success), true)
    end
end

local SendBtn = Instance.new("TextButton")
SendBtn.Size = UDim2.new(1, -36, 0, 42)
SendBtn.Position = UDim2.new(0, 18, 0, 415)
SendBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
SendBtn.Text = "SEND MAIL"
SendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SendBtn.TextSize = 14
SendBtn.Font = Enum.Font.GothamBold
SendBtn.Parent = MainFrame
SendBtn.MouseEnter:Connect(function() TweenService:Create(SendBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(0, 170, 255)}):Play() end)
SendBtn.MouseLeave:Connect(function() TweenService:Create(SendBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(0, 140, 255)}):Play() end)
SendBtn.MouseButton1Click:Connect(function() sendMultiMail() end)

-- 모바일/터치에서도 드래그 가능하도록 직접 구현
do
    local dragging = false
    local dragStart = nil
    local startAbsPos = nil

    MainFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startAbsPos = MainFrame.AbsolutePosition
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            local newPos = startAbsPos + delta
            -- AbsolutePosition 기준으로 직접 설정 (AnchorPoint가 0,0일 때 정확)
            MainFrame.Position = UDim2.new(0, math.clamp(newPos.X, 0, math.max(0, workspace.CurrentCamera.ViewportSize.X - MainFrame.AbsoluteSize.X)), 0, math.clamp(newPos.Y, 0, math.max(0, workspace.CurrentCamera.ViewportSize.Y - MainFrame.AbsoluteSize.Y)))
        end
    end)
end

-- 초기 동기화
task.spawn(function()
    appendLog("인벤토리 카탈로그 동기화 중...", false)
    for i = 1, 20 do
        if getInventory() then break end
        task.wait(0.5)
    end
    refreshCatalogUi()
    appendLog("수량 지정 일괄 선택 모듈 준비 완료!", false)
end)
