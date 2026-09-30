-- Vehicle Health Module v3 — integrated remote hook + auto HP detection
-- Replaces the previous vehicle_health.lua. Same public API.
-- Drop-in compatible with the main script.

local VehicleHealth = {}
print("[vehicle_health] v3 integrated build loaded")

VehicleHealth.enabled = false
VehicleHealth.currentVehicle = nil
VehicleHealth.vehicleName = nil
VehicleHealth.selectedVehicle = nil
VehicleHealth.trackedValues = {}
VehicleHealth.connections = {}
VehicleHealth.lastStatus = "Disabled"
VehicleHealth.hudEnabled = true
VehicleHealth.hudGui = nil
VehicleHealth.hudLabel = nil
VehicleHealth.hudConn = nil
VehicleHealth.hudVehicle = nil
VehicleHealth.hudLast = 0

-- =========================================================
-- REMOTE HOOK
-- =========================================================
local RS = game:GetService("ReplicatedStorage")
local EventsFolder = RS:FindFirstChild("Events")
local MainRemote = EventsFolder and EventsFolder:FindFirstChild("RemoteEvent")

local hpDiscovered = {
    guid = nil,
    parent = nil,
    key = nil,
    max = 0,
    lastUpdate = 0,
    debugDumped = false,
    sniffAttempts = 0,
    trackedNumerics = nil,   -- path -> {key, parent, value} on first ReplicateVehicle
    candidates = nil,        -- array of changed numeric fields on 2nd msg
    confirmed = false,
}

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Deep dump for the first payload only
local function dumpFirst(tbl, depth, indent, budget)
    if depth > 3 or budget[1] <= 0 then return end
    for k, v in pairs(tbl) do
        if budget[1] <= 0 then return end
        budget[1] = budget[1] - 1
        local tv = type(v)
        if tv == "number" or tv == "string" or tv == "boolean" then
            print(indent .. tostring(k) .. " = " .. tostring(v))
        elseif tv == "table" then
            print(indent .. tostring(k) .. " = <table " .. count(v) .. ">")
            dumpFirst(v, depth + 1, indent .. "  ", budget)
        elseif typeof(v) == "Instance" then
            print(indent .. tostring(k) .. " = <Instance " .. v.ClassName .. ">")
        end
    end
end

-- Collect every numeric field in the payload (deep)
local function collectNumerics(tbl, prefix, depth, out)
    if type(tbl) ~= "table" or depth > 4 then return end
    for k, v in pairs(tbl) do
        if type(v) == "number" then
            if v == math.floor(v) and v >= 10 and v <= 1000000 then
                out[prefix .. "." .. tostring(k)] = { key = k, parent = tbl, value = v }
            end
        elseif type(v) == "table" then
            collectNumerics(v, prefix .. "." .. tostring(k), depth + 1, out)
        end
    end
end

-- Find health-named fields explicitly
local function findNamedHP(tbl, depth, out, path)
    if type(tbl) ~= "table" or depth > 4 then return end
    for k, v in pairs(tbl) do
        if type(v) == "number" and type(k) == "string" then
            local n = k:lower():gsub("[%s_%-]", "")
            if not n:find("max") and (n:find("health") or n == "hp" or n:find("hull") or n == "curhealth") then
                if v >= 1 and v <= 1000000 and v == math.floor(v) then
                    table.insert(out, { key = k, parent = tbl, value = v, path = path .. "." .. k })
                end
            end
        elseif type(v) == "table" then
            findNamedHP(v, depth + 1, out, path .. "." .. tostring(k))
        end
    end
end

