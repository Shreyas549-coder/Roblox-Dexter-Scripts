-- BRM5 Vehicle Name Dumper (Bulletproof)
-- Run once with Jeep, once with Stryker.
-- Copies the exact list to your clipboard automatically!

local lines = {}
local function add(text)
    table.insert(lines, text)
    print(text)
end

add("=== BRM5 VEHICLE DUMP START ===")

-- 1. Scan Workspace.Live.Unsorted
local ok1, err1 = pcall(function()
    local live = workspace:FindFirstChild("Live")
    if live then
        local unsorted = live:FindFirstChild("Unsorted")
        if unsorted then
            add("\n--- Live.Unsorted Models ---")
            for _, child in ipairs(unsorted:GetChildren()) do
                if child:IsA("Model") and child.Name ~= "Male" then
                    add(child.Name)
                end
            end
        else
            add("Live.Unsorted not found")
        end
    else
        add("workspace.Live not found")
    end
end)
if not ok1 then add("Error scanning Unsorted: " .. tostring(err1)) end

-- 2. Scan Workspace.Live.Tech
local ok2, err2 = pcall(function()
    local live = workspace:FindFirstChild("Live")
    if live then
        local tech = live:FindFirstChild("Tech")
        if tech then
            add("\n--- Live.Tech Models ---")
            for _, child in ipairs(tech:GetChildren()) do
                if child:IsA("Model") and child.Name ~= "Male" then
                    add(child.Name)
                end
            end
        end
    end
end)
if not ok2 then add("Error scanning Tech: " .. tostring(err2)) end

-- 3. Scan top-level Workspace Models
local ok3, err3 = pcall(function()
    add("\n--- Workspace Top-Level Models ---")
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child.Name ~= "Male" and child.Name ~= "Terrain" then
            add(child.Name)
        end
    end
end)
if not ok3 then add("Error scanning Workspace: " .. tostring(err3)) end

add("\n=== BRM5 VEHICLE DUMP END ===")

local result = table.concat(lines, "\n")
pcall(function()
    if typeof(setclipboard) == "function" then
        setclipboard(result)
    elseif typeof(toclipboard) == "function" then
        toclipboard(result)
    end
end)

print("\n>>> [COPIED TO CLIPBOARD] Press Ctrl+V in chat! <<<")
