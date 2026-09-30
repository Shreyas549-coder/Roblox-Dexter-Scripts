-- BRM5 Vehicle & Config Inspector
local output = {}
local function log(str)
    table.insert(output, str)
    print(str)
end

log("=== BRM5 LIVE VEHICLES & CONFIGS ===")

-- 1. Scan Workspace.Live.Unsorted and Workspace.Live.Tech
local live = workspace:FindFirstChild("Live")
if live then
    local unsorted = live:FindFirstChild("Unsorted")
    if unsorted then
        log("\n[1] ALL CHILDREN IN Workspace.Live.Unsorted:")
        for _, child in ipairs(unsorted:GetChildren()) do
            local line = "  [" .. child.ClassName .. "] " .. child.Name
            log(line)
            -- If it has children or attributes
            for aName, aVal in pairs(child:GetAttributes()) do
                log("     Attr: " .. aName .. " = " .. tostring(aVal))
            end
            for _, sub in ipairs(child:GetChildren()) do
                if sub:IsA("ValueBase") or sub.Name:lower():find("health") or sub.Name:lower():find("hull") or sub.Name:lower():find("chassis") or sub.Name:lower():find("main") or sub.Name:lower():find("seat") then
                    log("     -> [" .. sub.ClassName .. "] " .. sub.Name .. (sub:IsA("ValueBase") and (" = " .. tostring(sub.Value)) or ""))
                end
            end
        end
    end

    local tech = live:FindFirstChild("Tech")
    if tech then
        log("\n[2] ALL CHILDREN IN Workspace.Live.Tech:")
        for _, child in ipairs(tech:GetChildren()) do
            log("  [" .. child.ClassName .. "] " .. child.Name)
            for aName, aVal in pairs(child:GetAttributes()) do
                log("     Attr: " .. aName .. " = " .. tostring(aVal))
            end
            for _, sub in ipairs(child:GetChildren()) do
                if sub:IsA("ValueBase") or sub.Name:lower():find("health") or sub.Name:lower():find("seat") then
                    log("     -> [" .. sub.ClassName .. "] " .. sub.Name)
                end
            end
        end
    end
end

-- 2. Inspect ReplicatedStorage.Shared.Configs.Vehicle
log("\n[3] REPLICATEDSTORAGE VEHICLE CONFIGS:")
local rep = game:GetService("ReplicatedStorage")
local shared = rep:FindFirstChild("Shared")
if shared then
    local configs = shared:FindFirstChild("Configs")
    if configs then
        local vehConfig = configs:FindFirstChild("Vehicle")
        if vehConfig then
            log("Vehicle Config Class: " .. vehConfig.ClassName)
            if vehConfig:IsA("ModuleScript") then
                local ok, data = pcall(require, vehConfig)
                if ok and type(data) == "table" then
                    log("Vehicle Config keys:")
                    for k, v in pairs(data) do
                        log("  " .. tostring(k) .. " = " .. type(v))
                        if type(v) == "table" then
                            for subK, subV in pairs(v) do
                                log("     " .. tostring(subK) .. " = " .. tostring(subV))
                            end
                        end
                    end
                end
            else
                for _, child in ipairs(vehConfig:GetChildren()) do
                    log("  [" .. child.ClassName .. "] " .. child.Name)
                    if child:IsA("ModuleScript") then
                        local ok, data = pcall(require, child)
                        if ok and type(data) == "table" then
                            for k, v in pairs(data) do
                                log("     " .. tostring(k) .. " = " .. tostring(v))
                            end
                        end
                    end
                end
            end
        else
            log("shared.Configs.Vehicle not found")
        end
    end
end

-- 3. Check VehicleSolver
local vehFolder = shared and shared:FindFirstChild("Vehicle")
if vehFolder then
    log("\n[4] VEHICLE SOLVER FOLDER:")
    for _, child in ipairs(vehFolder:GetChildren()) do
        log("  [" .. child.ClassName .. "] " .. child.Name)
    end
end

log("\n=== END ===")

local result = table.concat(output, "\n")
if typeof(setclipboard) == "function" then
    pcall(setclipboard, result)
    print("\n[SUCCESS] Automatically copied to clipboard! Just Ctrl+V here.")
elseif typeof(toclipboard) == "function" then
    pcall(toclipboard, result)
    print("\n[SUCCESS] Automatically copied to clipboard! Just Ctrl+V here.")
end
