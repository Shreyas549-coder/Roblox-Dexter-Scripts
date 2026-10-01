-- BRM5 v7.0 PVE Standalone Bundled Script
-- Made by: Shreyas549-coder
-- Can be executed directly in Xeno or any executor without external HTTP dependencies!

local __MODULES__ = {}

-- ==================== MODULE: services ====================
__MODULES__["services"] = (function()
-- Services Module
-- Provides access to Roblox game services

local Services = {}

Services.Players = game:GetService("Players")
Services.RunService = game:GetService("RunService")
Services.UserInputService = game:GetService("UserInputService")
Services.GuiService = game:GetService("GuiService")
Services.Workspace = game:GetService("Workspace")
Services.TweenService = game:GetService("TweenService")
Services.ReplicatedStorage = game:GetService("ReplicatedStorage")
Services.Lighting = game:GetService("Lighting")

-- Quick access to common objects
Services.localPlayer = Services.Players.LocalPlayer
Services.camera = Services.Workspace.CurrentCamera

return Services

end)()

-- ==================== MODULE: config ====================
__MODULES__["config"] = (function()
-- Configuration Module
-- Contains all settings, constants, and state variables

local Config = {}
local HttpService = game:GetService("HttpService")

-- CONSTANTS
Config.RAYCAST_COOLDOWN = 0.2
Config.MARKER_MAX_PER_STEP = 12
Config.TARGET_SYNC_INTERVAL = 0.25
Config.NPC_REFRESH_INTERVAL = 0.5
Config.TARGET_BOX_SIZE = Vector3.new(15, 15, 15) -- Size of the adjusted target bounds
Config.MAX_NPC_DETECTION_RADIUS = 3000
Config.npcDetectionRadius = Config.MAX_NPC_DETECTION_RADIUS
Config.CONFIG_FILE = "brm5_pve_config.json"

-- TOGGLES (State)
Config.highlightEnabled = false  -- Visibility markers
Config.sizingEnabled = false     -- Target sizing
Config.showTargetBox = false     -- Shows target bounds
Config.fullBrightEnabled = false -- Removes shadows/darkness
Config.guiVisible = true         -- Menu visibility
Config.isUnloaded = false        -- To stop the script

-- WEAPON PATCHES
Config.patchOptions = { 
    recoil = false, 
    firemodes = false 
}

-- COLORS (RGB: 0 to 255)
Config.visibleR, Config.visibleG, Config.visibleB = 0, 255, 0    -- Green for visible targets
Config.hiddenR, Config.hiddenG, Config.hiddenB = 255, 0, 0       -- Red for occluded targets
Config.visibleColor = Color3.fromRGB(Config.visibleR, Config.visibleG, Config.visibleB)
Config.hiddenColor = Color3.fromRGB(Config.hiddenR, Config.hiddenG, Config.hiddenB)

-- Update color function
function Config:updateVisibleColor(r, g, b)
    if r then self.visibleR = r end
    if g then self.visibleG = g end
    if b then self.visibleB = b end
    self.visibleColor = Color3.fromRGB(self.visibleR, self.visibleG, self.visibleB)
end

function Config:updateHiddenColor(r, g, b)
    if r then self.hiddenR = r end
    if g then self.hiddenG = g end
    if b then self.hiddenB = b end
    self.hiddenColor = Color3.fromRGB(self.hiddenR, self.hiddenG, self.hiddenB)
end

function Config:updateNPCDetectionRadius(value)
    self.npcDetectionRadius = math.clamp(
        math.floor(value or self.npcDetectionRadius),
        0,
        self.MAX_NPC_DETECTION_RADIUS
    )
end

function Config:isNPCDetectionEnabled()
    return self.sizingEnabled or self.showTargetBox or self.highlightEnabled
end

function Config:serialize()
    return {
        highlightEnabled = self.highlightEnabled,
        sizingEnabled = self.sizingEnabled,
        showTargetBox = self.showTargetBox,
        fullBrightEnabled = self.fullBrightEnabled,
        npcDetectionRadius = self.npcDetectionRadius,
        patchOptions = {
            recoil = self.patchOptions.recoil,
            firemodes = self.patchOptions.firemodes
        },
        visibleR = self.visibleR,
        visibleG = self.visibleG,
        visibleB = self.visibleB,
        hiddenR = self.hiddenR,
        hiddenG = self.hiddenG,
        hiddenB = self.hiddenB
    }
end

function Config:applySavedData(data)
    if type(data) ~= "table" then
        return
    end

    if data.highlightEnabled ~= nil then self.highlightEnabled = data.highlightEnabled end
    if data.sizingEnabled ~= nil then self.sizingEnabled = data.sizingEnabled end
    if data.showTargetBox ~= nil then self.showTargetBox = data.showTargetBox end
    if data.fullBrightEnabled ~= nil then self.fullBrightEnabled = data.fullBrightEnabled end
    if type(data.patchOptions) == "table" then
        if data.patchOptions.recoil ~= nil then self.patchOptions.recoil = data.patchOptions.recoil end
        if data.patchOptions.firemodes ~= nil then self.patchOptions.firemodes = data.patchOptions.firemodes end
    end

    self:updateVisibleColor(data.visibleR, data.visibleG, data.visibleB)
    self:updateHiddenColor(data.hiddenR, data.hiddenG, data.hiddenB)
    self:updateNPCDetectionRadius(data.npcDetectionRadius)
end

function Config:save()
    if type(writefile) ~= "function" then
        return false
    end

    local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, self:serialize())
    if not okEncode then
        return false
    end

    local okWrite = pcall(writefile, self.CONFIG_FILE, encoded)
    return okWrite
end

