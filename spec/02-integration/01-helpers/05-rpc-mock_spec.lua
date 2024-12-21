local helpers = require("spec.helpers")
local server = require("spec.helpers.rpc_mock.server")
local client = require("spec.helpers.rpc_mock.client")
local get_node_id = helpers.get_node_id

local function trigger_change()
  -- the initial sync is flaky. let's trigger a sync by creating a service
  local admin_client = helpers.admin_client()
  assert.res_status(201, admin_client:send {
    method = "POST",
    path = "/services/",
    body = {
      url = "http://example.com",
    },
    headers = {
      ["Content-Type"] = "application/json",
    },
  })
end

describe("rpc mock/hook", function()
  describe("server side", function()
    local server_mock

    lazy_setup(function()
      helpers.get_db_utils()

      server_mock = server.new()
      assert(server_mock:start())

      assert(helpers.start_kong({
        database = "off",
        role = "data_plane",
        cluster_mtls = "shared",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_rpc = "on",
        cluster_rpc_sync = "on",
        log_level = "debug",
        cluster_control_plane = "127.0.0.1:8005",
      }))
    end)

    lazy_teardown(function()
      server_mock:stop(true)
      helpers.stop_kong(nil, true)
    end)

    it("recording", function()
      trigger_change()

      local record = server_mock:wait_for_call()
      assert.is_table(record.response.result.default.deltas)
    end)

    it("mock", function()
      local client_version
      server_mock:mock("kong.sync.v2.get_delta", function(node_id, payload)
        client_version = payload.default.version
        return { default = { version = 100, deltas = {} } }
      end)
      server_mock:attach_debugger()

      local dp_id = get_node_id("servroot")

      server_mock:wait_for_node(dp_id)

      assert(server_mock:call(dp_id, "kong.sync.v2.notify_new_version", { default = { new_version = 100, } }))

      -- the mock should have been called
      helpers.wait_until(function()
        return client_version
      end, 20)
    end)
  end)
  
  describe("client side", function()
    local client_mock
    local called = false

    lazy_setup(function()
      helpers.get_db_utils()

      client_mock = assert(client.new())
      assert(helpers.start_kong({
        role = "control_plane",
        cluster_mtls = "shared",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_rpc = "on",
        cluster_rpc_sync = "on",
      }))

      client_mock.callbacks:register("kong.sync.v2.notify_new_version", function(node_id, payload)
        called = true
      end)

      client_mock:start()
      client_mock:wait_until_connected()   
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
      client_mock:stop()
    end)

    it("client->CP", function()
      local res, err = client_mock:call("control_plane", "kong.sync.v2.get_delta", { default = { version = 0,},})
      assert.is_nil(err)
      assert.is_table(res and res.default and res.default.deltas)

      local res, err = client_mock:call("control_plane", "kong.sync.v2.unknown", { default = { },})
      assert.is_string(err)
      assert.is_nil(res)
    end)

    it("CP->client", function()
      -- this registers the data plane node
      local res, err = client_mock:call("control_plane", "kong.sync.v2.get_delta", { default = { version = 0,},})
      assert.is_nil(err)
      assert.is_table(res and res.default and res.default.deltas)

      trigger_change()

      helpers.wait_until(function()
        return called
      end, 20)
    end)
  end)
end)
