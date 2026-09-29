local UserInputService = game:GetService("UserInputService")
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local ESSNCE_URL = IS_MOBILE
    and "https://raw.githubusercontent.com/Essluau/EssnceLibrary/refs/heads/main/MobileBuildFixed.lua"
    or "https://raw.githubusercontent.com/Essluau/EssnceLibrary/refs/heads/main/PcBuild.lua"

local Library = loadstring(game:HttpGet(ESSNCE_URL))()

if not Library then
    warn("ViksScripts: Error loading EssnceLibrary")
    return
end

-- EssnceLibrary has no built-in notifications, so we use StarterGui.
local function Notify(title, content, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title,
            Text = content,
            Duration = duration or 3,
        })
    end)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera


local settings = {
    safeEsp = false,
    invisible = false,
    highlight = false,
    spinbot = false,
    silentAim = false,
    meleeAura = false,
    meleeReach = false,
    bulletTracer = false,
    rageBot = false,
    hitSound = false,
    autoFarm = false,
    autoMoney = true,
    antiAfk = true,
}

local farmSettings = {
    MoveSpeed = 22,
    PickupDistance = 8,
    IgnoreDuration = 60,
    TargetY = 4.8,
    WaypointSpacing = 3,
    DebugPrint = true,
}

local bulletTracerSettings = {
    Color = Color3.fromRGB(255, 0, 0),
    Thickness = 0.1,
    Life = 2,
    Transparency = 0.65,
    Design = "Classic"
}

local rageBotSettings = {
    checkDowned = true,
    wallCheck = true,
    hitlogEnabled = true,
    useFOV = false,
    teamCheck = false,
    fovRadius = 75,
    shootSpeed = 15,
    fireInterval = 0.17,
    maxDistance = 100,
    bulletTracerEnabled = false,
    tracerColor = Color3.fromRGB(255, 0, 0),
    showFOV = false,
}

local SilentAim = {
    enabled = false,
    settings = {
        checkDowned = true,
        teamCheck = false,
        checkWhitelist = false,
        checkTarget = false,
        fovCircleCentered = true,
        drawColor = Color3.fromRGB(255, 255, 255),
        drawSize = 100,
        useHitChance = true,
        hitChance = 100,
        checkWall = true,
        targetPart = "Head",
        actualPart = "Head",
        drawCircle = false,
        targetChangeTime = 0.5,
        showHitPartNotification = false,
        notificationSize = 20,
        maxDistance = 120,
    },
    currentTarget = nil,
    visualizeConnection = nil,
    randomizerTimer = 0,
}

