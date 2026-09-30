-- Vehicle Health Module
-- Reads the vehicle the player is in, protects it from damage, and prevents explosions
-- Handles multiple vehicle architectures (Roblox Seats, welded mounts, Attributes, ValueBases, Humanoids, sub-components)

local VehicleHealth = {}

VehicleHealth.enabled = false
VehicleHealth.currentVehicle = nil
VehicleHealth.vehicleName = nil
VehicleHealth.trackedValues = {} -- Array of { obj = Instance, max = number, isAttribute = bool, attrName = string }
VehicleHealth.connections = {}
VehicleHealth.lastStatus = "Disabled"

-- Helper to find the actual player character
local function getCharacter(localPlayer)
    if not localPlayer then
        return nil
    end

    if localPlayer.Character and localPlayer.Character.Parent then
        return localPlayer.Character
    end

    local camera = workspace.CurrentCamera

    -- 1. Try CameraSubject if it's a Humanoid
    if camera and camera.CameraSubject and camera.CameraSubject:IsA("Humanoid") then
        local parentModel = camera.CameraSubject.Parent
        if parentModel and parentModel:IsA("Model") then
            return parentModel
        end
    end

    -- 2. Try Players:GetPlayerFromCharacter
    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") then
            local ok, p = pcall(game.Players.GetPlayerFromCharacter, game.Players, model)
            if ok and p == localPlayer then
                return model
            end
        end
    end

    local liveFolder = workspace:FindFirstChild("Live")
    if liveFolder then
        local liveChar = liveFolder:FindFirstChild(localPlayer.Name)
        if liveChar then
            return liveChar
        end
        for _, model in ipairs(liveFolder:GetChildren()) do
            if model:IsA("Model") then
                local ok, p = pcall(game.Players.GetPlayerFromCharacter, game.Players, model)
                if ok and p == localPlayer then
                    return model
                end
            end
        end
    end

    -- 3. Camera proximity fallback for BRM5 "Male" models
    if camera then
        local bestModel = nil
        local bestDist = 10
        local searchFolders = {liveFolder, workspace}
        for _, folder in ipairs(searchFolders) do
            if folder then
                for _, model in ipairs(folder:GetChildren()) do
                    if model:IsA("Model") and (model.Name == "Male" or model.Name == localPlayer.Name) and model:FindFirstChildOfClass("Humanoid") then
                        local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
                        if head then
                            local dist = (head.Position - camera.CFrame.Position).Magnitude
                            if dist < bestDist then
                                bestDist = dist
                                bestModel = model
                            end
                        end
                    end
                end
            end
        end
        if bestModel then
            return bestModel
        end
    end

    return workspace:FindFirstChild(localPlayer.Name)
end

-- Helper to determine the top-level vehicle model from any part or seat
local function findVehicleRoot(instance)
    if not instance then
        return nil
    end

    local current = instance
    local lastModel = nil

    while current and current ~= workspace and current ~= workspace:FindFirstChild("Live") do
        if current:IsA("Model") then
            local isPlayerModel = game.Players:GetPlayerFromCharacter(current) ~= nil or current.Name == "Male"
            if not isPlayerModel then
                lastModel = current
            end
        end
        current = current.Parent
    end

    return lastModel
end

-- Checks if a model looks like a vehicle (has seats, chassis, wheels, engine, or vehicle keywords)
local function isLikelyVehicle(model)
    if not model or not model:IsA("Model") then
        return false
    end

    if model.Name == "Male" or game.Players:GetPlayerFromCharacter(model) ~= nil then
        return false
    end

    local name = model.Name:lower()
    local keywords = {"stryker", "vehicle", "m1126", "heli", "blackhawk", "truck", "car", "jeep", "tank", "btr", "boat", "plane", "uh-60", "ch-47", "mi-17"}
    for _, kw in ipairs(keywords) do
        if name:find(kw) then
            return true
        end
    end

    if model:FindFirstChildOfClass("VehicleSeat") or model:FindFirstChildOfClass("Seat") then
        return true
    end

    if model:FindFirstChild("Body") or model:FindFirstChild("Chassis") or model:FindFirstChild("Engine") or model:FindFirstChild("Seats") then
        return true
    end

    for _, desc in ipairs(model:GetChildren()) do
        if desc:IsA("VehicleSeat") or desc:IsA("Seat") then
            return true
        end
        if desc.Name == "Seats" or desc.Name == "Chassis" or desc.Name == "Interior" or desc.Name == "DriveSeat" then
            return true
        end
    end

    return false
