-- Target Sizing / Silent Aim Module (Xeno-compatible)
-- Xeno has no hookmetamethod, so we hook the RemoteEvent's FireServer
-- function directly with hookfunction.

local SilentAim = {}

SilentAim.enabled = false
SilentAim.originalSizes = {}
SilentAim.currentTarget = nil
SilentAim.fireRemote = nil
SilentAim.originalFire = nil
SilentAim.hookInstalled = false
SilentAim.vectorArgIndex = nil
SilentAim.debugUntil = 0

local RS = game:GetService("ReplicatedStorage")

local function getFireRemote()
    local events = RS:FindFirstChild("Events")
    if not events then return nil end
    local re = events:FindFirstChild("RemoteEvent")
    if re then return re end
    return events:FindFirstChild("UnreliableRemoteEvent")
end

local function describeArgs(args)
    local parts = {}
    for i = 1, math.min(#args, 10) do
        local a = args[i]
        local t = typeof(a)
        if t == "Vector3" then
            parts[#parts+1] = ("[%d]Vec3%s"):format(i, tostring(a))
        elseif t == "number" or t == "string" or t == "boolean" then
            parts[#parts+1] = ("[%d]%s"):format(i, tostring(a))
        elseif t == "table" then
            parts[#parts+1] = ("[%d]table"):format(i)
        else
            parts[#parts+1] = ("[%d]%s"):format(i, t)
        end
    end
    return table.concat(parts, " ")
end

local function rewriteArgs(args, camera)
    if not SilentAim.currentTarget or not SilentAim.currentTarget.Parent then
        return args
    end
    local dir = (SilentAim.currentTarget.Position - camera.CFrame.Position).Unit

    local idx = SilentAim.vectorArgIndex
    if idx and idx <= #args and typeof(args[idx]) == "Vector3" then
        args[idx] = dir
        return args
    end

    -- first-pass: pick the first Vector3 with a small magnitude (a direction)
    for i = 1, #args do
        if typeof(args[i]) == "Vector3" and args[i].Magnitude < 5 then
            SilentAim.vectorArgIndex = i
            print(("[silent] locked Vector3 arg index = %d"):format(i))
            args[i] = dir
            return args
        end
    end
    return args
end

function SilentAim:install()
    if self.hookInstalled then return true end
    if type(hookfunction) ~= "function" then
        warn("[silent] hookfunction not available")
        return false
    end
    local remote = getFireRemote()
    if not remote then
        warn("[silent] no ReplicatedStorage.Events.RemoteEvent found")
        return false
    end
    self.fireRemote = remote

    -- Attempt 1: hook the FireServer function directly.
    local ok, fireFn = pcall(function() return remote.FireServer end)
    if not ok or type(fireFn) ~= "function" then
        warn("[silent] remote.FireServer is not a function value; falling back to getconnections path")
        return false
    end

    self.originalFire = fireFn
    local ourReplacement = function(selfObj, ...)
        local args = {...}
        if selfObj == remote then
            if os.clock() < SilentAim.debugUntil then
                print(("[silent][out] %s"):format(describeArgs(args)))
            end
            if SilentAim.enabled and SilentAim.currentTarget then
                local camera = workspace.CurrentCamera
                if camera then
                    args = rewriteArgs(args, camera)
                end
            end
            return SilentAim.originalFire(selfObj, table.unpack(args))
        end
        return SilentAim.originalFire(selfObj, ...)
    end

    local okHook = pcall(hookfunction, fireFn, ourReplacement)
    if not okHook then
        warn("[silent] hookfunction on FireServer failed")
        return false
    end

    self.hookInstalled = true
    print("[silent] hooked " .. remote:GetFullName() .. ".FireServer")
    return true
end

function SilentAim:pickTarget(npcManager)
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local screenCenter = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local maxRange = 300
    local closest, bestDist = nil, math.huge
    for _, data in pairs(npcManager:getActiveNPCs()) do
        local head = data.head
        if head and head.Parent then
            local sp, onScreen = camera:WorldToViewportPoint(head.Position)
            if onScreen then
                local d = (Vector2.new(sp.X, sp.Y) - screenCenter).Magnitude
                if d < maxRange and d < bestDist then
                    bestDist = d
                    closest = head
                end
            end
        end
    end
    return closest
end

function SilentAim:updateAllTargets(npcManager, config)
    self.enabled = config.sizingEnabled and true or false

    if not self.enabled then
        self.currentTarget = nil
        return
    end

    if not self.hookInstalled then
        self:install()
        if self.hookInstalled then
            self.debugUntil = os.clock() + 8
            print("[silent] debug window open for 8s — fire a few rounds and read the console")
        end
    end

    self.currentTarget = self:pickTarget(npcManager)
end

-- API compat
function SilentAim:cleanup(npcManager) self.currentTarget = nil end
function SilentAim:applyTargetSizing() end
function SilentAim:restoreOriginalSize() end

return SilentAim
