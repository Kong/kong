-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"
local pl_file = require "pl.file"

local CUSTOM_VAULTS = "./spec/fixtures/custom_vaults"
local CUSTOM_PLUGINS = "./spec/fixtures/custom_plugins"

local LUA_PATH = CUSTOM_VAULTS .. "/?.lua;" ..
                 CUSTOM_VAULTS .. "/?/init.lua;" ..
                 CUSTOM_PLUGINS .. "/?.lua;" ..
                 CUSTOM_PLUGINS .. "/?/init.lua;;"

local NESTED_HEADER = "X-This-Is-The-Secret"
local NESTED_HEADER_2 = "X-This-Is-The-Secret-2"
local DUMMY_PLUGIN_HEADER = "Dummy-Plugin"
local fmt = string.format
local utils = require "kong.tools.utils"
local VAULTS = require "spec-ee.fixtures.vaults.mock"


local noop = function(...) end

for _, vault in ipairs(VAULTS) do
  -- fill out some values that we'll use in route/service/plugin config
  vault.prefix     = vault.name .. "-ttl-test"
  vault.host       = vault.name .. ".vault-ttl.test"

  -- ...and fill out non-required methods
  vault.setup         = vault.setup or noop
  vault.teardown      = vault.teardown or noop
  vault.fixtures      = vault.fixtures or noop
end


-- TODO: this test only uses PostgreSQL (strategy is nil on get_db_utils below). Also test with the Off strategy
for _, attachment_point in ipairs({ 'global', 'service', 'route' }) do
for _, vault in ipairs(VAULTS) do
-- TODO: disabling aws and test temporarily. We should re-enable it accounting for the fact that AWS is "eventually consistent"
if vault.name ~= "test" and vault.name ~= "aws"  then


describe("vault ttl and rotation (#" .. attachment_point .. "_" .. vault.name .. ")", function()
  local client
  local secret = "my-secret-" .. utils.uuid()
  local secret_2 = "my-secret-2-" .. utils.uuid()


  local function http_get(path)
    path = path or "/"

    local res = client:get(path, {
      headers = {
        host = assert(vault.host),
      },
    })

    assert.response(res).has.status(200)

    return res
  end


  lazy_setup(function()
    helpers.setenv("KONG_LUA_PATH_OVERRIDE", LUA_PATH)
    helpers.setenv("KONG_VAULT_ROTATION_INTERVAL", "1")

    helpers.test_conf.loaded_plugins = {
      dummy = true,
    }

    vault:setup()
    vault:create_secret(secret, "init")
    vault:create_secret(secret_2, "init")

    local bp = helpers.get_db_utils(nil,
                                    nil,
                                    { "dummy" },
                                    { vault.name })

    assert(bp.vaults:insert({
      name     = vault.name,
      prefix   = vault.prefix,
      config   = vault.config,
    }))

    local service = assert(bp.services:insert({}))

    local route = assert(bp.routes:insert({
      name      = vault.host,
      hosts     = { vault.host },
      paths     = { "/" },
      service   = service,
    }))

    local secret_reference = fmt("{vault://%s/%s/secret?ttl=3&resurrect_ttl=3}", vault.prefix, secret)
    local secret_reference_2 = fmt("{vault://%s/%s/secret?ttl=3&resurrect_ttl=60}", vault.prefix, secret_2)
    assert(bp.plugins:insert({
      name = "dummy",
      config = {
        resp_header_value = secret_reference,
        resp_headers = {
          [NESTED_HEADER] = secret_reference,
          [NESTED_HEADER_2] = secret_reference_2,
        }
      },
      route = (attachment_point == 'route') and { id = route.id } or nil,
      service = (attachment_point == 'service') and { id = service.id } or nil,
    }))

    helpers.setenv("KONG_LICENSE_DATA", pl_file.read("spec-ee/fixtures/mock_license.json"))
    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      vaults     = vault.name,
      plugins    = "dummy",
      log_level  = "info",
    }, nil, nil, vault:fixtures()))

    client = helpers.proxy_client()
  end)


  lazy_teardown(function()
    if client then
      client:close()
    end

    pcall(vault.delete_secret, vault, secret)
    pcall(vault.delete_secret, vault, secret_2)
    vault:teardown()

    helpers.stop_kong()

    helpers.unsetenv("KONG_LUA_PATH_OVERRIDE")
  end)


  local function check_plugin_secret(expect1, expect2, timeout, level1_header, level2_header)
    assert
      .with_timeout(timeout)
      .with_step(0.5)
      .eventually(
      function()
        local res = http_get("/")

        local level1_value = res.headers[level1_header or DUMMY_PLUGIN_HEADER]
        local level2_value = res.headers[level2_header or NESTED_HEADER]

        if level1_value == expect1 and level2_value == expect2 then
          return true
        end

        return nil, { expected = fmt("%s and %s", expect1, expect2), got = fmt("%s and %s", level1_value, level2_value) }
      end)
      .is_truthy("expected plugin secret to be updated within " .. tostring(timeout) .. " seconds")
  end


  local function check_no_plugin_secret(timeout)
    assert
      .with_timeout(timeout)
      .with_step(0.5)
      .eventually(
      function()
        local res = http_get("/")
        return not res.headers[NESTED_HEADER] and not res.headers[DUMMY_PLUGIN_HEADER]
      end)
      .is_truthy("expected plugin secret to be removed within " .. tostring(timeout) .. " seconds")
  end

  it("updates plugin config references", function()

    -- Did we see the change from `init` to the newly set secret?
    vault:update_secret(secret, "updated_once", { ttl = 5, resurrect_ttl = 5 })
    check_plugin_secret("updated_once", "updated_once", 15)

    -- Did we see the change from previsouly set secret to the newly set secret?
    vault:update_secret(secret, "updated_twice", { ttl = 5, resurrect_ttl = 5 })
    check_plugin_secret("updated_twice", "updated_twice", 15)

    -- Does it disappear when we delete it from the vault?
    vault:delete_secret(secret)
    check_no_plugin_secret(100)
  end)

  it("#flaky respects resurrect_ttl times", function ()
    -- If we create a secret with a high resurrect time, we expect that it
    -- does not expire, even when we delete the secret from the vault
    -- inbetween
    check_plugin_secret("init", nil, 11, NESTED_HEADER_2)

    -- We delete a secret
    vault:delete_secret(secret_2)
    -- Check if we can still see it (it should be valid for at least a couple of seconds.)
    check_plugin_secret("init", nil, 11, NESTED_HEADER_2)
    -- re-create the secret
    vault:create_secret(secret_2, "created_again", { ttl = 5, resurrect_ttl = 5 })
    -- and check if this eventually changes to the new value
    check_plugin_secret("created_again", nil, 15, NESTED_HEADER_2)

    -- If we create it again(with a different value), do we see the changes?
    vault:update_secret(secret_2, "updated_yet_again", {ttl = 5, resurrect_ttl = 5})
    check_plugin_secret("updated_yet_again", nil, 15, NESTED_HEADER_2)
  end)
end)

end  -- conditional to exclude `test` vault
end -- each vault backend
end -- each attachment_point
