local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local CLUSTERING_SYNC_STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS

local admin = require "spec.fixtures.admin_api"

local CP_HOST = "127.0.0.1"
local CP_PORT = 9005

local PLUGIN_LIST


local function cluster_client(opts)
  opts = opts or {}
  local res, err = helpers.clustering_client({
    host = CP_HOST,
    port = CP_PORT,
    cert = "spec/fixtures/kong_clustering.crt",
    cert_key = "spec/fixtures/kong_clustering.key",
    node_hostname = opts.hostname or "test",
    node_id = opts.id or utils.uuid(),
    node_version = opts.version,
    node_plugins_list = PLUGIN_LIST,
  })

  assert.is_nil(err)
  if res and res.config_table then
    res.config = res.config_table
  end

  return res
end

local function get_plugin(node_id, node_version, name)
  local res, err = cluster_client({ id = node_id, version = node_version })
  assert.is_nil(err)
  assert.is_table(res and res.config and res.config.plugins,
                  "invalid response from clustering client")

  local plugin
  for _, p in ipairs(res.config.plugins) do
    if p.name == name then
      plugin = p
      break
    end
  end

  assert.not_nil(plugin, "plugin " .. name .. " not found in config")
  return plugin
end


local function get_sync_status(id)
  local status
  local admin_client = helpers.admin_client()

  helpers.wait_until(function()
    local res = admin_client:get("/clustering/data-planes")
    local body = assert.res_status(200, res)

    local json = cjson.decode(body)

    for _, v in pairs(json.data) do
      if v.id == id then
        status = v.sync_status
        return true
      end
    end
  end, 5, 0.5)

  admin_client:close()

  return status
end


for _, strategy in helpers.each_strategy() do

describe("CP/DP config compat transformations #" .. strategy, function()
  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy)

    PLUGIN_LIST = helpers.get_plugins_list()

    bp.routes:insert {
      name = "compat.test",
      hosts = { "compat.test" },
      service = bp.services:insert {
        name = "compat.test",
      }
    }

    assert(helpers.start_kong({
      role = "control_plane",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      database = strategy,
      db_update_frequency = 0.1,
      cluster_listen = CP_HOST .. ":" .. CP_PORT,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("plugin config fields", function()
    local rate_limit

    lazy_setup(function()
      rate_limit = admin.plugins:insert {
        name = "rate-limiting",
        enabled = true,
        config = {
          second = 1,
          policy = "local",

          -- [[ new fields
          error_code = 403,
          error_message = "go away!",
          sync_rate = -1,
          -- ]]
        },
      }
    end)

    lazy_teardown(function()
      admin.plugins:remove({ id = rate_limit.id })
    end)

    it("removes new fields before sending them to older DP nodes", function()
      local id = utils.uuid()
      local plugin = get_plugin(id, "3.0.0", rate_limit.name)

      --[[
        For 3.0.x
        should not have: error_code, error_message, sync_rate
      --]]
      local expected = utils.cycle_aware_deep_copy(rate_limit.config)
      expected.error_code = nil
      expected.error_message = nil
      expected.sync_rate = nil
      assert.same(expected, plugin.config)
      assert.equals(CLUSTERING_SYNC_STATUS.NORMAL, get_sync_status(id))


      --[[
        For 3.2.x
        should have: error_code, error_message
        should not have: sync_rate
      --]]
      id = utils.uuid()
      plugin = get_plugin(id, "3.2.0", rate_limit.name)
      expected = utils.cycle_aware_deep_copy(rate_limit.config)
      expected.sync_rate = nil
      assert.same(expected, plugin.config)
      assert.equals(CLUSTERING_SYNC_STATUS.NORMAL, get_sync_status(id))


      --[[
        For 3.3.x,
        should have: error_code, error_message
        should not have: sync_rate
      --]]
      id = utils.uuid()
      plugin = get_plugin(id, "3.3.0", rate_limit.name)
      expected = utils.cycle_aware_deep_copy(rate_limit.config)
      expected.sync_rate = nil
      assert.same(expected, plugin.config)
      assert.equals(CLUSTERING_SYNC_STATUS.NORMAL, get_sync_status(id))
    end)

    it("does not remove fields from DP nodes that are already compatible", function()
      local id = utils.uuid()
      local plugin = get_plugin(id, "3.4.0", rate_limit.name)
      assert.same(rate_limit.config, plugin.config)
      assert.equals(CLUSTERING_SYNC_STATUS.NORMAL, get_sync_status(id))
    end)
  end)
end)

end -- each strategy
