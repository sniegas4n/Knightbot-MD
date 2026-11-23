--!nonstrict
--[[
	DodgeMotion
	Location : ReplicatedStorage/Shared/Modules/DodgeMotion (ModuleScript)
	Purpose  : Applies a short horizontal burst of velocity to a character.
	           Must run on whoever has network ownership of the character:
	           the owning client for players, the server for NPCs.
	           Gravity is left alone (only X/Z are driven) so dodging off a ledge
	           still falls naturally.
	Depends  : nothing
]]

local DodgeMotion = {}

function DodgeMotion.apply(root, direction, speed, duration)
	if not root or not root.Parent then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	flat = flat.Unit

	local attachment = root:FindFirstChild("DodgeAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "DodgeAttachment"
		attachment.Parent = root
	end

	local previous = root:FindFirstChild("DodgeVelocity")
	if previous then
		previous:Destroy()
	end

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DodgeVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector

	local force = math.max(root.AssemblyMass, 1) * 3000
	local perAxisOk = pcall(function()
		velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		velocity.MaxAxesForce = Vector3.new(force, 0, force)
	end)
	if perAxisOk then
		velocity.VectorVelocity = flat * speed
	else
		-- Fallback for engines without per-axis limits: keep current vertical speed.
		velocity.MaxForce = force
		velocity.VectorVelocity = flat * speed + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
	end

	velocity.Parent = root
	task.delay(duration, function()
		if velocity.Parent then
			velocity:Destroy()
		end
	end)
end

return DodgeMotion
