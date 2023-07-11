-- this software is copyright kong inc. and its licensors.
-- use of the software is subject to the agreement between your organization
-- and kong inc. if there is no such agreement, use is governed by and
-- subject to the terms of the kong master software license agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ end of license 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local BaseEntitiesFactory = require("spec.fixtures.factories.plugins").EntitiesFactory
local BasePluginFactory = require("spec.fixtures.factories.plugins").PluginFactory

local EntitiesFactory = {}

function EntitiesFactory:setup(strategy)
	local bp, _ = helpers.get_db_utils(strategy,
		{ "plugins",
			"routes",
			"services",
			"consumers",
			"consumer_groups",
      "consumer_group_consumers" },
		{ "key-auth", "request-transformer" })


  local ef = BaseEntitiesFactory:setup(strategy)

	local consumer_group_plat = assert(bp.consumer_groups:insert {
    -- prefix names with A, B and C to ensure their ordering
    -- as we sort by name in this iteration.
    id = "00000000-0000-0000-0000-000000000000",
		name = "A_Platinum",
	})
	local consumer_group_gold = assert(bp.consumer_groups:insert {
    id = "10000000-0000-0000-0000-000000000000",
		name = "B_Gold",
	})
	local consumer_group_silver = assert(bp.consumer_groups:insert {
    id = "20000000-0000-0000-0000-000000000000",
		name = "C_Silver",
	})

  assert(bp.consumer_group_consumers:insert({
		consumer       = { id = ef.alice_id },
		consumer_group = { id = consumer_group_plat.id },
	}))

	assert(bp.consumer_group_consumers:insert({
		consumer       = { id = ef.eve_id },
		consumer_group = { id = consumer_group_gold.id },
	}))
	assert(bp.consumer_group_consumers:insert({
		consumer       = { id = ef.eve_id },
		consumer_group = { id = consumer_group_silver.id },
	}))

	ef.bp = bp
	ef.consumer_group_platinum_id = consumer_group_plat.id
	ef.consumer_group_gold_id = consumer_group_gold.id
	ef.consumer_group_silver_id = consumer_group_silver.id
	return ef
end


-- Define the PluginFactory table
local PluginFactory = {}
PluginFactory.__index = PluginFactory

-- Inherit from BasePluginFactory
setmetatable(PluginFactory, {__index = BasePluginFactory})

-- The setup function
function PluginFactory:setup(ef)
    -- Create a new instance with the correct metatable
    local instance = setmetatable({}, self)

    -- Call the setup function on the BasePluginFactory
    BasePluginFactory.setup(instance, ef)

    -- Add EE only attributes
    instance.consumer_group_platinum_id = ef.consumer_group_platinum_id
    instance.consumer_group_gold_id = ef.consumer_group_gold_id
    instance.consumer_group_silver_id = ef.consumer_group_silver_id

    return instance
end

function PluginFactory:consumer_group_multiple_groups()
	local header_name = "x-consumer-group-silver"
	self:produce(header_name, {
		-- eve is part of silver
		consumer_group = { id = self.consumer_group_silver_id},
	})
	self:produce("x-consumer-group-gold", {
		-- eve is part of gold
		consumer_group = { id = self.consumer_group_gold_id},
	})
	-- check if gold was set
	return "x-consumer-group-gold", header_name
end

function PluginFactory:consumer_group_service_route()
	local header_name = "x-consumer-group-and-service-and-route"
	self:produce(header_name, {
		consumer_group = { id = self.consumer_group_platinum_id },
		service = { id = self.service_id },
		route = { id = self.route_id },
	})
	return header_name
end

function PluginFactory:consumer_group_route()
	local header_name = "x-consumer-group-and-route"
	self:produce(header_name, {
		consumer_group = { id = self.consumer_group_platinum_id },
		route = { id = self.route_id },
	})
	return header_name
end

function PluginFactory:consumer_group_service()
	local header_name = "x-consumer-group-and-service"
	self:produce(header_name, {
		consumer_group = { id = self.consumer_group_platinum_id },
		service = { id = self.service_id },
	})
	return header_name
end

function PluginFactory:consumer_group()
	local header_name = "x-consumer-group"
	self:produce(header_name, {
		consumer_group = { id = self.consumer_group_platinum_id }
	})
	return header_name
end
return {
	PluginFactory = PluginFactory,
	EntitiesFactory = EntitiesFactory
}
