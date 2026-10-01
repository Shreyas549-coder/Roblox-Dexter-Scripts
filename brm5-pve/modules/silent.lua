-- Target Sizing / Silent Aim Module
-- Real silent aim: hooks Events.RemoteEvent:FireServer and rewrites the
-- direction Vector3 to point at the closest visible NPC head.
-- Keeps the old TargetSizing API so main.lua / gui.lua don't change.

local SilentAim = {}

SilentAim.enabled = false
SilentAim.originalSizes = {}   -- kept for API compat
SilentAim.currentTarget = nil
SilentAim.fireRemote = nil
SilentAim.hookInstalled = false
SilentAim.vectorArgIndex = nil
SilentAim.debugUntil = 0
SilentAim.debugMode = true     -- set false later to silence

local RS = game:GetService("ReplicatedStorage")

local function findFireRemote()
    local events = RS:FindFirstChild("Events")
    if not events then return nil end
    local re = events:FindFirstChild("RemoteEvent")
    if re then return re end
    return events:FindFirstChild("UnreliableRemoteEvent")
end

local function logCall(remote, args)
    local parts = {}
    for i = 1, math.min(#args, 8) do
        local a = args[i]
        local t = typeof(a)
        if t == "Vector3" then
            parts[#parts+1] = ("[%d]Vec3(%s)"):format(i, tostring(a))
        elseif t == "number" or t == "string" or t == "boolean" then
            parts[#parts+1] = ("[%d]%s"):format(i, tostring(a))
        else
            parts[#parts+1] = ("[%d]%s"):format(i, t)
        end
    end
    print(("[silent] %s | %s"):format(remote:GetFullName(), table.concat(parts, " ")))
end

local function rewriteArgs(args)
    if not SilentAim.currentTarget or not SilentAim.currentTarget.Parent then
        return args
    end
    local camera = workspace.CurrentCamera
    if not camera then return args end

    local dir = (SilentAim.currentTarget.Position - camera.CFrame.Position).Unit

    -- use cached index if valid
    local idx = SilentAim.vectorArgIndex
    if idx and idx <= #args and typeof(args[idx]) == "Vector3" then
        args[idx] = dir
        return args
    end

    -- auto-detect: pick the first Vector3 that looks like a direction
    -- (unit-length or small magnitude). This picks bullet direction, not
    -- positions, because positions are world-scale (hundreds of studs).
    for i = 1, #args do
        if typeof(args[i]) == "Vector3" then
            local v = args[i]
            local mag = v.Magnitude
            if mag < 1.5 or (mag > 0.5 and mag < 5 and math.abs(mag - 1) < 0.05) then
                SilentAim.vectorArgIndex = i
                print(("[silent] locked Vector3 arg index = %d"):format(i))
                args[i] = dir
                return args
            end
        end
    end
    return args
end

function SilentAim:install()
    if self.hookInstalled then return true end
    if type(hookmetamethod) ~= "function" then
        warn("[silent] hookmetamethod not available in this executor")
        return false
    end
    self.fireRemote = findFireRemote()
    if not self.fireRemote then
        warn("[silent] could not find ReplicatedStorage.Events.RemoteEvent")
        return false
    end

    local remote = self.fireRemote
    local oldNamecall = hookmetamethod(game, "__namecall", function(self2, ...)
        if self2 == remote then
            local method = getnamecallmethod and getnamecallmethod() or ""
            if method == "FireServer" then
                local args = {...}
                if SilentAim.debugMode and os.clock() < SilentAim.debugUntil then
                    logCall(remote, args)
                end
                if SilentAim.enabled and SilentAim.currentTarget then
                    args = rewriteArgs(args)
                    return oldNamecall(self2, table.unpack(args))
                end
            end
        end
        return oldNamecall(self2, ...)
    end)
    self.hookInstalled = true
    print("[silent] hooked " .. remote:GetFullName())
    return true
end

function SilentAim:pickTarget(npcManager, config)
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
    -- main.lua calls this every 0.25s. Map config.sizingEnabled -> enabled.
    self.enabled = config.sizingEnabled and true or false

    if not self.enabled then
        self.currentTarget = nil
        return
    end

    if not self.hookInstalled then
        self:install()
        if self.debugMode then
            self.debugUntil = os.clock() + 8
            print("[silent] debug window open for 8s — fire a few rounds now")
        end
    end

    self.currentTarget = self:pickTarget(npcManager, config)
end

-- API compat — main.lua still calls these on toggle off
function SilentAim:cleanup(npcManager)
    self.currentTarget = nil
end
function SilentAim:applyTargetSizing() end
function SilentAim:restoreOriginalSize() end

return SilentAim
