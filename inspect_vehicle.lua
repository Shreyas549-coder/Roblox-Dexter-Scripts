-- BRM5 Vehicle Diagnostic (Run in Xeno while in the Stryker)
print("================== BRM5 VEHICLE DIAGNOSTIC ==================")

local player = game.Players.LocalPlayer
local camera = workspace.CurrentCamera

-- 1. Camera Subject (Standard Roblox vehicle detection)
print("1. CAMERA:")
if camera then
    local subj = camera.CameraSubject
    if subj then
        print("   CameraSubject: " .. subj:GetFullName() .. " [" .. subj.ClassName .. "]")
        local subjModel = subj:FindFirstAncestorOfClass("Model")
        if subjModel then
            print("   CameraSubject Model: " .. subjModel:GetFullName())
        end
    else
        print("   CameraSubject is nil")
    end
end

-- 2. LocalPlayer Character
print("2. CHARACTER:")
local char = player.Character
if char then
    print("   player.Character: " .. char:GetFullName())
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        print("   Humanoid found. Sit: " .. tostring(hum.Sit) .. " | SitPart: " .. tostring(hum.SitPart and hum.SitPart:GetFullName() or "nil"))
    end
else
    print("   player.Character is NIL!")
end

-- 3. What is in workspace.Live?
print("3. WORKSPACE.LIVE CONTENTS:")
local live = workspace:FindFirstChild("Live")
if live then
    for _, child in ipairs(live:GetChildren()) do
        local info = "   [" .. child.ClassName .. "] " .. child.Name
        if child:IsA("Model") then
            local seat = child:FindFirstChildOfClass("VehicleSeat") or child:FindFirstChildOfClass("Seat")
            if seat then
                info = info .. " (HAS SEAT: " .. seat.Name .. ", Occupant: " .. tostring(seat.Occupant) .. ")"
            end
        end
        print(info)
    end
else
    print("   workspace.Live not found!")
end

-- 4. Check Camera WorldModel (BRM5 first-person model)
print("4. CAMERA WORLDMODEL:")
if camera and camera:FindFirstChild("WorldModel") then
    for _, child in ipairs(camera.WorldModel:GetChildren()) do
        print("   [" .. child.ClassName .. "] " .. child.Name)
    end
end

-- 5. Scan any models near camera (< 30 studs)
print("5. MODELS NEAR CAMERA (< 30 studs):")
local camPos = camera and camera.CFrame.Position or Vector3.zero
for _, obj in ipairs(workspace:GetDescendants()) do
    if obj:IsA("Model") and obj.Parent and (obj.Parent == workspace or obj.Parent == live) then
        local ok, cf, sz = pcall(function() return obj:GetBoundingBox() end)
        if ok and (cf.Position - camPos).Magnitude < 30 then
            print("   NEAR: " .. obj.Name .. " [" .. obj.ClassName .. "] at dist " .. math.floor((cf.Position - camPos).Magnitude))
            for _, c in ipairs(obj:GetChildren()) do
                if c:IsA("Seat") or c:IsA("VehicleSeat") or c:IsA("ValueBase") or c.Name:lower():find("health") or c.Name:lower():find("seat") then
                    print("     -> [" .. c.ClassName .. "] " .. c.Name)
                end
            end
        end
    end
end

print("================== END DIAGNOSTIC ==================")
