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


for _, attachment_point in ipairs({ 'global', 'service', 'route' }) do
for _, vault in ipairs(VAULTS) do

describe("vault try() (#" .. attachment_point .. "_" .. vault.name .. ")", function()
  local client
  local secret = "my-secret-" .. utils.uuid()

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
    helpers.setenv("KONG_VAULT_ROTATION_INTERVAL", "600")

    helpers.test_conf.loaded_plugins = {
      dummy = true,
    }

    vault:setup()
    vault:create_secret(secret, "init")

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

    local secret_reference = fmt("{vault://%s/%s/secret?ttl=30&resurrect_ttl=30}", vault.prefix, secret)
    assert(bp.plugins:insert({
      name = "dummy",
      config = {
        resp_header_value = secret_reference,
        resp_headers = {
          [NESTED_HEADER] = secret_reference,
        },
        test_try = true,
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
    vault:teardown()

    helpers.stop_kong()

    helpers.unsetenv("KONG_LUA_PATH_OVERRIDE")
  end)

  local function check_plugin_secret(expect_header, timeout)
    assert
      .with_timeout(timeout)
      .with_step(3)
      .eventually(
      function()
        local res = http_get("/")

        if not expect_header then
          return true
        end
        if res.headers["X-Try-Works"] == "true" then
          return true
        end

        return nil, { expected = "Expected to see the X-Try-Works to be true"}
      end)
      .is_truthy("expected plugin secret to be updated within " .. tostring(timeout) .. " seconds")
  end

  it("check if `try` retrieves a secret from the vault", function()
    -- The secret is set to `init` here. This makes the `check_plugin_secret` fn fail
    check_plugin_secret(false, 11)
    -- Update the secret to make `check_plugin_secret` pass
    vault:update_secret(secret, "open_sesame", {ttl = 5, resurrect_ttl = 5})
    -- This implicitly tests the try() function as the rotation timer is set to 600 seconds
    -- the try function needs to contact a vault implementation to retrieve the secret
    -- in order for this test to pass
    check_plugin_secret(true, 10)
  end)
end)

end -- each vault backend
end -- each attachment_point
