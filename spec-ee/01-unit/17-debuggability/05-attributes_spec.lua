-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local attributes = require "kong.enterprise_edition.debug_session.instrumentation.attributes"

describe("Debug Session Instrumentation Attributes", function()
  describe("SPAN_ATTRIBUTES", function()
    local span_attributes

    setup(function()
      span_attributes = attributes.SPAN_ATTRIBUTES
    end)

    it("should return a table", function()
      assert.is_table(span_attributes)
    end)

    it("should contain OTEL attributes", function()
      assert.equals("client.address", span_attributes.CLIENT_ADDRESS)
      assert.equals("client.port", span_attributes.CLIENT_PORT)
      assert.equals("destination.address", span_attributes.DESTINATION_ADDRESS)
    end)

    it("should use KONG_PREFIX for Kong-specific attributes", function()
      assert.equals("proxy.kong.service.id", span_attributes.KONG_SERVICE_ID)
      assert.equals("proxy.kong.route.id", span_attributes.KONG_ROUTE_ID)
      assert.equals("proxy.kong.consumer.id", span_attributes.KONG_CONSUMER_ID)
    end)

    it("should not contain ATC attributes", function()
      for _, value in pairs(span_attributes) do
        assert.is_not_equal("net.src.ip", value)
        assert.is_not_equal("net.src.port", value)
      end
    end)
  end)

  describe("SAMPLER_ATTRIBUTES", function()
    local sampler_attributes

    setup(function()
      sampler_attributes = attributes.SAMPLER_ATTRIBUTES
    end)

    it("should return a table", function()
      assert.is_table(sampler_attributes)
    end)

    it("should contain both OTEL and ATC attributes", function()
      assert.same({
        name = "client.address",
        alias = "net.src.ip",
        type = "IpAddr",
      }, sampler_attributes.CLIENT_ADDRESS)

      assert.same({
        name = "client.port",
        alias = "net.src.port",
        type = "Int",
      }, sampler_attributes.CLIENT_PORT)
    end)

    it("should use KONG_PREFIX for Kong-specific attributes", function()
      assert.same({
        name = "proxy.kong.service.id",
        alias = nil,
        type = "String",
      }, sampler_attributes.KONG_SERVICE_ID)
    end)

    it("should include type information", function()
      assert.equals("String", sampler_attributes.REQUEST_METHOD.type)
      assert.equals("Int", sampler_attributes.HTTP_RESPONSE_STATUS_CODE.type)
      assert.equals("IpAddr", sampler_attributes.NETWORK_PEER_ADDRESS.type)
    end)
  end)
end)
