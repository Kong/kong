local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Admin API - Kong routes", function()
  describe("/", function()
    local client

    setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong({
        license_path = "spec/fixtures/mock_license.json",
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
      local f = assert(io.open("spec/fixtures/mock_license.json"))
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
end)
