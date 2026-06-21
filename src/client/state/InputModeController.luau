--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputModeController = {}

local player = Players.LocalPlayer
local controls: any = nil
local activeLocks: {[string]: boolean} = {}
local cameraConn: RBXScriptConnection? = nil
local cameraStart: CFrame? = nil
local anchorStartPosition: Vector3? = nil

local function getControls()
	if controls then
		return controls
	end

	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule"))
	controls = playerModule:GetControls()
	return controls
end

local function getCameraAnchor(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("Head") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function hasActiveLock(): boolean
	for _, enabled in pairs(activeLocks) do
		if enabled then
			return true
		end
	end

	return false
end

local function stopCameraFollow()
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
	cameraStart = nil
	anchorStartPosition = nil
end

local function startCameraFollow()
	stopCameraFollow()

	local camera = workspace.CurrentCamera
	local anchor = getCameraAnchor()
	if not camera or not anchor then
		return
	end

	cameraStart = camera.CFrame
	anchorStartPosition = anchor.Position
	cameraConn = RunService.RenderStepped:Connect(function()
		if not hasActiveLock() then
			return
		end

		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		player.CameraMode = Enum.CameraMode.Classic

		local currentCamera = workspace.CurrentCamera
		local currentAnchor = getCameraAnchor()
		if not currentCamera or not currentAnchor or not cameraStart or not anchorStartPosition then
			return
		end

		currentCamera.CameraType = Enum.CameraType.Scriptable
		local positionDelta = currentAnchor.Position - anchorStartPosition
		local targetCameraCFrame = cameraStart + positionDelta
		currentCamera.CFrame = targetCameraCFrame
		currentCamera.Focus = targetCameraCFrame + targetCameraCFrame.LookVector
	end)
end

local function applyUnlockedUiMode()
	local ctl = getControls()
	ctl:Disable()

	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	player.CameraMode = Enum.CameraMode.Classic

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	startCameraFollow()
end

local function applyGameplayMode()
	local ctl = getControls()
	ctl:Enable()
	stopCameraFollow()

	UserInputService.MouseIconEnabled = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	player.CameraMode = Enum.CameraMode.LockFirstPerson

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

function InputModeController.setUiLock(reason: string, enabled: boolean)
	activeLocks[reason] = if enabled then true else nil
	if hasActiveLock() then
		applyUnlockedUiMode()
	else
		applyGameplayMode()
	end
end

function InputModeController.isUiLocked(): boolean
	return hasActiveLock()
end

return InputModeController