end

-- Dedicated finder for the single Stryker in the server
local function findStrykerInGame()
    -- 1. Direct search for Stryker / M1126 model
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("Model") and desc.Name ~= "Male" and game.Players:GetPlayerFromCharacter(desc) == nil then
            local n = desc.Name:lower()
            if n:find("stryker") or n:find("m1126") or n:find("icv") then
                return desc
            end
        end
    end

    -- 2. Search for any part/mesh/folder named with stryker or m1126
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("Folder") or desc:IsA("Configuration") then
            local n = desc.Name:lower()
            if n:find("stryker") or n:find("m1126") then
                local veh = findVehicleRoot(desc)
                if veh then
                    return veh
                end
            end
        end
    end

    -- 3. Search for any vehicle model with a VehicleSeat or DriveSeat
    local searchContainers = {workspace:FindFirstChild("Live"), workspace:FindFirstChild("Vehicles"), workspace}
    for _, container in ipairs(searchContainers) do
        if container then
            for _, obj in ipairs(container:GetChildren()) do
                if obj:IsA("Model") and obj.Name ~= "Male" and game.Players:GetPlayerFromCharacter(obj) == nil then
                    if obj:FindFirstChildOfClass("VehicleSeat") or obj:FindFirstChild("DriveSeat") or obj:FindFirstChild("Chassis") then
                        return obj
                    end
                end
            end
        end
    end

    return nil
end

-- Attempts to find the vehicle model the player is in through multiple detection methods
local function getPlayerVehicle(localPlayer)
    -- Priority: Lock directly onto the server's Stryker
    local serverStryker = findStrykerInGame()
    if serverStryker then
        return serverStryker
    end

    local camera = workspace.CurrentCamera

    -- Method 0: Check Camera.CameraSubject (most reliable in Roblox vehicles)
    if camera and camera.CameraSubject then
        local subj = camera.CameraSubject
        local veh = findVehicleRoot(subj)
        if veh and isLikelyVehicle(veh) then
            return veh
        end
        local subjModel = subj:FindFirstAncestorOfClass("Model")
        if subjModel and isLikelyVehicle(subjModel) then
            return subjModel
        end
    end

    local character = getCharacter(localPlayer)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso") or character:FindFirstChild("Root") or character:FindFirstChild("Head"))

    -- Method 1: Humanoid.SitPart (Standard Roblox Seating)
    if humanoid and humanoid.SitPart then
        local veh = findVehicleRoot(humanoid.SitPart)
        if veh then
            return veh
        end
    end

    -- Method 2: Check SeatPart alias if present
    if humanoid then
        local ok, seatPart = pcall(function() return humanoid.SeatPart end)
        if ok and seatPart then
            local veh = findVehicleRoot(seatPart)
            if veh then
                return veh
            end
        end
    end

    -- Method 3: Check Welds / WeldConstraints / Motor6Ds attached to character parts
    if character then
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") then
                for _, child in ipairs(part:GetChildren()) do
                    if child:IsA("Weld") or child:IsA("WeldConstraint") or child:IsA("Motor6D") then
                        local other = (child.Part0 == part) and child.Part1 or child.Part0
                        if other and other:IsDescendantOf(workspace) and not other:IsDescendantOf(character) then
                            local veh = findVehicleRoot(other)
                            if veh and isLikelyVehicle(veh) then
                                return veh
                            end
                        end
                    end
                end
            end
        end
    end

    -- Method 4: Scan workspace seats for Occupant == humanoid
    if humanoid then
        local function checkSeatsInFolder(folder)
            if not folder then return nil end
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and isLikelyVehicle(obj) then
                    for _, desc in ipairs(obj:GetDescendants()) do
                        if (desc:IsA("Seat") or desc:IsA("VehicleSeat")) and desc.Occupant == humanoid then
                            return obj
                        end
                    end
                end
            end
            return nil
        end

        local seatOccupantVeh = checkSeatsInFolder(workspace:FindFirstChild("Live")) or checkSeatsInFolder(workspace)
        if seatOccupantVeh then
            return seatOccupantVeh
        end
    end

    -- Method 5: Proximity / Bounding Box Check from Character or Camera
    local checkPos = rootPart and rootPart.Position or (camera and camera.CFrame.Position)
    if checkPos then
        local function checkProximityInFolder(folder)
            if not folder then return nil end
            local bestVeh = nil
            local bestDist = 18
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and isLikelyVehicle(obj) then
                    local ok, cframe, size = pcall(function() return obj:GetBoundingBox() end)
                    if ok and cframe and size then
                        local relPos = cframe:PointToObjectSpace(checkPos)
                        local halfSize = size / 2 + Vector3.new(4, 6, 4)
                        if math.abs(relPos.X) <= halfSize.X and math.abs(relPos.Y) <= halfSize.Y and math.abs(relPos.Z) <= halfSize.Z then
                            return obj
                        end
                        local centerDist = (cframe.Position - checkPos).Magnitude
                        if centerDist < bestDist then
                            bestDist = centerDist
                            bestVeh = obj
                        end
                    end
                end
            end
            return bestVeh
        end

        local proxVeh = checkProximityInFolder(workspace:FindFirstChild("Live")) or checkProximityInFolder(workspace)
        if proxVeh then
            return proxVeh
        end
    end

    return nil
