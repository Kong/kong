-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

-- unsets kong license env vars and returns a function to restore their values
-- on test teardown
--
-- replace distributions_constants.lua to mock a GA release distribution
local function setup_distribution()
  local kld = os.getenv("KONG_LICENSE_DATA")
  helpers.unsetenv("KONG_LICENSE_DATA")

  local klp = os.getenv("KONG_LICENSE_PATH")
  helpers.unsetenv("KONG_LICENSE_PATH")

  local tmp_filename = "/tmp/distributions_constants.lua"
  assert(helpers.file.copy("kong/enterprise_edition/distributions_constants.lua", tmp_filename, true))
  assert(helpers.file.copy("spec-ee/fixtures/mock_distributions_constants.lua", "kong/enterprise_edition/distributions_constants.lua", true))

  return function()
    if kld then
      helpers.setenv("KONG_LICENSE_DATA", kld)
    end

    if klp then
      helpers.setenv("KONG_LICENSE_PATH", klp)
    end

    if helpers.path.exists(tmp_filename) then
      -- restore and delete backup
      assert(helpers.file.copy(tmp_filename, "kong/enterprise_edition/distributions_constants.lua", true))
      assert(helpers.file.delete(tmp_filename))
    end
  end
end

describe("Admin API - Kong routes", function()
  local valid_license, expired_license, grace_period_license

  lazy_setup(function()
    local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
    valid_license = f:read("*a")
    f:close()

    f = assert(io.open("spec-ee/fixtures/mock_expired_license.json"))
    expired_license = f:read("*a")
    f:close()

    f = assert(io.open("spec-ee/fixtures/mock_grace_period_license_tmpl.json"))
    local tmpl = f:read("*a")
    grace_period_license = string.format(tmpl, os.date("%Y-%m-%d", os.time()-5*3600*24))
    f:close()

  end)

  describe("/", function()
    local client

    lazy_setup(function()
      helpers.get_db_utils()
      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong({
        license_path = "spec-ee/fixtures/mock_license.json",
      }))
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
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

    lazy_setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong({
        license_data = valid_license,
      }))
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
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

    lazy_setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong({
        license_data = ngx.encode_base64(valid_license),
      }))
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
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

    lazy_setup(function()
      helpers.get_db_utils()

      helpers.setenv("MY_LICENSE", assert(valid_license))

      assert(helpers.start_kong({
        license_data = "{vault://env/my-license}",
      }))
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
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

    lazy_setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong())
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
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

    lazy_setup(function()
      helpers.get_db_utils()
      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong())
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    it("create a webhook when the license is deployed via the admin API", function()
      local res = assert(client:send {
        method = "POST",
        path = "/licenses",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = { payload = valid_license },
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

    lazy_setup(function()
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

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong("servroot1")
      helpers.stop_kong("servroot2")
    end)

    it("reload license across all nodes in a cluster when the license is deployed via Admin API", function()
      local res = assert(client:send {
        method = "POST",
        path = "/licenses",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = { payload = valid_license },
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

  describe("/", function()
    local client

    lazy_setup(function()
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

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong("servroot1")
      helpers.stop_kong("servroot2")
    end)

    it("should be able to update license when current license is invalide", function()
      local res = assert(client:send {
        method = "POST",
        path = "/licenses",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = { payload = expired_license },
      })
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      local id_expired = json.id


      res = assert(client:send {
        method = "POST",
        path = "/licenses",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = { payload = valid_license },
      })

      body = assert.res_status(201, res)
      json = cjson.decode(body)
      local id_valid = json.id

      local res = assert(client:send {
        method = "DELETE",
        path = "/licenses/" .. id_valid,
      })
      assert.res_status(204, res)

      local res = assert(client:send {
        method = "DELETE",
        path = "/licenses/" .. id_expired,
      })
      assert.res_status(204, res)
    end)
  end)

  describe("with an expired license is configured and the grace period is exceeded", function()
    local client, reset_distribution

    lazy_setup(function()
      helpers.get_db_utils(strategy, {"licenses"})
      reset_distribution = setup_distribution()

      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong({
        license_data = expired_license,
      }))
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      reset_distribution()
    end)

    -- We already recognize correlation-id as an EE plugin in distributions_constants.lua
    it("add EE plugin is not allowed", function()
      local res = assert(client:send {
        method = "POST",
        path = "/plugins",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          name = "correlation-id",
        },
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.equal("schema violation (name: 'correlation-id' is an enterprise only plugin)",
                  json["message"])
    end)

    it("add CE plugin is allowed", function()
      local res = assert(client:send {
        method = "POST",
        path = "/plugins",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          name = "cors",
        },
      })
      assert.res_status(201, res)
    end)

    it("get EE entities is allowed", function()
      local res = assert(client:send {
        method = "GET",
        path = "/event-hooks",
      })
      assert.res_status(200, res)
    end)

    it("add EE entities is not allowed", function()
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
      local body = assert.res_status(403, res)
      local json = cjson.decode(body)
      assert.equal("Enterprise license missing or expired",
                  json["message"])
    end)

    it("get workspace is allowed", function()
      local res = assert(client:send {
        method = "GET",
        path = "/workspaces",
      })
      assert.res_status(200, res)
    end)

    it("add workspace is not allowed", function()
      local res = assert(client:send {
        method = "POST",
        path = "/workspaces",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          name = "ws1",
        },
      })
      local body = assert.res_status(403, res)
      local json = cjson.decode(body)
      assert.equal("Enterprise license missing or expired",
                  json["message"])
    end)
  end)

  describe("with an expired license is configured but within the grace period", function()
    local client, reset_distribution

    lazy_setup(function()
      helpers.get_db_utils(strategy, {"licenses"})
      reset_distribution = setup_distribution()

      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong({
        license_data = grace_period_license,
      }))
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      reset_distribution()
    end)

    -- We already recognize correlation-id as an EE plugin in distributions_constants.lua
    it("add EE plugin is allowed", function()
      local res = assert(client:send {
        method = "POST",
        path = "/plugins",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          name = "correlation-id",
        },
      })
      assert.res_status(201, res)
    end)

    it("add CE plugin is allowed", function()
      local res = assert(client:send {
        method = "POST",
        path = "/plugins",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          name = "cors",
        },
      })
      assert.res_status(201, res)
    end)

    it("get EE entities is allowed", function()
      local res = assert(client:send {
        method = "GET",
        path = "/event-hooks",
      })
      assert.res_status(200, res)
    end)

    it("add EE entities is allowed", function()
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

    it("get workspace is allowed", function()
      local res = assert(client:send {
        method = "GET",
        path = "/workspaces",
      })
      assert.res_status(200, res)
    end)

    it("add workspace is allowed", function()
      local res = assert(client:send {
        method = "POST",
        path = "/workspaces",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          name = "ws1",
        },
      })
      assert.res_status(201, res)
    end)
  end)

  describe("with no license is configured", function()
    local client, reset_distribution

    lazy_setup(function()
      helpers.get_db_utils(strategy, {"licenses"})
      reset_distribution = setup_distribution()

      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong())
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      reset_distribution()
    end)

    -- We already recognize correlation-id as an EE plugin in distributions_constants.lua
    it("add EE plugin is not allowed", function()
      local res = assert(client:send {
        method = "POST",
        path = "/plugins",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          name = "correlation-id",
        },
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.equal("schema violation (name: 'correlation-id' is an enterprise only plugin)",
                  json["message"])
    end)

    it("add CE plugin is allowed", function()
      local res = assert(client:send {
        method = "POST",
        path = "/plugins",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          name = "cors",
        },
      })
      assert.res_status(201, res)
    end)

    it("get EE entities is not allowed", function()
      local res = assert(client:send {
        method = "GET",
        path = "/event-hooks",
      })
      local body = assert.res_status(403, res)
      local json = cjson.decode(body)
      assert.equal("Enterprise license missing or expired",
                  json["message"])
    end)

    it("add EE entities is not allowed", function()
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
      local body = assert.res_status(403, res)
      local json = cjson.decode(body)
      assert.equal("Enterprise license missing or expired",
                  json["message"])
    end)

    it("get workspace is allowed", function()
      local res = assert(client:send {
        method = "GET",
        path = "/workspaces",
      })
      assert.res_status(200, res)
    end)

    it("add workspace is not allowed", function()
      local res = assert(client:send {
        method = "POST",
        path = "/workspaces",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          name = "ws1",
        },
      })
      local body = assert.res_status(403, res)
      local json = cjson.decode(body)
      assert.equal("Enterprise license missing or expired",
                  json["message"])
    end)
  end)

  describe("/", function ()
    local admin_gui_client, admin_api_client

    lazy_setup(function ()
      helpers.get_db_utils()
      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong({
        admin_listen = "127.0.0.1:8001",
        admin_gui_listen = "127.0.0.1:8002",
        proxy_listen = "off",
        portal = "on",
        vitals = "off",
        portal_and_vitals_key = get_portal_and_vitals_key()
      }))
      admin_api_client = helpers.admin_client(nil, 8001)
      admin_gui_client = helpers.admin_gui_client(nil, 8002)
    end)

    lazy_teardown(function ()
      if admin_api_client then
        admin_api_client:close()
      end
      if admin_gui_client then
        admin_gui_client:close()
      end
      helpers.stop_kong()
    end)

    it('should update license through Admin API will update portal / vitals enabled status', function ()
      helpers.pwait_until(function()
        local res = assert(admin_gui_client:send {
          method = "GET",
          path = "/kconfig.js",
        })
        local kconfig_content = assert.res_status(200, res)
        assert.matches("'PORTAL': 'false'", kconfig_content, nil, true)
        assert.matches("'VITALS': 'false'", kconfig_content, nil, true)
      end, 30)

      local res = assert(admin_api_client:send {
        method = "POST",
        path = "/licenses",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = { payload = valid_license },
      })
      assert.res_status(201, res)

      helpers.pwait_until(function()
        local res = assert(admin_gui_client:send {
          method = "GET",
          path = "/kconfig.js",
        })
        local kconfig_content = assert.res_status(200, res)
        assert.matches("'PORTAL': 'true'", kconfig_content, nil, true)
        assert.matches("'VITALS': 'false'", kconfig_content, nil, true)
      end, 30)
    end)
  end)
