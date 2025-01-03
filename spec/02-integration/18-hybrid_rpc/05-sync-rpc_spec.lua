local constants = require("kong.constants")
local helpers = require("spec.helpers")
local misc = require("spec.internal.misc")
local cp = require("spec.helpers.rpc_mock.cp")
local dp = require("spec.helpers.rpc_mock.dp")
local setup = require("spec.helpers.rpc_mock.setup")
local get_node_id = misc.get_node_id
local DP_PREFIX = "servroot_dp"
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH

local function change_config()
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

describe("kong.sync.v2", function()
  lazy_setup(setup.setup)
  lazy_teardown(setup.teardown)

  describe("CP side", function()
    local mocked_cp, node_id

    lazy_setup(function()
      helpers.get_db_utils()

      mocked_cp = cp.new()
      assert(mocked_cp:start())

      assert(helpers.start_kong({
        prefix = DP_PREFIX,
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

      node_id = get_node_id(DP_PREFIX)

      mocked_cp:wait_for_node(node_id)
    end)

    lazy_teardown(function()
      mocked_cp:stop()
      helpers.stop_kong(DP_PREFIX)
    end)

    it("config change", function()
      -- this get DP to make a "kong.sync.v2.get_delta" call to the CP
      -- CP->DP: notify_new_version
      -- DP->CP: get_delta
      change_config()

      -- wait for the "kong.sync.v2.get_delta" call and get the record
      local record = mocked_cp:wait_for_a_call()
      -- ensure the content of the call is correct
      assert.is_table(record.response.result.default.deltas)
    end)

    it("notify_new_version triggers get_delta", function()
      local called = false
      mocked_cp:mock("kong.sync.v2.get_delta", function(node_id, payload)
        called = true
        return { default = { version = "100", deltas = {} } }
      end)

      -- make a call from the mocked cp
      -- CP->DP: notify_new_version
      assert(mocked_cp:call(node_id, "kong.sync.v2.notify_new_version", { default = { new_version = "100", } }))

      -- DP->CP: get_delta
      -- the dp after receiving the notification will make a call to the cp
      -- which is mocked
      -- the mocking handler is called
      helpers.wait_until(function()
        return called
      end, 20)
    end)
  end)
  
  describe("DP side", function()
    local mocked_dp, register_dp
    local called = false

    lazy_setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong({
        role = "control_plane",
        cluster_mtls = "shared",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_rpc = "on",
        cluster_rpc_sync = "on",
      }))

      mocked_dp = assert(dp.new())

      mocked_dp.callbacks:register("kong.sync.v2.notify_new_version", function(node_id, payload)
        called = true
      end)

      mocked_dp:start()
      mocked_dp:wait_until_connected()


      -- this is a workaround to registers the data plane node
      -- CP does not register the DP node until it receives a call from the DP
      function register_dp()
        local res, err = mocked_dp:call("control_plane", "kong.sync.v2.get_delta", { default = { version = "0",},})
        assert.is_nil(err)
        assert.is_table(res and res.default and res.default.deltas)
      end
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      mocked_dp:stop()
    end)

    it("rpc call", function()
      local res, err = mocked_dp:call("control_plane", "kong.sync.v2.get_delta", { default = { version = "0",},})
      assert.is_nil(err)
      assert.is_table(res and res.default and res.default.deltas)

      local res, err = mocked_dp:call("control_plane", "kong.sync.v2.unknown", { default = {},})
      assert.is_string(err)
      assert.is_nil(res)
    end)

    it("config change triggers notify_new_version", function()
      register_dp()

      -- this makes CP to initiate a "kong.sync.notify_new_version" call to DP
      change_config()

      -- the mocking handler is called
      helpers.wait_until(function()
        return called
      end, 20)
    end)
  end)
end)
