local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local LOG = "[MailTool]"

local CATEGORIES = {
	"Seeds",
	"Sprinklers",
	"WateringCans",
	"Trowels",
	"Mushrooms",
	"Raccoons",
	"Gnomes",
	"HarvestedFruits",
	"Pets",
}

-- Per-unit categories: every unit occupies one mail line (mirrors the delivery bot).
local LINE_EXPANDED = { Pets = true, HarvestedFruits = true }

local DEFAULT_CFG = {
	recipient = "",
	category = "Pets", -- any category from CATEGORIES table
	itemKey = "Raccoon", -- any item key from the category like "Raccoon" or "Trowel" or "Dragon's Breath" etc.
	count = 1,
	note = "GAG2 mail tool",
	autoSend = false, -- place true if you wanna to send mails via cfg, if false then do it with UI
	showUi = true,
	toggleUiKey = "RightControl",
	maxMailLines = 20,
	sendCooldownSec = 11,
}

local function log(...)
	print(LOG, ...)
end

local function warnLog(...)
	warn(LOG, ...)
end

local function shallowMerge(into, from)
	if typeof(from) ~= "table" then
		return into
	end
	for k, v in pairs(from) do
		into[k] = v
	end
	return into
end

local function loadCfg()
	local cfg = table.clone(DEFAULT_CFG)
	if typeof(_G.GAG2_MAIL_CFG) == "table" then
		shallowMerge(cfg, _G.GAG2_MAIL_CFG)
	end
	if typeof(readfile) == "function" and typeof(isfile) == "function" then
		local paths = { "config/mail-tool.json", "mail-tool.json" }
		for _, path in paths do
			if isfile(path) then
				local ok, decoded = pcall(function()
					return HttpService:JSONDecode(readfile(path))
				end)
				if ok and typeof(decoded) == "table" then
					shallowMerge(cfg, decoded)
					log("config loaded from", path)
					break
				else
					warnLog("failed to parse", path)
				end
			end
		end
	end
	cfg.count = math.max(1, math.floor(tonumber(cfg.count) or 1))
	cfg.maxMailLines = math.clamp(math.floor(tonumber(cfg.maxMailLines) or 20), 1, 100)
	cfg.sendCooldownSec = math.max(0, tonumber(cfg.sendCooldownSec) or 11)
	return cfg
end

local CFG = loadCfg()

local Networking = require(ReplicatedStorage:WaitForChild("SharedModules", 120):WaitForChild("Networking"))
local PlayerStateClient = require(ReplicatedStorage:WaitForChild("ClientModules", 120):WaitForChild("PlayerStateClient"))

local MailboxItemCatalog: any = nil
pcall(function()
	local controllers = LocalPlayer:WaitForChild("PlayerScripts", 15):WaitForChild("Controllers", 15)
	MailboxItemCatalog = require(controllers:WaitForChild("MailboxController"):WaitForChild("MailboxItemCatalog"))
end)

-- =============================================================================
-- Inventory
-- =============================================================================

local function getReplica()
	return PlayerStateClient:GetLocalReplica()
end

local function getInventory()
	local replica = getReplica()
	return replica and replica.Data and replica.Data.Inventory
end

local function waitReplica(timeout: number?)
	local limit = timeout or 45
	local started = os.clock()
	while os.clock() - started < limit do
		if getReplica() then
			return true
		end
		task.wait(0.25)
	end
	return false
end

-- Entry can be a plain number (stackables) or a table with .Count (HarvestedFruits).
local function getStackCount(category: string, itemKey: string): number
	local inv = getInventory()
	local bucket = inv and inv[category]
	if typeof(bucket) ~= "table" then
		return 0
	end
	local entry = bucket[itemKey]
	if typeof(entry) == "number" then
		return entry
	end
	if typeof(entry) == "table" and typeof(entry.Count) == "number" then
		return entry.Count
	end
	if entry ~= nil then
		return 1
	end
	return 0
end

local function normalizePetKey(value: string): string
	return (string.gsub(string.lower(value), "[%s%p]", ""))
end

local function readPetFields(data: any): (string?, boolean)
	if typeof(data) ~= "table" then
		return nil, false
	end
	local species = data.Name or data.name or data.Species or data.species or data.PetName or data.petName
	local equipped = data.Equipped == true
	if typeof(species) ~= "string" or species == "" then
		return nil, equipped
	end
	return species, equipped
end

-- Unequipped pet uuids matching the species (case/space-insensitive).
local function matchPets(species: string): { string }
	local inv = getInventory()
	local bucket = inv and inv.Pets
	if typeof(bucket) ~= "table" then
		return {}
	end
	local want = normalizePetKey(species)
	local matched: { string } = {}
	for uuid, data in bucket do
		local sp, equipped = readPetFields(data)
		if sp and normalizePetKey(sp) == want and not equipped then
			table.insert(matched, tostring(uuid))
		end
	end
	return matched
end

local function keyVariants(category: string, itemKey: string): { string }
	local variants = { itemKey }
	if category == "Seeds" then
		table.insert(variants, itemKey .. " Seed")
		table.insert(variants, (string.gsub(itemKey, " Seed$", "")))
	end
	return variants
end

-- Real inventory key for a stackable/per-unit (non-pet) item:
-- MailboxItemCatalog first, then key variants, then a case-insensitive bucket scan.
local function resolveStackKey(category: string, itemKey: string): string?
	if MailboxItemCatalog then
		local inv = getInventory()
		local entryValue = inv and inv[category] and inv[category][itemKey]
		local ok, catalogKey = pcall(MailboxItemCatalog.Resolve, category, itemKey, entryValue)
		if ok and typeof(catalogKey) == "string" and getStackCount(category, catalogKey) > 0 then
			return catalogKey
		end
	end
	local variants = keyVariants(category, itemKey)
	for _, key in variants do
		if getStackCount(category, key) > 0 then
			return key
		end
	end
	local inv = getInventory()
	local bucket = inv and inv[category]
	if typeof(bucket) == "table" then
		for key in bucket do
			for _, variant in variants do
				if string.lower(tostring(key)) == string.lower(variant) then
					return tostring(key)
				end
			end
		end
	end
	return nil
end

local function getAvailableCount(category: string, itemKey: string): number
	if category == "Pets" then
		return #matchPets(itemKey)
	end
	local key = resolveStackKey(category, itemKey)
	if not key then
		return 0
	end
	return getStackCount(category, key)
end

-- InventoryItem: { itemKey, displayName, count, iconId? }

local function resolveDisplayName(category: string, itemKey: string, entryValue: any): string
	if MailboxItemCatalog then
		local ok, resolved = pcall(MailboxItemCatalog.Resolve, category, itemKey, entryValue)
		if ok and typeof(resolved) == "string" and resolved ~= "" then
			return resolved
		end
	end
	return itemKey
end