function Config:load()
    if type(isfile) ~= "function" or type(readfile) ~= "function" or not isfile(self.CONFIG_FILE) then
        return false
    end

    local okRead, raw = pcall(readfile, self.CONFIG_FILE)
    if not okRead or type(raw) ~= "string" or raw == "" then
        return false
    end

    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not okDecode then
        return false
    end

    self:applySavedData(data)
    return true
end

return Config

end)()

-- ==================== MODULE: npc_manager ====================
__MODULES__["npc_manager"] = (function()
-- NPC Manager Module
-- Handles detection and tracking of enemy NPCs

local NPCManager = {}
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

NPCManager.activeNPCs = {}      -- List of enemies currently in the game
NPCManager.wallConnections = {} -- List of connections to clean up later
NPCManager.modelConnections = {} -- Per-model connections for delayed NPC detection

-- Finds the main part of a character (Root)
function NPCManager.getRootPart(model)
    return model:FindFirstChild("Root") or 
           model:FindFirstChild("HumanoidRootPart") or 
           model:FindFirstChild("UpperTorso")
end

function NPCManager:getDetectionOrigin(workspace)
    local character = localPlayer and localPlayer.Character
    local root = character and self.getRootPart(character)
    if root then
        return root.Position
    end

    local camera = workspace and workspace.CurrentCamera
    return camera and camera.CFrame.Position or nil
end

function NPCManager:isWithinDetectionRadius(model, workspace, config)
    if not config then
        return true
    end

    local origin = self:getDetectionOrigin(workspace)
    if not origin then
        return true
    end

    local root = self.getRootPart(model) or model:FindFirstChild("Head")
    local targetPosition = root and root.Position or model:GetPivot().Position
    return (targetPosition - origin).Magnitude <= (config.npcDetectionRadius or math.huge)
end

-- Gets all valid NPC models from Workspace.Model children.
function NPCManager:getNPCModels(container, workspace, config)
    if not (config and config.isNPCDetectionEnabled and config:isNPCDetectionEnabled()) then
        return {}
    end

    if not container or not container:IsA("Model") then
        return {}
    end

    if container.Name ~= "Model" then
        return {}
    end

    local npcs = {}
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Model") then
            if child.Name == "NPCS" then
                if self:isWithinDetectionRadius(child, workspace, config) then
                    table.insert(npcs, child)
                end
            elseif child.Name == "Male" then
                local hasBillboard = child:FindFirstChildOfClass("BillboardGui") ~= nil
                if not hasBillboard and self:isWithinDetectionRadius(child, workspace, config) then
                    child.Name = "NPCS"
                    table.insert(npcs, child)
                end
            end
        end
    end

    return npcs
end

-- Checks if the container matches the new NPC structure
function NPCManager:isNPCModel(container, workspace, config)
    return #self:getNPCModels(container, workspace, config) > 0
end

-- Adds a specific NPC model to our tracking list
function NPCManager:addNPCModel(npc, container, markerModule, config)
    if not npc or self.activeNPCs[npc] then
        return
    end
    local head = npc:FindFirstChild("Head")
    local root = self.getRootPart(npc)
    
    if not head or not root then 
        return 
    end
    
    self.activeNPCs[npc] = { head = head, root = root, character = npc, container = container }
    
    -- Create marker box if visibility markers are enabled
    if markerModule and markerModule.isEnabled() then
        markerModule.createBoxForPart(head, config)
    end
end

-- Adds all valid NPCs under a container
function NPCManager:addNPC(container, workspace, markerModule, config)
    local npcs = self:getNPCModels(container, workspace, config)
    if #npcs == 0 then
        return
    end

    for _, npc in ipairs(npcs) do
        self:addNPCModel(npc, container, markerModule, config)
    end
end

-- Tracks a model and waits for Male if it appears later
function NPCManager:trackPotentialNPC(container, workspace, markerModule, config)
    if not (config and config.isNPCDetectionEnabled and config:isNPCDetectionEnabled()) then
        return
    end

    local npcs = self:getNPCModels(container, workspace, config)
    local hasUntracked = false
    for _, npc in ipairs(npcs) do
        if not self.activeNPCs[npc] then
            hasUntracked = true
            break
        end
    end
    if #npcs > 0 and not hasUntracked then
        return
    end
    if #npcs > 0 then
        self:addNPC(container, workspace, markerModule, config)
        return
    end
    if not container:IsA("Model") then
        return
    end
    if container.Name ~= "Model" or self.modelConnections[container] then
        return
    end

    local connection
    connection = container.ChildAdded:Connect(function(child)
        if child:IsA("Model") and (child.Name == "Male" or child.Name == "NPCS") then
            self:addNPC(container, workspace, markerModule, config)
        end
    end)
    self.modelConnections[container] = connection
end

-- Removes an NPC from tracking
function NPCManager:removeNPC(model)
    self.activeNPCs[model] = nil
end

-- Gets all active NPCs
function NPCManager:getActiveNPCs()
    return self.activeNPCs
end

function NPCManager:removeNPCModel(model, markerModule, targetSizing)
    local data = self.activeNPCs[model]
    if not data then
        return
    end

    if targetSizing then
        targetSizing:restoreOriginalSize(model, self)
    end
    if markerModule and data.head then
        markerModule.destroyBoxForPart(data.head)
    end

    self.activeNPCs[model] = nil
end

function NPCManager:refreshTrackedNPCs(workspace, markerModule, targetSizing, config)
    if not (config and config.isNPCDetectionEnabled and config:isNPCDetectionEnabled()) then
        local trackedModels = {}
        for model, _ in pairs(self.activeNPCs) do
            table.insert(trackedModels, model)
        end
        for _, model in ipairs(trackedModels) do
            self:removeNPCModel(model, markerModule, targetSizing)
        end
        return
    end

    local modelsToRemove = {}
    for model, _ in pairs(self.activeNPCs) do
        if not model.Parent or not self:isWithinDetectionRadius(model, workspace, config) then
            table.insert(modelsToRemove, model)
        end
    end
    for _, model in ipairs(modelsToRemove) do
        self:removeNPCModel(model, markerModule, targetSizing)
    end

    for _, container in ipairs(workspace:GetChildren()) do
        if container:IsA("Model") and container.Name == "Model" then
            self:trackPotentialNPC(container, workspace, markerModule, config)
        end
    end
end

-- Scans workspace for existing NPCs
function NPCManager:scanWorkspace(workspace, markerModule, config)
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m.Name == "Model" then 
            self:trackPotentialNPC(m, workspace, markerModule, config)
        end
    end
end

-- Sets up listener for new NPCs
function NPCManager:setupListener(workspace, markerModule, config)
    local connection = workspace.ChildAdded:Connect(function(m)
        if m:IsA("Model") and m.Name == "Model" then 
            task.delay(0.2, function() 
                self:trackPotentialNPC(m, workspace, markerModule, config)
            end) 
        end
    end)
    
    table.insert(self.wallConnections, connection)
end

-- Cleanup all connections
function NPCManager:cleanup()
    for _, c in ipairs(self.wallConnections) do 
        pcall(function() c:Disconnect() end) 
    end
    self.wallConnections = {}
    for _, c in pairs(self.modelConnections) do
        pcall(function() c:Disconnect() end)
    end
    self.modelConnections = {}
    self.activeNPCs = {}
end

return NPCManager

end)()

