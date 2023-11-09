-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson         = require "cjson"
local helpers       = require "spec.helpers"
local utils         = require "kong.tools.utils"
local pl_file       = require "pl.file"
local pl_stringx    = require "pl.stringx"
local pl_path       = require "pl.path"

local FILE_LOG_PATH = os.tmpname()


for _, strategy in helpers.each_strategy() do

describe("cache the workspace names #" .. strategy, function()

  lazy_setup(function()
    helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "clustering_data_planes",
    }) -- runs migrations

    assert(helpers.start_kong({
      role = "control_plane",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      db_update_frequency = 0.1,
      database = strategy,
      cluster_listen = "127.0.0.1:9005",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      -- additional attributes for PKI:
      cluster_mtls = "pki",
      cluster_ca_cert = "spec/fixtures/kong_clustering_ca.crt",
    }))

    assert(helpers.start_kong({
      role = "data_plane",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      database = "off",
      prefix = "servroot2",
      cluster_cert = "spec/fixtures/kong_clustering_client.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering_client.key",
      cluster_control_plane = "127.0.0.1:9005",
      proxy_listen = "0.0.0.0:9002",
      -- additional attributes for PKI:
      cluster_mtls = "pki",
      cluster_server_name = "kong_clustering",
      cluster_ca_cert = "spec/fixtures/kong_clustering.crt",
      log_level = "info",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong("servroot2")
    helpers.stop_kong()
  end)

  it("dp includes workspace_name in payload", function()
    local admin_client = helpers.admin_client(10000)
    finally(function()
      admin_client:close()
    end)

    -- create workspace
    local res = assert(admin_client:post("/workspaces", {
      body   = {
        name = "foo-ws",
      },
      headers = {
        ["Content-Type"] = "application/json",
      }
    }))
    assert.res_status(201, res)

    res = assert(admin_client:post("/foo-ws/services", {
      body = { name = "mockbin-service", url = "https://127.0.0.1:15556/request", },
      headers = {["Content-Type"] = "application/json"}
    }))
    assert.res_status(201, res)

    res = assert(admin_client:post("/foo-ws/services/mockbin-service/routes", {
      body = { paths = { "/" }, },
      headers = {["Content-Type"] = "application/json"}
    }))
    assert.res_status(201, res)

    res = assert(admin_client:post("/foo-ws/plugins", {
      body = {
        name = "file-log",
        config = {
          path = FILE_LOG_PATH,
          reopen = true,
        }
      },
      headers = {["Content-Type"] = "application/json"}
    }))

    local uuid = utils.random_string()
    helpers.wait_until(function()
      -- Making the request
      local proxy_client = helpers.http_client("127.0.0.1", 9002)
      res = proxy_client:send({
        method  = "GET",
        path    = "/",
        headers = {
          ["file-log-uuid"] = uuid
        }
      })

      local status = res and res.status
      proxy_client:close()
      if status == 200 then
        return true
      end
    end, 10)

    helpers.wait_until(function()
      return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
    end, 10)

    local log = pl_file.read(FILE_LOG_PATH)
    local log_message = cjson.decode(pl_stringx.strip(log):match("%b{}"))
    assert.same("127.0.0.1", log_message.client_ip)
    assert.same(uuid, log_message.request.headers["file-log-uuid"])
    assert.same("foo-ws", log_message.workspace_name)
  end)
end)

end
