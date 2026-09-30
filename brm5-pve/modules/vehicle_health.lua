-- Vehicle Health Module v2 — reads HP from BRM5's ValuesVehicle remote
-- Preserves the original public API: enabled, update, getStatus, cleanup,
-- selectVehicle, getAvailableVehicles.
-- Also keeps HUD toggle on End key.

local VehicleHealth = {}
print("[vehicle_health] v2 remote-sniffer build loaded")

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
-- REMOTE SNIFFER — hooks ReplicatedStorage.Events.RemoteEvent
-- =========================================================
local RS = game:GetService("ReplicatedStorage")
local EventsFolder = RS:FindFirstChild("Events")
local MainRemote = EventsFolder and EventsFolder:FindFirstChild("RemoteEvent")

local hpState = {
    current = nil,
    max = nil,
    guid = nil,
    table_ref = nil,
    field = nil,
    max_field = nil,
    last_update = 0,
    dumped = 0,
    known_fields = {},
}

-- one-time payload dump helper
local function dumpTable(tbl, depth, maxDepth, budget, indent)
    indent = indent or ""
    depth = depth or 0
    if depth > maxDepth or budget[1] <= 0 then return end
    for k, v in pairs(tbl) do
        if budget[1] <= 0 then return end
        budget[1] = budget[1] - 1
        local kk = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
        local tv = type(v)
        if tv == "number" or tv == "string" or tv == "boolean" then
            print(indent .. kk .. " = " .. tostring(v))
        elseif tv == "table" then
            local n = 0; for _ in pairs(v) do n = n + 1 end
            print(indent .. kk .. " = <table " .. n .. " keys>")
            dumpTable(v, depth + 1, maxDepth, budget, indent .. "  ")
        elseif typeof(v) == "Instance" then
            print(indent .. kk .. " = <Instance " .. v.ClassName .. ">")
        else
            print(indent .. kk .. " = <" .. tv .. ">")
        end
    end
end

local function scoreField(name)
    local n = tostring(name):lower():gsub("[%s_%-]", "")
    if n:find("max") then return 0 end
    if n:find("health") or n:find("hull") then return 10 end
    if n == "hp" then return 10 end
    if n:find("damage") then return 5 end
    if n:find("armor") or n:find("armour") then return 6 end
    return 0
end

local function scanTable(tbl, depth, out)
    if type(tbl) ~= "table" or depth > 3 then return end
    for k, v in pairs(tbl) do
        if type(v) == "number" and type(k) == "string" then
            local s = scoreField(k)
            if s > 0 then
                local rec = { key = k, value = v, score = s, depth = depth, parent = tbl }
                if not out.best or s > out.best.score then out.best = rec end
            end
            -- also look for max pairs
            local kl = k:lower()
            if kl:find("max") and not out.maxField then
                local base = kl:gsub("max", ""):gsub("[%s_%-]", "")
                if base:find("health") or base:find("hull") or base == "hp" then
                    out.maxField = k
                    out.maxValue = v
                end
            end
        elseif type(v) == "table" then
            scanTable(v, depth + 1, out)
        end
    end
end

local function sniffPayload(name, guid, tbl)
    if type(tbl) ~= "table" then return end
    local n = 0; for _ in pairs(tbl) do n = n + 1 end
    if n == 0 then return end

    -- one-time payload dump so we can inspect the shape
    if os.clock() - hpState.dumped > 5 then
        hpState.dumped = os.clock()
        print(("[vehicle_health] payload '%s' guid=%s keys=%d"):format(tostring(name), tostring(guid), n))
        dumpTable(tbl, 0, 3, {150}, "   ")
    end

    local out = { best = nil, maxField = nil, maxValue = nil }
    scanTable(tbl, 1, out)
    if out.best then
        hpState.current = out.best.value
        hpState.guid = guid
        hpState.table_ref = out.best.parent
        hpState.field = out.best.key
        hpState.last_update = os.clock()
        if out.maxField then
            hpState.max_field = out.maxField
            hpState.max = out.maxValue
        end
        if not hpState.known_fields[out.best.key] then
            hpState.known_fields[out.best.key] = true
            print(("[vehicle_health] HP field picked: %s = %s (max=%s)"):format(
                tostring(out.best.key), tostring(out.best.value), tostring(hpState.max)))
        end
    end
end

