local helpers = require "spec.helpers"

local EntitiesFactory = {}

function EntitiesFactory:setup(strategy)
	local bp, _ = helpers.get_db_utils(strategy,
		{ "plugins",
			"routes",
			"services",
			"consumers", },
		{ "key-auth", "request-transformer" })


	local alice = assert(bp.consumers:insert {
		custom_id = "alice"
	})

	local bob = assert(bp.consumers:insert {
		username = "bob",
	})

	local eve = assert(bp.consumers:insert{
		username = "eve"
	})

	assert(bp.keyauth_credentials:insert {
		key      = "bob",
		consumer = { id = bob.id },
	})
	assert(bp.keyauth_credentials:insert {
		key = "alice",
		consumer = { id = alice.id },
	})
	assert(bp.keyauth_credentials:insert {
		key = "eve",
		consumer = { id = eve.id },
	})

	local service = assert(bp.services:insert {
		path = "/anything",
	})

	local route = assert(bp.routes:insert {
		service = { id = service.id },
		hosts = { "route.test" },
	})
	assert(bp.key_auth_plugins:insert())

	self.bp = bp
	self.alice_id = alice.id
	self.bob_id = bob.id
	self.eve_id = eve.id
	self.route_id = route.id
	self.service_id = service.id
	return self
end

local PluginFactory = {}
function PluginFactory:setup(ef)
	self.bp = ef.bp
	self.bob_id = ef.bob_id
	self.alice_id = ef.alice_id
	self.eve_id = ef.eve_id
	self.route_id = ef.route_id
	self.service_id = ef.service_id
	return self
end

function PluginFactory:produce(header_name, plugin_scopes)
	local plugin_cfg = {
		name = "request-transformer",
		config = {
			add = {
				headers = { ("%s:true"):format(header_name) }
			}
		}
	}
	for k, v in pairs(plugin_scopes) do
		plugin_cfg[k] = v
	end
	return assert(self.bp.plugins:insert(plugin_cfg))
end

function PluginFactory:consumer_route_service()
	local header_name = "x-consumer-and-service-and-route"
	self:produce(header_name, {
		consumer = { id = self.alice_id },
		service = { id = self.service_id },
		route = { id = self.route_id },
	})
	return header_name
end

function PluginFactory:consumer_route()
	local header_name = "x-consumer-and-route"
	self:produce(header_name, {
		consumer = { id = self.alice_id },
		route = { id = self.route_id },
	})
	return header_name
end

function PluginFactory:consumer_service()
	local header_name = "x-consumer-and-service"
	self:produce(header_name, {
		consumer = { id = self.alice_id },
		service = { id = self.service_id },
	})
	return header_name
end

function PluginFactory:route_service()
	local header_name = "x-route-and-service"
	self:produce(header_name, {
		route = { id = self.route_id },
		service = { id = self.service_id },
	})
	return header_name
end

function PluginFactory:consumer()
	local header_name = "x-consumer"
	self:produce(header_name, {
		consumer = { id = self.alice_id }
	})
	return header_name
end

function PluginFactory:route()
	local header_name = "x-route"
	self:produce(header_name, {
		route = { id = self.route_id }
	})
	return header_name
end

function PluginFactory:service()
	local header_name = "x-service"
	self:produce(header_name, {
		service = { id = self.service_id }
	})
	return header_name
end

function PluginFactory:global()
	local header_name = "x-global"
	self:produce(header_name, {})
	return header_name
end

return {
	PluginFactory = PluginFactory,
	EntitiesFactory = EntitiesFactory
}