end

-- Checks if a name indicates vehicle health
local function isHealthName(name)
    local n = name:lower():gsub("[%s_%-]", "")
    return n == "health"
        or n == "hp"
        or n == "vehiclehealth"
        or n == "curhealth"
        or n == "currenthealth"
        or n == "hull"
        or n == "hullhealth"
        or n == "enginehealth"
        or n == "armor"
        or n == "armour"
        or n == "durability"
end

-- Checks if a name indicates max health
local function isMaxHealthName(name)
    local n = name:lower():gsub("[%s_%-]", "")
    return n == "maxhealth"
        or n == "maxhp"
        or n == "fullhealth"
        or n == "maxhull"
        or n == "maxhullhealth"
        or n == "maxengine"
        or n == "maxarmor"
end

-- Clears active listeners
function VehicleHealth:clearListeners()
    for _, conn in ipairs(self.connections) do
        pcall(function() conn:Disconnect() end)
    end
    self.connections = {}
end

-- Finds all health components (Attributes, ValueBases, Humanoid) within the vehicle
function VehicleHealth:bindHealthObjects(vehicle)
    self:clearListeners()
    self.trackedValues = {}

    local detectedMax = nil

    -- 1. Scan attributes on the vehicle model itself
    local attrs = vehicle:GetAttributes()
    for attrName, attrValue in pairs(attrs) do
        if type(attrValue) == "number" then
            if isMaxHealthName(attrName) then
                detectedMax = attrValue
            end
        end
    end

    for attrName, attrValue in pairs(attrs) do
        if type(attrValue) == "number" and isHealthName(attrName) then
            local maxVal = detectedMax or (attrValue > 0 and attrValue or 1000)
            table.insert(self.trackedValues, {
                isAttribute = true,
                attrName = attrName,
                instance = vehicle,
                max = maxVal,
                current = attrValue
            })

            -- Hook attribute change for instant healing
            local conn = vehicle:GetAttributeChangedSignal(attrName):Connect(function()
                if self.enabled then
                    local cur = vehicle:GetAttribute(attrName)
                    if type(cur) == "number" and cur < maxVal then
                        pcall(function() vehicle:SetAttribute(attrName, maxVal) end)
                    end
                end
            end)
            table.insert(self.connections, conn)
        end
    end

    -- 2. Scan ValueBase descendants (Health, HP, Hull, Armor, Engine, etc.)
    -- First pass: find any explicit max health values
    for _, desc in ipairs(vehicle:GetDescendants()) do
        if desc:IsA("NumberValue") or desc:IsA("IntValue") or desc:IsA("DoubleConstrainedValue") then
            if isMaxHealthName(desc.Name) and desc.Value > 0 then
                detectedMax = desc.Value
            end
        end
    end

    -- Second pass: track all health-related values
    for _, desc in ipairs(vehicle:GetDescendants()) do
        if desc:IsA("NumberValue") or desc:IsA("IntValue") or desc:IsA("DoubleConstrainedValue") then
            if isHealthName(desc.Name) then
                local maxVal = detectedMax or (desc.Value > 0 and desc.Value or 1000)
                table.insert(self.trackedValues, {
                    isAttribute = false,
                    instance = desc,
                    max = maxVal,
                    current = desc.Value
                })

                -- Hook property change for immediate 0-delay restoration
                local conn = desc:GetPropertyChangedSignal("Value"):Connect(function()
                    if self.enabled and desc.Value < maxVal then
                        pcall(function() desc.Value = maxVal end)
                    end
                end)
                table.insert(self.connections, conn)
            end
        end
    end

    -- 3. Check for Humanoid inside vehicle (some vehicle systems use a Humanoid for health)
    for _, desc in ipairs(vehicle:GetDescendants()) do
        if desc:IsA("Humanoid") and desc.Parent ~= vehicle:FindFirstAncestorOfClass("Model") then
            local maxVal = desc.MaxHealth > 0 and desc.MaxHealth or 1000
            table.insert(self.trackedValues, {
                isHumanoid = true,
                instance = desc,
                max = maxVal,
                current = desc.Health
            })

            local conn = desc:GetPropertyChangedSignal("Health"):Connect(function()
                if self.enabled and desc.Health < desc.MaxHealth then
                    pcall(function() desc.Health = desc.MaxHealth end)
                end
            end)
            table.insert(self.connections, conn)
        end
    end

    return #self.trackedValues > 0
