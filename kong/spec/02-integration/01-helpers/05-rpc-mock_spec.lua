local helpers = require("spec.helpers")
local misc = require("spec.internal.misc")
local cp = require("spec.helpers.rpc_mock.cp")
local dp = require("spec.helpers.rpc_mock.dp")
local setup = require("spec.helpers.rpc_mock.setup")
local get_node_id = misc.get_node_id
local DP_PREFIX = "servroot_dp"

describe("rpc mock/hooc", function()
  lazy_setup(setup.setup)
  lazy_teardown(setup.teardown)

  describe("CP side mock", function()
    local mocked_cp, node_id

    lazy_setup(function()
      local _, db = helpers.get_db_utils(nil, nil, { "rpc-hello-test" })

      mocked_cp = cp.new({
        plugins = "bundled,rpc-hello-test",
      })

      local service = assert(db.services:insert({
        host = helpers.mock_upstream_host,
      }))

      assert(db.routes:insert({
        service = service,
        paths = { "/" },
      }))

      assert(db.plugins:insert({
        service = service,
        name = "rpc-hello-test",
        config = {},
      }))

      assert(mocked_cp:start())

      assert(helpers.start_kong({
        prefix = DP_PREFIX,
        database = "off",
        role = "data_plane",
        cluster_mtls = "shared",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,rpc-hello-test",
        cluster_rpc = "on",
        cluster_rpc_sync = "on",
        log_level = "debug",
        cluster_control_plane = "127.0.0.1:8005",
      }))

      node_id = get_node_id(DP_PREFIX)
      mocked_cp:wait_for_node(node_id)
    end)

    lazy_teardown(function()
      mocked_cp:stop(true)
      helpers.stop_kong(DP_PREFIX, true)
    end)

    it("interception", function()
      local body
      helpers.pwait_until(function()
        local proxy_client = assert(helpers.proxy_client())

        body = assert.res_status(200, proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["x-greeting"] = "world",
          }
        })
      end, 10)

      assert.equal("hello world", body)

      -- wait for the "kong.sync.v2.get_delta" call and get the record
      local record = mocked_cp:wait_for_a_call(function(call)
        return call.method == "kong.test.hello"
      end)

      -- ensure the content of the call is correct
      assert.same({
        method = 'kong.test.hello',
        node_id = node_id,
        proxy_id = 'control_plane',
        request = 'world',
        response = {
          result = 'hello world',
        },
      }, record)
    end)

    it("mock", function()
      finally(function()
        mocked_cp:unmock("kong.test.hello")
      end)
      local called = false
      mocked_cp:mock("kong.test.hello", function(node_id, payload)
        called = true
        return "goodbye " .. payload
      end)

      local body
      helpers.pwait_until(function()
        local proxy_client = assert(helpers.proxy_client())

        body = assert.res_status(200, proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["x-greeting"] = "world",
          }
        })
      end, 10)

      assert.equal("goodbye world", body)
      assert.truthy(called)
    end)

    it("call", function()
      local res, err = mocked_cp:call(node_id, "kong.test.hello", "world")
      assert.is_nil(err)
      assert.equal("hello world", res)

      local res, err = mocked_cp:call(node_id, "kong.test.unknown", "world")
      assert.is_string(err)
      assert.is_nil(res)
    end)

    it("prehook/posthook", function()
      local prehook_called = false
      mocked_cp:prehook("kong.test.hello", function(node_id, payload)
        prehook_called = true
        return node_id .. "'s " .. payload
      end)

      local body
      helpers.pwait_until(function()
        local proxy_client = assert(helpers.proxy_client())

        body = assert.res_status(200, proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["x-greeting"] = "world",
          }
        })
      end, 10)

      assert.equal("hello " .. node_id .. "'s world", body)
      assert.truthy(prehook_called)

      prehook_called = false
      local posthook_called = false
      mocked_cp:posthook("kong.test.hello", function(node_id, payload)
        posthook_called = true
        return "Server: " .. payload.result
      end)

      local proxy_client = assert(helpers.proxy_client())

      body = assert.res_status(200, proxy_client:send {
        method = "GET",
        path = "/",
        headers = {
          ["x-greeting"] = "world",
        }
      })

      assert.equal("Server: hello " .. node_id .. "'s world", body)
      assert.truthy(prehook_called)
      assert.truthy(posthook_called)
    end)
  end)
  
  describe("DP side", function()
    local mocked_dp
    local called = false

    lazy_setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong({
        role = "control_plane",
        cluster_mtls = "shared",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        plugins = "bundled,rpc-hello-test",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_rpc = "on",
        cluster_rpc_sync = "on",
      }))

      mocked_dp = assert(dp.new())

      mocked_dp.callbacks:register("kong.test.hello", function(node_id, payload)
        called = true
        return "goodbye " .. payload
      end)

      mocked_dp:start()
      mocked_dp:wait_until_connected()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      mocked_dp:stop()
    end)

    it("rpc call", function()
      local res, err = mocked_dp:call("control_plane", "kong.test.hello", "world")
      assert.is_nil(err)
      assert.equal("hello world", res)

      local res, err = mocked_dp:call("control_plane", "kong.sync.v2.unknown", { default = {},})
      assert.is_string(err)
      assert.is_nil(res)
    end)

    it("get called", function()
      local admin_client = helpers.admin_client()
      local node_id = mocked_dp.node_id

      local res = assert.res_status(200, admin_client:send {
        method = "GET",
        path = "/rpc-hello-test",
        headers = {
          ["x-greeting"] = "world",
          ["x-node-id"] = node_id,
        },
      })

      assert.equal("goodbye world", res)
      assert.truthy(called)
    end)
  end)
end)