local ValidParts = { "Head", "HumanoidRootPart", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local circle = Drawing.new("Circle")
circle.Visible = false
circle.Transparency = 1
circle.Thickness = 1.5
circle.Filled = false

local notificationText = Drawing.new("Text")
notificationText.Visible = false
notificationText.Color = Color3.fromRGB(255, 255, 255)
notificationText.Center = true
notificationText.Outline = true
notificationText.Font = 2
notificationText.Size = IS_MOBILE and 26 or 20

local function UpdateCircleProps()
    circle.Color = SilentAim.settings.drawColor
    circle.Radius = SilentAim.settings.drawSize
end

local DrawCircleConnection
local function UpdateCircle()
    if DrawCircleConnection then
        DrawCircleConnection:Disconnect()
        DrawCircleConnection = nil
    end
    if SilentAim.settings.drawCircle then
        circle.Visible = true
        UpdateCircleProps()
        local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        DrawCircleConnection = RunService.RenderStepped:Connect(function()
            circle.Position = screenCenter
        end)
    else
        circle.Visible = false
    end
end

local function ShowHitPartNotification(newPart)
    if not SilentAim.settings.showHitPartNotification then
        return
    end
    notificationText.Size = SilentAim.settings.notificationSize
    notificationText.Text = "New Hit Part: " .. newPart
    notificationText.Position = Vector2.new(Camera.ViewportSize.X - 200, Camera.ViewportSize.Y / 2 - (IS_MOBILE and 60 or 0))
    notificationText.Visible = true
    task.delay(1, function()
        notificationText.Visible = false
    end)
end

local randomTargetConnection
local function StopRandomizer()
    if randomTargetConnection then
        randomTargetConnection:Disconnect()
        randomTargetConnection = nil
    end
end

local function StartRandomizer()
    StopRandomizer()
    if not SilentAim.enabled or SilentAim.settings.targetPart ~= "Random" then
        return
    end
    SilentAim.randomizerTimer = 0
    randomTargetConnection = RunService.Heartbeat:Connect(function(dt)
        SilentAim.randomizerTimer = (SilentAim.randomizerTimer or 0) + dt
        if SilentAim.randomizerTimer >= SilentAim.settings.targetChangeTime then
            local currentPart = SilentAim.settings.actualPart
            local newPart = ValidParts[math.random(1, #ValidParts)]
            if newPart ~= currentPart then
                SilentAim.settings.actualPart = newPart
                ShowHitPartNotification(newPart)
            end
            SilentAim.randomizerTimer = 0
        end
    end)
end

local function IsPlayerDowned(p)
    if not p or not p.Character then
        return false
    end
    local hum = p.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 15 then
        return true
    end

    local cs = p.Character:FindFirstChild("CharStats")
    if cs then
        local downed = cs:FindFirstChild("Downed")
        if downed and typeof(downed.Value) == "boolean" then
            return downed.Value
        end
    end
    return false
end

local function GetSilentAimTarget(IsPlayerWhitelisted, IsPlayerTargeted)
    if not SilentAim.enabled then
        return nil
    end
    local closest, minDist = nil, SilentAim.settings.drawSize
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not localRoot then
        return nil
    end

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then
            continue
        end
        if SilentAim.settings.teamCheck and player.Team == LocalPlayer.Team then
            continue
        end
        if SilentAim.settings.checkWhitelist and IsPlayerWhitelisted and IsPlayerWhitelisted(player) then
            continue
        end
        if SilentAim.settings.checkTarget and IsPlayerTargeted and not IsPlayerTargeted(player) then
            continue
        end

        local character = player.Character
        if not character then
            continue
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart")
        if
            not humanoid
            or not root
            or humanoid.Health <= 0
            or character:FindFirstChildOfClass("ForceField")
        then
            continue
        end
        if SilentAim.settings.checkDowned and IsPlayerDowned(player) then
            continue
        end

        local partName = SilentAim.settings.targetPart == "Random" and SilentAim.settings.actualPart
            or SilentAim.settings.targetPart
        local part = character:FindFirstChild(partName)
        if not part then
            continue
        end

        if (localRoot.Position - part.Position).Magnitude > SilentAim.settings.maxDistance then
            continue
        end
        if SilentAim.settings.checkWall then
            local parts = Camera:GetPartsObscuringTarget(
                { part.Position },
                { Camera, LocalPlayer.Character, character }
            )
            if #parts > 0 then
                continue
            end
        end

        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if onScreen then
            local distance = (screenCenter - Vector2.new(screenPos.X, screenPos.Y)).Magnitude
            if distance < minDist then
                closest = player
                minDist = distance
            end
        end
    end

    if closest and SilentAim.settings.useHitChance and math.random(1, 100) > SilentAim.settings.hitChance then
        return nil
    end
    return closest
end

function SilentAim:Toggle(val, IsPlayerWhitelisted, IsPlayerTargeted)
    self.enabled = val

    if self.visualizeConnection then
        self.visualizeConnection:Disconnect()
        self.visualizeConnection = nil
    end
    if self.silentAimTask then
        task.cancel(self.silentAimTask)
        self.silentAimTask = nil
    end

    if val then
        self.silentAimTask = task.spawn(function()
            while self.enabled do
                self.currentTarget = GetSilentAimTarget(IsPlayerWhitelisted, IsPlayerTargeted)
                task.wait(0.1)
            end
        end)
        StartRandomizer()

        local success1, visualizeEvent = pcall(function()
            return ReplicatedStorage:FindFirstChild("Events2", 5):FindFirstChild("Visualize", 5)
        end)

        local success2, damageEvent = pcall(function()
            return ReplicatedStorage:FindFirstChild("Events", 5):FindFirstChild("ZFKLF__H", 5)
        end)

        if success1 and success2 and visualizeEvent and damageEvent then
            self.visualizeConnection = visualizeEvent.Event:Connect(
                function(_, shotCode, _, gun, _, startPos, bulletsPerShot)
                    local target = self.currentTarget
                    if not self.enabled or not gun or not target or not target.Character then
                        return
                    end
                    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
                    if not tool or gun ~= tool or target.Character:FindFirstChildOfClass("ForceField") then
                        return
                    end

                    local partName = self.settings.targetPart == "Random" and self.settings.actualPart
                        or self.settings.targetPart
                    local validPartName = partName
                    if partName == "HumanoidRootPart" then
                        validPartName = target.Character:FindFirstChild("UpperTorso") and "UpperTorso"
                            or target.Character:FindFirstChild("Torso") and "Torso"
                            or target.Character:FindFirstChild("LowerTorso") and "LowerTorso"
                            or "Head"
                    end

                    local hitPart = target.Character:FindFirstChild(validPartName)
                    if not hitPart then
                        return
                    end

                    local hitPos = hitPart.Position
                    local bullets = {}
                    local bulletCount = type(bulletsPerShot) == "table" and #bulletsPerShot or 1
                    for i = 1, math.clamp(bulletCount, 1, 100) do
                        bullets[i] = CFrame.new(startPos, hitPos).LookVector
                    end

                    task.wait(0.005)
                    for idx, direction in pairs(bullets) do
                        pcall(function()
                            damageEvent:FireServer("🧈", gun, shotCode, idx, hitPart, hitPos, direction)
                        end)
                    end

                    if gun:FindFirstChild("Hitmarker") then
                        pcall(function()
                            gun.Hitmarker:Fire(hitPart)
                        end)
                    end
                end
            )
        end
    else
        StopRandomizer()
    end
end

function SilentAim:UpdateCircle()
    UpdateCircle()
end

function SilentAim:UpdateCircleProps()
    UpdateCircleProps()
end

function SilentAim:StartRandomizer()
    StartRandomizer()
end

function SilentAim:StopRandomizer()
    StopRandomizer()
end

local MeleeAura = {
    enabled = false,
    settings = {
        showAnim = false,
        targetPart = "Head",
        checkDowned = true,
        teamCheck = false,
        checkWhitelist = false,
        checkTarget = false,
        distance = 10,
        targetChangeTime = 0.5,
    },
    randomPart = "Head",
}

local ValidPartsMelee = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local function IsDownedMelee(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid then
        return true
    end
    if humanoid.Health <= 15 then
        return true
    end

    local stats = character:FindFirstChild("CharStats")
    if not stats then
        for _ = 1, 5 do
            task.wait(0.1)
            stats = character:FindFirstChild("CharStats")
            if stats then
                break
            end
        end
    end
    local downed = stats and stats:FindFirstChild("Downed")
    if downed and downed:IsA("BoolValue") then
        return downed.Value == true
    end

    return false
end

function MeleeAura:StartRandomizer()
    task.spawn(function()
        while true do
            if self.enabled and self.settings.targetPart == "Random" then
                self.randomPart = ValidPartsMelee[math.random(1, #ValidPartsMelee)]
                task.wait(self.settings.targetChangeTime)
            else
                task.wait(0.5)
            end
        end
    end)
end

function MeleeAura:StartMainLoop(IsPlayerWhitelisted, IsPlayerTargeted)
    task.spawn(function()
        local remote1, remote2

        pcall(function()
            remote1 = ReplicatedStorage:FindFirstChild("Events", 5):FindFirstChild("XMHH.2", 5)
            remote2 = ReplicatedStorage:FindFirstChild("Events", 5):FindFirstChild("XMHH2.2", 5)
        end)

        if not remote1 or not remote2 then
            warn("Melee Aura: Required remotes not found")
            return
        end

        local attackTick = tick()
        local attackCooldown = 0.1

        local AttackCooldowns = {
            ["Fists"] = 0.05,
            ["Knuckledusters"] = 0.05,
            ["Nunchucks"] = 0.05,
            ["Shiv"] = 0.05,
            ["Bat"] = 1,
            ["Metal-Bat"] = 1,
            ["Chainsaw"] = 2.5,
            ["Balisong"] = 0.05,
            ["Rambo"] = 0.3,
            ["Shovel"] = 3,
            ["Sledgehammer"] = 2,
            ["Katana"] = 0.1,
            ["Wrench"] = 0.1,
            ["Fire Axe"] = 2,
        }

        local function GetTool()
            local character = LocalPlayer.Character
            return character and character:FindFirstChildOfClass("Tool")
        end

        local function GetMyHRP()
            local character = LocalPlayer.Character
            return character and character:FindFirstChild("HumanoidRootPart")
        end

        local function Attack(target)
            if not target then
                return
            end

            local character = LocalPlayer.Character
            local tool = GetTool()
            if not tool then
                return
            end

            local animationFolder = tool:FindFirstChild("AnimsFolder")
            local slashAnimation = animationFolder and animationFolder:FindFirstChild("Slash1")

            if tick() - attackTick >= attackCooldown then
                local success, result = pcall(function()
                    return remote1:InvokeServer("🍞", tick(), tool, "43TRFWX", "Normal", tick(), true)
                end)

                if not success then
                    return
                end

                attackCooldown = AttackCooldowns[tool.Name] or 0.5

                if self.settings.showAnim then
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    if humanoid and slashAnimation then
                        local animator = humanoid:FindFirstChild("Animator")
                        if animator then
                            local animationTrack = animator:LoadAnimation(slashAnimation)
                            animationTrack:Play()
                            animationTrack:AdjustSpeed(1.3)
                        end
                    end
                end

                task.wait(0.3)

                local handle = tool:FindFirstChild("WeaponHandle") or tool:FindFirstChild("Handle")
                if not handle and character then
                    handle = character:FindFirstChild("Right Arm")
                end

                local hitPartName = self.settings.targetPart == "Random" and self.randomPart
                    or self.settings.targetPart
                local targetPart = target:FindFirstChild(hitPartName)
                local myHRP = GetMyHRP()

                if not handle or not targetPart or not myHRP then
                    return
                end

                local arguments = {
                    "🍞",
                    tick(),
                    tool,
                    "2389ZFX34",
                    result,
                    true,
                    handle,
                    targetPart,
                    target,
                    myHRP.Position,
                    targetPart.Position,
                }

                pcall(function()
                    if tool.Name == "Chainsaw" then
                        for i = 1, 15 do
                            remote2:FireServer(unpack(arguments))
                        end
                    else
                        remote2:FireServer(unpack(arguments))
                    end
                end)

                attackTick = tick()
            end
        end

        LocalPlayer.CharacterAdded:Connect(function(character)
            repeat
                task.wait()
            until character:FindFirstChild("HumanoidRootPart")
        end)

        while true do
            if self.enabled then
                local myHRP = GetMyHRP()
                if myHRP then
                    for _, player in pairs(Players:GetPlayers()) do
                        if player ~= LocalPlayer then
                            local character = player.Character
                            local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
                            local humanoid = character and character:FindFirstChildOfClass("Humanoid")

                            if humanoidRootPart and humanoid then
                                local distance = (myHRP.Position - humanoidRootPart.Position).Magnitude
                                if distance <= self.settings.distance then
                                    if self.settings.teamCheck and player.Team == LocalPlayer.Team then
                                        continue
                                    end
                                    if self.settings.checkDowned and IsDownedMelee(player) then
                                        continue
                                    end
                                    if self.settings.checkWhitelist and IsPlayerWhitelisted and IsPlayerWhitelisted(player) then
                                        continue
                                    end
                                    if self.settings.checkTarget and IsPlayerTargeted and not IsPlayerTargeted(player) then
                                        continue
                                    end

                                    Attack(character)
                                end
                            end
                        end
                    end
                end
            end
            task.wait(0.1)
        end
    end)
end

local MeleeReach = {
    enabled = false,
    loopRunning = false,
    loopTask = nil,
    settings = {
        checkDowned = true,
        checkWhitelist = false,
        checkTarget = false,
        distance = 10,
        teamCheck = false,
    },
}

local function isDownedReach(player)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not character or not humanoid then
        return true
    end

    if humanoid.Health <= 15 then
        return true
    end

    local stats = character:FindFirstChild("CharStats")
    local downed = stats and stats:FindFirstChild("Downed")

    return downed and downed:IsA("BoolValue") and downed.Value == true or false
end

local function isEligible(player, isPlayerWhitelisted, isPlayerTargeted)
    if not player or player == LocalPlayer then
        return false
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not character or not humanoid or not root or humanoid.Health <= 0 then
        return false
    end

    if character:FindFirstChildOfClass("ForceField") then
        return false
    end

    if MeleeReach.settings.teamCheck and player.Team == LocalPlayer.Team then
        return false
    end

    if MeleeReach.settings.checkDowned and isDownedReach(player) then
        return false
    end

    if MeleeReach.settings.checkWhitelist and isPlayerWhitelisted and isPlayerWhitelisted(player) then
        return false
    end

    if MeleeReach.settings.checkTarget and isPlayerTargeted and not isPlayerTargeted(player) then
        return false
    end

    return true
end

local function getEquippedTool(character)
    if not character then
        return nil
    end

    for _, child in pairs(character:GetChildren()) do
        if child:IsA("Tool") then
            return child
        end
    end

    return nil
end

local function randomAxisOffset(size)
    local extent = math.max(0, math.floor(math.abs(size) * 10))

    if extent == 0 then
        return 0
    end

    return math.random(-extent, extent) / 10
end

local function randomPointInPart(part)
    local size = part.Size

    return part.Position
        + Vector3.new(randomAxisOffset(size.X), randomAxisOffset(size.Y), randomAxisOffset(size.Z))
end

local function collectReachObjects(tool, character)
    local objects = {}

    if not tool then
        return objects
    end

    local weaponHandle = tool:FindFirstChild("WeaponHandle")

    if weaponHandle then
        for _, child in pairs(weaponHandle:GetChildren()) do
            objects[#objects + 1] = child
        end
    end

    if tool.Name == "Fists" and character then
        local leftArm = character:FindFirstChild("Left Arm")
        local rightArm = character:FindFirstChild("Right Arm")

        if leftArm then
            objects[#objects + 1] = leftArm
        end

        if rightArm then
            objects[#objects + 1] = rightArm
        end
    end

    if tool.Name == "Sledgehammer" and weaponHandle then
        objects[#objects + 1] = weaponHandle
    end

    return objects
end

local function placeReachObject(object, targetRoot)
    if not object or not targetRoot then
        return
    end

    local targetFrame = CFrame.new(randomPointInPart(targetRoot))

    if object:IsA("BasePart") then
        pcall(function()
            object.CFrame = targetFrame
        end)
    else
        pcall(function()
            object.WorldCFrame = targetFrame * CFrame.new(0, 0.5, 0)
        end)

        pcall(function()
            object.CFrame = CFrame.new(0, 0.4, 0)
        end)
    end
end

local function processTarget(tool, localCharacter, player)
    local targetCharacter = player.Character
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")

    if not targetRoot or not localRoot then
        return
    end

    if (targetRoot.Position - localRoot.Position).Magnitude > MeleeReach.settings.distance then
        return
    end

    for _, object in pairs(collectReachObjects(tool, localCharacter)) do
        placeReachObject(object, targetRoot)
    end
end

function MeleeReach:StartMainLoop(isPlayerWhitelisted, isPlayerTargeted)
    if self.loopRunning then
        return self.loopTask
    end

    self.loopRunning = true
    self.loopTask = task.spawn(function()
        while self.loopRunning do
            if self.enabled then
                local character = LocalPlayer.Character
                local tool = getEquippedTool(character)

                if character and tool then
                    for _, player in pairs(Players:GetPlayers()) do
                        if isEligible(player, isPlayerWhitelisted, isPlayerTargeted) then
                            processTarget(tool, character, player)
                        end
                    end
                end
            end

            task.wait(0.05)
        end

        self.loopTask = nil
    end)

    return self.loopTask
end

local InvisActive = false
local InvisPossible = true
local InvisAnim = Instance.new("Animation")
InvisAnim.AnimationId = "rbxassetid://215384594"
local InvisAnimTrack = nil
local InvisWarningLabel = nil

local function isGrounded()
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid:IsDescendantOf(workspace) and humanoid.FloorMaterial ~= Enum.Material.Air
end

local function loadInvisAnim()
    if InvisAnimTrack then
        pcall(function() InvisAnimTrack:Stop() end)
        InvisAnimTrack = nil
    end
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local success, track = pcall(function() return humanoid:LoadAnimation(InvisAnim) end)
        if success then
            InvisAnimTrack = track
            InvisAnimTrack.Priority = Enum.AnimationPriority.Action4
        else
            InvisAnimTrack = nil
        end
    else
        InvisAnimTrack = nil
    end
end

local function disableInvis()
    if not InvisActive then return end
    InvisActive = false
    if InvisAnimTrack then
        pcall(function() InvisAnimTrack:Stop() end)
    end
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        workspace.CurrentCamera.CameraSubject = humanoid
    end
    if char then
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency == 0.5 then
                part.Transparency = 0
            end
        end
    end
    if InvisWarningLabel then
        InvisWarningLabel.Visible = false
    end
end

local function enableInvis()
    if InvisActive or not InvisPossible then return end
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not humanoid or not hrp then return end
    if not char:FindFirstChild("Torso") then
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "Invisible Error",
                Text = "Requires R6 character for full invisibility.",
                Duration = 5,
            })
        end)
        InvisPossible = false
        return
    end
    InvisActive = true
    workspace.CurrentCamera.CameraSubject = hrp
    loadInvisAnim()
end

local function toggleInvis()
    if InvisActive then
        disableInvis()
    else
        enableInvis()
    end
    return InvisActive
end

local function setupInvisWarning()
    local coreGui = game:GetService("CoreGui")
    local warningGui = Instance.new("ScreenGui")
    warningGui.Name = "InvisWarningGUI"
    warningGui.Parent = coreGui
    warningGui.ResetOnSpawn = false
    warningGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    InvisWarningLabel = Instance.new("TextLabel", warningGui)
    InvisWarningLabel.Text = "YOU ARE VISIBLE"
    InvisWarningLabel.Visible = false
    InvisWarningLabel.Size = UDim2.new(0, 200, 0, 30)
    InvisWarningLabel.Position = UDim2.new(0.5, -100, 0.85, 0)
    InvisWarningLabel.BackgroundTransparency = 1
    InvisWarningLabel.Font = Enum.Font.GothamSemibold
    InvisWarningLabel.TextSize = 24
    InvisWarningLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
    InvisWarningLabel.TextStrokeTransparency = 0.5
    InvisWarningLabel.ZIndex = 10
end
setupInvisWarning()

RunService.Heartbeat:Connect(function()
    if not InvisActive or not InvisPossible then
        local char = LocalPlayer.Character
        if not InvisActive and char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Transparency == 0.5 then
                    part.Transparency = 0
                end
            end
        end
        if InvisWarningLabel then
            InvisWarningLabel.Visible = false
        end
        return
    end
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not humanoid or not hrp or not humanoid:IsDescendantOf(workspace) or humanoid.Health <= 0 then
        if InvisWarningLabel then InvisWarningLabel.Visible = false end
        return
    end
    if InvisWarningLabel then
        InvisWarningLabel.Visible = not isGrounded()
    end

    local speed = 12
    if humanoid.MoveDirection.Magnitude > 0 then
        local move = humanoid.MoveDirection * speed * RunService.Heartbeat:Wait()
        hrp.CFrame = hrp.CFrame + move
    end

    local originalCF = hrp.CFrame
    local originalCamOffset = humanoid.CameraOffset
    local _, cameraYaw = workspace.CurrentCamera.CFrame:ToOrientation()

    hrp.CFrame = CFrame.new(hrp.CFrame.Position) * CFrame.fromOrientation(0, cameraYaw, 0)
    hrp.CFrame = hrp.CFrame * CFrame.Angles(math.rad(90), 0, 0)
    humanoid.CameraOffset = Vector3.new(0, 1.44, 0)

    if InvisAnimTrack then
        local success = pcall(function()
            if not InvisAnimTrack.IsPlaying then
                InvisAnimTrack:Play()
            end
            InvisAnimTrack:AdjustSpeed(0)
            InvisAnimTrack.TimePosition = 0.3
        end)
        if not success then
            loadInvisAnim()
        end
    elseif humanoid and humanoid.Health > 0 then
        loadInvisAnim()
    end

    RunService.RenderStepped:Wait()

    if humanoid and humanoid:IsDescendantOf(workspace) then
        humanoid.CameraOffset = originalCamOffset
    end
    if hrp and hrp:IsDescendantOf(workspace) then
        hrp.CFrame = originalCF
    end
    if InvisAnimTrack then
        pcall(function() InvisAnimTrack:Stop() end)
    end
    if hrp and hrp:IsDescendantOf(workspace) then
        local lookVec = workspace.CurrentCamera.CFrame.LookVector
        local flatLook = Vector3.new(lookVec.X, 0, lookVec.Z).Unit
        if flatLook.Magnitude > 0.1 then
            hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + flatLook)
        end
    end
    if char then
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency ~= 1 then
                part.Transparency = 0.5
            end
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function(newChar)
    if InvisAnimTrack then
        pcall(function() InvisAnimTrack:Stop() end)
        InvisAnimTrack = nil
    end
    task.wait()
    local humanoid = newChar:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        task.wait(0.5)
        humanoid = newChar:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            InvisPossible = false
            if InvisActive then disableInvis() end
            return
        end
    end
    if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
        InvisPossible = false
        if InvisActive then disableInvis() end
        return
    else
        InvisPossible = true
    end
    if InvisActive then
        local hrp = newChar:FindFirstChild("HumanoidRootPart")
        if hrp then workspace.CurrentCamera.CameraSubject = hrp end
        loadInvisAnim()
    end
end)

local highlights = {}

local function updateHighlights()
    for _, h in pairs(highlights) do
        if h and h.Parent then
            h:Destroy()
        end
    end
    highlights = {}

    if not settings.highlight then
        return
    end

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local char = player.Character
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local humanoid = char:FindFirstChild("Humanoid")
            if hrp and humanoid and humanoid.Health > 0 then
                local h = Instance.new("Highlight")
                h.Adornee = char
                h.FillColor = Color3.fromRGB(255, 0, 0)
                h.FillTransparency = 0.5
                h.OutlineColor = Color3.fromRGB(255, 255, 255)
                h.OutlineTransparency = 0
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = char
                table.insert(highlights, h)
            end
        end
    end
end

local spinbotActive = false

local function updateSpinbot()
    if not settings.spinbot then
        spinbotActive = false
        return
    end

    local char = LocalPlayer.Character
    if not char then
        return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end

    spinbotActive = true
    hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(15), 0)
end

RunService.RenderStepped:Connect(function()
    if spinbotActive then
        updateSpinbot()
    end
end)

local espElements = {}
local espEnabled = false
local espTextSize = 20

local function formatName(rawName)
    rawName = string.gsub(rawName, "([a-z])([A-Z])", "%1 %2")
    rawName = string.gsub(rawName, "_", " ")
    if rawName:lower():find("safe") then
        return "Safe " .. rawName
    elseif rawName:lower():find("register") then
        return "Register " .. rawName
    end
    return rawName
end

local function createHighlight(part, color)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight"
    highlight.Adornee = part
    highlight.FillColor = color
    highlight.FillTransparency = 0.5
    highlight.OutlineColor = Color3.new(1, 1, 1)
    highlight.OutlineTransparency = 0
    highlight.Parent = part
    return highlight
end

local function updateSafeESP()
    if not espEnabled then
        for obj, data in pairs(espElements) do
            pcall(function()
                if data.billboard then
                    data.billboard:Destroy()
                end
                if data.highlight then
                    data.highlight:Destroy()
                end
            end)
        end
        espElements = {}
        return
    end

    local bredFolder = nil
    local map = Workspace:FindFirstChild("Map")
    if map then
        bredFolder = map:FindFirstChild("BredMakurz")
    end
    if not bredFolder then
        local filter = Workspace:FindFirstChild("Filter")
        if filter then
            bredFolder = filter:FindFirstChild("BredMakurz")
        end
    end
    if not bredFolder then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj.Name == "BredMakurz" and obj:IsA("Folder") then
                bredFolder = obj
                break
            end
        end
    end
    if not bredFolder then
        return
    end

    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end

    for _, obj in ipairs(bredFolder:GetChildren()) do
        local nameLower = obj.Name:lower()
        if nameLower:find("safe") or nameLower:find("register") then
            local mainPart = obj.PrimaryPart or obj:FindFirstChildOfClass("BasePart")
            if not mainPart then
                continue
            end
            if mainPart.Position.Y < 4.8 then
                continue
            end

            local values = obj:FindFirstChild("Values")
            local brokenVal = values and values:FindFirstChild("Broken")
            local isBroken = brokenVal and brokenVal.Value
            local color = isBroken and Color3.new(1, 0, 0) or Color3.new(0, 1, 0)

            local esp = espElements[obj]
            if not esp then
                local billboard = Instance.new("BillboardGui")
                billboard.Name = "ESP_Billboard"
                billboard.Adornee = mainPart
                billboard.Size = UDim2.new(0, 200, 0, 50)
                billboard.StudsOffset = Vector3.new(0, 4, 0)
                billboard.AlwaysOnTop = true
                billboard.MaxDistance = 1000
                billboard.Parent = obj

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundTransparency = 1
                label.Font = Enum.Font.SourceSansBold
                label.TextScaled = false
                label.Text = formatName(obj.Name)
                label.TextColor3 = color
                label.TextStrokeTransparency = 0
                label.TextStrokeColor3 = Color3.new(0, 0, 0)
                label.TextSize = espTextSize
                label.Parent = billboard

                local highlight = createHighlight(obj, color)

                espElements[obj] = {
                    billboard = billboard,
                    highlight = highlight,
                    label = label
                }

                if brokenVal then
                    brokenVal:GetPropertyChangedSignal("Value"):Connect(function()
                        if not espEnabled or not espElements[obj] then
                            return
                        end
                        local e = espElements[obj]
                        if brokenVal.Value then
                            e.label.TextColor3 = Color3.new(1, 0, 0)
                            if e.highlight then
                                e.highlight.FillColor = Color3.new(1, 0, 0)
                            end
                        else
                            e.label.TextColor3 = Color3.new(0, 1, 0)
                            if e.highlight then
                                e.highlight.FillColor = Color3.new(0, 1, 0)
                            end
                        end
                    end)
                end
            else
                if brokenVal then
                    esp.label.TextColor3 = isBroken and Color3.new(1, 0, 0) or Color3.new(0, 1, 0)
                    if esp.highlight then
                        esp.highlight.FillColor = isBroken and Color3.new(1, 0, 0) or Color3.new(0, 1, 0)
                    end
                end
                if esp.label then
                    esp.label.TextSize = espTextSize
                end
            end
        end
    end

    for obj, data in pairs(espElements) do
        if not obj or not obj.Parent then
            pcall(function()
                if data.billboard then
                    data.billboard:Destroy()
                end
                if data.highlight then
                    data.highlight:Destroy()
                end
            end)
            espElements[obj] = nil
        end
    end
end

local bulletBeamStyles = {
    Classic = {
        id = "rbxassetid://446111271",
        len = 1,
        spd = 1,
    },
    Rainbow = {
        id = "rbxassetid://2490624870",
        len = 3,
        spd = 2,
    },
}

local function createBulletBeam(startPos, endPos)
    if not settings.bulletTracer then
        return
    end

    local ter = Workspace:FindFirstChildOfClass("Terrain")
    if not ter then
        return
    end

    local att1 = Instance.new("Attachment")
    local att2 = Instance.new("Attachment")
    att1.Position = startPos
    att2.Position = endPos
    att1.Parent = ter
    att2.Parent = ter

    local beam = Instance.new("Beam")
    local style = bulletBeamStyles[bulletTracerSettings.Design] or bulletBeamStyles.Classic
    beam.Attachment0 = att1
    beam.Attachment1 = att2
    beam.Color = ColorSequence.new(bulletTracerSettings.Color)
    beam.Width0 = bulletTracerSettings.Thickness
    beam.Width1 = bulletTracerSettings.Thickness * 0.4
    beam.Texture = style.id
    beam.TextureLength = style.len
    beam.TextureSpeed = style.spd
    beam.TextureMode = Enum.TextureMode.Wrap
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, bulletTracerSettings.Transparency * 0.4),
        NumberSequenceKeypoint.new(0.5, bulletTracerSettings.Transparency),
        NumberSequenceKeypoint.new(1, 1),
    })
    beam.FaceCamera = true
    beam.LightEmission = 0.6
    beam.LightInfluence = 0.1
    beam.Parent = ter

    task.delay(bulletTracerSettings.Life, function()
        pcall(function()
            beam:Destroy()
            att1:Destroy()
            att2:Destroy()
        end)
    end)
end

local function setupTracerInterception()
    local events2 = ReplicatedStorage:FindFirstChild("Events2")
    local visualize = events2 and events2:FindFirstChild("Visualize")
    if visualize and visualize.Event then
        visualize.Event:Connect(function(_, _, _, tool, _, origin, directions)
            if not settings.bulletTracer or not tool then
                return
            end
            local char = LocalPlayer.Character
            if not char or char:FindFirstChildOfClass("Tool") ~= tool then
                return
            end

            local muzzle = tool and (tool:FindFirstChild("Muzzle", true) or tool:FindFirstChild("FirePoint", true))
            local startPos = origin
            if muzzle then
                startPos = muzzle:IsA("Attachment") and muzzle.WorldPosition or muzzle.Position
            end

            if type(directions) == "table" then
                for _, dir in pairs(directions) do
                    if typeof(dir) == "Vector3" and dir.Magnitude > 0 then
                        local params = RaycastParams.new()
                        params.FilterType = Enum.RaycastFilterType.Exclude
                        params.FilterDescendantsInstances = { Camera, char, tool }
                        params.IgnoreWater = true
                        local result = Workspace:Raycast(startPos, dir.Unit * 1000, params)
                        createBulletBeam(startPos, result and result.Position or startPos + dir.Unit * 500)
                    end
                end
            end
        end)
    end
end
setupTracerInterception()

local RageBot = {
    enabled = false,
    loopTask = nil,
    lastShotTime = 0,
    lastHitNotify = {},
}

local RageCircle = Drawing.new("Circle")
RageCircle.Color = Color3.fromRGB(255, 255, 255)
RageCircle.Thickness = 1.5
RageCircle.Filled = false
RageCircle.Transparency = 0.5
RageCircle.Radius = rageBotSettings.fovRadius
RageCircle.Visible = false

local RageCircleConnection
local function UpdateRageCircle()
    if RageCircleConnection then
        RageCircleConnection:Disconnect()
        RageCircleConnection = nil
    end

    if rageBotSettings.showFOV then
        RageCircle.Visible = true
        RageCircle.Radius = rageBotSettings.fovRadius
        RageCircleConnection = RunService.RenderStepped:Connect(function()
            RageCircle.Position = UserInputService:GetMouseLocation()
        end)
    else
        RageCircle.Visible = false
    end
end

local function createTracer(startPos, endPos)
    if not rageBotSettings.bulletTracerEnabled then
        return
    end

    local tracer = Instance.new("Part")
    tracer.Anchored = true
    tracer.CanCollide = false
    tracer.Material = Enum.Material.Neon
    tracer.Color = rageBotSettings.tracerColor
    tracer.Shape = Enum.PartType.Cylinder
    local distance = (startPos - endPos).Magnitude
    tracer.Size = Vector3.new(distance, 0.12, 0.12)
    tracer.CFrame = CFrame.new((startPos + endPos) / 2, endPos) * CFrame.Angles(0, math.pi / 2, 0)
    tracer.Parent = Workspace
    task.spawn(function()
        for t = 0, 1, 0.02 do
            if tracer then
                tracer.Transparency = t
                task.wait(1 / 50)
            end
        end
        if tracer then
            tracer:Destroy()
        end
    end)
end

local function RandomString(len)
    local s = ""
    for i = 1, len do
        s = s .. string.char(math.random(97, 122))
    end
    return s
end

local function IsValidTarget(p)
    if not p or not p.Character then
        return false
    end
    if p == LocalPlayer then
        return false
    end
    if rageBotSettings.teamCheck and p.Team == LocalPlayer.Team then
        return false
    end
    local hum = p.Character:FindFirstChildOfClass("Humanoid")
    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then
        return false
    end
    if hum.Health <= 0 then
        return false
    end
    if p.Character:FindFirstChildOfClass("ForceField") then
        return false
    end
    if rageBotSettings.checkDowned and IsPlayerDowned(p) then
        return false
    end
    return true
end

local function GetHeadPart(char)
    if not char then
        return nil
    end
    return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end

local function MakeRaycastParams()
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Blacklist
    rp.FilterDescendantsInstances = {}
    if LocalPlayer.Character then
        table.insert(rp.FilterDescendantsInstances, LocalPlayer.Character)
    end
    rp.IgnoreWater = true
    return rp
end

local WallbangSamples = 72
local WallbangRadius = 10
local WallbangHeight = 6

local function FindWallbangPoint(origin, targetPart)
    if not origin or not targetPart then
        return nil
    end
    local base = targetPart.Position
    local rp = MakeRaycastParams()
    for i = 1, WallbangSamples do
        local angle = (i / WallbangSamples) * math.pi * 2
        local r = WallbangRadius * (0.6 + math.random() * 0.8)
        local yOff = (math.random() * 2 - 1) * WallbangHeight
        local offset = Vector3.new(math.cos(angle) * r, yOff, math.sin(angle) * r)
        local testPoint = base + offset
        local dir = (testPoint - origin)
        if dir.Magnitude > 0 then
            local result = Workspace:Raycast(origin, dir, rp)
            if result then
                if result.Instance and result.Instance:IsDescendantOf(targetPart.Parent) then
                    return testPoint
                else
                    local distHitToTarget = (result.Position - base).Magnitude
                    if distHitToTarget <= 2.0 then
                        return testPoint
                    end
                end
            else
                return testPoint
            end
        end
    end
    return nil
end

local function GetClosestEnemy()
    local me = LocalPlayer.Character
    if not me or not me:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    local closest, shortest = nil, math.huge
    local originPos = me.HumanoidRootPart.Position

    for _, p in ipairs(Players:GetPlayers()) do
        if IsValidTarget(p) then
            local head = GetHeadPart(p.Character)
            if head then
                local dist3D = (originPos - head.Position).Magnitude
                if dist3D <= rageBotSettings.maxDistance then
                    if rageBotSettings.useFOV then
                        local mousePos = UserInputService:GetMouseLocation()
                        local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                        if onScreen then
                            local d2 = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                            if d2 <= rageBotSettings.fovRadius and d2 < shortest then
                                shortest = d2
                                closest = p
                            end
                        end
                    else
                        if dist3D < shortest then
                            shortest = dist3D
                            closest = p
                        end
                    end
                end
            end
        end
    end
    return closest
end

local function SendHitNotification(targetPlayer, health)
    if not rageBotSettings.hitlogEnabled then
        return
    end
    if not targetPlayer then
        return
    end
    local now = tick()
    local id = targetPlayer.UserId or targetPlayer.Name
    if RageBot.lastHitNotify[id] and now - RageBot.lastHitNotify[id] < 0.35 then
        return
    end
    RageBot.lastHitNotify[id] = now

    Notify("RageBot HitLog", "Hit " .. targetPlayer.Name .. " | Health: " .. math.floor(health or 0), 2)
end

local function Shoot(target)
    if not target or not target.Character then
        return
    end
    local head = GetHeadPart(target.Character)
    if not head then
        return
    end
    if not LocalPlayer.Character then
        return
    end
    local tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if not tool then
        return
    end
    local values = tool:FindFirstChild("Values")
    local hitMarker = tool:FindFirstChild("Hitmarker")
    if not values or not hitMarker then
        return
    end
    local ammo = values:FindFirstChild("SERVER_Ammo")
    if not ammo or ammo.Value <= 0 then
        return
    end

    local handle = tool:FindFirstChild("WeaponHandle")
    local origin = (handle and handle.Position) or Camera.CFrame.Position
    local aimPos = head.Position
    local dir = (aimPos - origin)
    local rp = MakeRaycastParams()

    local ray = Workspace:Raycast(origin, dir, rp)
    local lineOfSight = false
    if ray and ray.Instance and ray.Instance:IsDescendantOf(target.Character) then
        lineOfSight = true
    elseif not ray then
        lineOfSight = true
    end

    local chosenAimPoint = aimPos
    local wallbangFound = false
    if not lineOfSight then
        local found = FindWallbangPoint(origin, head)
        if found then
            chosenAimPoint = found
            wallbangFound = true
        end
    end

    if not lineOfSight and rageBotSettings.wallCheck and not wallbangFound then
        return
    end

    local finalDir = (chosenAimPoint - origin).Unit
    local key = RandomString(30) .. "0"

    local fireRemote = ReplicatedStorage:FindFirstChild("Events", true):FindFirstChild("GNX_S")
    local hitRemote = ReplicatedStorage:FindFirstChild("Events", true):FindFirstChild("ZFKLF__H")

    if fireRemote and hitRemote then
        pcall(function()
            fireRemote:FireServer(tick(), key, tool, "FDS9I83", origin, { finalDir }, false)
        end)
        pcall(function()
            hitRemote:FireServer("🧈", tool, key, 1, head, chosenAimPoint, finalDir)
        end)
    end

    ammo.Value = math.max(0, ammo.Value - 1)
    pcall(function()
        hitMarker:Fire(head)
    end)
    createTracer(origin, chosenAimPoint)

    if settings.hitSound then
        pcall(function()
            local sound = Instance.new("Sound")
            sound.SoundId = "rbxassetid://8679627751"
            sound.Volume = 0.5
            sound.Parent = workspace
            sound:Play()
            task.delay(sound.TimeLength + 0.1, function()
                sound:Destroy()
            end)
        end)
    end

    local hum = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
    local remaining = hum and hum.Health or 0
    SendHitNotification(target, remaining)
end

function RageBot:Toggle(val)
    self.enabled = val
    if val then
        if self.loopTask then
            return
        end
        self.loopTask = task.spawn(function()
            while self.enabled and LocalPlayer.Character do
                local ok, tool = pcall(function()
                    return LocalPlayer.Character:FindFirstChildOfClass("Tool")
                end)
                if not ok or not tool then
                    task.wait(0.2)
                    continue
                end

                local target = GetClosestEnemy()
                if target then
                    local now = tick()
                    if now - self.lastShotTime >= rageBotSettings.fireInterval then
                        Shoot(target)
                        self.lastShotTime = now
                    end
                end
                task.wait(0.05)
            end
            self.loopTask = nil
        end)
    end
end

function RageBot:UpdateShootSpeed(val)
    rageBotSettings.shootSpeed = val
    rageBotSettings.fireInterval = math.max(0.03, 0.35 - (val * 0.012))
end

function RageBot:UpdateFOVCircle()
    UpdateRageCircle()
end

local hitSoundConnections = {}

local function setupHitSound()
    for _, conn in pairs(hitSoundConnections) do
        if conn then
            pcall(function()
                conn:Disconnect()
            end)
        end
    end
    hitSoundConnections = {}

    if not settings.hitSound then
        return
    end

    local events2 = ReplicatedStorage:FindFirstChild("Events2")
    local visualize = events2 and events2:FindFirstChild("Visualize")
    if visualize and visualize.Event then
        local conn = visualize.Event:Connect(function(_, _, _, gun, _, _, _)
            if gun and LocalPlayer.Character then
                local tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
                if tool and tool == gun then
                    pcall(function()
                        local sound = Instance.new("Sound")
                        sound.SoundId = "rbxassetid://8679627751"
                        sound.Volume = 0.5
                        sound.Parent = workspace
                        sound:Play()
                        task.delay(sound.TimeLength + 0.1, function()
                            sound:Destroy()
                        end)
                    end)
                end
            end
        end)
        table.insert(hitSoundConnections, conn)
    end

    local events = ReplicatedStorage:FindFirstChild("Events")
    local meleeHit = events and events:FindFirstChild("XMHH2.2")
    if meleeHit and meleeHit.OnClientEvent then
        local conn = meleeHit.OnClientEvent:Connect(function(tool, ...)
            if tool and LocalPlayer.Character then
                local myTool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
                if myTool and myTool == tool then
                    pcall(function()
                        local sound = Instance.new("Sound")
                        sound.SoundId = "rbxassetid://8679627751"
                        sound.Volume = 0.5
                        sound.Parent = workspace
                        sound:Play()
                        task.delay(sound.TimeLength + 0.1, function()
                            sound:Destroy()
                        end)
                    end)
                end
            end
        end)
        table.insert(hitSoundConnections, conn)
    end

    local gnx = events and events:FindFirstChild("GNX_S")
    if gnx and gnx.OnClientEvent then
        local conn = gnx.OnClientEvent:Connect(function(_, _, tool, ...)
            if tool and LocalPlayer.Character then
                local myTool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
                if myTool and myTool == tool then
                    pcall(function()
                        local sound = Instance.new("Sound")
                        sound.SoundId = "rbxassetid://8679627751"
                        sound.Volume = 0.5
                        sound.Parent = workspace
                        sound:Play()
                        task.delay(sound.TimeLength + 0.1, function()
                            sound:Destroy()
                        end)
                    end)
                end
            end
        end)
        table.insert(hitSoundConnections, conn)
    end
end

local Farm = {
    Enabled = false,
    Status = "Idle",
    ProcessedList = {},
    TempIgnored = {},
    IgnoredList = {},
    IsDead = false,
    TargetY = 4.8,
    HasReachedTargetY = false,
    IsRising = false,
    RetryCount = 0,
}

local function farmLog(msg)
    if farmSettings.DebugPrint then
        print("[AutoFarm]", msg)
    end
end

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function isDead()
    local humanoid = getHumanoid()
    return not humanoid or humanoid.Health <= 0
end

local function getMap()
    return Workspace:FindFirstChild("Map")
end

local function getBredFolder()
    local map = getMap()
    if map then
        local bred = map:FindFirstChild("BredMakurz")
        if bred then
            return bred
        end
    end
    local filter = Workspace:FindFirstChild("Filter")
    if filter then
        local bred = filter:FindFirstChild("BredMakurz")
        if bred then
            return bred
        end
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name == "BredMakurz" and obj:IsA("Folder") then
            return obj
        end
    end
    return nil
end

local function getTargetPart(obj)
    return obj:FindFirstChild("MainPart") or obj.PrimaryPart
end

local function isTargetBroken(obj)
    local values = obj:FindFirstChild("Values")
    local broken = values and values:FindFirstChild("Broken")
    return broken and broken:IsA("BoolValue") and broken.Value == true
end

local function cleanTempIgnored()
    local now = tick()
    for obj, expiry in pairs(Farm.TempIgnored) do
        if now > expiry then
            Farm.TempIgnored[obj] = nil
            for i, v in ipairs(Farm.IgnoredList) do
                if v == obj then
                    table.remove(Farm.IgnoredList, i)
                    break
                end
            end
            farmLog("Ignored object unlocked")
        end
    end
end

local function updateTargetsList()
    cleanTempIgnored()
    local bredFolder = getBredFolder()
    if not bredFolder then
        return 0, 0
    end
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return 0, 0
    end
    local targets = {}
    for _, obj in ipairs(bredFolder:GetChildren()) do
        local nameLower = obj.Name:lower()
        if nameLower:find("safe") or nameLower:find("register") then
            if Farm.ProcessedList[obj] then
                continue
            end
            if Farm.TempIgnored[obj] then
                continue
            end
            if isTargetBroken(obj) then
                continue
            end
            local mainPart = getTargetPart(obj)
            if mainPart and mainPart.Position.Y >= Farm.TargetY then
                table.insert(targets, {
                    obj = obj,
                    part = mainPart,
                    pos = mainPart.Position,
                    dist = (mainPart.Position - hrp.Position).Magnitude
                })
            end
        end
    end
    table.sort(targets, function(a, b)
        return a.dist < b.dist
    end)
    return targets, #targets
end

local function computePath(startPos, endPos)
    local pathParamsList = {
        { Radius = 1, Height = 4, Spacing = 2 },
        { Radius = 1.2, Height = 4.5, Spacing = 2.5 },
        { Radius = 1.5, Height = 5, Spacing = 3 },
        { Radius = 2, Height = 5.5, Spacing = 4 },
        { Radius = 2.5, Height = 6, Spacing = 5 },
        { Radius = 3, Height = 6.5, Spacing = 5 },
        { Radius = 3.5, Height = 7, Spacing = 6 },
        { Radius = 4, Height = 7.5, Spacing = 6 },
        { Radius = 1, Height = 8, Spacing = 3 },
        { Radius = 5, Height = 5, Spacing = 5 },
        { Radius = 1.8, Height = 4.2, Spacing = 2.2 },
        { Radius = 2.2, Height = 5.8, Spacing = 4.5 },
        { Radius = 2.8, Height = 6.2, Spacing = 5.5 },
        { Radius = 3.2, Height = 6.8, Spacing = 5.8 },
        { Radius = 3.8, Height = 7.2, Spacing = 6.2 }
    }
    for _, params in ipairs(pathParamsList) do
        local path = PathfindingService:CreatePath({
            AgentRadius = params.Radius,
            AgentHeight = params.Height,
            AgentCanJump = true,
            AgentCanClimb = true,
            WaypointSpacing = params.Spacing,
        })
        local success, _ = pcall(function()
            path:ComputeAsync(startPos, endPos)
        end)
        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            if waypoints and #waypoints >= 2 then
                return waypoints
            end
        end
        task.wait(0.05)
    end
    return nil
end

local function moveToTarget(targetPart)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid or isDead() then
        return false
    end

    local startPos = hrp.Position
    local targetPos = targetPart.Position

    if not Farm.HasReachedTargetY and startPos.Y < Farm.TargetY - 0.1 then
        farmLog("Rising to height " .. Farm.TargetY)
        Farm.Status = "Rising"
        local steps = 20
        for i = 1, steps do
            local alpha = i / steps
            local y = startPos.Y + (Farm.TargetY - startPos.Y) * alpha
            local pos = Vector3.new(startPos.X, y, startPos.Z)
            local tween = TweenService:Create(hrp, TweenInfo.new(0.1, Enum.EasingStyle.Linear), {
                CFrame = CFrame.new(pos)
            })
            tween:Play()
            tween.Completed:Wait()
        end
        Farm.HasReachedTargetY = true
    end

    Farm.Status = "Path to target"
    local path = computePath(startPos, targetPos)
    if not path then
        farmLog("Path not found")
        return false
    end

    for _, waypoint in ipairs(path) do
        if not Farm.Enabled or isDead() then
            return false
        end
        local wpPos = waypoint.Position
        local targetCF = CFrame.new(wpPos.X, wpPos.Y + 2.5, wpPos.Z)
        local dist = (wpPos - hrp.Position).Magnitude
        if dist > 0.5 then
            local duration = dist / farmSettings.MoveSpeed
            local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
                CFrame = targetCF
            })
            tween:Play()
            tween.Completed:Wait()
        end
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
            task.wait(0.1)
        end
    end

    farmLog("Target reached")
    Farm.Status = "At target"
    return true