end

-- Scans the vehicle the player is currently in and caches health references
function VehicleHealth:scanVehicle(localPlayer)
    local vehicle = getPlayerVehicle(localPlayer)
    if not vehicle then
        self:cleanup()
        self.lastStatus = "No vehicle detected"
        return false
    end

    if vehicle == self.currentVehicle and #self.trackedValues > 0 then
        return true -- Already actively protecting this vehicle
    end

    self.currentVehicle = vehicle
    self.vehicleName = vehicle.Name

    local hasHealth = self:bindHealthObjects(vehicle)
    if hasHealth then
        self.lastStatus = self.vehicleName .. " | Protected"
        return true
    else
        -- Vehicle detected, but no explicit health values found (still protect wheels/seats)
        self.lastStatus = self.vehicleName .. " (No HP bar - Active)"
        return true
    end
end

-- The core heal loop: resets all tracked health objects to max
function VehicleHealth:heal()
    if not self.enabled or not self.currentVehicle then
        return
    end

    for _, entry in ipairs(self.trackedValues) do
        pcall(function()
            if entry.isAttribute then
                local cur = entry.instance:GetAttribute(entry.attrName)
                entry.current = cur
                if type(cur) == "number" and cur < entry.max then
                    entry.instance:SetAttribute(entry.attrName, entry.max)
                end
            elseif entry.isHumanoid then
                entry.current = entry.instance.Health
                if entry.instance.Health < entry.instance.MaxHealth then
                    entry.instance.Health = entry.instance.MaxHealth
                end
            elseif entry.instance and entry.instance.Parent then
                entry.current = entry.instance.Value
                if entry.instance.Value < entry.max then
                    entry.instance.Value = entry.max
                end
            end
        end)
    end
end

-- Update function called every frame from the main heartbeat loop
function VehicleHealth:update(localPlayer)
    if not self.enabled then
        return
    end

    if not self.currentVehicle or not self.currentVehicle.Parent then
        self:scanVehicle(localPlayer)
    else
        -- Verify player is still in the same vehicle
        local currentVeh = getPlayerVehicle(localPlayer)
        if currentVeh ~= self.currentVehicle then
            self:scanVehicle(localPlayer)
        end
    end

    self:heal()
end

-- Returns a formatted status string for the GUI
function VehicleHealth:getStatus()
    if not self.enabled then
        return "Disabled"
    end

    if not self.currentVehicle then
        return "No vehicle detected (Sit in vehicle)"
    end

    if #self.trackedValues > 0 then
        local primary = self.trackedValues[1]
        local cur = "?"
        pcall(function()
            if primary.isAttribute then
                cur = tostring(math.floor(primary.instance:GetAttribute(primary.attrName)))
            elseif primary.isHumanoid then
                cur = tostring(math.floor(primary.instance.Health))
            else
                cur = tostring(math.floor(primary.instance.Value))
            end
        end)
        return self.vehicleName .. " | HP: " .. cur .. "/" .. tostring(math.floor(primary.max))
    end

    return self.vehicleName .. " | Locked & Active"
end

-- Full cleanup of references and signals
function VehicleHealth:cleanup()
    self:clearListeners()
    self.currentVehicle = nil
    self.vehicleName = nil
    self.trackedValues = {}
    self.lastStatus = "Disabled"
end

return VehicleHealth