local function processReplicate(guid, payload)
    if type(payload) ~= "table" then return end
    hpDiscovered.sniffAttempts = hpDiscovered.sniffAttempts + 1

    -- One-time dump so we can eyeball the shape
    if not hpDiscovered.debugDumped then
        hpDiscovered.debugDumped = true
        print("=== First ReplicateVehicle payload (partial dump) ===")
        dumpFirst(payload, 0, "  ", {180})
        print("=== end dump ===")
    end

    -- Approach 1: named fields
    local named = {}
    findNamedHP(payload, 0, named, "p")
    if #named > 0 then
        table.sort(named, function(a, b) return a.value > b.value end)
        local pick = named[1]
        if not hpDiscovered.confirmed or hpDiscovered.guid ~= guid then
            hpDiscovered.guid = guid
            hpDiscovered.parent = pick.parent
            hpDiscovered.key = pick.key
            hpDiscovered.max = pick.value
            hpDiscovered.confirmed = true
            hpDiscovered.lastUpdate = os.clock()
            print(("[vehicle_health] HP field: %s = %s"):format(pick.path, tostring(pick.value)))
            return
        end
        hpDiscovered.parent = pick.parent
        hpDiscovered.key = pick.key
        hpDiscovered.lastUpdate = os.clock()
        if pick.value > hpDiscovered.max then hpDiscovered.max = pick.value end
        if VehicleHealth.enabled and pick.value < hpDiscovered.max then
            pcall(function() pick.parent[pick.key] = hpDiscovered.max end)
        end
        return
    end

    -- Approach 2: auto-detect by diffing consecutive payloads
    local numerics = {}
    collectNumerics(payload, "p", 0, numerics)

    if not hpDiscovered.trackedNumerics then
        hpDiscovered.trackedNumerics = numerics
        print(("[vehicle_health] no named health field; captured %d numeric fields, waiting for next payload to diff"):format(count(numerics)))
        return
    end

    -- Diff
    local changed = {}
    for path, rec in pairs(numerics) do
        local prev = hpDiscovered.trackedNumerics[path]
        if prev and prev.value ~= rec.value then
            table.insert(changed, {
                key = rec.key,
                parent = rec.parent,
                value = rec.value,
                prev = prev.value,
                path = path,
            })
        end
    end
    hpDiscovered.trackedNumerics = numerics

    if #changed == 0 then return end

    -- HP is the changed value in a plausible HP range (100..50000) that decreases or is near max
    table.sort(changed, function(a, b) return a.value > b.value end)
    local pick = nil
    for _, c in ipairs(changed) do
        if c.value >= 100 and c.value <= 50000 then
            pick = c
            break
        end
    end
    if not pick then return end

    if not hpDiscovered.confirmed or hpDiscovered.guid ~= guid then
        hpDiscovered.guid = guid
        hpDiscovered.parent = pick.parent
        hpDiscovered.key = pick.key
        hpDiscovered.max = math.max(pick.value, pick.prev)
        hpDiscovered.confirmed = true
        hpDiscovered.lastUpdate = os.clock()
        print(("[vehicle_health] HP field (auto): %s  cur=%s prev=%s max=%s"):format(
            pick.path, tostring(pick.value), tostring(pick.prev), tostring(hpDiscovered.max)))
        return
    end

    hpDiscovered.parent = pick.parent
    hpDiscovered.key = pick.key
    hpDiscovered.lastUpdate = os.clock()
    if pick.value > hpDiscovered.max then hpDiscovered.max = pick.value end
    if VehicleHealth.enabled and pick.value < hpDiscovered.max then
        pcall(function() pick.parent[pick.key] = hpDiscovered.max end)
    end
end

-- Install hook once per connection, re-scan every 5s for new connections
local wrapped = {}
local function installHook()
    if not MainRemote then return 0 end
    if type(getconnections) ~= "function" or type(hookfunction) ~= "function" then return 0 end
    local ok, conns = pcall(getconnections, MainRemote.OnClientEvent)
    if not ok or type(conns) ~= "table" then return 0 end
    local n = 0
    for _, c in ipairs(conns) do
        local orig = c.Function
        if type(orig) == "function" and not wrapped[orig] then
            wrapped[orig] = true
            local okHook = pcall(hookfunction, orig, function(...)
                local args = {...}
                if args[1] == "ReplicateVehicle" then
                    pcall(processReplicate, args[2], args[3])
                end
                return orig(...)
            end)
            if okHook then n = n + 1 else wrapped[orig] = nil end
        end
    end
    return n
end

print("[vehicle_health] initial hooks: " .. installHook())
task.spawn(function()
    while true do
        task.wait(5)
        pcall(installHook)
    end
end)

