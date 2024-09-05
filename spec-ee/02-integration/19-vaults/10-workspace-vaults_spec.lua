-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fmt = string.format
local pl_file = require "pl.file"
local json = require "cjson"
local mock_server_port = helpers.get_available_port()

local fixtures = {
  http_mock = {
    mock_hcv_server = fmt([[
      server {
        listen %s;
        listen [::]:%s;

        error_log logs/proxy.log debug;

        location = /v1/secret/data/kong {
          content_by_lua_block {

            local vault_token = ngx.req.get_headers()["X-Vault-Token"]
            if vault_token ~= "correct_token" then
              ngx.status = 403
              ngx.say('{"errors": ["permission denied"]}')
              return
            end

            ngx.req.read_body()
            ngx.status = 200
            ngx.header["Content-Type"] = "application/json"
            ngx.say('{"data": {"data": {"abc": "X-Test-Header:test-header-value"}}}')
          }
        }
      }
    ]], mock_server_port, mock_server_port),
  }
}

for _, strategy in helpers.each_strategy() do
  describe("Vault entity in a non-default workspace", function()
    local bp, proxy_client, admin_client, license_env
    lazy_setup(function()
      helpers.setenv("KONG_VAULT_ROTATION_INTERVAL", "2")
      license_env = os.getenv("KONG_LICENSE_DATA")
      helpers.setenv("KONG_LICENSE_DATA", pl_file.read("spec-ee/fixtures/mock_license.json"))

      bp, _ = helpers.get_db_utils(strategy, {
        "workspaces",
        "vaults",
        "plugins",
      }, {"request-transformer-advanced", "post-function"}, { "hcv" })

      local ws = assert(bp.workspaces:insert({
        name = "test-ws",
      }))

      assert(bp.vaults:insert_ws({
        name     = "hcv",
        prefix   = "hcv-test",
        config   = {
          protocol      = "http",
          host          = "localhost",
          port          = mock_server_port,
          kv            = "v2",
          auth_method   = "token",
          token         = "wrong_token",
          ttl           = 3,
          neg_ttl       = 4,
          resurrect_ttl = 3,
        },
      }, ws))

      local route = assert(bp.routes:insert_ws({
        name      = "test-route",
        hosts     = { "test.com" },
        paths     = { "/" },
        service   = assert(bp.services:insert_ws(nil, ws)),
      }, ws))


      -- used by the plugin config test case
      assert(bp.plugins:insert_ws({
        name = "request-transformer-advanced",
        config = {
          add = {
            headers = {"{vault://hcv-test/kong/abc}"},
          },
        },
        route = { id = route.id },
      }, ws))

      assert(bp.plugins:insert_ws({
        name = "post-function",
        config = {
          access ={
            [[local header = kong.request.get_header("X-Test-Header")
              if header then
                kong.response.exit(200, {["header"]=header, ["pid"]=ngx.worker.pid()})
              else
                kong.response.exit(500, {["header"]=nil, ["pid"]=ngx.worker.pid()})
              end]],
          },
        },
        route = { id = route.id },
      }, ws))

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        log_level = "info",
        vaults = "bundled",
        plugins = "request-transformer-advanced, post-function",
        dedicated_config_processing = false,
        nginx_main_worker_processes = 2,
      }, nil, nil, fixtures))

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      if proxy_client then proxy_client:close() end
      if admin_client then admin_client:close() end
      if license_env then
        helpers.setenv("KONG_LICENSE_DATA", license_env)
      else
        helpers.unsetenv("KONG_LICENSE_DATA")
      end
    end)

    it("secrets can be updated correctly by rotation", function()
      -- fetch all worker ids
      local status_ret = admin_client:get("/")
      local body = assert.res_status(200, status_ret)
      local json_body = json.decode(body)
      assert.truthy(json_body)
      local worker_pids = json_body.pids.workers
      assert.truthy(#worker_pids == 2)
      local worker_secret_hits = {}
      for _, worker_pid in ipairs(worker_pids) do
        worker_secret_hits[tostring(worker_pid)] = false
      end

      helpers.clean_logfile()
      -- configured with wrong token, so the request should fail
      local res = proxy_client:get("/", {
        headers = {
          ["Host"] = "test.com",
        }
      })
      assert.res_status(500, res)
      assert.logfile().has.line([[unable to retrieve secret from vault: {"errors": ["permission denied"]}]], true, 3)

      -- update to the correct token
      local res = admin_client:patch("/test-ws/vaults/hcv-test", {
        body = {
          config = {
            token = "correct_token",
          }
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      assert.res_status(200, res)
      helpers.clean_logfile()

      assert.with_timeout(10)
            .with_step(0.5)
            .ignore_exceptions(true)
            .eventually(function()
              local new_client = helpers.proxy_client()
              local res = new_client:get("/", {
                headers = {
                  ["Host"] = "test.com",
                }
              })
              local body = assert.res_status(200, res)
              local json_body = json.decode(body)
              new_client:close()
              assert.same(json_body.header, "test-header-value")
              worker_secret_hits[tostring(json_body.pid)] = true

              for k, v in pairs(worker_secret_hits) do
                if not v then
                  return false, "worker pid " .. k .. " did not hit the secret"
                end
              end

              return true
            end).is_truthy("expect requests to all workers succeed after the token is updated")

      -- rotation should also become normal
      assert.logfile().has.no.line([[unable to retrieve secret from vault: {"errors": ["permission denied"]}]], true, 3)
    end)
  end)
end
