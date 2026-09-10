return function(context)
	local RunService = context.RunService
	local workspaceService = workspace
	local camera = workspaceService.CurrentCamera

	local enabled = false
	local target
	local connection
	local previousType
	local previousSubject
	local smoothCFrame

	local function getTargetPart(entry)
		if not entry then return nil end
		if entry.part and entry.part.Parent then return entry.part end
		local object = entry.object
		if object and object.Parent then
			if object:IsA("BasePart") then return object end
			if object:IsA("Model") then
				if object.PrimaryPart then return object.PrimaryPart end
				return object:FindFirstChildWhichIsA("BasePart", true)
			end
		end
		return nil
	end

	local function restoreCamera()
		if not camera then return end
		pcall(function()
			if previousType then camera.CameraType = previousType end
			if previousSubject and previousSubject.Parent then camera.CameraSubject = previousSubject end
		end)
		previousType = nil
		previousSubject = nil
		smoothCFrame = nil
	end

	local function stopConnection()
		if connection then
			pcall(function() connection:Disconnect() end)
			connection = nil
		end
	end

	local function disable()
		enabled = false
		stopConnection()
		restoreCamera()
	end

	local function render()
		if not enabled then return end
		camera = workspaceService.CurrentCamera or camera
		if not camera then return end
		local part = getTargetPart(target)
		if not part then return end

		local focus = part.Position + Vector3.new(0, 1.5, 0)
		local localRoot = context.getLocalRoot and context.getLocalRoot()
		local direction
		if localRoot then
			direction = (localRoot.Position - focus)
		end
		if not direction or direction.Magnitude < 1 then
			direction = Vector3.new(1, 0.45, 1)
		end
		direction = direction.Unit
		local distance = math.clamp(math.max(part.Size.X, part.Size.Y, part.Size.Z) * 4, 12, 28)
		local desiredPosition = focus + direction * distance + Vector3.new(0, 7, 0)
		local desired = CFrame.lookAt(desiredPosition, focus)

		if not smoothCFrame then
			smoothCFrame = desired
		else
			smoothCFrame = smoothCFrame:Lerp(desired, 0.12)
		end
		camera.CFrame = smoothCFrame
	end

	local function enable()
		if enabled then return end
		camera = workspaceService.CurrentCamera
		if not camera then return end
		enabled = true
		previousType = camera.CameraType
		previousSubject = camera.CameraSubject
		camera.CameraType = Enum.CameraType.Scriptable
		connection = RunService.RenderStepped:Connect(render)
	end

	local function setEnabled(value)
		if value then enable() else disable() end
	end

	local function setTarget(entry)
		target = entry
	end

	local function destroy()
		disable()
		target = nil
	end

	local function getStatus()
		return {
			enabled = enabled,
			target = target and (target.name or (target.object and target.object.Name)) or nil,
		}
	end

	return {
		setEnabled = setEnabled,
		setTarget = setTarget,
		destroy = destroy,
		getStatus = getStatus,
	}
end