-- =========================================================
-- Structural detection (unchanged)
-- =========================================================
local function getCharacter(localPlayer)
    if not localPlayer then return nil end
    if localPlayer.Character and localPlayer.Character.Parent then return localPlayer.Character end
    local cam = workspace.CurrentCamera
    if cam and cam.CameraSubject and cam.CameraSubject:IsA("Humanoid") then
        local pm = cam.CameraSubject.Parent
        if pm and pm:IsA("Model") then return pm end
    end
    local live = workspace:FindFirstChild("Live")
    if live then
        local lc = live:FindFirstChild(localPlayer.Name)
        if lc then return lc end
    end
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and (m.Name == "Male" or m.Name == localPlayer.Name) then
            if m:FindFirstChildOfClass("Humanoid") then return m end
        end
    end
    return nil
end

local sigCache = setmetatable({}, { __mode = "k" })
local NEGATIVE_TTL = 5
local function getVehicleSignature(model)
    local c = sigCache[model]
    if c and (c.ground or c.heli or (os.clock() - c.t) < NEGATIVE_TTL) then
        return c.wheels, c.ground, c.heli
    end
    local wheels, ground, heli = 0, false, false
    for _, d in ipairs(model:GetDescendants()) do
        local a = d:GetAttribute("Component")
        if type(a) == "string" then
            local f = a:sub(1, 1)
            if f == "F" or f == "R" then wheels = wheels + 1 end
        end
        if d:IsA("AudioEmitter") then
            if d.Name == "Emitter_Ground" then ground = true
            elseif d.Name == "Emitter_Helicopter" then heli = true end
        end
    end
    sigCache[model] = { wheels = wheels, ground = ground, heli = heli, t = os.clock() }
    return wheels, ground, heli
end

local function isLikelyVehicle(model)
    if not model or not model:IsA("Model") then return false end
    if model.Name == "Male" or game.Players:GetPlayerFromCharacter(model) then return false end
    if model:FindFirstChild("Male") then return false end
    local n = model.Name:lower()
    for _, kw in ipairs({"stryker","vehicle","m1126","heli","blackhawk","truck","jeep","tank","btr","boat","plane"}) do
        if n:find(kw) then return true end
    end
    if model:FindFirstChildOfClass("VehicleSeat") or model:FindFirstChildOfClass("Seat") then return true end
    local _, g, h = getVehicleSignature(model)
    return g or h
end

local function getPlayerVehicle(localPlayer)
    if VehicleHealth.selectedVehicle and VehicleHealth.selectedVehicle.Parent then
        return VehicleHealth.selectedVehicle
    end
    local cam = workspace.CurrentCamera
    local camPos = cam and cam.CFrame.Position
    local best, bestDist = nil, math.huge
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m.Name ~= "Male" and not m:FindFirstChild("Male") then
            local w, g, h = getVehicleSignature(m)
            if g or h or w >= 4 then
                if camPos then
                    local ok, cf = pcall(function() return m:GetPivot() end)
                    if ok and cf then
                        local d = (cf.Position - camPos).Magnitude
                        if d < bestDist then bestDist = d; best = m end
                    end
                else
                    best = best or m
                end
            end
        end
    end
    return best
end

-- =========================================================
-- ValueBase fallback binding (kept for non-BRM5 vehicles)
-- =========================================================
local function isHealthName(name)
    local n = name:lower():gsub("[%s_%-]", "")
    return n == "health" or n == "hp" or n == "vehiclehealth" or n == "curhealth"
        or n == "hull" or n == "hullhealth" or n == "enginehealth"
        or n == "armor" or n == "armour" or n == "durability"
end
local function isMaxName(name)
    local n = name:lower():gsub("[%s_%-]", "")
    return n == "maxhealth" or n == "maxhp" or n == "fullhealth"
        or n == "maxhull" or n == "maxhullhealth" or n == "maxengine" or n == "maxarmor"
end

function VehicleHealth:clearListeners()
    for _, c in ipairs(self.connections) do pcall(function() c:Disconnect() end) end
    self.connections = {}
end

