-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local helpers = require "spec.helpers"


describe("License restrictions in \"free\" mode", function()
  local client

  local function start_kong(license_path)
    return function()
      helpers.get_db_utils()
      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong({
        license_path = license_path,
        vaults = "bundled",
      }))
      client = helpers.admin_client()
    end
  end

  local function stop_kong()
    if client then
      client:close()
    end
    helpers.stop_kong()
  end

  local function try_create_vault(type, config, expected_status, expected_message)
    local res = client:put("/vaults/test-vault-" .. type, {
      headers = { ["Content-Type"] = "application/json" },
      body = {
        name = type,
        config = config
      },
    })
    local body = assert.res_status(expected_status, res)
    if expected_message then
      local response = cjson.decode(body)
      assert.equal(expected_message, response.message)
    end
  end

  local vaults = {
    gcp = {
      project_id = "my-project-id",
    },
    hcv = {
      token = "foobar",
    },
    aws = {
      region = "us-east-1"
    },
    azure = {
      vault_uri = "http://example.com",
      location = "eu-west"
    }
  }

  describe("/", function()
    setup(start_kong("spec-ee/fixtures/mock_license.json"))
    teardown(stop_kong)

    it("can create restricted vaults with license", function()
      for type, config in pairs(vaults) do
        try_create_vault(type, config, 200)
      end
    end)
  end)

  describe("/", function()
    setup(start_kong())
    teardown(stop_kong)

    it("cannot create restricted vaults without license", function()
      for type, config in pairs(vaults) do
        try_create_vault(type, config, 400, "schema violation (vault " .. type .. " requires a license to be used)")
      end
    end)
  end)

  describe("/", function()
    setup(function()
      local bp = helpers.get_db_utils()

      -- create a plugin that using vault
      assert(bp.plugins:insert {
        name = "rate-limiting",
        config = {
          second = 5,
          redis_host = helpers.redis_host,
          redis_port =  helpers.redis_port,
          redis_password = "{vault://hcv/secret/redis_password}",
        },
      })
    end)

    teardown(stop_kong)

    it("should not crash while using any vault in \"free\" mode", function()
      -- restart Kong and should not cause crash
      assert(helpers.start_kong({
        vaults = "bundled",
      }))

      assert.logfile().has.line("vault hcv requires a license to be used", true)
    end)
  end)
end)