-- ==================== MODULE: silent ====================
__MODULES__["silent"] = (function()
-- Target Sizing Module
-- Handles adjustment of NPC target bounds for visibility/testing

local TargetSizing = {}

TargetSizing.originalSizes = {} -- Storage for original sizes to restore them later

-- Adjusts the NPC target bounds
function TargetSizing:applyTargetSizing(model, root, config)
    if not self.originalSizes[model] then 
        self.originalSizes[model] = root.Size 
    end
    
    if root.Size ~= config.TARGET_BOX_SIZE then
        root.Size = config.TARGET_BOX_SIZE
    end
    local targetTransparency = config.showTargetBox and 0.85 or 1
    if root.Transparency ~= targetTransparency then
        root.Transparency = targetTransparency -- If showTargetBox is true, you'll see a faint target box
    end
    if not root.CanCollide then
        root.CanCollide = true
    end
end

-- Restores target bounds to their normal size
function TargetSizing:restoreOriginalSize(model, npcManager)
    local data = npcManager:getActiveNPCs()[model]
    local root = data and data.root
    if not root then
        local character = data and data.character
        root = character and npcManager.getRootPart(character) or npcManager.getRootPart(model)
    end
    if root and self.originalSizes[model] then
        root.Size = self.originalSizes[model]
        root.Transparency = 1
        root.CanCollide = false
    end
    self.originalSizes[model] = nil
end

-- Updates target bounds for all NPCs based on config
function TargetSizing:updateAllTargets(npcManager, config)
    if not config.sizingEnabled then
        if next(self.originalSizes) then
            self:cleanup(npcManager)
        end
        return
    end
    for model, data in pairs(npcManager:getActiveNPCs()) do
        if data.root then
            self:applyTargetSizing(model, data.root, config)
        end
    end
end

-- Cleanup all adjusted target bounds
function TargetSizing:cleanup(npcManager)
    for model, _ in pairs(self.originalSizes) do
        self:restoreOriginalSize(model, npcManager)
    end
end

return TargetSizing

end)()

-- ==================== MODULE: walls ====================
__MODULES__["walls"] = (function()

local Markers = {}

Markers.trackedParts = {} -- List of body parts we are watching
Markers.enabled = false
Markers.boxTransparency = 0.3

local function ensureBox(part, color)
    local box = part:FindFirstChild("Marker_Box")
    if box then
        box.Color3 = color
        return box
    end

    local box = Instance.new("BoxHandleAdornment")
    box.Name = "Marker_Box"
    box.Size = part.Size + Vector3.new(0.1, 0.1, 0.1)
    box.Adornee = part
    box.AlwaysOnTop = true
    box.ZIndex = 10
    box.Color3 = color
    box.Transparency = Markers.boxTransparency
    box.Parent = part

    return box
end

function Markers.createBoxForPart(part, config)
    if not part then
        return
    end

    ensureBox(part, (config and config.visibleColor) or Color3.fromRGB(0, 255, 0))
    Markers.trackedParts[part] = true
end

function Markers.destroyBoxForPart(part)
    if not part then
        return
    end

    local box = part:FindFirstChild("Marker_Box")
    if box then
        pcall(function() box:Destroy() end)
    end
    Markers.trackedParts[part] = nil
end

-- Removes all marker boxes
function Markers.destroyAllBoxes()
    for part, _ in pairs(Markers.trackedParts) do
        if part then
            local box = part:FindFirstChild("Marker_Box")
            if box then
                pcall(function() box:Destroy() end)
            end
        end
    end
    Markers.trackedParts = {}
end

-- Updates marker colors based on line of sight
function Markers.updateColors(npcManager, camera, workspace, localPlayer, config)
    if not Markers.enabled then 
        return 
    end
    camera = camera or (workspace and workspace.CurrentCamera)
    if not camera or not localPlayer then
        return
    end
    local character = localPlayer.Character
    if not character and camera.CameraSubject then
        character = camera.CameraSubject:FindFirstAncestorOfClass("Model")
    end

    local processed = 0
    local maxPerStep = config.MARKER_MAX_PER_STEP or 12
    local origin = camera.CFrame.Position

    for model, data in pairs(npcManager:getActiveNPCs()) do
        if processed >= maxPerStep then
            break
        end
        if data.head and data.head:FindFirstChild("Marker_Box") then
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Blacklist
            rp.FilterDescendantsInstances = character and {character, data.head} or {data.head}

            local result = workspace:Raycast(origin, data.head.Position - origin, rp)
            local isVisible = (not result or result.Instance:IsDescendantOf(model))
            data.head.Marker_Box.Color3 = isVisible
                and config.visibleColor
                or config.hiddenColor
            data.head.Marker_Box.Transparency = Markers.boxTransparency
            processed = processed + 1
        end
    end
end

-- Enables visibility markers
function Markers.enable(npcManager, config)
    Markers.enabled = true
    for _, data in pairs(npcManager:getActiveNPCs()) do 
        Markers.createBoxForPart(data.head, config) 
    end
end

-- Disables visibility markers
function Markers.disable()
    Markers.enabled = false
    Markers.destroyAllBoxes()
end

-- Check if markers are enabled
function Markers.isEnabled()
    return Markers.enabled
end

return Markers

end)()