local function installHook()
    if not MainRemote then return 0 end
    if type(getconnections) ~= "function" or type(hookfunction) ~= "function" then
        warn("[vehicle_health] executor lacks getconnections/hookfunction")
        return 0
    end
    local ok, conns = pcall(getconnections, MainRemote.OnClientEvent)
    if not ok or type(conns) ~= "table" then return 0 end
    local hooked = 0
    for _, c in ipairs(conns) do
        local original = c.Function
        if type(original) == "function" then
            local okHook = pcall(function()
                hookfunction(original, function(...)
                    local args = {...}
                    local rname = args[1]
                    if rname == "ValuesVehicle" or rname == "ReplicateVehicle" then
                        pcall(sniffPayload, rname, args[2], args[3])
                    end
                    return original(...)
                end)
            end)
            if okHook then hooked = hooked + 1 end
        end
    end
    return hooked
end

local firstHooked = installHook()
print("[vehicle_health] initial OnClientEvent hooks: " .. firstHooked)

task.spawn(function()
    while true do
        task.wait(5)
        installHook()
    end
end)

-- =========================================================
-- Configs.Vehicle — lookup max HP by vehicle type name
-- =========================================================
local configMaxCache = {}
local function getConfigMaxHP(vehicleType)
    if not vehicleType then return nil end
    if configMaxCache[vehicleType] ~= nil then return configMaxCache[vehicleType] or nil end
    configMaxCache[vehicleType] = false
    local shared = RS:FindFirstChild("Shared")
    local configs = shared and shared:FindFirstChild("Configs")
    local vehicleCfg = configs and configs:FindFirstChild("Vehicle")
    if not vehicleCfg then return nil end
    local ok, data = pcall(require, vehicleCfg)
    if not ok or type(data) ~= "table" then return nil end
    for _, category in pairs(data) do
        if type(category) == "table" then
            local entry = category[vehicleType]
            if type(entry) == "table" then
                for _, k in ipairs({"MaxHealth","Health","MaxHP","HP","MaxHull","Hull","MaxArmor"}) do
                    if type(entry[k]) == "number" and entry[k] > 0 then
                        configMaxCache[vehicleType] = entry[k]
                        return entry[k]
                    end
                end
                -- dump keys once for debugging
                if not VehicleHealth._cfgDumped then
                    VehicleHealth._cfgDumped = true
                    local keys = {}
                    for k, v in pairs(entry) do
                        table.insert(keys, k .. "[" .. type(v) .. "]" .. (type(v)=="number" and "="..v or ""))
                    end
                    print("[vehicle_health] Configs.Vehicle." .. vehicleType .. ": " .. table.concat(keys, ", "))
                end
            end
        end
    end
    return nil
end

-- Try to infer the vehicle type from the model (best-effort)
local function inferVehicleType(vehicle)
    if not vehicle then return nil end
    -- Look for a nearby Value/StringValue named "Type"/"VehicleType"/"Name" in the model
    for _, d in ipairs(vehicle:GetDescendants()) do
        if d:IsA("StringValue") then
            local n = d.Name:lower()
            if n == "type" or n == "vehicletype" or n == "prefab" or n == "name" then
                local v = tostring(d.Value)
                if v ~= "" and #v < 40 then return v end
            end
        end
    end
    -- Structural guess
    local wheels, ground, heli = 0, false, false
    for _, d in ipairs(vehicle:GetDescendants()) do
        local c = d:GetAttribute("Component")
        if type(c) == "string" and (c:sub(1,1) == "F" or c:sub(1,1) == "R") then wheels = wheels + 1 end
        if d:IsA("AudioEmitter") then
            if d.Name == "Emitter_Ground" then ground = true end
            if d.Name == "Emitter_Helicopter" then heli = true end
        end
    end
    if ground and wheels >= 8 then return "Stryker" end
    if heli then return "UH60" end
    return nil
end

