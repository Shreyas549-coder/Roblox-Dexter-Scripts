-- BRM5 Deep Module & Stryker Dumper for Xeno
-- Run this in Xeno while your Stryker is spawned.
-- The complete output is automatically COPIED TO YOUR CLIPBOARD so you can just press Ctrl+V here!

local output = {}
local function log(str)
    table.insert(output, str)
    print(str)
end

log("=== BRM5 DEEP SCAN START ===")

-- 1. CAMERA SUBJECT & FOCUS
log("\n[1] CAMERA STATUS:")
local camera = workspace.CurrentCamera
if camera then
    if camera.CameraSubject then
        log("CameraSubject: " .. camera.CameraSubject:GetFullName() .. " [" .. camera.CameraSubject.ClassName .. "]")
    else
        log("CameraSubject is nil")
    end
end

-- 2. ALL SEATS IN WORKSPACE (Finds every seat currently in the game)
log("\n[2] ALL SEATS IN WORKSPACE:")
local seatCount = 0
for _, desc in ipairs(workspace:GetDescendants()) do
    if desc:IsA("Seat") or desc:IsA("VehicleSeat") then
        seatCount = seatCount + 1
        log("Seat #" .. seatCount .. ": " .. desc:GetFullName() .. " [" .. desc.ClassName .. "]")
        local rootModel = desc:FindFirstAncestorOfClass("Model")
        if rootModel then
            log("   -> Model: " .. rootModel:GetFullName())
        end
    end
end
if seatCount == 0 then
    log("No Seat or VehicleSeat found in workspace.")
end

-- 3. WORKSPACE.LIVE CHILDREN (Where entities usually live in BRM5)
log("\n[3] WORKSPACE.LIVE:")
local live = workspace:FindFirstChild("Live")
if live then
    for _, child in ipairs(live:GetChildren()) do
        log("Live Child: [" .. child.ClassName .. "] " .. child.Name)
        if child:IsA("Model") then
            for _, sub in ipairs(child:GetChildren()) do
                if sub:IsA("Model") or sub:IsA("Seat") or sub:IsA("VehicleSeat") or sub:IsA("ValueBase") or sub.Name:lower():find("seat") or sub.Name:lower():find("chassis") or sub.Name:lower():find("health") then
                    log("   -> [" .. sub.ClassName .. "] " .. sub.Name)
                end
            end
        end
    end
else
    log("workspace.Live does not exist.")
end

-- 4. SEARCH FOR STRYKER / VEHICLE KEYWORDS IN WORKSPACE
log("\n[4] VEHICLE/STRYKER KEYWORD MATCHES IN WORKSPACE:")
local foundModels = {}
for _, desc in ipairs(workspace:GetDescendants()) do
    local n = desc.Name:lower()
    if n:find("stryker") or n:find("m1126") or n:find("icv") or n:find("turret") or n:find("chassis") then
        local model = desc:IsA("Model") and desc or desc:FindFirstAncestorOfClass("Model")
        if model and not foundModels[model] then
            foundModels[model] = true
            log("\nFOUND MATCH: " .. model:GetFullName() .. " [" .. model.ClassName .. "]")
            log("   Attributes:")
            for aName, aVal in pairs(model:GetAttributes()) do
                log("     Attr: " .. aName .. " = " .. tostring(aVal))
            end
            log("   Children summary:")
            for _, c in ipairs(model:GetChildren()) do
                log("     [" .. c.ClassName .. "] " .. c.Name)
                if c:IsA("ValueBase") then
                    log("        Value = " .. tostring(c.Value))
                end
                for aName, aVal in pairs(c:GetAttributes()) do
                    log("        Attr: " .. aName .. " = " .. tostring(aVal))
                end
                -- 1 level deeper for seats/values
                for _, sub in ipairs(c:GetChildren()) do
                    if sub:IsA("ValueBase") or sub:IsA("Seat") or sub:IsA("VehicleSeat") or sub.Name:lower():find("health") or sub.Name:lower():find("seat") then
                        log("        -> [" .. sub.ClassName .. "] " .. sub.Name .. (sub:IsA("ValueBase") and (" = " .. tostring(sub.Value)) or ""))
                    end
                end
            end
        end
    end
end

-- 5. REPLICATED STORAGE MODULES (Configs, Vehicles, Packages)
log("\n[5] REPLICATEDSTORAGE MODULES:")
local rep = game:GetService("ReplicatedStorage")
local function scanModules(folder, depth, maxDepth)
    if depth > maxDepth or not folder then return end
    for _, child in ipairs(folder:GetChildren()) do
        local n = child.Name:lower()
        if child:IsA("ModuleScript") then
            if n:find("veh") or n:find("stryk") or n:find("config") or n:find("tune") or n:find("health") or n:find("damage") or n:find("shared") then
                log("Module: " .. child:GetFullName())
            end
        end
        if child:IsA("Folder") or child:IsA("Configuration") or child:IsA("Model") then
            scanModules(child, depth + 1, maxDepth)
        end
    end
end
scanModules(rep, 1, 5)

log("\n=== BRM5 DEEP SCAN END ===")

local result = table.concat(output, "\n")

-- Auto-copy to Windows clipboard
local copied = false
if typeof(setclipboard) == "function" then
    pcall(setclipboard, result)
    copied = true
elseif typeof(toclipboard) == "function" then
    pcall(toclipboard, result)
    copied = true
end

if copied then
    print("\n[SUCCESS] Output has been automatically copied to your clipboard! Just press Ctrl+V in the chat.")
else
    print("\n[INFO] Please copy the output from the developer console (F9).")
end