-- ==================== MODULE: fullbright ====================
__MODULES__["fullbright"] = (function()
-- Lighting Module
-- Controls game lighting for FullBright feature

local Lighting = {}

Lighting.originalLighting = {}
Lighting.fullBrightApplied = false

-- Stores original lighting settings
function Lighting:storeOriginalSettings(lightingService)
    self.originalLighting = {
        Brightness = lightingService.Brightness,
        ClockTime = lightingService.ClockTime,
        FogEnd = lightingService.FogEnd,
        GlobalShadows = lightingService.GlobalShadows,
        Ambient = lightingService.Ambient
    }
end

-- Applies FullBright (removes shadows and darkness)
function Lighting:applyFullBright(lightingService)
    lightingService.Brightness = 2
    lightingService.ClockTime = 12
    lightingService.FogEnd = 100000
    lightingService.GlobalShadows = false
    lightingService.Ambient = Color3.new(1, 1, 1)
    self.fullBrightApplied = true
end

-- Restores original lighting settings
function Lighting:restoreOriginal(lightingService)
    for property, value in pairs(self.originalLighting) do
        lightingService[property] = value
    end
    self.fullBrightApplied = false
end

-- Updates lighting based on config
function Lighting:update(lightingService, config)
    if config.fullBrightEnabled then
        self:applyFullBright(lightingService)
        return
    end
    if self.fullBrightApplied then
        self:restoreOriginal(lightingService)
    end
end

return Lighting

end)()

-- ==================== MODULE: norecoil ====================
__MODULES__["norecoil"] = (function()
-- Weapons Module
-- Handles weapon adjustments (Stability, Firemodes)

local Weapons = {}

-- Applies weapon patches (Stability and/or Firemodes)
function Weapons.patchWeapons(replicatedStorage, patchOptions)
    local weaponsFolder = replicatedStorage:FindFirstChild("Shared")
        and replicatedStorage.Shared:FindFirstChild("Configs")
        and replicatedStorage.Shared.Configs:FindFirstChild("Weapon")
        and replicatedStorage.Shared.Configs.Weapon:FindFirstChild("Weapons_Player")
    
    if not weaponsFolder then 
        return 
    end

    for _, platform in pairs(weaponsFolder:GetChildren()) do
        if platform.Name:match("^Platform_") then
            for _, weapon in pairs(platform:GetChildren()) do
                for _, child in pairs(weapon:GetChildren()) do
                    if child:IsA("ModuleScript") and child.Name:match("^Receiver%.") then
                        local success, receiver = pcall(require, child)
                        if success and receiver and receiver.Config and receiver.Config.Tune then
                            local tune = receiver.Config.Tune
                            
                        
                            if patchOptions.recoil then
                                tune.Recoil_X = 0 
                                tune.Recoil_Z = 0 
                                tune.RecoilForce_Tap = 0
                                tune.RecoilForce_Impulse = 0 
                                tune.Recoil_Range = Vector2.zero
                                tune.Recoil_Camera = 0 
                                tune.RecoilAccelDamp_Crouch = Vector3.new(1, 1, 1)
                                tune.RecoilAccelDamp_Prone = Vector3.new(1, 1, 1)
                            end
                            
                            -- Adjust Firemodes
                            if patchOptions.firemodes then 
                                tune.Firemodes = {3, 2, 1, 0} 
                            end
                        end
                    end
                end
            end
        end
    end
end

return Weapons

end)()

-- ==================== MODULE: gui ====================
__MODULES__["gui"] = (function()
-- GUI Module
-- Creates and manages the user interface

local GUI = {}

GUI.screenGui = nil
GUI.mainFrame = nil
GUI.modalOverlay = nil
GUI.cursorIndicator = nil
GUI.toggleButton = nil
GUI.tabButtons = {}
GUI.tabs = {}

-- Creates a new tab page
local function createTab(container)
    local f = Instance.new("ScrollingFrame", container)
    f.Size = UDim2.new(1, 0, 1, 0)
    f.BackgroundTransparency = 1
    f.Visible = false
    f.ScrollBarThickness = 2
    f.CanvasSize = UDim2.new(0, 0, 0, 0)
    f.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local l = Instance.new("UIListLayout", f)
    l.Padding = UDim.new(0, 12)
    l.HorizontalAlignment = Enum.HorizontalAlignment.Center
    l.SortOrder = Enum.SortOrder.LayoutOrder

    return f
end

-- Creates a toggle button
local function createButton(parent, text, initialActive, callback)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1, -10, 0, 35)
    btn.BackgroundColor3 = initialActive and Color3.fromRGB(85, 170, 255) or Color3.fromRGB(35, 35, 35)
    btn.Text = text
    btn.TextColor3 = initialActive and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
    btn.Font = "Gotham"
    btn.TextSize = 13
    Instance.new("UICorner", btn)
    
    local active = initialActive and true or false
    btn.MouseButton1Click:Connect(function()
        active = not active
        btn.BackgroundColor3 = active and Color3.fromRGB(85, 170, 255) or Color3.fromRGB(35, 35, 35)
        btn.TextColor3 = active and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
        callback(active)
    end)
