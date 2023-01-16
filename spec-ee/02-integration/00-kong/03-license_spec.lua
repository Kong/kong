-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Admin API - Kong routes", function()
  describe("/", function()
    local client

    setup(function()
      helpers.get_db_utils()
      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong({
        license_path = "spec-ee/fixtures/mock_license.json",
      }))
      client = helpers.admin_client()
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    it("displays license data via path env", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.license)
      assert.is_nil(json.license.license_key)
    end)
  end)

  describe("/", function()
    local client

    setup(function()
      local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
      local d = f:read("*a")
      f:close()

      helpers.get_db_utils()
      assert(helpers.start_kong({
        license_data = d,
      }))
      client = helpers.admin_client()
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    it("displays license data via data env", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.license)
      assert.is_nil(json.license.license_key)
    end)
  end)

  describe("/", function()
    local client

    setup(function()
      local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
      local d = f:read("*a")
      f:close()

      helpers.get_db_utils()
      assert(helpers.start_kong({
        license_data = ngx.encode_base64(d),
      }))
      client = helpers.admin_client()
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    it("displays license data configured as base64", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.license)
      assert.is_nil(json.license.license_key)
    end)
  end)

  describe("/", function()
    local client

    setup(function()
      local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
      local d = f:read("*a")
      f:close()

      helpers.get_db_utils()

      helpers.setenv("MY_LICENSE", d)

      assert(helpers.start_kong({
        license_data = "{vault://env/my-license}",
      }))
      client = helpers.admin_client()
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      helpers.unsetenv("MY_LICENSE")
    end)

    it("displays license data via data env using vault", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.license)
      assert.is_nil(json.license.license_key)
    end)
  end)

  describe("/", function()
    local client

    setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong())
      client = helpers.admin_client()
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    it("does not display license data without a license", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_nil(json.license)
    end)
  end)

  describe("/event-hooks", function()
    local client

    setup(function()
      helpers.get_db_utils()
      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong())
      client = helpers.admin_client()
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    it("create a webhook when the license is deployed via the admin API", function()
      local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
      local d = f:read("*a")
      f:close()

      local res = assert(client:send {
        method = "POST",
        path = "/licenses",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = { payload = d },
      })
      assert.res_status(201, res)

      local res = assert(client:send {
        method = "POST",
        path = "/event-hooks",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          source = "crud",
          event = "services:create",
          handler = "webhook",
          config = {
            url = "https://webhook.site/a145401f-1f24-4a21-b1b0-3c70140dd8cf"
          }
        },
      })
      assert.res_status(201, res)
    end)
  end)

  describe("/", function()
    local client

    setup(function()
      helpers.get_db_utils()
      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong({
        prefix = "servroot1",
        admin_listen = "127.0.0.1:8001",
        admin_gui_listen = "off",
        proxy_listen = "off",
        db_update_frequency = 0.1,
      }))
      assert(helpers.start_kong({
        prefix = "servroot2",
        admin_listen = "127.0.0.1:9001",
        admin_gui_listen = "off",
        proxy_listen = "off",
        db_update_frequency = 0.1,
      }))
      client = helpers.admin_client(nil, 8001)
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong("servroot1")
      helpers.stop_kong("servroot2")
    end)

    it("reload license across all nodes in a cluster when the license is deployed via Admin API", function()
      local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
      local d = f:read("*a")
      f:close()

      local res = assert(client:send {
        method = "POST",
        path = "/licenses",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = { payload = d },
      })
      assert.res_status(201, res)

      helpers.pwait_until(function()
        local res = assert(client:send {
          method = "GET",
          path = "/",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        return assert.is_table(json.license)
      end, 30)

      helpers.pwait_until(function()
        local res = assert(helpers.admin_client(nil, 9001):send {
          method = "GET",
          path = "/",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        return assert.is_table(json.license)
      end, 30)
    end)
  end)
end)
