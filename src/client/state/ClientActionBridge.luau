--!strict

local ClientActionBridge = {}

local handlers: {[string]: (...any) -> ()} = {}

function ClientActionBridge.register(actionName: string, handler: (...any) -> ())
	handlers[actionName] = handler
end

function ClientActionBridge.invoke(actionName: string, ...: any): boolean
	local handler = handlers[actionName]
	if not handler then
		return false
	end

	handler(...)
	return true
end

return ClientActionBridge