function VehicleHealth:bindHealthObjects(vehicle)
    self:clearListeners()
    self.trackedValues = {}
    if not vehicle then return false end
    local detectedMax
    for _, d in ipairs(vehicle:GetDescendants()) do
        if (d:IsA("NumberValue") or d:IsA("IntValue")) and isMaxName(d.Name) and d.Value > 0 then
            detectedMax = d.Value
        end
    end
    for _, d in ipairs(vehicle:GetDescendants()) do
        if (d:IsA("NumberValue") or d:IsA("IntValue")) and isHealthName(d.Name) then
            local maxVal = detectedMax or (d.Value > 0 and d.Value or 1000)
            table.insert(self.trackedValues, { instance = d, max = maxVal })
            local c = d:GetPropertyChangedSignal("Value"):Connect(function()
                if self.enabled and d.Value < maxVal then
                    pcall(function() d.Value = maxVal end)
                end
            end)
            table.insert(self.connections, c)
        end
    end
    return #self.trackedValues > 0
end

function VehicleHealth:selectVehicle(vehicle)
    if not vehicle or not vehicle.Parent then return false end
    self.selectedVehicle = vehicle
    self.currentVehicle = vehicle
    self.vehicleName = vehicle.Name
    self:bindHealthObjects(vehicle)
    self.lastStatus = vehicle.Name .. " (Selected)"
    return true
end

function VehicleHealth:getAvailableVehicles()
    local list, seen = {}, {}
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and not seen[m] and m.Name ~= "Male" and not m:FindFirstChild("Male") then
            local w, g, h = getVehicleSignature(m)
            if g or h or w >= 4 then
                seen[m] = true
                local tag, priority = "Vehicle", 10
                if g and w >= 8 then tag, priority = "⭐ STRYKER (8x8)", 1
                elseif g then tag, priority = "Ground (" .. w .. " wheels)", 2
                elseif h then tag, priority = "Helicopter", 2 end
                table.insert(list, { instance = m, rawName = m.Name, name = m.Name .. " [" .. tag .. "]", priority = priority })
            end
        end
    end
    table.sort(list, function(a, b) return a.priority < b.priority end)
    return list
end

-- =========================================================
-- HUD
-- =========================================================
local HUD_TOGGLE_KEY = Enum.KeyCode.End

local function getDisplayName(v)
    local w, g, h = getVehicleSignature(v)
    if g and w >= 8 then return "Stryker (8x8)"
    elseif g then return "Ground (" .. w .. " wheels)"
    elseif h then return "Helicopter" end
    return v.Name
end

local function readHP()
    if hpDiscovered.confirmed and hpDiscovered.parent and hpDiscovered.key then
        local ok, v = pcall(function() return hpDiscovered.parent[hpDiscovered.key] end)
        if ok and type(v) == "number" then
            return v, hpDiscovered.max, "remote"
        end
    end
    local p = VehicleHealth.trackedValues[1]
    if p then
        local ok, v = pcall(function() return p.instance.Value end)
        if ok and type(v) == "number" then return v, p.max, "value" end
    end
    return nil, nil, "none"
end

function VehicleHealth:createHUD()
    if self.hudGui and self.hudGui.Parent then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "VehicleHealthHUD"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 320, 0, 78)
    label.Position = UDim2.new(0, 16, 0, 140)
    label.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    label.BackgroundTransparency = 0.35
    label.BorderSizePixel = 0
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Font = Enum.Font.Code
    label.TextSize = 15
    label.Text = "Vehicle HUD"
    label.Parent = gui

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingTop = UDim.new(0, 6)
    pad.Parent = label

    pcall(function()
        if type(gethui) == "function" then gui.Parent = gethui()
        else gui.Parent = game:GetService("CoreGui") end
    end)
    if not gui.Parent then
        local lp = game.Players.LocalPlayer
        if lp and lp:FindFirstChildOfClass("PlayerGui") then
            gui.Parent = lp:FindFirstChildOfClass("PlayerGui")
        end
    end

    self.hudGui = gui
    self.hudLabel = label

    if not self.hudConn then
        self.hudConn = game:GetService("UserInputService").InputBegan:Connect(function(input, gp)
            if not gp and input.KeyCode == HUD_TOGGLE_KEY then
                self.hudEnabled = not self.hudEnabled
                if self.hudGui then self.hudGui.Enabled = self.hudEnabled end
            end
        end)
    end