-- =========================================================
-- Vehicle signature (unchanged from original)
-- =========================================================
local sigCache = setmetatable({}, { __mode = "k" })
local NEGATIVE_TTL = 5
local function getVehicleSignature(model)
    local cached = sigCache[model]
    if cached then
        if cached.ground or cached.heli or (os.clock() - cached.t) < NEGATIVE_TTL then
            return cached.wheels, cached.ground, cached.heli
        end
    end
    local wheels, ground, heli = 0, false, false
    for _, d in ipairs(model:GetDescendants()) do
        local c = d:GetAttribute("Component")
        if type(c) == "string" then
            local f = c:sub(1, 1)
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
    if model.Name == "Male" or game.Players:GetPlayerFromCharacter(model) ~= nil then return false end
    if model:FindFirstChild("Male") then return false end
    local name = model.Name:lower()
    for _, kw in ipairs({"stryker","vehicle","m1126","heli","blackhawk","truck","jeep","tank","btr","boat","plane"}) do
        if name:find(kw) then return true end
    end
    if model:FindFirstChildOfClass("VehicleSeat") or model:FindFirstChildOfClass("Seat") then return true end
    local _, ground, heli = getVehicleSignature(model)
    return ground or heli
end

-- =========================================================
-- Player vehicle detection — keep the structural fallback
-- =========================================================
local function getPlayerVehicle(localPlayer)
    if VehicleHealth.selectedVehicle and VehicleHealth.selectedVehicle.Parent then
        return VehicleHealth.selectedVehicle
    end
    -- Scan workspace for any structural vehicle, prefer the one closest to camera
    local cam = workspace.CurrentCamera
    local camPos = cam and cam.CFrame.Position
    local best, bestDist = nil, math.huge
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m.Name ~= "Male" and not m:FindFirstChild("Male") then
            local wheels, ground, heli = getVehicleSignature(m)
            if ground or heli or wheels >= 4 then
                if camPos then
                    local ok, cfr = pcall(function() return m:GetPivot() end)
                    if ok and cfr then
                        local d = (cfr.Position - camPos).Magnitude
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
-- bindHealthObjects — still useful if a vehicle has ValueBases
-- =========================================================
local function isHealthName(name)
    local n = name:lower():gsub("[%s_%-]", "")
    return n == "health" or n == "hp" or n == "vehiclehealth" or n == "curhealth"
        or n == "hull" or n == "hullhealth" or n == "enginehealth" or n == "armor"
        or n == "armour" or n == "durability"
end
local function isMaxHealthName(name)
    local n = name:lower():gsub("[%s_%-]", "")
    return n == "maxhealth" or n == "maxhp" or n == "fullhealth" or n == "maxhull"
        or n == "maxhullhealth" or n == "maxengine" or n == "maxarmor"
end

function VehicleHealth:clearListeners()
    for _, c in ipairs(self.connections) do pcall(function() c:Disconnect() end) end
    self.connections = {}
end

function VehicleHealth:bindHealthObjects(vehicle)
    self:clearListeners()
    self.trackedValues = {}
    if not vehicle then return false end
    local detectedMax = nil
    for _, d in ipairs(vehicle:GetDescendants()) do
        if (d:IsA("NumberValue") or d:IsA("IntValue")) and isMaxHealthName(d.Name) and d.Value > 0 then
            detectedMax = d.Value
        end
    end
    for _, d in ipairs(vehicle:GetDescendants()) do
        if (d:IsA("NumberValue") or d:IsA("IntValue")) and isHealthName(d.Name) then
            local maxVal = detectedMax or (d.Value > 0 and d.Value or 1000)
            table.insert(self.trackedValues, { instance = d, max = maxVal, current = d.Value })
            local conn = d:GetPropertyChangedSignal("Value"):Connect(function()
                if self.enabled and d.Value < maxVal then
                    pcall(function() d.Value = maxVal end)
                end
            end)
            table.insert(self.connections, conn)
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
    self.lastStatus = self.vehicleName .. " (Selected)"
    return true
end

function VehicleHealth:getAvailableVehicles()
    local list, seen = {}, {}
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and not seen[m] and m.Name ~= "Male" and not m:FindFirstChild("Male") then
            local wheels, ground, heli = getVehicleSignature(m)
            if ground or heli or wheels >= 4 then
                seen[m] = true
                local tag = "Vehicle"
                local priority = 10
                if ground and wheels >= 8 then tag = "⭐ STRYKER (8x8)"; priority = 1
                elseif ground then tag = "Ground (" .. wheels .. " wheels)"; priority = 2
                elseif heli then tag = "Helicopter"; priority = 2 end
                table.insert(list, {
                    instance = m,
                    rawName = m.Name,
                    name = m.Name .. " [" .. tag .. "]",
                    priority = priority,
                })
            end
        end
    end
    table.sort(list, function(a,b) return a.priority < b.priority end)
    return list
end