end

-- Creates a label
local function createLabel(parent, text, color, layoutIndex)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size = UDim2.new(1, -10, 0, 30)
    lbl.Text = text
    lbl.TextColor3 = color
    lbl.Font = "GothamBold"
    lbl.BackgroundTransparency = 1
    if layoutIndex then
        lbl.LayoutOrder = layoutIndex
    end
    return lbl
end

local function createInfoLabel(parent, text)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size = UDim2.new(1, -10, 0, 74)
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(185, 185, 185)
    lbl.Font = "Gotham"
    lbl.TextSize = 12
    lbl.TextWrapped = true
    lbl.TextXAlignment = "Left"
    lbl.TextYAlignment = "Top"
    lbl.BackgroundTransparency = 1
    return lbl
end

local function updateToggleButtonText(button, isVisible)
    if button then
        button.Text = isVisible and "Hide GUI" or "Open GUI"
    end
end

-- Creates a slider
local function createSlider(parent, label, initialValue, maxValue, callback, layoutIndex, services)
    local f = Instance.new("Frame", parent)
    f.Size = UDim2.new(1, -10, 0, 50)
    f.BackgroundTransparency = 1
    if layoutIndex then
        f.LayoutOrder = layoutIndex
    end

    local l = Instance.new("TextLabel", f)
    l.Text = label .. ": " .. initialValue
    l.Size = UDim2.new(1, 0, 0, 20)
    l.TextColor3 = Color3.new(1, 1, 1)
    l.BackgroundTransparency = 1
    l.TextXAlignment = "Left"

    local bar = Instance.new("Frame", f)
    bar.Position = UDim2.new(0, 0, 0, 25)
    bar.Size = UDim2.new(1, 0, 0, 8)
    bar.BackgroundColor3 = Color3.fromRGB(45, 45, 45)

    local fill = Instance.new("Frame", bar)
    fill.Size = UDim2.new(maxValue > 0 and (initialValue / maxValue) or 0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(85, 170, 255)

    local dragging = false
    local function update()
        local mousePos = services.UserInputService:GetMouseLocation().X
        local p = math.clamp((mousePos - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local val = math.floor(p * maxValue)
        fill.Size = UDim2.new(p, 0, 1, 0)
        l.Text = label .. ": " .. val
        callback(val)
    end

    bar.InputBegan:Connect(function(input) 
        if input.UserInputType == Enum.UserInputType.MouseButton1 then 
            dragging = true 
            update() 
        end 
    end)
    
    services.UserInputService.InputEnded:Connect(function(input) 
        if input.UserInputType == Enum.UserInputType.MouseButton1 then 
            dragging = false 
        end 
    end)
    
    services.RunService.RenderStepped:Connect(function() 
        if dragging then 
            update() 
        end 
    end)
end

-- Initialize the GUI
function GUI:init(services, config, callbacks)
    local localPlayer = services.localPlayer
    local playerMouse = localPlayer:GetMouse()
    
    -- Create ScreenGui
    self.screenGui = Instance.new("ScreenGui", localPlayer.PlayerGui)
    self.screenGui.Name = "BRM5_V6_Final"
    self.screenGui.ResetOnSpawn = false
    self.screenGui.DisplayOrder = 9999
    self.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local modalOverlay = Instance.new("TextButton", self.screenGui)
    modalOverlay.Name = "ModalOverlay"
    modalOverlay.Size = UDim2.fromScale(1, 1)
    modalOverlay.Position = UDim2.fromScale(0, 0)
    modalOverlay.BackgroundTransparency = 1
    modalOverlay.BorderSizePixel = 0
    modalOverlay.Text = ""
    modalOverlay.AutoButtonColor = false
    modalOverlay.Modal = true
    modalOverlay.Active = true
    modalOverlay.Visible = config.guiVisible
    modalOverlay.ZIndex = 0
    self.modalOverlay = modalOverlay

    local cursorIndicator = Instance.new("Frame", self.screenGui)
    cursorIndicator.Name = "CursorIndicator"
    cursorIndicator.Size = UDim2.fromOffset(10, 10)
    cursorIndicator.AnchorPoint = Vector2.new(0.5, 0.5)
    cursorIndicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    cursorIndicator.BorderSizePixel = 0
    cursorIndicator.Visible = config.guiVisible
    cursorIndicator.ZIndex = 100
    Instance.new("UICorner", cursorIndicator).CornerRadius = UDim.new(1, 0)
    self.cursorIndicator = cursorIndicator

    local cursorStroke = Instance.new("UIStroke", cursorIndicator)
    cursorStroke.Color = Color3.fromRGB(0, 0, 0)
    cursorStroke.Thickness = 1.5

    local toggleButton = Instance.new("TextButton", self.screenGui)
    toggleButton.Name = "GuiToggleButton"
    toggleButton.Size = UDim2.fromOffset(110, 36)
    toggleButton.Position = UDim2.new(0, 20, 0.5, -18)
    toggleButton.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    toggleButton.BorderSizePixel = 0
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.Font = "GothamBold"
    toggleButton.TextSize = 13
    toggleButton.ZIndex = 101
    Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0, 8)
    self.toggleButton = toggleButton
    updateToggleButtonText(toggleButton, config.guiVisible)

    toggleButton.MouseButton1Click:Connect(function()
        if callbacks.onVisibilityToggle then
            callbacks.onVisibilityToggle()
        else
            self:toggleVisibility()
        end
    end)

    -- Main Window Frame
    local main = Instance.new("Frame", self.screenGui)
    main.Size = UDim2.new(0, 500, 0, 350)
    main.Position = UDim2.new(0.5, -250, 0.5, -175)
    main.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    main.BorderSizePixel = 0
    main.Active = true
    main.Visible = config.guiVisible
    main.ZIndex = 1
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    self.mainFrame = main

    -- Make draggable
    local dragging, dragInput, dragStart, startPos
    local function updateDrag(input)
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, 
                                  startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end

    local topBar = Instance.new("Frame", main)
    topBar.Size = UDim2.new(1, 0, 0, 40)
    topBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    topBar.BorderSizePixel = 0
    Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 8)

    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then 
                    dragging = false 
                end
            end)
        end
    end)

    topBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then 
            dragInput = input 
        end
    end)

    services.RunService.RenderStepped:Connect(function()
        if dragging and dragInput then 
            updateDrag(dragInput) 
        end

        if self.cursorIndicator then
            self.cursorIndicator.Position = UDim2.fromOffset(
                playerMouse.X,
                playerMouse.Y
            )
        end
    end)

    -- Title
    local title = Instance.new("TextLabel", topBar)
    title.Size = UDim2.new(1, -20, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.Text = "BRM5 v7.0 🎇 PVE"
    title.Font = "GothamBold"
    title.TextColor3 = Color3.fromRGB(85, 170, 255)
    title.TextSize = 16
    title.TextXAlignment = "Left"
    title.BackgroundTransparency = 1

    -- Sidebar
    local sidebar = Instance.new("Frame", main)
    sidebar.Position = UDim2.new(0, 0, 0, 40)
    sidebar.Size = UDim2.new(0, 130, 1, -40)
    sidebar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    sidebar.BorderSizePixel = 0

    local sideLayout = Instance.new("UIListLayout", sidebar)
    sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sideLayout.Padding = UDim.new(0, 8)

    -- Content Container
    local container = Instance.new("Frame", main)
    container.Position = UDim2.new(0, 140, 0, 50)
    container.Size = UDim2.new(1, -150, 1, -60)
    container.BackgroundTransparency = 1

    -- Create Tabs
    local tabCombat = createTab(container)
    local tabVisuals = createTab(container)
    local tabWeapons = createTab(container)
    local tabColors = createTab(container)
    local tabCredits = createTab(container)
    tabCombat.Visible = true

    self.tabs = {
        combat = tabCombat,
        visuals = tabVisuals,
        weapons = tabWeapons,
        colors = tabColors,
        credits = tabCredits
    }

    -- Add Tab Buttons
    local function addTabBtn(name, targetTab)
        local b = Instance.new("TextButton", sidebar)
        b.Size = UDim2.new(1, -20, 0, 35)
        b.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        b.TextColor3 = Color3.new(0.8, 0.8, 0.8)
        b.Font = "GothamMedium"
        b.TextSize = 13
        Instance.new("UICorner", b)

        self.tabButtons[name] = b
        if name == "Combat" then
            b.BackgroundColor3 = Color3.fromRGB(85, 170, 255)
            b.TextColor3 = Color3.new(0, 0, 0)
        end

        b.Text = name
        b.MouseButton1Click:Connect(function()
            for _, btn in pairs(self.tabButtons) do
                btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
                btn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
            end
            b.BackgroundColor3 = Color3.fromRGB(85, 170, 255)
            b.TextColor3 = Color3.new(0, 0, 0)

            for _, tab in pairs(self.tabs) do
                tab.Visible = false
            end
            targetTab.Visible = true
        end)
    end

    addTabBtn("Combat", tabCombat)
    addTabBtn("Visuals", tabVisuals)
    addTabBtn("Weapons", tabWeapons)
    addTabBtn("Colors", tabColors)
    addTabBtn("Credits and Help", tabCredits)

    -- COMBAT TAB
    createButton(tabCombat, "Silent 🎯", config.sizingEnabled, callbacks.onSizingToggle)
    createButton(tabCombat, "Show HitBox", config.showTargetBox, callbacks.onShowTargetBoxToggle)

    -- VISUALS TAB
    createButton(tabVisuals, "Walls 🔎", config.highlightEnabled, callbacks.onHighlightsToggle)
    createButton(tabVisuals, "FullBright 💡", config.fullBrightEnabled, callbacks.onFullBrightToggle)
    createSlider(
        tabVisuals,
        "NPC Range",
        config.npcDetectionRadius,
        config.MAX_NPC_DETECTION_RADIUS,
        callbacks.onNPCDetectionRadiusChange,
        nil,
        services
    )
    createInfoLabel(
        tabVisuals,
        "If you're having performance issues, try lowering the NPC Range to the minimum and then gradually increasing it until you achieve good performance with the maximum possible distance."
    )

    -- WEAPONS TAB
    local weaponNote = createLabel(tabWeapons, "Reset character to apply changes", 
                                   Color3.fromRGB(255, 100, 100))
    createButton(tabWeapons, "No recoil", config.patchOptions.recoil, callbacks.onStabilityToggle)
    createButton(tabWeapons, "All Firemodes", config.patchOptions.firemodes, callbacks.onFiremodeOptionsToggle)

    -- COLORS TAB
    local layoutIndex = 1
    createLabel(tabColors, "-- VISIBLE COLOR --", Color3.new(0.5, 1, 0.5), layoutIndex)
    layoutIndex = layoutIndex + 1
    
    createSlider(tabColors, "R", config.visibleR, 255, callbacks.onVisibleRChange, layoutIndex, services)
    layoutIndex = layoutIndex + 1
    createSlider(tabColors, "G", config.visibleG, 255, callbacks.onVisibleGChange, layoutIndex, services)
    layoutIndex = layoutIndex + 1
    createSlider(tabColors, "B", config.visibleB, 255, callbacks.onVisibleBChange, layoutIndex, services)
    layoutIndex = layoutIndex + 1

    createLabel(tabColors, "-- HIDDEN COLOR --", Color3.new(1, 0.5, 0.5), layoutIndex)
    layoutIndex = layoutIndex + 1
    
    createSlider(tabColors, "R", config.hiddenR, 255, callbacks.onHiddenRChange, layoutIndex, services)
    layoutIndex = layoutIndex + 1
    createSlider(tabColors, "G", config.hiddenG, 255, callbacks.onHiddenGChange, layoutIndex, services)
    layoutIndex = layoutIndex + 1
    createSlider(tabColors, "B", config.hiddenB, 255, callbacks.onHiddenBChange, layoutIndex, services)

    -- CREDITS TAB
    local function addCredit(text, font, size)
        local c = Instance.new("TextLabel", tabCredits)
        c.Size = UDim2.new(1, -10, 0, size or 50)
        c.Text = text
        c.TextColor3 = Color3.new(0.9, 0.9, 0.9)
        c.Font = font or "Gotham"
        c.TextSize = 12
        c.TextWrapped = true
        c.BackgroundTransparency = 1
    end
    
    local clipboardStatus = createInfoLabel(tabCredits, "Click a link to copy it to the clipboard.")
    clipboardStatus.Size = UDim2.new(1, -10, 0, 40)
    clipboardStatus.TextColor3 = Color3.fromRGB(140, 200, 255)

    local function copyToClipboard(text, label)
        if type(setclipboard) == "function" then
            local ok = pcall(setclipboard, text)
            if ok then
                clipboardStatus.Text = "Copied to clipboard: " .. label
                return
            end
        end
        clipboardStatus.Text = "Clipboard is not available in this executor."
    end

    local function addLinkButton(label, url, accentColor)
        local btn = Instance.new("TextButton", tabCredits)
        btn.Size = UDim2.new(1, -10, 0, 44)
        btn.BackgroundColor3 = accentColor
        btn.Text = label
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = "GothamBold"
        btn.TextSize = 13
        btn.AutoButtonColor = true
        Instance.new("UICorner", btn)

        btn.MouseButton1Click:Connect(function()
            copyToClipboard(url, label)
        end)

        local urlLabel = Instance.new("TextLabel", btn)
        urlLabel.Size = UDim2.new(1, -16, 0, 16)
        urlLabel.Position = UDim2.new(0, 8, 1, -18)
        urlLabel.BackgroundTransparency = 1
        urlLabel.Text = url
        urlLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
        urlLabel.Font = "Gotham"
        urlLabel.TextSize = 10
    end

    addCredit("Credits and Help", "GothamBold", 28)
    addCredit("Made by: Shreyas549-coder", "GothamBold", 24)
    addLinkButton("GitHub", "https://github.com/Shreyas549-coder/Roblox-Dexter-Scripts", Color3.fromRGB(45, 95, 160))
    addLinkButton("Reddit", "https://www.reddit.com/r/BRM5Scripts/", Color3.fromRGB(185, 75, 45))

    -- UNLOAD BUTTON
    local unl = Instance.new("TextButton", sidebar)
    unl.Size = UDim2.new(0, 110, 0, 35)
    unl.AnchorPoint = Vector2.new(0.5, 0)
    unl.Position = UDim2.new(0.5, 0, 0, 0)
    unl.Text = "Unload Script"
    unl.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
    unl.TextColor3 = Color3.new(1, 1, 1)
    Instance.new("UICorner", unl)
    unl.MouseButton1Click:Connect(callbacks.onUnload)
end

function GUI:setVisibleState(isVisible)
    if self.mainFrame then
        self.mainFrame.Visible = isVisible
    end
    if self.modalOverlay then
        self.modalOverlay.Visible = isVisible
    end
    if self.cursorIndicator then
        self.cursorIndicator.Visible = isVisible
    end
    updateToggleButtonText(self.toggleButton, isVisible)
    return isVisible
end

-- Toggle GUI visibility
function GUI:toggleVisibility()
    if self.mainFrame then
        return self:setVisibleState(not self.mainFrame.Visible)
    end
    return false
end

-- Destroy GUI
function GUI:destroy()
    if self.screenGui then
        self.screenGui:Destroy()
    end
    self.screenGui = nil
    self.mainFrame = nil
    self.modalOverlay = nil
    self.cursorIndicator = nil
    self.toggleButton = nil
end

return GUI


end)()