end

function VehicleHealth:destroyHUD()
    if self.hudConn then pcall(function() self.hudConn:Disconnect() end); self.hudConn = nil end
    if self.hudGui then pcall(function() self.hudGui:Destroy() end) end
    self.hudGui, self.hudLabel, self.hudVehicle = nil, nil, nil
end

function VehicleHealth:updateHUD(localPlayer)
    if not self.hudEnabled then
        if self.hudGui then self.hudGui.Enabled = false end
        return
    end
    local now = os.clock()
    if now - self.hudLast < 0.2 then return end
    self.hudLast = now

    self:createHUD()
    if not self.hudLabel then return end
    self.hudGui.Enabled = true

    local vehicle = getPlayerVehicle(localPlayer)
    if not vehicle or not vehicle.Parent then
        self.hudVehicle = nil
        self.hudLabel.Text = "VEHICLE: none\nHP: -\nGOD: " .. (self.enabled and "ON" or "OFF")
        self.hudLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        return
    end

    if vehicle ~= self.hudVehicle then
        self.hudVehicle = vehicle
        pcall(function() self:bindHealthObjects(vehicle) end)
    end

    local cur, max, source = readHP()
    local line2, color
    if type(cur) == "number" then
        max = (type(max) == "number" and max > 0) and max or cur
        local pct = math.clamp(cur / max, 0, 1)
        line2 = string.format("HP: %d / %d (%d%%) [%s]", math.floor(cur), math.floor(max), math.floor(pct * 100), source)
        if pct > 0.6 then color = Color3.fromRGB(90, 255, 120)
        elseif pct > 0.3 then color = Color3.fromRGB(255, 220, 80)
        else color = Color3.fromRGB(255, 90, 90) end
    else
        line2 = "HP: waiting for next server tick..."
        color = Color3.fromRGB(255, 180, 120)
    end

    self.hudLabel.Text = "VEHICLE: " .. getDisplayName(vehicle) .. "\n" .. line2 .. "\nGOD: " .. (self.enabled and "ON" or "OFF")
    self.hudLabel.TextColor3 = color
end

-- =========================================================
-- Heal loop
-- =========================================================
function VehicleHealth:heal()
    -- remote state
    if hpDiscovered.confirmed and hpDiscovered.parent and hpDiscovered.key and hpDiscovered.max > 0 then
        pcall(function()
            local cur = hpDiscovered.parent[hpDiscovered.key]
            if type(cur) == "number" and cur < hpDiscovered.max then
                hpDiscovered.parent[hpDiscovered.key] = hpDiscovered.max
            end
        end)
    end
    -- valuebases
    for _, entry in ipairs(self.trackedValues) do
        pcall(function()
            if entry.instance and entry.instance.Parent and entry.instance.Value < entry.max then
                entry.instance.Value = entry.max
            end
        end)
    end
end

-- =========================================================
-- Public update
-- =========================================================
function VehicleHealth:update(localPlayer)
    if self.enabled then
        local veh = getPlayerVehicle(localPlayer)
        if veh then
            self.currentVehicle = veh
            self.vehicleName = veh.Name
            self:heal()
        end
    end
    pcall(function() self:updateHUD(localPlayer) end)
end

function VehicleHealth:getStatus()
    if not self.enabled then return "Disabled" end
    local vehicle = self.currentVehicle
    if not vehicle then return "No vehicle detected" end
    local cur, max = readHP()
    if type(cur) == "number" then
        return string.format("%s | HP: %d/%s", self.vehicleName or "?", math.floor(cur), max and math.floor(max) or "?")
    end
    return (self.vehicleName or "?") .. " | detecting HP field..."
end

function VehicleHealth:cleanup()
    self:clearListeners()
    self.currentVehicle = nil
    self.vehicleName = nil
    self.trackedValues = {}
    self.lastStatus = "Disabled"
end

return VehicleHealth