-- =========================================================
-- HUD
-- =========================================================
local HUD_TOGGLE_KEY = Enum.KeyCode.End

local function getDisplayName(vehicle)
    local wheels, ground, heli = getVehicleSignature(vehicle)
    if ground and wheels >= 8 then return "Stryker (8x8)"
    elseif ground then return "Ground vehicle (" .. wheels .. " wheels)"
    elseif heli then return "Helicopter" end
    return vehicle.Name
end

-- Returns cur, max, source-string
local function readHP(vehicle)
    -- 1) live remote-sniffed value
    if hpState.current and (os.clock() - hpState.last_update) < 5 then
        local cur = hpState.current
        local max = hpState.max
        -- If the table_ref is still alive, read the live value again
        if hpState.table_ref and hpState.field then
            local ok, v = pcall(function() return hpState.table_ref[hpState.field] end)
            if ok and type(v) == "number" then cur = v end
        end
        if not max and vehicle then
            local inferred = inferVehicleType(vehicle)
            if inferred then max = getConfigMaxHP(inferred) end
        end
        return cur, max, "remote"
    end
    -- 2) fall back to any ValueBase we tracked
    local primary = VehicleHealth.trackedValues[1]
    if primary then
        local ok, v = pcall(function() return primary.instance.Value end)
        if ok and type(v) == "number" then return v, primary.max, "value" end
    end
    -- 3) fall back to config max only (no live reading possible)
    if vehicle then
        local inferred = inferVehicleType(vehicle)
        if inferred then
            local m = getConfigMaxHP(inferred)
            if m then return nil, m, "config" end
        end
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
    label.Size = UDim2.new(0, 300, 0, 78)
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
        if lp and lp:FindFirstChildOfClass("PlayerGui") then gui.Parent = lp:FindFirstChildOfClass("PlayerGui") end
    end

    self.hudGui = gui
    self.hudLabel = label

    if not self.hudConn then
        self.hudConn = game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
            if not processed and input.KeyCode == HUD_TOGGLE_KEY then
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

    local cur, max, source = readHP(vehicle)
    local line2, color
    if type(cur) == "number" then
        max = (type(max) == "number" and max > 0) and max or cur
        local pct = math.clamp(cur / max, 0, 1)
        line2 = string.format("HP: %d / %d (%d%%) [%s]", math.floor(cur), math.floor(max), math.floor(pct*100), source)
        if pct > 0.6 then color = Color3.fromRGB(90, 255, 120)
        elseif pct > 0.3 then color = Color3.fromRGB(255, 220, 80)
        else color = Color3.fromRGB(255, 90, 90) end
    elseif type(max) == "number" then
        line2 = string.format("HP: -- / %d (waiting) [%s]", math.floor(max), source)
        color = Color3.fromRGB(200, 200, 200)
    else
        line2 = "HP: waiting for remote data..."
        color = Color3.fromRGB(255, 180, 120)
    end

    self.hudLabel.Text = "VEHICLE: " .. getDisplayName(vehicle) .. "\n" .. line2 .. "\nGOD: " .. (self.enabled and "ON" or "OFF")
    self.hudLabel.TextColor3 = color
end

-- =========================================================
-- HEAL — remote + ValueBases
-- =========================================================
function VehicleHealth:heal()
    -- ValueBase healing
    for _, entry in ipairs(self.trackedValues) do
        pcall(function()
            if entry.instance and entry.instance.Parent then
                if entry.instance.Value < entry.max then
                    entry.instance.Value = entry.max
                end
            end
        end)
    end
    -- Remote payload healing
    if hpState.table_ref and hpState.field and hpState.max then
        pcall(function()
            local cur = hpState.table_ref[hpState.field]
            if type(cur) == "number" and cur < hpState.max then
                hpState.table_ref[hpState.field] = hpState.max
            end
        end)
    end
end

-- =========================================================
-- UPDATE (called from Heartbeat in the main script)
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
    local cur, max = readHP(vehicle)
    if type(cur) == "number" then
        return string.format("%s | HP: %d/%s", self.vehicleName or "?", math.floor(cur), max and math.floor(max) or "?")
    end
    return (self.vehicleName or "?") .. " | waiting for remote"
end

function VehicleHealth:cleanup()
    self:clearListeners()
    self.currentVehicle = nil
    self.vehicleName = nil
    self.trackedValues = {}
    self.lastStatus = "Disabled"
end

return VehicleHealth