local function listCategoryItems(category: string): { any }
	local inv = getInventory()
	local bucket = inv and inv[category]
	local items: { any } = {}
	if typeof(bucket) ~= "table" then
		return items
	end

	if category == "Pets" then
		local groups: { [string]: number } = {}
		for _, data in bucket do
			local species, equipped = readPetFields(data)
			if species and not equipped then
				groups[species] = (groups[species] or 0) + 1
			end
		end
		for species, count in groups do
			table.insert(items, {
				itemKey = species,
				displayName = species,
				count = count,
			})
		end
	elseif category == "HarvestedFruits" then
		for key, data in bucket do
			local count = 1
			local displayName = tostring(key)
			if typeof(data) == "table" then
				if typeof(data.Count) == "number" then
					count = data.Count
				end
				displayName = tostring(data.Name or data.FruitName or data.Species or data.DisplayName or key)
			end
			if count > 0 then
				table.insert(items, {
					itemKey = tostring(key),
					displayName = resolveDisplayName(category, tostring(key), data),
					count = count,
				})
			end
		end
	else
		for key, entry in bucket do
			local count = getStackCount(category, tostring(key))
			if count > 0 then
				table.insert(items, {
					itemKey = tostring(key),
					displayName = resolveDisplayName(category, tostring(key), entry),
					count = count,
				})
			end
		end
	end

	table.sort(items, function(a, b)
		if a.displayName ~= b.displayName then
			return a.displayName < b.displayName
		end
		return a.itemKey < b.itemKey
	end)

	return items
end

-- =============================================================================
-- Item icons (asset ids from game data)
-- =============================================================================

local ItemIcons = {}

function ItemIcons.parseAssetId(value: any): number?
	if typeof(value) == "number" and value > 0 then
		return math.floor(value)
	end
	if typeof(value) ~= "string" or value == "" then
		return nil
	end
	local id = string.match(value, "rbxassetid://(%d+)") or string.match(value, "^(%d+)$")
	if id then
		return tonumber(id)
	end
	return nil
end

local function safeTableGet(tbl: any, field: string): any?
	if typeof(tbl) ~= "table" then
		return nil
	end
	local ok, val = pcall(function()
		return tbl[field]
	end)
	if ok then
		return val
	end
	return nil
end

function ItemIcons.iconFromTable(data: any): number?
	if typeof(data) ~= "table" then
		return nil
	end
	for _, key in { "Icon", "Image", "IMG", "icon", "image", "Texture", "SeedIcon", "Thumbnail" } do
		local id = ItemIcons.parseAssetId(safeTableGet(data, key))
		if id then
			return id
		end
	end
	local seed = safeTableGet(data, "Seed")
	if typeof(seed) == "table" then
		return ItemIcons.iconFromTable(seed)
	end
	local item = safeTableGet(data, "Item")
	if typeof(item) == "table" then
		return ItemIcons.iconFromTable(item)
	end
	return nil
end

function ItemIcons.lookup(itemKeys: { string }): { [string]: number }
	local out: { [string]: number } = {}
	if #itemKeys == 0 then
		return out
	end

	local wanted: { [string]: string } = {}
	for _, key in itemKeys do
		wanted[string.lower(key)] = key
	end

	local function storeIcon(key: string, id: number?)
		if id and not out[key] then
			out[key] = id
		end
	end

	local function scanTable(mod: any)
		if typeof(mod) ~= "table" then
			return
		end
		local dataBucket = safeTableGet(mod, "Data")
		if typeof(dataBucket) == "table" then
			for _, entry in dataBucket do
				if typeof(entry) ~= "table" then
					continue
				end
				local entryName = safeTableGet(entry, "Name") or safeTableGet(entry, "SprinklerName")
				if typeof(entryName) == "string" then
					local canonical = wanted[string.lower(entryName)]
					if canonical then
						storeIcon(canonical, ItemIcons.iconFromTable(entry))
					end
				end
			end
		end
		for name, data in mod do
			if typeof(name) ~= "string" then
				continue
			end
			local canonical = wanted[string.lower(name)]
			if canonical and typeof(data) == "table" then
				storeIcon(canonical, ItemIcons.iconFromTable(data))
			end
			if typeof(data) == "table" then
				local entryName = safeTableGet(data, "Name") or safeTableGet(data, "SprinklerName")
				if typeof(entryName) == "string" then
					local canon = wanted[string.lower(entryName)]
					if canon then
						storeIcon(canon, ItemIcons.iconFromTable(data))
					end
				end
			end
		end
	end

	local function scanDataModules(root: Instance?)
		if not root then
			return
		end
		for _, inst in root:GetDescendants() do
			if not inst:IsA("ModuleScript") then
				continue
			end
			if not string.match(inst.Name, "Data$") then
				continue
			end
			pcall(function()
				scanTable(require(inst))
			end)
		end
	end

	local RS = ReplicatedStorage
	pcall(function()
		local PetData = require(RS:WaitForChild("SharedData"):WaitForChild("PetData"))
		for _, key in itemKeys do
			if PetData.GetImage then
				storeIcon(key, ItemIcons.parseAssetId(PetData.GetImage(key)))
			else
				local petEntry = safeTableGet(PetData, key)
				if typeof(petEntry) == "table" then
					storeIcon(key, ItemIcons.iconFromTable(petEntry))
				end
			end
		end
		scanTable(PetData)
	end)
	pcall(function()
		local seedImages = RS:WaitForChild("SharedModules"):WaitForChild("SeedData"):FindFirstChild("SeedImages")
		for _, key in itemKeys do
			if out[key] then
				continue
			end
			local sv = seedImages and seedImages:FindFirstChild(key)
			if sv and sv:IsA("StringValue") then
				storeIcon(key, ItemIcons.parseAssetId(sv.Value))
			end
		end
	end)

	scanDataModules(RS:FindFirstChild("SharedModules"))
	scanDataModules(RS:FindFirstChild("SharedData"))

	return out
end

local function attachIcons(items: { any })
	local keys: { string } = {}
	for _, item in items do
		table.insert(keys, item.displayName)
		if item.displayName ~= item.itemKey then
			table.insert(keys, item.itemKey)
		end
	end
	local ok, icons = pcall(ItemIcons.lookup, keys)
	if not ok or typeof(icons) ~= "table" then
		warnLog("icon lookup failed:", icons)
		return
	end
	for _, item in items do
		item.iconId = icons[item.displayName] or icons[item.itemKey]
	end
end

local function rbxThumb(assetId: number): string
	return string.format("rbxthumb://type=Asset&id=%d&w=150&h=150", assetId)
end

-- =============================================================================
-- Mail building & sending
-- =============================================================================

local function remoteCall(remote: any, ...: any): (boolean, ...any)
	local args = { ... }
	if remote == nil then
		return false, "nil remote"
	end
	if typeof(remote.Fire) == "function" then
		return pcall(function()
			return remote:Fire(table.unpack(args))
		end)
	end
	if typeof(remote.Invoke) == "function" then
		return pcall(function()
			return remote:Invoke(table.unpack(args))
		end)
	end
	return false, "remote has no Fire/Invoke"
end

local lookupCache: { [string]: { userId: number, expires: number } } = {}

local function lookupUser(username: string): (number?, string?)
	local key = string.lower(username)
	local cached = lookupCache[key]
	if cached and os.clock() < cached.expires then
		return cached.userId, nil
	end
	local ok, userId = remoteCall(Networking.Mailbox.LookupPlayer, username)
	if ok and typeof(userId) == "number" and userId > 0 then
		lookupCache[key] = { userId = userId, expires = os.clock() + 600 }
		return userId, nil
	end
	return nil, "Player '" .. username .. "' not found"
end

