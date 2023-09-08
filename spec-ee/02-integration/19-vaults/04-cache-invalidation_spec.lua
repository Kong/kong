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

local DUMMY_PLUGIN_HEADER = "Dummy-Plugin"

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
if vault.name ~= "test" then


describe("vault cache invalidation (#" .. attachment_point .. "_" .. vault.name .. ")", function()
  local client, admin_client
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
    helpers.setenv("KONG_VAULT_ROTATION_INTERVAL", "360")

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

    -- 60 second TTL
    local secret_reference = fmt("{vault://%s/%s/secret?ttl=60&resurrect_ttl=60}", vault.prefix, secret)
    assert(bp.plugins:insert({
      name = "dummy",
      config = {
        resp_header_value = secret_reference,
        resp_headers = {
          [NESTED_HEADER] = secret_reference,
        },
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
    client.reopen = true
  end)

  before_each(function()
    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
    if client then
      client:close()
    end
    if admin_client then
      admin_client:close()
    end

    pcall(vault.delete_secret, vault, secret)
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

  it("check if caches get evicted when configuration of vault changes", function()
    check_plugin_secret("init", "init", 22)

    -- call any CRUD operation on a vault
    vault:update_secret(secret, "did_rotate_run", {ttl = 5, resurrect_ttl = 5})
    local HEADERS = { ["Content-Type"] = "application/json" }
    local res = admin_client:patch(fmt("/vaults/%s", vault.prefix), {
      headers = HEADERS,
      body = {
        config = {
          neg_ttl = 30
        },
      },
    })
    assert.res_status(200, res)

    check_plugin_secret("did_rotate_run", "did_rotate_run", 22)
  end)
end)

end
end -- each vault backend
end -- each attachment_point
