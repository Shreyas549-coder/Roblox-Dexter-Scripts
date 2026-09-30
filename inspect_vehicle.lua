-- BRM5 Stryker Scanner for Xeno
-- Spawn a Stryker then run this. Finds it by name in workspace.

local function dumpTree(inst, depth)
    if depth > 5 then return end
    local indent = string.rep("  ", depth)
    local info = indent .. "[" .. inst.ClassName .. "] " .. inst.Name
    if inst:IsA("ValueBase") then
        pcall(function() info = info .. " = " .. tostring(inst.Value) end)
    end
    print(info)
    pcall(function()
        for _, c in ipairs(inst:GetChildren()) do
            dumpTree(c, depth + 1)
        end
    end)
end

print("=== BRM5 STRYKER SCAN ===")

-- Method 1: Search workspace children for anything with "stryker" in name
local found = false
for _, child in ipairs(workspace:GetChildren()) do
    if child.Name:lower():find("stryker") or child.Name:lower():find("vehicle") or child.Name:lower():find("m1126") then
        print("")
        print("FOUND: " .. child.Name .. " [" .. child.ClassName .. "]")
        dumpTree(child, 0)
        found = true
    end
end

-- Method 2: Check if player is seated
local player = game.Players.LocalPlayer
local char = player.Character
if char then
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SitPart then
        print("")
        print("SEATED IN: " .. hum.SitPart:GetFullName())
        local root = hum.SitPart
        while root.Parent and root.Parent ~= workspace do
            root = root.Parent
        end
        print("VEHICLE ROOT: " .. root.Name)
        if not found then
            dumpTree(root, 0)
        end
        found = true
    else
        print("NOT SEATED (SitPart is nil)")
    end
else
    print("NO CHARACTER")
end

-- Method 3: If nothing found, just list workspace top-level
if not found then
    print("")
    print("=== WORKSPACE TOP-LEVEL (find your Stryker name) ===")
    for _, child in ipairs(workspace:GetChildren()) do
        print("  [" .. child.ClassName .. "] " .. child.Name)
    end
end

print("")
print("=== DONE ===")
