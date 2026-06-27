pcall(function()
    local c = game:GetService("CoreGui")
    local p = game:GetService("Players").LocalPlayer.PlayerGui
    if c:FindFirstChild("GCAT_Inf") then c.GCAT_Inf:Destroy() end
    if p:FindFirstChild("GCAT_Inf") then p.GCAT_Inf:Destroy() end
end)
task.wait(0.1)

local Net = require(game:GetService("ReplicatedStorage"):WaitForChild("SharedModules"):WaitForChild("Networking"))
local PS = require(game:GetService("ReplicatedStorage"):WaitForChild("ClientModules"):WaitForChild("PlayerStateClient"))
local MailboxConfig = { SavedUsers = {} }

local function getInv()
    local ok, r = pcall(function() return PS:WaitForLocalReplica(5) end)
    return ok and r and r.Data and type(r.Data.Inventory) == "table" and r.Data.Inventory
end

local function buildBatch(inv, name, amt)
    local out, max = {}, 20
    local want = math.max(1, math.floor(tonumber(amt) or 1))
    local search = tostring(name):lower()

    for cat, tbl in pairs(inv) do
        if want <= 0 or #out >= max then break end
        if type(tbl) == "table" then
            for iKey, iData in pairs(tbl) do
                if want <= 0 or #out >= max then break end
                if type(iData) == "table" and iData.Name and string.find(tostring(iData.Name):lower(), search) then
                    local c = tonumber(iData.Count or iData.Amount or 1) or 1
                    local s = math.min(want, c)
                    table.insert(out, { Category = cat, ItemKey = iKey, Count = s })
                    want = want - s
                elseif type(iData) == "number" and string.find(tostring(iKey):lower(), search) and iData > 0 then
                    local s = math.min(want, iData)
                    table.insert(out, { Category = cat, ItemKey = iKey, Count = s })
                    want = want - s
                end
            end
        end
    end
    return out
end

local isSending = false
local function doMailShot(statusLabel, userBox, itemBox, amountBox)
    if isSending then return end
    isSending = true
    
    local tUser = tostring(userBox.Text):gsub("^%s*(.-)%s*$", "%1")
    local tItem = tostring(itemBox.Text):gsub("^%s*(.-)%s*$", "%1")
    local tAmt = tonumber(amountBox.Text) or 0
    
    if tUser == "" or tItem == "" or tAmt <= 0 then
        statusLabel.Text = "상태: 입력창 확인"
        statusLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
        isSending = false; return
    end

    local inv = getInv()
    if not inv then statusLabel.Text = "상태: 로드 실패"; isSending = false; return end
    
    local batch = buildBatch(inv, tItem, tAmt)
    if #batch == 0 then 
        statusLabel.Text = "상태: 아이템 없음"
        statusLabel.TextColor3 = Color3.fromRGB(255, 180, 50)
        isSending = false; return
    end
    
    statusLabel.Text = "상태: 유저 조회 중..."
    local ok, uid = pcall(function() return Net.Mailbox.LookupPlayer:Fire(tUser) end)
    if not ok or type(uid) ~= "number" or uid <= 0 then 
        statusLabel.Text = "상태: 조회 실패"
        statusLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
        isSending = false; return
    end
    
    statusLabel.Text = "상태: 우편 발송 중..."
    local success, msg = nil, nil
    ok, success, msg = pcall(function() return Net.Mailbox.SendBatch:Fire(uid, batch, "") end)
    
    if success == true then
        statusLabel.Text = "상태: 실제 발송 성공! 🌟"
        statusLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
    else
        statusLabel.Text = "상태: 서버 실패 (" .. tostring(msg or "쿨타임") .. ")"
        statusLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
    end
    isSending = false
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GCAT_Inf"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 340, 0, 225)
MainFrame.Position = UDim2.new(0.5, -170, 0.4, -112)
MainFrame.BackgroundColor3 = Color3.fromRGB(13, 14, 18)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 4)
TopBar.BackgroundColor3 = Color3.fromRGB(0, 225, 255)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 35)
Title.Position = UDim2.new(0, 0, 0, 4)
Title.BackgroundTransparency = 1
Title.Text = "✉️  G C A T  H U B  [PRO]"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 13
Title.Font = Enum.Font.SourceSansBold
Title.Parent = MainFrame

local function makeModernBox(placeholder, y)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -30, 0, 32)
    box.Position = UDim2.new(0, 15, 0, y)
    box.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
    box.BorderSizePixel = 0
    box.Text = ""
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = Color3.fromRGB(90, 95, 110)
    box.TextSize = 13
    box.Font = Enum.Font.SourceSans
    box.ClearTextOnFocus = false
    box.Parent = MainFrame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = box
    return box
end

local UserBox = makeModernBox("👤 받는 사람 닉네임", 40)
local ItemBox = makeModernBox("📦 보낼 아이템 이름", 77)
local AmountBox = makeModernBox("🔢 보낼 개수 (숫자)", 114)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -30, 0, 22)
StatusLabel.Position = UDim2.new(0, 15, 0, 152)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "상태: 유료 핵심 커널 주입 완료"
StatusLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
StatusLabel.TextSize = 12
StatusLabel.Font = Enum.Font.SourceSansBold
StatusLabel.Parent = MainFrame

local ActionBtn = Instance.new("TextButton")
ActionBtn.Size = UDim2.new(1, -30, 0, 36)
ActionBtn.Position = UDim2.new(0, 15, 0, 178)
ActionBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
ActionBtn.Text = "🚀 우편 1회 보내기"
ActionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ActionBtn.TextSize = 14
ActionBtn.Font = Enum.Font.SourceSansBold
ActionBtn.Parent = MainFrame
local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(0, 6)
BtnCorner.Parent = ActionBtn

ActionBtn.MouseButton1Click:Connect(function()
    task.spawn(function() doMailShot(StatusLabel, UserBox, ItemBox, AmountBox) end)
end)
