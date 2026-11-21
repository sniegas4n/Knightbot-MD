--[[
	Signal (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Modules > Signal

	Petit système d'évènements interne (sans BindableEvent) pour faire
	communiquer les services entre eux sans dépendances circulaires.

	local s = Signal.new()
	local conn = s:Connect(function(a, b) ... end)
	s:Fire(1, 2)
	conn:Disconnect()

	Chaque écouteur est exécuté dans son propre thread (task.spawn) : une
	erreur dans un écouteur n'empêche pas les autres de s'exécuter.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(callback: (...any) -> ()): Connection
	assert(type(callback) == "function", "[Signal] Connect attend une fonction")

	local handlers = self._handlers
	local connection = { Connected = true }

	function connection.Disconnect(conn)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local index = table.find(handlers, conn)
		if index then
			table.remove(handlers, index)
		end
	end

	connection._callback = callback
	table.insert(handlers, connection)
	return connection :: any
end

function Signal:Fire(...: any)
	-- Copie : un écouteur peut se déconnecter pendant l'itération.
	for _, connection in table.clone(self._handlers) do
		if connection.Connected then
			task.spawn(connection._callback, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._handlers) do
		connection:Disconnect()
	end
end

return Signal