end)

describe("Admin API #off", function()
  local valid_license, expired_license, grace_period_license

  local declarative_config_ee = [[
    _format_version: '3.0'
    plugins:
    - enabled: true
      name: correlation-id
      protocols:
      - http
      - https
    services:
    - host: localhost
      name: local
      port: 80
      protocol: http
      routes:
      - name: headers
        paths:
        - /headers
        strip_path: false
  ]]

  local declarative_config_ce = [[
    _format_version: '3.0'
    plugins:
    - enabled: true
      name: cors
      protocols:
      - http
      - https
    services:
    - host: localhost
      name: local
      port: 80
      protocol: http
      routes:
      - name: headers
        paths:
        - /headers
        strip_path: false
  ]]

  lazy_setup(function()
    local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
    valid_license = f:read("*a")
    f:close()

    f = assert(io.open("spec-ee/fixtures/mock_expired_license.json"))
    expired_license = f:read("*a")
    f:close()

    f = assert(io.open("spec-ee/fixtures/mock_grace_period_license_tmpl.json"))
    local tmpl = f:read("*a")
    grace_period_license = string.format(tmpl, os.date("%Y-%m-%d", os.time()-5*3600*24))
    f:close()

  end)

  describe("with an expired license is configured and the grace period is exceeded", function()
    local client, reset_distribution

    lazy_setup(function()
      reset_distribution = setup_distribution()

      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong({
        database = "off",
        mem_cache_size = "15m",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        license_data = expired_license,
      }))
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      reset_distribution()
    end)

    -- We already recognize correlation-id as an EE plugin in distributions_constants.lua
    it("add EE plugin is not allowed from /config", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          config = declarative_config_ee,
        },
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.equal("declarative config is invalid: {plugins={{name=\"'correlation-id' is an enterprise only plugin\"}}}",
                  json["message"])
    end)

    it("add CE plugin is allowed", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          config = declarative_config_ce,
        },
      })
      assert.res_status(201, res)
    end)
  end)

  describe("with an expired license is configured but within the grace period", function()
    local client, reset_distribution

    lazy_setup(function()
      reset_distribution = setup_distribution()

      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong({
        database = "off",
        mem_cache_size = "15m",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        license_data = grace_period_license,
      }))
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      reset_distribution()
    end)

    -- We already recognize correlation-id as an EE plugin in distributions_constants.lua
    it("add EE plugin is allowed from /config", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          config = declarative_config_ee,
        },
      })
      assert.res_status(201, res)
    end)

    it("add CE plugin is allowed from /config", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          config = declarative_config_ce,
        },
      })
      assert.res_status(201, res)
    end)
  end)

  describe("with no license is configured", function()
    local client, reset_distribution

    lazy_setup(function()
      reset_distribution = setup_distribution()

      helpers.unsetenv("KONG_LICENSE_DATA")
      helpers.unsetenv("KONG_TEST_LICENSE_DATA")
      assert(helpers.start_kong({
        database = "off",
        mem_cache_size = "15m",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      reset_distribution()
    end)

    -- We already recognize correlation-id as an EE plugin in distributions_constants.lua
    it("add EE plugin is not allowed from /config", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          config = declarative_config_ee,
        },
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.equal("declarative config is invalid: {plugins={{name=\"'correlation-id' is an enterprise only plugin\"}}}",
                  json["message"])
    end)

    it("add CE plugin is allowed from /config", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          config = declarative_config_ce,
        },
      })
      assert.res_status(201, res)
    end)
  end)
end)