-- Splits the request into mails, honoring maxMailLines. Pets use one line per
-- uuid; HarvestedFruits keep one payload entry per mail but every unit counts
-- as a line server-side; stackables fit the whole count into a single line.
local function buildMails(category: string, itemKey: string, count: number): ({ { any } }?, string?)
	local maxLines = CFG.maxMailLines

	if category == "Pets" then
		local matched = matchPets(itemKey)
		if #matched < count then
			return nil, string.format("Pets/%s: need %d, have %d (equipped pets are skipped)", itemKey, count, #matched)
		end
		local mails: { { any } } = {}
		local current: { any } = {}
		for i = 1, count do
			if #current >= maxLines then
				table.insert(mails, current)
				current = {}
			end
			table.insert(current, { Category = "Pets", ItemKey = matched[i], Count = 1 })
		end
		if #current > 0 then
			table.insert(mails, current)
		end
		return mails, nil
	end

	local resolvedKey = resolveStackKey(category, itemKey)
	if not resolvedKey then
		return nil, string.format("%s/%s not found in inventory", category, itemKey)
	end
	local have = getStackCount(category, resolvedKey)
	if have < count then
		return nil, string.format("%s/%s: need %d, have %d", category, resolvedKey, count, have)
	end

	if LINE_EXPANDED[category] then
		local mails: { { any } } = {}
		local remaining = count
		while remaining > 0 do
			local take = math.min(remaining, maxLines)
			table.insert(mails, { { Category = category, ItemKey = resolvedKey, Count = take } })
			remaining -= take
		end
		return mails, nil
	end

	return { { { Category = category, ItemKey = resolvedKey, Count = count } } }, nil
end

local function lineWeight(entry: any): number
	if entry.Category == "Pets" then
		return 1
	end
	if LINE_EXPANDED[entry.Category] then
		return math.max(1, math.floor(tonumber(entry.Count) or 1))
	end
	return 1
end

-- Expands one cart row into SendBatch payload entries (before mail packing).
local function buildLinesForEntry(category: string, itemKey: string, count: number): ({ any }?, string?)
	count = math.max(1, math.floor(tonumber(count) or 1))

	if category == "Pets" then
		local matched = matchPets(itemKey)
		if #matched < count then
			return nil, string.format("Pets/%s: need %d, have %d (equipped pets are skipped)", itemKey, count, #matched)
		end
		local lines: { any } = {}
		for i = 1, count do
			table.insert(lines, { Category = "Pets", ItemKey = matched[i], Count = 1 })
		end
		return lines, nil
	end

	local resolvedKey = resolveStackKey(category, itemKey)
	if not resolvedKey then
		return nil, string.format("%s/%s not found in inventory", category, itemKey)
	end
	local have = getStackCount(category, resolvedKey)
	if have < count then
		return nil, string.format("%s/%s: need %d, have %d", category, resolvedKey, count, have)
	end

	return { { Category = category, ItemKey = resolvedKey, Count = count } }, nil
end

-- Packs payload entries into mails, honoring maxMailLines (HarvestedFruits Count = line cost).
local function packPayloadLines(lines: { any }): { { any } }
	local maxLines = CFG.maxMailLines
	local mails: { { any } } = {}
	local current: { any } = {}
	local used = 0

	local function flush()
		if #current > 0 then
			table.insert(mails, current)
			current = {}
			used = 0
		end
	end

	for _, entry in lines do
		local remaining = math.max(1, math.floor(tonumber(entry.Count) or 1))
		local category = entry.Category
		local itemKey = entry.ItemKey

		if LINE_EXPANDED[category] then
			while remaining > 0 do
				local space = maxLines - used
				if space <= 0 then
					flush()
					space = maxLines
				end
				local take = math.min(remaining, space)
				table.insert(current, { Category = category, ItemKey = itemKey, Count = take })
				used += take
				remaining -= take
				if used >= maxLines then
					flush()
				end
			end
		else
			local cost = lineWeight(entry)
			if used + cost > maxLines and #current > 0 then
				flush()
			end
			table.insert(current, entry)
			used += cost
			if used >= maxLines then
				flush()
			end
		end
	end

	flush()
	return mails
end

-- Cart row: { id, category, itemKey, displayName, sendCount, maxAvailable, iconId? }
local function buildMailsFromCart(cart: { any }): ({ { any } }?, string?)
	if #cart == 0 then
		return nil, "Cart is empty"
	end

	local allLines: { any } = {}
	for _, row in cart do
		local lines, err = buildLinesForEntry(row.category, row.itemKey, row.sendCount)
		if not lines then
			return nil, err
		end
		for _, line in lines do
			table.insert(allLines, line)
		end
	end

	return packPayloadLines(allLines), nil
end

local function countCartLines(cart: { any }): number
	local total = 0
	for _, row in cart do
		local lines, err = buildLinesForEntry(row.category, row.itemKey, row.sendCount)
		if lines then
			for _, line in lines do
				total += lineWeight(line)
			end
		end
	end
	return total
end

local function parseCooldownSeconds(message: string?): number
	if not message then
		return CFG.sendCooldownSec
	end
	local n = string.match(string.lower(message), "wait (%d+)s")
	if n then
		return math.max(tonumber(n) or CFG.sendCooldownSec, CFG.sendCooldownSec)
	end
	return CFG.sendCooldownSec
end

local lastSendAt = 0

local function waitSendCooldown()
	local need = CFG.sendCooldownSec - (os.clock() - lastSendAt)
	if need > 0 then
		task.wait(need)
	end
end

local function sendBatchOnce(userId: number, payload: { any }, note: string): (boolean, string)
	local ok, success, message = remoteCall(Networking.Mailbox.SendBatch, userId, payload, note or "")
	if not ok then
		return false, "SendBatch crash: " .. tostring(success)
	end
	if success == true then
		return true, message or "Gift sent!"
	end
	return false, message or "Could not send gift"
end

local function sendMailCart(recipient: string, cart: { any }, note: string, onProgress: ((string) -> ())?): (boolean, string)
	local function progress(text: string)
		if onProgress then
			onProgress(text)
		end
	end

	if recipient == "" then
		return false, "Recipient is empty"
	end
	if #cart == 0 then
		return false, "Cart is empty - add items first"
	end
	if not waitReplica(30) then
		return false, "PlayerState replica not ready"
	end

	local userId, lookupErr = lookupUser(recipient)
	if not userId then
		return false, lookupErr or "lookup failed"
	end

	local mails, buildErr = buildMailsFromCart(cart)
	if not mails then
		return false, buildErr or "payload build failed"
	end

	local lineTotal = 0
	for _, payload in mails do
		for _, line in payload do
			lineTotal += lineWeight(line)
		end
	end

	log(string.format("-> %s (%d): %d item(s), %d line(s), %d mail(s)", recipient, userId, #cart, lineTotal, #mails))

	for i, payload in mails do
		if i > 1 then
			progress(string.format("Cooldown before mail %d/%d...", i, #mails))
			waitSendCooldown()
		end
		progress(string.format("Sending mail %d/%d...", i, #mails))
		local retries = 0
		while true do
			local ok, err = sendBatchOnce(userId, payload, note)
			lastSendAt = os.clock()
			if ok then
				log(string.format("  mail %d/%d OK (%d line(s))", i, #mails, #payload))
				break
			end
			local lower = string.lower(err or "")
			if string.find(lower, "before sending another gift", 1, true) and retries < 6 then
				retries += 1
				local waitS = parseCooldownSeconds(err)
				warnLog(string.format("  cooldown %ds, retry %d/6", waitS, retries))
				progress(string.format("Server cooldown %ds, retry %d/6...", waitS, retries))
				task.wait(waitS + 0.5)
			else
				return false, err
			end
		end
	end

	return true, string.format("Sent %d item(s) to %s (%d mail(s), %d lines)", #cart, recipient, #mails, lineTotal)
end

-- onProgress(text) is optional; used by the UI to show live progress.
local function sendMail(recipient: string, category: string, itemKey: string, count: number, note: string, onProgress: ((string) -> ())?): (boolean, string)
	local function progress(text: string)
		if onProgress then
			onProgress(text)
		end
	end

	count = math.max(1, math.floor(tonumber(count) or 1))
	if recipient == "" then
		return false, "Recipient is empty"
	end
	if not waitReplica(30) then
		return false, "PlayerState replica not ready"
	end

	local userId, lookupErr = lookupUser(recipient)
	if not userId then
		return false, lookupErr or "lookup failed"
	end

	local mails, buildErr = buildMails(category, itemKey, count)
	if not mails then
		return false, buildErr or "payload build failed"
	end

	log(string.format("-> %s (%d): %s/%s x %d, %d mail(s)", recipient, userId, category, itemKey, count, #mails))

	for i, payload in mails do
		if i > 1 then
			progress(string.format("Cooldown before mail %d/%d...", i, #mails))
			waitSendCooldown()
		end
		progress(string.format("Sending mail %d/%d...", i, #mails))
		local retries = 0
		while true do
			local ok, err = sendBatchOnce(userId, payload, note)
			lastSendAt = os.clock()
			if ok then
				log(string.format("  mail %d/%d OK (%d line(s))", i, #mails, #payload))
				break
			end
			local lower = string.lower(err or "")
			if string.find(lower, "before sending another gift", 1, true) and retries < 6 then
				retries += 1
				local waitS = parseCooldownSeconds(err)
				warnLog(string.format("  cooldown %ds, retry %d/6", waitS, retries))
				progress(string.format("Server cooldown %ds, retry %d/6...", waitS, retries))
				task.wait(waitS + 0.5)
			else
				return false, err
			end
		end
	end

	return true, string.format("Sent %d x %s/%s to %s (%d mail(s))", count, category, itemKey, recipient, #mails)
end

-- =============================================================================
-- UI
-- =============================================================================

local COLORS = {
	panel = Color3.fromRGB(24, 26, 33),
	panelStroke = Color3.fromRGB(58, 62, 78),
	titleBar = Color3.fromRGB(30, 33, 42),
	field = Color3.fromRGB(37, 40, 51),
	fieldStroke = Color3.fromRGB(52, 56, 70),
	text = Color3.fromRGB(235, 238, 245),
	textDim = Color3.fromRGB(148, 154, 170),
	textFaint = Color3.fromRGB(105, 111, 128),
	accent = Color3.fromRGB(52, 168, 107),
	accentHover = Color3.fromRGB(62, 190, 122),
	ok = Color3.fromRGB(96, 214, 138),
	err = Color3.fromRGB(255, 118, 118),
	warnCol = Color3.fromRGB(245, 190, 92),
}

local UI = {}
local gui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local stockLabel: TextLabel? = nil
local sendButton: TextButton? = nil
local categoryButton: TextButton? = nil
local itemButton: TextButton? = nil
local categoryDropdown: Frame? = nil
local itemDropdown: Frame? = nil
local itemScroll: ScrollingFrame? = nil
local cartScroll: ScrollingFrame? = nil
local fields: { [string]: TextBox } = {}
local selectedCategory = CFG.category
local categoryItems: { any } = {}
-- Cart: { id, category, itemKey, displayName, sendCount, maxAvailable, iconId? }
local cart: { any } = {}
local sending = false

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function makeLabel(parent: Instance, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 11
	l.TextColor3 = COLORS.textDim
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.new(1, 0, 0, 14)
	l.Text = string.upper(text)
	l.Parent = parent
	return l
end

local function makeBox(parent: Instance, placeholder: string, default: string?): TextBox
	local b = Instance.new("TextBox")
	b.BackgroundColor3 = COLORS.field
	b.BorderSizePixel = 0
	b.Font = Enum.Font.Gotham
	b.TextSize = 14
	b.TextColor3 = COLORS.text
	b.PlaceholderText = placeholder
	b.PlaceholderColor3 = COLORS.textFaint
	b.ClearTextOnFocus = false
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.Size = UDim2.new(1, 0, 0, 32)
	b.Text = default or ""
	b.Parent = parent
	corner(b, 7)
	stroke(b, COLORS.fieldStroke)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = b
	return b
end

-- Row = label on top, content below; stacked by the body's UIListLayout.
local function makeRow(parent: Instance, order: number, labelText: string): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 50)
	row.LayoutOrder = order
	row.Parent = parent
	local label = makeLabel(row, labelText)
	label.Position = UDim2.fromOffset(0, 0)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 32)
	holder.Position = UDim2.fromOffset(0, 18)
	holder.Parent = row
	return holder
end

local function setStatus(text: string, color: Color3?)
	if statusLabel then
		statusLabel.Text = text
		statusLabel.TextColor3 = color or COLORS.textDim
	end
	log(text)
end

local function readUiFields(): (string, string)
	local recipient = fields.recipient and fields.recipient.Text or CFG.recipient
	local note = fields.note and fields.note.Text or CFG.note
	return recipient, note
end

local function cartEntryId(category: string, itemKey: string): string
	return category .. "/" .. itemKey
end

local function findCartEntry(id: string): any?
	for _, entry in cart do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function clampSendCount(entry: any, value: number): number
	return math.clamp(math.floor(value), 1, math.max(1, entry.maxAvailable))
end

local function addToCart(itemKey: string, displayName: string, maxAvailable: number, iconId: number?)
	local id = cartEntryId(selectedCategory, itemKey)
	local existing = findCartEntry(id)
	if existing then
		existing.sendCount = clampSendCount(existing, existing.sendCount + 1)
		if iconId and not existing.iconId then
			existing.iconId = iconId
		end
	else
		table.insert(cart, {
			id = id,
			category = selectedCategory,
			itemKey = itemKey,
			displayName = displayName,
			sendCount = 1,
			maxAvailable = maxAvailable,
			iconId = iconId,
		})
	end
	closeItemDropdown()
	UI.refreshCart()
	UI.refreshStock()
end

local function removeFromCart(id: string)
	for i, entry in cart do
		if entry.id == id then
			table.remove(cart, i)
			break
		end
	end
	UI.refreshCart()
	UI.refreshStock()
end

local function clearCart()
	table.clear(cart)
	UI.refreshCart()
	UI.refreshStock()
end

local function closeCategoryDropdown()
	if categoryDropdown then
		categoryDropdown.Visible = false
	end
end

local function closeItemDropdown()
	if itemDropdown then
		itemDropdown.Visible = false
	end
end

local function closeAllDropdowns()
	closeCategoryDropdown()
	closeItemDropdown()
end

function UI.refreshStock()
	if not stockLabel then
		return
	end
	if #cart == 0 then
		stockLabel.Text = "Cart empty - pick items below"
		stockLabel.TextColor3 = COLORS.textDim
		return
	end
	local lines = countCartLines(cart)
	local mails = math.max(1, math.ceil(lines / CFG.maxMailLines))
	stockLabel.Text = string.format("Cart: %d item(s), %d line(s), ~%d mail(s)", #cart, lines, mails)
	stockLabel.TextColor3 = if lines <= CFG.maxMailLines then COLORS.ok else COLORS.warnCol
end

function UI.refreshCart()
	if not cartScroll then
		return
	end
	for _, child in cartScroll:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
			child:Destroy()
		end
	end

	if #cart == 0 then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 12
		empty.TextColor3 = COLORS.textFaint
		empty.Size = UDim2.new(1, -8, 0, 28)
		empty.Text = "  No items yet"
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.LayoutOrder = 1
		empty.Parent = cartScroll
		UI.refreshStock()
		return
	end

	for i, entry in cart do
		local row = Instance.new("Frame")
		row.Name = "Cart_" .. string.gsub(entry.id, "[^%w%-_]", "_")
		row.BackgroundColor3 = COLORS.field
		row.BackgroundTransparency = 0.15
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -4, 0, 40)
		row.LayoutOrder = i
		row.Parent = cartScroll
		corner(row, 6)

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundColor3 = COLORS.panel
		icon.BackgroundTransparency = 0.3
		icon.BorderSizePixel = 0
		icon.Size = UDim2.fromOffset(28, 28)
		icon.Position = UDim2.fromOffset(6, 6)
		icon.Parent = row
		corner(icon, 5)
		if entry.iconId then
			icon.Image = rbxThumb(entry.iconId)
		end

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextSize = 12
		nameLabel.TextColor3 = COLORS.text
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Size = UDim2.new(1, -150, 0, 16)
		nameLabel.Position = UDim2.fromOffset(40, 4)
		nameLabel.Text = entry.displayName
		nameLabel.Parent = row

		local catLabel = Instance.new("TextLabel")
		catLabel.BackgroundTransparency = 1
		catLabel.Font = Enum.Font.Gotham
		catLabel.TextSize = 10
		catLabel.TextColor3 = COLORS.textFaint
		catLabel.TextXAlignment = Enum.TextXAlignment.Left
		catLabel.Size = UDim2.new(1, -150, 0, 14)
		catLabel.Position = UDim2.fromOffset(40, 20)
		catLabel.Text = entry.category
		catLabel.Parent = row

		local countBox = Instance.new("TextBox")
		countBox.Name = "CountBox"
		countBox.BackgroundColor3 = COLORS.titleBar
		countBox.BorderSizePixel = 0
		countBox.Font = Enum.Font.GothamMedium
		countBox.TextSize = 13
		countBox.TextColor3 = COLORS.text
		countBox.TextXAlignment = Enum.TextXAlignment.Center
		countBox.ClearTextOnFocus = false
		countBox.Size = UDim2.fromOffset(44, 28)
		countBox.Position = UDim2.new(1, -84, 0.5, -14)
		countBox.Text = tostring(entry.sendCount)
		countBox.Parent = row
		corner(countBox, 5)
		stroke(countBox, COLORS.fieldStroke)

		local entryId = entry.id
		countBox.FocusLost:Connect(function()
			local entryRef = findCartEntry(entryId)
			if not entryRef then
				return
			end
			entryRef.sendCount = clampSendCount(entryRef, tonumber(countBox.Text) or 1)
			countBox.Text = tostring(entryRef.sendCount)
			UI.refreshStock()
		end)

		local removeBtn = Instance.new("TextButton")
		removeBtn.BackgroundTransparency = 1
		removeBtn.Font = Enum.Font.GothamBold
		removeBtn.TextSize = 14
		removeBtn.TextColor3 = COLORS.textDim
		removeBtn.Size = UDim2.fromOffset(28, 28)
		removeBtn.Position = UDim2.new(1, -34, 0.5, -14)
		removeBtn.Text = "X"
		removeBtn.Parent = row
		removeBtn.MouseEnter:Connect(function()
			removeBtn.TextColor3 = COLORS.err
		end)
		removeBtn.MouseLeave:Connect(function()
			removeBtn.TextColor3 = COLORS.textDim
		end)
		removeBtn.MouseButton1Click:Connect(function()
			removeFromCart(entryId)
		end)
	end

	task.defer(function()
		if not cartScroll then
			return
		end
		local list = cartScroll:FindFirstChildOfClass("UIListLayout")
		local contentH = list and list.AbsoluteContentSize.Y or (#cart * 44)
		cartScroll.CanvasSize = UDim2.fromOffset(0, math.max(contentH + 4, 32))
	end)

	UI.refreshStock()
end

local function selectCategory(name: string)
	selectedCategory = name
	if categoryButton then
		categoryButton.Text = name
	end
	closeAllDropdowns()
	UI.refreshItemList()
	UI.refreshStock()
end

local function refreshRowIcons()
	if not itemScroll then
		return
	end
	for _, row in itemScroll:GetChildren() do
		if not row:IsA("TextButton") or row.Name:sub(1, 5) ~= "Item_" then
			continue
		end
		local key = row.Name:sub(6)
		for _, item in categoryItems do
			if item.itemKey == key and item.iconId then
				local icon = row:FindFirstChild("Icon")
				if icon and icon:IsA("ImageLabel") then
					icon.Image = rbxThumb(item.iconId)
					icon.BackgroundTransparency = 0.2
				end
				break
			end
		end
	end
end

local function makeItemPickerRow(parent: Instance, item: any, order: number)
	local inCart = findCartEntry(cartEntryId(selectedCategory, item.itemKey)) ~= nil
	local row = Instance.new("TextButton")
	row.Name = "Item_" .. item.itemKey
	row.BackgroundColor3 = COLORS.titleBar
	row.BackgroundTransparency = if inCart then 0.75 else 1
	row.BorderSizePixel = 0
	row.AutoButtonColor = false
	row.Size = UDim2.new(1, -8, 0, 36)
	row.LayoutOrder = order
	row.ZIndex = 12
	row.Parent = parent

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundColor3 = COLORS.field
	icon.BackgroundTransparency = 0.2
	icon.BorderSizePixel = 0
	icon.Size = UDim2.fromOffset(28, 28)
	icon.Position = UDim2.fromOffset(6, 4)
	icon.ZIndex = 13
	icon.Parent = row
	corner(icon, 6)
	if item.iconId then
		icon.Image = rbxThumb(item.iconId)
	else
		icon.Image = ""
		icon.BackgroundTransparency = 0.5
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = COLORS.text
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Size = UDim2.new(1, -96, 1, 0)
	nameLabel.Position = UDim2.fromOffset(40, 0)
	nameLabel.Text = item.displayName .. (if inCart then "  +" else "")
	nameLabel.ZIndex = 13
	nameLabel.Parent = row

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.BackgroundTransparency = 1
	countLabel.Font = Enum.Font.GothamMedium
	countLabel.TextSize = 12
	countLabel.TextColor3 = COLORS.textDim
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.Size = UDim2.fromOffset(44, 36)
	countLabel.Position = UDim2.new(1, -50, 0, 0)
	countLabel.Text = "x" .. tostring(item.count)
	countLabel.ZIndex = 13
	countLabel.Parent = row

	row.MouseEnter:Connect(function()
		row.BackgroundTransparency = 0.88
		row.BackgroundColor3 = COLORS.text
	end)
	row.MouseLeave:Connect(function()
		row.BackgroundTransparency = if inCart then 0.75 else 1
	end)
	row.MouseButton1Click:Connect(function()
		addToCart(item.itemKey, item.displayName, item.count, item.iconId)
		UI.refreshItemList()
	end)
end

local function paintItemList(items: { any })
	if #items == 0 then
		if itemScroll then
			for _, child in itemScroll:GetChildren() do
				if child:IsA("GuiObject") and child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
					child:Destroy()
				end
			end
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Font = Enum.Font.Gotham
			empty.TextSize = 12
			empty.TextColor3 = COLORS.textFaint
			empty.Size = UDim2.new(1, -8, 0, 36)
			empty.Text = "  No giftable items"
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.LayoutOrder = 1
			empty.ZIndex = 12
			empty.Parent = itemScroll
			itemScroll.CanvasSize = UDim2.fromOffset(0, 44)
		end
		return
	end

	if not itemScroll then
		return
	end
	for _, child in itemScroll:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
			child:Destroy()
		end
	end
	for i, item in items do
		makeItemPickerRow(itemScroll, item, i)
	end
	task.defer(function()
		if not itemScroll then
			return
		end
		local list = itemScroll:FindFirstChildOfClass("UIListLayout")
		local contentH = list and list.AbsoluteContentSize.Y or (#items * 40)
		contentH = math.max(contentH, 40)
		local viewH = math.min(contentH + 8, 220)
		itemScroll.CanvasSize = UDim2.fromOffset(0, contentH + 8)
		if itemDropdown then
			itemDropdown.Size = UDim2.new(1, 0, 0, viewH)
		end
	end)
end

function UI.refreshItemList()
	local ok, err = pcall(function()
		categoryItems = listCategoryItems(selectedCategory)
		paintItemList(categoryItems)

		local snapshot = categoryItems
		local snapshotCategory = selectedCategory
		task.spawn(function()
			attachIcons(snapshot)
			if snapshotCategory == selectedCategory and snapshot == categoryItems then
				refreshRowIcons()
			end
			local cartKeys: { string } = {}
			for _, entry in cart do
				table.insert(cartKeys, entry.displayName)
				if entry.displayName ~= entry.itemKey then
					table.insert(cartKeys, entry.itemKey)
				end
			end
			if #cartKeys > 0 then
				local okIcons, icons = pcall(ItemIcons.lookup, cartKeys)
				if okIcons and typeof(icons) == "table" then
					for _, entry in cart do
						entry.iconId = icons[entry.displayName] or icons[entry.itemKey] or entry.iconId
					end
					UI.refreshCart()
				end
			end
		end)
	end)
	if not ok then
		warnLog("refreshItemList failed:", err)
		setStatus("Failed to load inventory list", COLORS.err)
	end
end

function UI.doSend()
	if sending then
		return
	end
	sending = true
	closeAllDropdowns()
	if sendButton then
		sendButton.Text = "SENDING..."
		sendButton.BackgroundColor3 = COLORS.field
		sendButton.AutoButtonColor = false
	end
	local recipient, note = readUiFields()
	setStatus("Preparing...", nil)
	task.spawn(function()
		local ok, msg = sendMailCart(recipient, cart, note, function(text)
			setStatus(text, COLORS.warnCol)
		end)
		setStatus(msg, if ok then COLORS.ok else COLORS.err)
		if ok then
			clearCart()
		end
		UI.refreshStock()
		if sendButton then
			sendButton.Text = "SEND"
			sendButton.BackgroundColor3 = COLORS.accent
			sendButton.AutoButtonColor = true
		end
		sending = false
	end)
end

local function makeDraggable(handle: GuiObject, target: GuiObject)
	local draggingUi = false
	local dragStart: Vector3? = nil
	local startPos: UDim2? = nil
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingUi = true
			dragStart = input.Position
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					draggingUi = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not draggingUi or not dragStart or not startPos then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

function UI.build()
	if gui then
		gui:Destroy()
		gui = nil
	end
	-- Also clean up panels left behind by previous runs of the script.
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	for _, child in playerGui:GetChildren() do
		if child.Name == "GAG2MailTool" then
			child:Destroy()
		end
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "GAG2MailTool"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 50
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = COLORS.panel
	panel.BorderSizePixel = 0
	panel.Size = UDim2.fromOffset(320, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.ClipsDescendants = true
	panel.Position = UDim2.new(0, 24, 0.5, -230)
	panel.Parent = gui
	corner(panel, 12)
	stroke(panel, COLORS.panelStroke)

	-- Title bar (drag handle)
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundColor3 = COLORS.titleBar
	titleBar.BorderSizePixel = 0
	titleBar.Size = UDim2.new(1, 0, 0, 40)
	titleBar.Parent = panel
	corner(titleBar, 12)
	-- Square off the bottom corners of the title bar
	local titleFix = Instance.new("Frame")
	titleFix.BackgroundColor3 = COLORS.titleBar
	titleFix.BorderSizePixel = 0
	titleFix.Size = UDim2.new(1, 0, 0, 12)
	titleFix.Position = UDim2.new(0, 0, 1, -12)
	titleFix.Parent = titleBar

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = COLORS.text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.fromOffset(14, 0)
	title.Text = "Mail Tool"
	title.ZIndex = 2
	title.Parent = titleBar

	local hideBtn = Instance.new("TextButton")
	hideBtn.BackgroundTransparency = 1
	hideBtn.Font = Enum.Font.GothamBold
	hideBtn.TextSize = 16
	hideBtn.TextColor3 = COLORS.textDim
	hideBtn.Size = UDim2.fromOffset(32, 32)
	hideBtn.Position = UDim2.new(1, -38, 0, 4)
	hideBtn.Text = "X"
	hideBtn.ZIndex = 2
	hideBtn.Parent = titleBar
	hideBtn.MouseButton1Click:Connect(function()
		if gui then
			gui.Enabled = false
		end
	end)

	makeDraggable(titleBar, panel)

	-- Body
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Position = UDim2.fromOffset(0, 40)
	body.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.Parent = body

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = body

	-- Recipient
	local recipientHolder = makeRow(body, 1, "Recipient")
	fields.recipient = makeBox(recipientHolder, "roblox username", CFG.recipient)

	-- Category (dropdown)
	local categoryHolder = makeRow(body, 2, "Category")
	-- Sibling ZIndex ordering: lift the whole category row so the dropdown
	-- paints above the rows below it.
	categoryHolder.Parent.ZIndex = 5
	categoryButton = Instance.new("TextButton")
	categoryButton.BackgroundColor3 = COLORS.field
	categoryButton.BorderSizePixel = 0
	categoryButton.Font = Enum.Font.Gotham
	categoryButton.TextSize = 14
	categoryButton.TextColor3 = COLORS.text
	categoryButton.TextXAlignment = Enum.TextXAlignment.Left
	categoryButton.Size = UDim2.new(1, 0, 0, 32)
	categoryButton.Text = selectedCategory
	categoryButton.AutoButtonColor = true
	categoryButton.ZIndex = 3
	categoryButton.Parent = categoryHolder
	corner(categoryButton, 7)
	stroke(categoryButton, COLORS.fieldStroke)
	local catPad = Instance.new("UIPadding")
	catPad.PaddingLeft = UDim.new(0, 10)
	catPad.Parent = categoryButton

	categoryDropdown = Instance.new("Frame")
	categoryDropdown.BackgroundColor3 = COLORS.titleBar
	categoryDropdown.BorderSizePixel = 0
	categoryDropdown.Size = UDim2.new(1, 0, 0, #CATEGORIES * 28 + 8)
	categoryDropdown.Position = UDim2.new(0, 0, 1, 4)
	categoryDropdown.Visible = false
	categoryDropdown.ZIndex = 10
	categoryDropdown.Parent = categoryButton
	corner(categoryDropdown, 8)
	stroke(categoryDropdown, COLORS.panelStroke)

	local ddList = Instance.new("UIListLayout")
	ddList.SortOrder = Enum.SortOrder.LayoutOrder
	ddList.Parent = categoryDropdown
	local ddPad = Instance.new("UIPadding")
	ddPad.PaddingTop = UDim.new(0, 4)
	ddPad.PaddingBottom = UDim.new(0, 4)
	ddPad.PaddingLeft = UDim.new(0, 4)
	ddPad.PaddingRight = UDim.new(0, 4)
	ddPad.Parent = categoryDropdown

	for i, name in CATEGORIES do
		local opt = Instance.new("TextButton")
		opt.BackgroundColor3 = COLORS.titleBar
		opt.BackgroundTransparency = 1
		opt.BorderSizePixel = 0
		opt.Font = Enum.Font.Gotham
		opt.TextSize = 13
		opt.TextColor3 = if LINE_EXPANDED[name] then COLORS.warnCol else COLORS.text
		opt.TextXAlignment = Enum.TextXAlignment.Left
		opt.Size = UDim2.new(1, 0, 0, 28)
		opt.LayoutOrder = i
		opt.Text = "  " .. name .. (if LINE_EXPANDED[name] then "  (1 line/unit)" else "")
		opt.ZIndex = 11
		opt.Parent = categoryDropdown
		opt.MouseEnter:Connect(function()
			opt.BackgroundTransparency = 0.85
			opt.BackgroundColor3 = COLORS.text
		end)
		opt.MouseLeave:Connect(function()
			opt.BackgroundTransparency = 1
		end)
		opt.MouseButton1Click:Connect(function()
			selectCategory(name)
		end)
	end

	categoryButton.MouseButton1Click:Connect(function()
		closeItemDropdown()
		if categoryDropdown then
			categoryDropdown.Visible = not categoryDropdown.Visible
		end
	end)

	-- Add item (inventory picker)
	local itemRow = Instance.new("Frame")
	itemRow.BackgroundTransparency = 1
	itemRow.Size = UDim2.new(1, 0, 0, 50)
	itemRow.LayoutOrder = 3
	itemRow.ZIndex = 4
	itemRow.Parent = body

	local itemLabel = makeLabel(itemRow, "Add item")
	itemLabel.Size = UDim2.new(1, 0, 0, 14)

	local itemHolder = Instance.new("Frame")
	itemHolder.BackgroundTransparency = 1
	itemHolder.Size = UDim2.new(1, 0, 0, 32)
	itemHolder.Position = UDim2.fromOffset(0, 18)
	itemHolder.ZIndex = 4
	itemHolder.Parent = itemRow

	itemButton = Instance.new("TextButton")
	itemButton.Name = "ItemButton"
	itemButton.BackgroundColor3 = COLORS.field
	itemButton.BorderSizePixel = 0
	itemButton.AutoButtonColor = true
	itemButton.Font = Enum.Font.Gotham
	itemButton.TextSize = 13
	itemButton.TextColor3 = COLORS.textDim
	itemButton.TextXAlignment = Enum.TextXAlignment.Left
	itemButton.Text = "  Click to pick from inventory..."
	itemButton.Size = UDim2.new(1, 0, 0, 32)
	itemButton.ZIndex = 5
	itemButton.Parent = itemHolder
	corner(itemButton, 7)
	stroke(itemButton, COLORS.fieldStroke)

	itemDropdown = Instance.new("Frame")
	itemDropdown.Name = "ItemDropdown"
	itemDropdown.BackgroundColor3 = COLORS.titleBar
	itemDropdown.BorderSizePixel = 0
	itemDropdown.Size = UDim2.new(1, 0, 0, 180)
	itemDropdown.Position = UDim2.new(0, 0, 1, 4)
	itemDropdown.Visible = false
	itemDropdown.ZIndex = 20
	itemDropdown.Parent = itemButton
	corner(itemDropdown, 8)
	stroke(itemDropdown, COLORS.panelStroke)

	itemScroll = Instance.new("ScrollingFrame")
	itemScroll.Name = "ItemScroll"
	itemScroll.BackgroundTransparency = 1
	itemScroll.BorderSizePixel = 0
	itemScroll.Size = UDim2.new(1, -8, 1, -8)
	itemScroll.Position = UDim2.fromOffset(4, 4)
	itemScroll.CanvasSize = UDim2.fromOffset(0, 0)
	itemScroll.ScrollBarThickness = 4
	itemScroll.ScrollBarImageColor3 = COLORS.textFaint
	itemScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	itemScroll.CanvasSize = UDim2.fromOffset(0, 0)
	itemScroll.AutomaticSize = Enum.AutomaticSize.None
	itemScroll.ZIndex = 21
	itemScroll.Parent = itemDropdown

	local itemList = Instance.new("UIListLayout")
	itemList.SortOrder = Enum.SortOrder.LayoutOrder
	itemList.Padding = UDim.new(0, 4)
	itemList.Parent = itemScroll
	itemList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if itemScroll then
			itemScroll.CanvasSize = UDim2.fromOffset(0, itemList.AbsoluteContentSize.Y + 8)
		end
	end)

	itemButton.MouseButton1Click:Connect(function()
		closeCategoryDropdown()
		if itemDropdown then
			if not itemDropdown.Visible then
				UI.refreshItemList()
			end
			itemDropdown.Visible = not itemDropdown.Visible
		end
	end)

	-- Cart (multi-item send list)
	local cartRow = Instance.new("Frame")
	cartRow.BackgroundTransparency = 1
	cartRow.Size = UDim2.new(1, 0, 0, 150)
	cartRow.LayoutOrder = 4
	cartRow.Parent = body

	local cartHdrRow = Instance.new("Frame")
	cartHdrRow.BackgroundTransparency = 1
	cartHdrRow.Size = UDim2.new(1, 0, 0, 14)
	cartHdrRow.Parent = cartRow
	local cartLabel = makeLabel(cartHdrRow, "Cart")
	cartLabel.Size = UDim2.new(1, -56, 1, 0)

	local clearBtn = Instance.new("TextButton")
	clearBtn.BackgroundTransparency = 1
	clearBtn.Font = Enum.Font.GothamMedium
	clearBtn.TextSize = 11
	clearBtn.TextColor3 = COLORS.textDim
	clearBtn.Size = UDim2.fromOffset(52, 14)
	clearBtn.Position = UDim2.new(1, -52, 0, 0)
	clearBtn.Text = "clear"
	clearBtn.Parent = cartHdrRow
	clearBtn.MouseEnter:Connect(function()
		clearBtn.TextColor3 = COLORS.err
	end)
	clearBtn.MouseLeave:Connect(function()
		clearBtn.TextColor3 = COLORS.textDim
	end)
	clearBtn.MouseButton1Click:Connect(clearCart)

	cartScroll = Instance.new("ScrollingFrame")
	cartScroll.Name = "CartScroll"
	cartScroll.BackgroundColor3 = COLORS.field
	cartScroll.BackgroundTransparency = 0.5
	cartScroll.BorderSizePixel = 0
	cartScroll.Size = UDim2.new(1, 0, 0, 130)
	cartScroll.Position = UDim2.fromOffset(0, 18)
	cartScroll.CanvasSize = UDim2.fromOffset(0, 0)
	cartScroll.ScrollBarThickness = 4
	cartScroll.ScrollBarImageColor3 = COLORS.textFaint
	cartScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	cartScroll.Parent = cartRow
	corner(cartScroll, 7)
	stroke(cartScroll, COLORS.fieldStroke)

	local cartList = Instance.new("UIListLayout")
	cartList.SortOrder = Enum.SortOrder.LayoutOrder
	cartList.Padding = UDim.new(0, 4)
	cartList.Parent = cartScroll
	cartList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if cartScroll then
			cartScroll.CanvasSize = UDim2.fromOffset(0, cartList.AbsoluteContentSize.Y + 8)
		end
	end)

	local cartPad = Instance.new("UIPadding")
	cartPad.PaddingTop = UDim.new(0, 4)
	cartPad.PaddingBottom = UDim.new(0, 4)
	cartPad.PaddingLeft = UDim.new(0, 4)
	cartPad.PaddingRight = UDim.new(0, 4)
	cartPad.Parent = cartScroll

	-- Note
	local noteHolder = makeRow(body, 5, "Note")
	fields.note = makeBox(noteHolder, "mail note", CFG.note)

	-- Stock line + refresh
	local stockRow = Instance.new("Frame")
	stockRow.BackgroundTransparency = 1
	stockRow.Size = UDim2.new(1, 0, 0, 24)
	stockRow.LayoutOrder = 6
	stockRow.Parent = body

	stockLabel = Instance.new("TextLabel")
	stockLabel.BackgroundTransparency = 1
	stockLabel.Font = Enum.Font.GothamMedium
	stockLabel.TextSize = 13
	stockLabel.TextColor3 = COLORS.textDim
	stockLabel.TextXAlignment = Enum.TextXAlignment.Left
	stockLabel.Size = UDim2.new(1, -70, 1, 0)
	stockLabel.Text = "In inventory: -"
	stockLabel.Parent = stockRow

	local refreshBtn = Instance.new("TextButton")
	refreshBtn.BackgroundTransparency = 1
	refreshBtn.Font = Enum.Font.GothamMedium
	refreshBtn.TextSize = 13
	refreshBtn.TextColor3 = COLORS.textDim
	refreshBtn.Size = UDim2.fromOffset(64, 24)
	refreshBtn.Position = UDim2.new(1, -64, 0, 0)
	refreshBtn.Text = "refresh"
	refreshBtn.Parent = stockRow
	refreshBtn.MouseEnter:Connect(function()
		refreshBtn.TextColor3 = COLORS.text
	end)
	refreshBtn.MouseLeave:Connect(function()
		refreshBtn.TextColor3 = COLORS.textDim
	end)
	refreshBtn.MouseButton1Click:Connect(function()
		UI.refreshItemList()
		UI.refreshStock()
	end)

	-- Send button
	sendButton = Instance.new("TextButton")
	sendButton.BackgroundColor3 = COLORS.accent
	sendButton.BorderSizePixel = 0
	sendButton.Font = Enum.Font.GothamBold
	sendButton.TextSize = 14
	sendButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	sendButton.Size = UDim2.new(1, 0, 0, 36)
	sendButton.LayoutOrder = 7
	sendButton.Text = "SEND"
	sendButton.Parent = body
	corner(sendButton, 8)
	sendButton.MouseEnter:Connect(function()
		if not sending then
			sendButton.BackgroundColor3 = COLORS.accentHover
		end
	end)
	sendButton.MouseLeave:Connect(function()
		if not sending then
			sendButton.BackgroundColor3 = COLORS.accent
		end
	end)
	sendButton.MouseButton1Click:Connect(UI.doSend)

	-- Status
	statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 12
	statusLabel.TextColor3 = COLORS.textDim
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.Size = UDim2.new(1, 0, 0, 34)
	statusLabel.LayoutOrder = 8
	statusLabel.Text = "Ready"
	statusLabel.Parent = body

	-- Footer hint
	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextColor3 = COLORS.textFaint
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Size = UDim2.new(1, 0, 0, 14)
	hint.LayoutOrder = 9
	hint.Text = CFG.toggleUiKey .. " - show/hide | click items to add to cart"
	hint.Parent = body

	for _, box in pairs(fields) do
		if box ~= fields.note then
			box.FocusLost:Connect(function()
				task.defer(UI.refreshStock)
			end)
		end
	end

	-- Seed cart from config defaults (single item)
	if CFG.category and CFG.itemKey and CFG.count then
		local have = getAvailableCount(CFG.category, CFG.itemKey)
		if have > 0 then
			table.insert(cart, {
				id = cartEntryId(CFG.category, CFG.itemKey),
				category = CFG.category,
				itemKey = CFG.itemKey,
				displayName = CFG.itemKey,
				sendCount = math.min(math.max(1, CFG.count), have),
				maxAvailable = have,
			})
		end
	end

	UI.refreshCart()
	UI.refreshItemList()
	UI.refreshStock()
	gui.Enabled = CFG.showUi ~= false
end

function UI.toggle()
	if not gui then
		UI.build()
		return
	end
	gui.Enabled = not gui.Enabled
end

-- =============================================================================
-- Public API + startup
-- =============================================================================

local Tool = {}

function Tool.send(override: { recipient: string?, category: string?, itemKey: string?, count: number?, note: string?, items: { any }? }?)
	local recipient = CFG.recipient
	local note = CFG.note
	if gui and gui.Enabled and not override then
		recipient, note = readUiFields()
		if #cart > 0 then
			return sendMailCart(recipient, cart, note)
		end
	end
	if typeof(override) == "table" then
		recipient = override.recipient or recipient
		note = override.note or note
		if typeof(override.items) == "table" and #override.items > 0 then
			local tempCart: { any } = {}
			for _, row in override.items do
				if typeof(row) == "table" and row.category and row.itemKey then
					local count = math.max(1, math.floor(tonumber(row.count) or 1))
					local have = getAvailableCount(row.category, row.itemKey)
					table.insert(tempCart, {
						id = cartEntryId(row.category, row.itemKey),
						category = row.category,
						itemKey = row.itemKey,
						displayName = row.displayName or row.itemKey,
						sendCount = math.min(count, math.max(1, have)),
						maxAvailable = have,
					})
				end
			end
			return sendMailCart(recipient, tempCart, note)
		end
		local category = override.category or CFG.category
		local itemKey = override.itemKey or CFG.itemKey
		local count = override.count or CFG.count
		return sendMail(recipient, category, itemKey, count, note)
	end
	if #cart > 0 then
		return sendMailCart(recipient, cart, note)
	end
	return sendMail(recipient, CFG.category, CFG.itemKey, CFG.count, note)
end

function Tool.sendCart(recipient: string?, note: string?)
	local r = recipient or CFG.recipient
	local n = note or CFG.note
	if gui and gui.Enabled and not recipient then
		r, n = readUiFields()
	end
	return sendMailCart(r, cart, n)
end

function Tool.clearCart()
	clearCart()
end

function Tool.getCart()
	return cart
end

function Tool.stock(category: string?, itemKey: string?)
	local cat = category or CFG.category
	local key = itemKey or CFG.itemKey
	local have = getAvailableCount(cat, key)
	log(string.format("stock %s/%s = %d", cat, key, have))
	return have
end

function Tool.reloadCfg()
	CFG = loadCfg()
	log("config reloaded")
end

function Tool.getCfg()
	return CFG
end

function Tool.toggleUi()
	UI.toggle()
end

_G.GAG2MailTool = Tool

local toggleKeyOk, toggleKey = pcall(function()
	return Enum.KeyCode[CFG.toggleUiKey]
end)
if not toggleKeyOk or typeof(toggleKey) ~= "EnumItem" then
	warnLog("unknown toggleUiKey '" .. tostring(CFG.toggleUiKey) .. "', falling back to RightControl")
	toggleKey = Enum.KeyCode.RightControl
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == toggleKey then
		UI.toggle()
	end
end)

log("started | UI:", CFG.showUi ~= false, "| toggle:", CFG.toggleUiKey)
log(string.format("defaults: %s -> %s/%s x %d", CFG.recipient, CFG.category, CFG.itemKey, CFG.count))

if CFG.showUi ~= false then
	UI.build()
end

if CFG.autoSend then
	task.defer(function()
		local ok, msg = Tool.send()
		setStatus(msg, if ok then COLORS.ok else COLORS.err)
	end)
end

return Tool