-- ==================== MAIN COORDINATOR ====================
-- BRM5 v7.0 by dexter 
-- Credits to ryknuq and their overvoltage script, which helped me understand how to integrate the Aim into my script. Without their script, I don't think I could have done this.
-- Coordinates all modules

if typeof(clear) == "function" then
    clear()
end

local MAIN_VERSION = "cache-bust-2026-03-18-01"
local GITHUB_BASE = "https://raw.githubusercontent.com/Shreyas549-coder/Roblox-Dexter-Scripts/main/brm5-pve/modules/"
local CACHE_BUSTER = MAIN_VERSION .. "-" .. tostring(os.time())

local function loadModule(moduleName)
    if __MODULES__[moduleName] then
        return __MODULES__[moduleName]
    end
    warn("Unknown module: " .. tostring(moduleName))
    return nil
end

local Services = loadModule("services")
local Config = loadModule("config")
local NPCManager = loadModule("npc_manager")
local TargetSizing = loadModule("silent")
local Markers = loadModule("walls")
local Lighting = loadModule("fullbright")
local Weapons = loadModule("norecoil")
local GUI = loadModule("gui")

if not (Services and Config and NPCManager and TargetSizing and Markers and Lighting and Weapons and GUI) then
    error("Failed to load one or more modules. Please verify the remote module files.")
