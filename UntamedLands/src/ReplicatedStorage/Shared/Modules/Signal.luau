--!nonstrict
--[[
	Signal
	Location : ReplicatedStorage/Shared/Modules/Signal (ModuleScript)
	Purpose  : Lightweight Lua event. Unlike BindableEvent it passes tables by
	           reference (BindableEvents deep-copy tables and strip metatables).
	Depends  : nothing
]]

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self._handlers
	local handler = { fn = fn, connected = true }
	table.insert(handlers, handler)
	return {
		Disconnect = function()
			if not handler.connected then
				return
			end
			handler.connected = false
			local index = table.find(handlers, handler)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, handler in ipairs(table.clone(self._handlers)) do
		if handler.connected then
			task.spawn(handler.fn, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

return Signal