end

local function hasTool(toolName)
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local character = LocalPlayer.Character
    return (backpack and backpack:FindFirstChild(toolName)) or (character and character:FindFirstChild(toolName))
end

local function equipTool(toolName)
    local tool = LocalPlayer:FindFirstChild("Backpack") and LocalPlayer.Backpack:FindFirstChild(toolName)
    if tool and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        pcall(function()
            LocalPlayer.Character.Humanoid:EquipTool(tool)
        end)
        task.wait(0.5)
        return true
    end
    return false
end

local function findCrowbarDealer()
    local map = getMap()
    if not map then
        return nil
    end
    local shops = map:FindFirstChild("Shopz")
    if not shops then
        return nil
    end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return nil
    end

    local closestDealer = nil
    local closestDist = math.huge
    for _, shop in ipairs(shops:GetChildren()) do
        local stocks = shop:FindFirstChild("CurrentStocks")
        if stocks then
            local crowbarStock = stocks:FindFirstChild("Crowbar")
            if crowbarStock and crowbarStock.Value > 0 then
                local mainPart = shop:FindFirstChild("MainPart")
                if mainPart then
                    local dist = (hrp.Position - mainPart.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closestDealer = shop
                    end
                end
            end
        end
    end
    return closestDealer
end

local function buyCrowbar()
    local dealer = findCrowbarDealer()
    if not dealer then
        farmLog("Crowbar dealer not found")
        return false
    end
    local mainPart = dealer:FindFirstChild("MainPart")
    if not mainPart then
        return false
    end

    Farm.Status = "Path to dealer"
    if not moveToTarget(mainPart) then
        farmLog("Failed to reach dealer")
        return false
    end

    Farm.Status = "Buying crowbar"
    task.wait(1.5)
    local events = ReplicatedStorage:FindFirstChild("Events")
    if events then
        pcall(function()
            events.BYZERSPROTEC:FireServer(true, "shop", mainPart, "IllegalStore")
        end)
        task.wait(1)
        pcall(function()
            events.SSHPRMTE1:InvokeServer("IllegalStore", "Melees", "Crowbar", mainPart, nil, true)
        end)
        task.wait(20)
        pcall(function()
            events.BYZERSPROTEC:FireServer(false)
        end)
    end
    task.wait(2)
    local has = hasTool("Crowbar")
    if has then
        farmLog("Crowbar bought successfully")
    else
        farmLog("Failed to buy crowbar")
    end
    return has
end

local function hackSafe(safeObj)
    if not hasTool("Crowbar") then
        farmLog("No crowbar, trying to buy...")
        if not buyCrowbar() then
            return false
        end
    end
    if not LocalPlayer.Character:FindFirstChild("Crowbar") then
        equipTool("Crowbar")
    end

    local events = ReplicatedStorage:FindFirstChild("Events")
    if not events then
        return false
    end
    local remote1 = events:FindFirstChild("XMHH.2")
    local remote2 = events:FindFirstChild("XMHH2.2")
    local mainPart = safeObj:FindFirstChild("MainPart") or safeObj.PrimaryPart
    if not remote1 or not remote2 or not mainPart then
        return false
    end

    farmLog("Hacking safe")
    Farm.Status = "Hacking"
    local startTime = tick()
    local hits = 0

    while Farm.Enabled and safeObj.Parent and not isTargetBroken(safeObj) and tick() - startTime < 25 do
        local crowbar = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Crowbar")
        if not crowbar then
            crowbar = LocalPlayer.Backpack and LocalPlayer.Backpack:FindFirstChild("Crowbar")
            if crowbar then
                equipTool("Crowbar")
            end
        end
        if not crowbar then
            break
        end

        local arm = LocalPlayer.Character:FindFirstChild("Right Arm") or LocalPlayer.Character:FindFirstChild("RightHand")
        if not arm then
            break
        end

        local success, result = pcall(function()
            return remote1:InvokeServer("🍞", tick(), crowbar, "DZDRRRKI", safeObj, "Register")
        end)
        if success and result then
            pcall(function()
                remote2:FireServer("🍞", tick(), crowbar, "2389ZFX34", result, false, arm, mainPart, safeObj, mainPart.Position, mainPart.Position)
            end)
            hits = hits + 1
        end
        task.wait(0.4)
    end

    farmLog("Hacking complete, hits: " .. hits)
    Farm.Status = "Idle"
    return isTargetBroken(safeObj)
end

local function collectMoneyNearTarget(targetObj)
    if not settings.autoMoney then
        return false
    end
    local spawnedBread = Workspace:FindFirstChild("Filter") and Workspace.Filter:FindFirstChild("SpawnedBread")
    if not spawnedBread then
        return false
    end

    local mainPart = getTargetPart(targetObj)
    if not mainPart then
        return false
    end

    local collected = 0
    local pickupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("CZDPZUS")
    if not pickupEvent then
        return false
    end

    for _, money in ipairs(spawnedBread:GetChildren()) do
        if money:IsA("BasePart") and money.Transparency < 1 then
            if (money.Position - mainPart.Position).Magnitude <= farmSettings.PickupDistance + 5 then
                pcall(function()
                    pickupEvent:FireServer(money)
                    collected = collected + 1
                end)
                task.wait(0.1)
            end
        end
    end
    return collected > 0
end

local function farmLoop()
    while Farm.Enabled do
        if isDead() then
            Farm.Status = "Dead"
            Farm.IsDead = true
            task.wait(2)
            continue
        end
        Farm.IsDead = false

        if not hasTool("Crowbar") then
            Farm.Status = "No crowbar"
            if not buyCrowbar() then
                task.wait(5)
                continue
            end
        end

        local targets, count = updateTargetsList()
        if count == 0 then
            Farm.Status = "No targets"
            task.wait(5)
            continue
        end

        local target = targets[1]
        if not target then
            task.wait(1)
            continue
        end

        local obj = target.obj
        local part = target.part

        farmLog("Going to target: " .. obj.Name)

        if not moveToTarget(part) then
            farmLog("Failed to reach target")
            Farm.TempIgnored[obj] = tick() + farmSettings.IgnoreDuration
            table.insert(Farm.IgnoredList, obj)
            task.wait(2)
            continue
        end

        if hackSafe(obj) then
            farmLog("Safe hacked successfully!")
            collectMoneyNearTarget(obj)
            Farm.ProcessedList[obj] = true
        else
            farmLog("Failed to hack safe")
            Farm.TempIgnored[obj] = tick() + farmSettings.IgnoreDuration
            table.insert(Farm.IgnoredList, obj)
        end

        task.wait(2)
    end
end

local function toggleFarm(state)
    settings.autoFarm = state
    Farm.Enabled = state
    if state then
        Farm.ProcessedList = {}
        Farm.TempIgnored = {}
        Farm.IgnoredList = {}
        Farm.IsDead = false
        Farm.HasReachedTargetY = false
        task.spawn(farmLoop)
        Notify("AutoFarm", "Farm started", 3)
    else
        Farm.Status = "Stopped"
        Notify("AutoFarm", "Farm stopped", 3)
    end
end

local antiAfkConnection = nil
local virtualUser = game:GetService("VirtualUser")

local function setupAntiAfk()
    if antiAfkConnection then
        antiAfkConnection:Disconnect()
        antiAfkConnection = nil
    end
    if not settings.antiAfk then
        return
    end

    antiAfkConnection = LocalPlayer.Idled:Connect(function()
        if settings.antiAfk then
            pcall(function()
                virtualUser:CaptureController()
                virtualUser:ClickButton2(Vector2.new())
            end)
            farmLog("Anti-AFK triggered")
        end
    end)
end
setupAntiAfk()

task.spawn(function()
    while true do
        if settings.safeEsp then
            updateSafeESP()
        end
        task.wait(0.5)
    end
end)

Players.PlayerAdded:Connect(function()
    task.wait(0.5)
    updateHighlights()
end)
Players.PlayerRemoving:Connect(function()
    task.wait(0.5)
    updateHighlights()
end)

local Window = Library:CreateWindow({
    Name = "ViksScripts Criminality v3.0",
    Accent = Color3.fromHex("#FF5555"),
    ConfigFolder = "ViksScripts_Criminality",
})

-- EssnceLibrary allows max 4 custom tabs (+ built-in Settings tab)
-- and max 2 subtabs per tab, so features are grouped accordingly.

--================================================== CHARACTER
local CharacterTab = Window:CreateTab("Character")

local CharacterSub = CharacterTab:CreateSubTab({
    IconText = "👤",
    ActiveSize = 24,
    InactiveSize = 20,
})

local CharacterCard = CharacterSub:CreateCard("Left", "Character", 120)

CharacterCard:AddToggle({
    Name = "Invisible (R6)",
    Default = false,
    Flag = "invisible",
    Callback = function(state)
        settings.invisible = state
        if state then
            enableInvis()
        else
            disableInvis()
        end
    end,
})

--================================================== VISUALS
local VisualsTab = Window:CreateTab("Visuals")

local VisualsSub1 = VisualsTab:CreateSubTab({
    IconText = "👁",
    ActiveSize = 24,
    InactiveSize = 20,
})

local EspCard = VisualsSub1:CreateCard("Left", "ESP", 220)

EspCard:AddToggle({
    Name = "Safe/Register ESP",
    Default = false,
    Flag = "safe_esp",
    Callback = function(state)
        espEnabled = state
        settings.safeEsp = state
        if not state then
            for obj, data in pairs(espElements) do
                pcall(function()
                    if data.billboard then
                        data.billboard:Destroy()
                    end
                    if data.highlight then
                        data.highlight:Destroy()
                    end
                end)
            end
            espElements = {}
        end
    end,
})

EspCard:AddToggle({
    Name = "Highlight",
    Default = false,
    Flag = "highlight",
    Callback = function(state)
        settings.highlight = state
        updateHighlights()
    end,
})

EspCard:AddSlider({
    Name = "ESP Text Size",
    Default = 20,
    Min = 10,
    Max = 40,
    Flag = "esp_text_size",
    Callback = function(val)
        espTextSize = val
        for _, data in pairs(espElements) do
            if data.label then
                data.label.TextSize = val
            end
        end
    end,
})

local TracerCard = VisualsSub1:CreateCard("Right", "Bullet Tracers", 300)

TracerCard:AddToggle({
    Name = "Bullet Tracers",
    Default = false,
    Flag = "bullet_tracers",
    Callback = function(state)
        settings.bulletTracer = state
    end,
})

TracerCard:AddColorPicker({
    Name = "Tracer Color",
    Default = Color3.fromRGB(255, 0, 0),
    Flag = "tracer_color",
    Callback = function(color)
        bulletTracerSettings.Color = color
    end,
})

TracerCard:AddSlider({
    Name = "Tracer Thickness",
    Default = 0.1,
    Min = 0.02,
    Max = 0.5,
    Precise = 2,
    Flag = "tracer_thickness",
    Callback = function(val)
        bulletTracerSettings.Thickness = val
    end,
})

TracerCard:AddSlider({
    Name = "Life Time (sec)",
    Default = 2,
    Min = 0.5,
    Max = 5,
    Precise = 1,
    Flag = "tracer_life",
    Callback = function(val)
        bulletTracerSettings.Life = val
    end,
})

TracerCard:AddDropdown({
    Name = "Tracer Style",
    Default = "Classic",
    Options = { "Classic", "Rainbow" },
    Flag = "tracer_style",
    Callback = function(selected)
        bulletTracerSettings.Design = selected
    end,
})

TracerCard:AddToggle({
    Name = "Hitsound",
    Default = false,
    Flag = "hitsound",
    Callback = function(state)
        settings.hitSound = state
        setupHitSound()
    end,
})

--================================================== COMBAT
local CombatTab = Window:CreateTab("Combat")

local CombatSub1 = CombatTab:CreateSubTab({
    IconText = "🎯",
    ActiveSize = 24,
    InactiveSize = 20,
})

local SilentCard = CombatSub1:CreateCard("Left", "Silent Aim", 420)

SilentCard:AddToggle({
    Name = "Spinbot",
    Default = false,
    Flag = "spinbot",
    Callback = function(state)
        settings.spinbot = state
        spinbotActive = state
    end,
})

SilentCard:AddToggle({
    Name = "Silent Aim",
    Default = false,
    Flag = "silent_aim",
    Callback = function(state)
        SilentAim:Toggle(state, nil, nil)
        settings.silentAim = state
    end,
})

SilentCard:AddSlider({
    Name = "Silent Aim FOV",
    Default = 100,
    Min = 30,
    Max = 360,
    Flag = "silent_aim_fov",
    Callback = function(val)
        SilentAim.settings.drawSize = val
        SilentAim:UpdateCircleProps()
    end,
})

SilentCard:AddSlider({
    Name = "Hit Chance",
    Default = 100,
    Min = 1,
    Max = 100,
    Flag = "silent_aim_hitchance",
    Callback = function(val)
        SilentAim.settings.hitChance = val
    end,
})

SilentCard:AddSlider({
    Name = "Max Distance",
    Default = 120,
    Min = 50,
    Max = 300,
    Flag = "silent_aim_maxdist",
    Callback = function(val)
        SilentAim.settings.maxDistance = val
    end,
})

SilentCard:AddDropdown({
    Name = "Target Part",
    Default = "Head",
    Options = { "Head", "HumanoidRootPart", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Random" },
    ZIndex = 25,
    Flag = "silent_aim_part",
    Callback = function(selected)
        SilentAim.settings.targetPart = selected
        SilentAim.settings.actualPart = selected
        if selected == "Random" then
            SilentAim:StartRandomizer()
        else
            SilentAim:StopRandomizer()
        end
    end,
})

SilentCard:AddToggle({
    Name = "Draw FOV Circle",
    Default = false,
    Flag = "silent_aim_drawcircle",
    Callback = function(state)
        SilentAim.settings.drawCircle = state
        SilentAim:UpdateCircle()
    end,
})

SilentCard:AddToggle({
    Name = "Check Wall",
    Default = true,
    Flag = "silent_aim_checkwall",
    Callback = function(state)
        SilentAim.settings.checkWall = state
    end,
})

SilentCard:AddToggle({
    Name = "Check Downed",
    Default = true,
    Flag = "silent_aim_checkdowned",
    Callback = function(state)
        SilentAim.settings.checkDowned = state
    end,
})

local RageCard = CombatSub1:CreateCard("Right", "RageBot", 460)

RageCard:AddToggle({
    Name = "RageBot",
    Default = false,
    Flag = "ragebot",
    Callback = function(state)
        settings.rageBot = state
        RageBot:Toggle(state)
        UpdateRageCircle()
    end,
})

RageCard:AddSlider({
    Name = "RageBot Fire Rate",
    Default = 15,
    Min = 1,
    Max = 100,
    Flag = "ragebot_firerate",
    Callback = function(val)
        RageBot:UpdateShootSpeed(val)
    end,
})

RageCard:AddSlider({
    Name = "RageBot Max Distance",
    Default = 100,
    Min = 50,
    Max = 500,
    Flag = "ragebot_maxdist",
    Callback = function(val)
        rageBotSettings.maxDistance = val
    end,
})

RageCard:AddToggle({
    Name = "Use FOV",
    Default = false,
    Flag = "ragebot_usefov",
    Callback = function(state)
        rageBotSettings.useFOV = state
        RageBot:UpdateFOVCircle()
    end,
})

RageCard:AddSlider({
    Name = "FOV Radius",
    Default = 75,
    Min = 30,
    Max = 360,
    Flag = "ragebot_fovradius",
    Callback = function(val)
        rageBotSettings.fovRadius = val
        RageBot:UpdateFOVCircle()
    end,
})

RageCard:AddToggle({
    Name = "Show FOV Circle",
    Default = false,
    Flag = "ragebot_showfov",
    Callback = function(state)
        rageBotSettings.showFOV = state
        RageBot:UpdateFOVCircle()
    end,
})

RageCard:AddToggle({
    Name = "WallCheck",
    Default = true,
    Flag = "ragebot_wallcheck",
    Callback = function(state)
        rageBotSettings.wallCheck = state
    end,
})

RageCard:AddToggle({
    Name = "Check Downed",
    Default = true,
    Flag = "ragebot_checkdowned",
    Callback = function(state)
        rageBotSettings.checkDowned = state
    end,
})

RageCard:AddToggle({
    Name = "Check Team",
    Default = false,
    Flag = "ragebot_checkteam",
    Callback = function(state)
        rageBotSettings.teamCheck = state
    end,
})

RageCard:AddToggle({
    Name = "Hitlog",
    Default = true,
    Flag = "ragebot_hitlog",
    Callback = function(state)
        rageBotSettings.hitlogEnabled = state
    end,
})

RageCard:AddToggle({
    Name = "Bullet Tracer (Rage)",
    Default = false,
    Flag = "ragebot_tracer",
    Callback = function(state)
        rageBotSettings.bulletTracerEnabled = state
    end,
})

RageCard:AddColorPicker({
    Name = "Tracer Color (Rage)",
    Default = Color3.fromRGB(255, 0, 0),
    Flag = "ragebot_tracer_color",
    Callback = function(color)
        rageBotSettings.tracerColor = color
    end,
})

local CombatSub2 = CombatTab:CreateSubTab({
    IconText = "🗡",
    ActiveSize = 24,
    InactiveSize = 20,
})

local MeleeCard = CombatSub2:CreateCard("Left", "Melee Aura", 160)

MeleeCard:AddToggle({
    Name = "Melee Aura",
    Default = false,
    Flag = "melee_aura",
    Callback = function(state)
        MeleeAura.enabled = state
        settings.meleeAura = state
        if state then
            MeleeAura:StartMainLoop(nil, nil)
            MeleeAura:StartRandomizer()
        end
    end,
})

MeleeCard:AddSlider({
    Name = "Melee Aura Distance",
    Default = 10,
    Min = 1,
    Max = 20,
    Flag = "melee_aura_dist",
    Callback = function(val)
        MeleeAura.settings.distance = val
    end,
})

MeleeCard:AddToggle({
    Name = "Show Animation",
    Default = false,
    Flag = "melee_aura_anim",
    Callback = function(state)
        MeleeAura.settings.showAnim = state
    end,
})

local ReachCard = CombatSub2:CreateCard("Right", "Melee Reach", 120)

ReachCard:AddToggle({
    Name = "Melee Reach",
    Default = false,
    Flag = "melee_reach",
    Callback = function(state)
        MeleeReach.enabled = state
        settings.meleeReach = state
        if state then
            MeleeReach:StartMainLoop(nil, nil)
        end
    end,
})

ReachCard:AddSlider({
    Name = "Melee Reach Distance",
    Default = 10,
    Min = 1,
    Max = 20,
    Flag = "melee_reach_dist",
    Callback = function(val)
        MeleeReach.settings.distance = val
    end,
})

--================================================== FARM
local FarmTab = Window:CreateTab("Farm")

local FarmSub = FarmTab:CreateSubTab({
    IconText = "⛏",
    ActiveSize = 24,
    InactiveSize = 20,
})

local FarmCard = FarmSub:CreateCard("Left", "AutoFarm", 160)

FarmCard:AddToggle({
    Name = "AutoFarm",
    Default = false,
    Flag = "autofarm",
    Callback = function(state)
        toggleFarm(state)
    end,
})

FarmCard:AddToggle({
    Name = "Auto Money",
    Default = true,
    Flag = "auto_money",
    Callback = function(state)
        settings.autoMoney = state
    end,
})

FarmCard:AddToggle({
    Name = "Anti-AFK",
    Default = true,
    Flag = "anti_afk",
    Callback = function(state)
        settings.antiAfk = state
        setupAntiAfk()
    end,
})

local FarmStatusCard = FarmSub:CreateCard("Right", "Status", 90)

local farmStatusRow = Instance.new("Frame")
farmStatusRow.Size = UDim2.new(1, 0, 0, 22)
farmStatusRow.BackgroundTransparency = 1
farmStatusRow.Parent = FarmStatusCard.Container

local farmStatusLabel = Instance.new("TextLabel")
farmStatusLabel.Text = "Status: Idle"
farmStatusLabel.Font = Enum.Font.SourceSans
farmStatusLabel.TextSize = 14
farmStatusLabel.TextColor3 = Color3.fromRGB(240, 235, 245)
farmStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
farmStatusLabel.BackgroundTransparency = 1
farmStatusLabel.Size = UDim2.new(1, 0, 1, 0)
farmStatusLabel.Parent = farmStatusRow

task.spawn(function()
    while true do
        pcall(function()
            farmStatusLabel.Text = "Status: " .. tostring(Farm.Status)
        end)
        task.wait(0.5)
    end
end)

local FarmSettingsCard = FarmSub:CreateCard("Right", "Farm Settings", 140)

FarmSettingsCard:AddSlider({
    Name = "Move Speed",
    Default = 22,
    Min = 10,
    Max = 45,
    Flag = "farm_movespeed",
    Callback = function(val)
        farmSettings.MoveSpeed = val
    end,
})

FarmSettingsCard:AddSlider({
    Name = "Pickup Distance",
    Default = 8,
    Min = 3,
    Max = 20,
    Flag = "farm_pickupdist",
    Callback = function(val)
        farmSettings.PickupDistance = val
    end,
})

FarmSettingsCard:AddSlider({
    Name = "Ignore Duration (sec)",
    Default = 60,
    Min = 10,
    Max = 120,
    Flag = "farm_ignoreduration",
    Callback = function(val)
        farmSettings.IgnoreDuration = val
    end,
})

print("ViksScripts Criminality v3.0 loaded | TG: @Prompts_Stars")