end

Config:load()
Lighting:storeOriginalSettings(Services.Lighting)

local runtimeConnections = {}

local function saveConfig()
    Config:save()
end

local function syncMouseState()
    if Config.guiVisible then
        Services.UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        Services.UserInputService.MouseIconEnabled = true
    end
end

local function forceMouseLock()
    Services.UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    Services.UserInputService.MouseIconEnabled = false
end

local function toggleGUIVisibility()
    local wasVisible = Config.guiVisible
    Config.guiVisible = GUI:toggleVisibility()
    if Config.guiVisible then
        syncMouseState()
    elseif wasVisible then
        forceMouseLock()
    end
    return Config.guiVisible
end

local function disconnectRuntimeConnections()
    for _, connection in ipairs(runtimeConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    runtimeConnections = {}
end

local callbacks = {
    onSizingToggle = function(enabled)
        Config.sizingEnabled = enabled
        if not enabled then
            TargetSizing:cleanup(NPCManager)
        end
        NPCManager:refreshTrackedNPCs(Services.Workspace, Markers, TargetSizing, Config)
        saveConfig()
    end,

    onShowTargetBoxToggle = function(enabled)
        Config.showTargetBox = enabled
        NPCManager:refreshTrackedNPCs(Services.Workspace, Markers, TargetSizing, Config)
        saveConfig()
    end,

    onHighlightsToggle = function(enabled)
        Config.highlightEnabled = enabled
        NPCManager:refreshTrackedNPCs(Services.Workspace, Markers, TargetSizing, Config)
        if enabled then
            Markers.enable(NPCManager, Config)
        else
            Markers.disable()
        end
        saveConfig()
    end,

    onFullBrightToggle = function(enabled)
        Config.fullBrightEnabled = enabled
        if not enabled then
            Lighting:restoreOriginal(Services.Lighting)
        end
        saveConfig()
    end,

    onStabilityToggle = function(enabled)
        Config.patchOptions.recoil = enabled
        Weapons.patchWeapons(Services.ReplicatedStorage, Config.patchOptions)
        saveConfig()
    end,

    onFiremodeOptionsToggle = function(enabled)
        Config.patchOptions.firemodes = enabled
        Weapons.patchWeapons(Services.ReplicatedStorage, Config.patchOptions)
        saveConfig()
    end,

    onVisibleRChange = function(value)
        Config:updateVisibleColor(value, nil, nil)
        saveConfig()
    end,

    onVisibleGChange = function(value)
        Config:updateVisibleColor(nil, value, nil)
        saveConfig()
    end,

    onVisibleBChange = function(value)
        Config:updateVisibleColor(nil, nil, value)
        saveConfig()
    end,

    onHiddenRChange = function(value)
        Config:updateHiddenColor(value, nil, nil)
        saveConfig()
    end,

    onHiddenGChange = function(value)
        Config:updateHiddenColor(nil, value, nil)
        saveConfig()
    end,

    onHiddenBChange = function(value)
        Config:updateHiddenColor(nil, nil, value)
        saveConfig()
    end,

    onNPCDetectionRadiusChange = function(value)
        Config:updateNPCDetectionRadius(value)
        NPCManager:refreshTrackedNPCs(Services.Workspace, Markers, TargetSizing, Config)
        saveConfig()
    end,

    onVisibilityToggle = function()
        toggleGUIVisibility()
    end,

    onUnload = function()
        if Config.isUnloaded then
            return
        end

        Config.isUnloaded = true
        disconnectRuntimeConnections()
        Markers.disable()
        TargetSizing:cleanup(NPCManager)
        NPCManager:cleanup()
        Lighting:restoreOriginal(Services.Lighting)
        Config.guiVisible = false
        saveConfig()
        forceMouseLock()
        GUI:destroy()
    end
}

GUI:init(Services, Config, callbacks)
syncMouseState()

NPCManager:scanWorkspace(Services.Workspace, Markers, Config)
NPCManager:setupListener(Services.Workspace, Markers, Config)
if Config.highlightEnabled then
    Markers.enable(NPCManager, Config)
end
if Config.patchOptions.recoil or Config.patchOptions.firemodes then
    Weapons.patchWeapons(Services.ReplicatedStorage, Config.patchOptions)
end

local markerAccumulator = 0
local targetAccumulator = 0
local npcAccumulator = 0

table.insert(runtimeConnections, Services.RunService.Heartbeat:Connect(function(dt)
    if Config.isUnloaded then
        return
    end

    if Config.guiVisible then
        syncMouseState()
    end
    Lighting:update(Services.Lighting, Config)

    npcAccumulator = npcAccumulator + dt
    if npcAccumulator >= Config.NPC_REFRESH_INTERVAL then
        NPCManager:refreshTrackedNPCs(Services.Workspace, Markers, TargetSizing, Config)
        npcAccumulator = 0
    end

    markerAccumulator = markerAccumulator + dt
    if markerAccumulator >= Config.RAYCAST_COOLDOWN then
        local okMarkers, markerError = pcall(
            Markers.updateColors,
            NPCManager,
            Services.Workspace.CurrentCamera or Services.camera,
            Services.Workspace,
            Services.localPlayer,
            Config
        )
        if not okMarkers then
            warn("Markers.updateColors failed: " .. tostring(markerError))
        end
        markerAccumulator = 0
    end

    targetAccumulator = targetAccumulator + dt
    if targetAccumulator >= Config.TARGET_SYNC_INTERVAL then
        TargetSizing:updateAllTargets(NPCManager, Config)
        targetAccumulator = 0
    end
end))

table.insert(runtimeConnections, Services.UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if Config.isUnloaded then
        return
    end

    if not gameProcessed and input.KeyCode == Enum.KeyCode.Insert then
        toggleGUIVisibility()
    end
end))
