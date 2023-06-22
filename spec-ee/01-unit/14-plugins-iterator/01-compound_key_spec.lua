-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local build_compound_key = require("kong.runloop.plugins_iterator").build_compound_key


describe("build_compound_key", function()
	it("should return compound key with route_id and service_id only", function()
		local compound_key = build_compound_key("route_1", "service_1", nil, nil)
		assert.are.same("route_1:service_1::", compound_key)
	end)

	it("should return compound key with route_id and consumer_id only", function()
		local compound_key = build_compound_key("route_1", nil, "consumer_1", nil)
		assert.are.same("route_1::consumer_1:", compound_key)
	end)

	it("should return compound key with route_id and consumer_group_id only", function()
		local compound_key = build_compound_key("route_1", nil, nil, "group_1")
		assert.are.same("route_1:::group_1", compound_key)
	end)

	it("should return compound key with service_id and consumer_id only", function()
		local compound_key = build_compound_key(nil, "service_1", "consumer_1", nil)
		assert.are.same(":service_1:consumer_1:", compound_key)
	end)

	it("should return compound key with service_id and consumer_group_id only", function()
		local compound_key = build_compound_key(nil, "service_1", nil, "group_1")
		assert.are.same(":service_1::group_1", compound_key)
	end)

	it("should return compound key with consumer_id and consumer_group_id only", function()
		local compound_key = build_compound_key(nil, nil, "consumer_1", "group_1")
		assert.are.same("::consumer_1:group_1", compound_key)
	end)

	it("should return compound key with route_id, service_id, and consumer_id only", function()
		local compound_key = build_compound_key("route_1", "service_1", "consumer_1", nil)
		assert.are.same("route_1:service_1:consumer_1:", compound_key)
	end)

	it("should return compound key with route_id, service_id, and consumer_group_id only", function()
		local compound_key = build_compound_key("route_1", "service_1", nil, "group_1")
		assert.are.same("route_1:service_1::group_1", compound_key)
	end)

	it("should return compound key with route_id, consumer_id, and consumer_group_id only", function()
		local compound_key = build_compound_key("route_1", nil, "consumer_1", "group_1")
		assert.are.same("route_1::consumer_1:group_1", compound_key)
	end)

	it("should return compound key with service_id, consumer_id, and consumer_group_id only", function()
		local compound_key = build_compound_key(nil, "service_1", "consumer_1", "group_1")
		assert.are.same(":service_1:consumer_1:group_1", compound_key)
	end)

	it("should return compound key with all values present", function()
		local compound_key = build_compound_key("route_1", "service_1", "consumer_1", "group_1")
		assert.are.same("route_1:service_1:consumer_1:group_1", compound_key)
	end)

	it("should return empty compound key when all arguments are nil", function()
		local compound_key = build_compound_key(nil, nil, nil, nil)
		assert.are.same(":::", compound_key)
	end)

	it("should return compound key with only route_id", function()
		local compound_key = build_compound_key("route_1", nil, nil, nil)
		assert.are.same("route_1:::", compound_key)
	end)

	it("should return compound key with only service_id", function()
		local compound_key = build_compound_key(nil, "service_1", nil, nil)
		assert.are.same(":service_1::", compound_key)
	end)

	it("should return compound key with only consumer_id", function()
		local compound_key = build_compound_key(nil, nil, "consumer_1", nil)
		assert.are.same("::consumer_1:", compound_key)
	end)

	it("should return compound key with only consumer_group_id", function()
		local compound_key = build_compound_key(nil, nil, nil, "group_1")
		assert.are.same(":::group_1", compound_key)
	end)
end)
