local RunService = game:GetService("RunService")
local BridgeNet2 = require(script.Parent:WaitForChild("BridgeNet2"))

-- Proxcies
local machineProxy = {
	-- example:
	-- state1 = {Type = "State", Value = State}
	-- state2 = {Type = "State", Value = State}
}

local stateProxy = {
	Priority = { Readonly = false, Value = 0 },
	Enabled = { Readonly = false, Value = false },
	Active = { Readonly = true, Value = false },
	Changed = { Readonly = true, Value = "Instance" },
}

-- Variables
local bridge = BridgeNet2.ReferenceBridge("Priority4")
local module = {}
module.memory = {}
module.replicating = {}

-- Private Functions
local function deepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			v = deepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

-- Module Functions
function module.CreateMachine(object: Instance): StateMachine
	local machineProxy = deepCopy(machineProxy)
	local meta = {}

	assert(object, "First argument for CreateMachine is nil.")

	if RunService:IsClient() then
		bridge:Fire({ "get", object })
	end

	machineProxy["CreateState.Hidden"] = function(i)
		local stateProxy = deepCopy(stateProxy)
		local meta = {}

		stateProxy["Changed.Hidden"] = Instance.new("BindableEvent")

		meta.__index = function(t, i)
			local exists = stateProxy[i]

			if exists then
				return exists.Value
			end
		end

		meta.__newindex = function(t, i, v)
			if i == "Updated.Hidden" and v == true then
				-- private property that fires Changed signal
				stateProxy["Changed.Hidden"]:Fire(stateProxy.Enabled.Value, stateProxy.Active.Value)
				return
			end

			if stateProxy[i] ~= nil and typeof(stateProxy[i].Value) == typeof(v) then
				stateProxy[i].Value = v
				machineProxy["Update.Hidden"]()
			end
		end

		meta.__tostring = function(t)
			local str = ""
			str = str .. tostring((stateProxy.Enabled.Value == true and "🟢") or "⚫")
			str = str .. tostring((stateProxy.Active.Value == true and "🟢") or "⚫")
			return str
		end

		local state = setmetatable({}, meta)
		rawset(state, "Proxy.Hidden", stateProxy)
		stateProxy.Changed.Value = stateProxy["Changed.Hidden"].Event

		machineProxy[i] = { Type = "State", Value = state }

		return machineProxy[i]
	end

	machineProxy["Update.Hidden"] = function()
		local enabledClasses = {}

		for i, state in machineProxy do
			if typeof(state) == "table" and state.Type == "State" then
				if state.Value.Enabled then
					table.insert(enabledClasses, { i, state.Value.Priority })
				end
			end
		end

		table.sort(enabledClasses, function(a, b)
			return a[2] > b[2]
		end)

		for i, state in machineProxy do
			if typeof(state) == "table" and state.Type == "State" then
				if #enabledClasses > 0 and enabledClasses[1][1] == i then
					-- highest priority
					rawget(state.Value, "Proxy.Hidden").Active.Value = true
				else
					-- not highest priority
					rawget(state.Value, "Proxy.Hidden").Active.Value = false
				end

				state.Value["Updated.Hidden"] = true
			end
		end
	end

	meta.__index = function(t, i)
		if i == "meta" then
			return machineProxy
		end

		local exists = machineProxy[i] -- check if indexed item exists

		if exists then
			if exists.Type == "State" then
				-- Return State

				return exists.Value
			end
		else
			return machineProxy["CreateState.Hidden"](i).Value
		end
	end

	meta.__newindex = function(t, i, v)
		local exists = machineProxy[i] -- check if indexed item exists

		if not exists then
			-- Create State
			exists = machineProxy["CreateState.Hidden"](i)
		end

		if exists and exists.Type == "State" then
			-- Change State Proprty

			if typeof(v) == "boolean" and exists.Value.Enabled ~= v then
				exists.Value.Enabled = v
			elseif typeof(v) == "number" and exists.Value.Priority ~= v then
				exists.Value.Priority = v
			end

			if RunService:IsServer() then
				for player: Player, objects: { Instance } in module.replicating do
					if table.find(objects, object) then
						bridge:Fire(player, { "set", object, i, v })
					end
				end
			end
		end
	end

	meta.__tostring = function(t)
		local str = ""

		for i, v in machineProxy do
			if typeof(v) == "table" and v.Type == "State" then
				str = str .. i .. ":" .. tostring(v.Value) .. " "
			end
		end

		return str
	end

	local machine = setmetatable({}, meta)

	module.memory[object] = machine

	return machine
end

function module.GetMachine(object: Instance)
	return module.memory[object] or module.CreateMachine(object)
end

if RunService:IsClient() then
	bridge:Connect(function(content)
		local action = content[1]

		if action == "set" then
			local object, i, v = table.unpack(content, 2)
			local machine = module.GetMachine(object)

			if machine then
				machine[i] = v
			end
		end
	end)
elseif RunService:IsServer() then
	bridge:Connect(function(player, content)
		local action = content[1]

		if action == "get" then
			local object = table.unpack(content, 2)
			local machine = module.GetMachine(object)

			if module.replicating[player] == nil then
				module.replicating[player] = {}
			end

			table.insert(module.replicating[player], object)

			for c, b in machine.meta do
				if typeof(b) == "table" and b.Type == "State" then
					bridge:Fire(player, { "set", object, c, b.Value.Enabled })
					bridge:Fire(player, { "set", object, c, b.Value.Priority })
				end
			end
		end
	end)
end

-- Types
export type StateMachine = typeof(machineProxy)
export type State = typeof(stateProxy)

-- Return Module
return module
