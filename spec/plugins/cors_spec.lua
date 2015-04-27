local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local PROXY_URL = spec_helper.PROXY_URL

describe("CORS Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("OPTIONS", function()

    it("should give appropriate defaults when no options are passed", function()
      local response, status, headers = http_client.options(PROXY_URL.."/", {}, {host = "cors1.com"})

      -- assertions
      assert.are.equal(204, status)
      assert.are.equal("*", headers["access-control-allow-origin"])
      assert.are.equal("GET,HEAD,PUT,PATCH,POST,DELETE", headers["access-control-allow-methods"])
      assert.are.equal(nil, headers["access-control-allow-headers"])
      assert.are.equal(nil, headers["access-control-expose-headers"])
      assert.are.equal(nil, headers["access-control-allow-credentials"])
      assert.are.equal(nil, headers["access-control-max-age"])
    end)
    
    it("should reflect what is specified in options", function()
      -- make proxy request
      local response, status, headers = http_client.options(PROXY_URL.."/", {}, {host = "cors2.com"})

      -- assertions
      assert.are.equal(204, status)
      assert.are.equal("example.com", headers["access-control-allow-origin"])
      assert.are.equal("origin, type, accepts", headers["access-control-allow-headers"])
      assert.are.equal(nil, headers["access-control-expose-headers"])
      assert.are.equal("GET", headers["access-control-allow-methods"])
      assert.are.equal(tostring(23), headers["access-control-max-age"])
      assert.are.equal(tostring(true), headers["access-control-allow-credentials"])
    end)
    
  end)
  
  describe("GET,PUT,POST,ETC", function()

    it("should give appropriate defaults when no options are passed", function()
      -- make proxy request
      local response, status, headers = http_client.get(PROXY_URL.."/", {}, {host = "cors1.com"})

      -- assertions
      assert.are.equal(200, status)
      assert.are.equal("*", headers["access-control-allow-origin"])
      assert.are.equal(nil, headers["access-control-allow-methods"])
      assert.are.equal(nil, headers["access-control-allow-headers"])
      assert.are.equal(nil, headers["access-control-expose-headers"])
      assert.are.equal(nil, headers["access-control-allow-credentials"])
      assert.are.equal(nil, headers["access-control-max-age"])
    end)
    
    it("should reflect some of what is specified in options", function()
      -- make proxy request
      local response, status, headers = http_client.get(PROXY_URL.."/", {}, {host = "cors2.com"})

      -- assertions
      assert.are.equal(200, status)
      assert.are.equal("example.com", headers["access-control-allow-origin"])
      assert.are.equal("x-auth-token", headers["access-control-expose-headers"])
      assert.are.equal(nil, headers["access-control-allow-headers"])
      assert.are.equal(nil, headers["access-control-allow-methods"])
      assert.are.equal(nil, headers["access-control-max-age"])
      assert.are.equal(tostring(true), headers["access-control-allow-credentials"])
    end)
    
  end)

end)