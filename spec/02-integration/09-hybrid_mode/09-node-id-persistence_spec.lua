local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

local uuid = utils.uuid
local is_valid_uuid = utils.is_valid_uuid

local PREFIX = "servroot.dp"
local NODE_ID = PREFIX .. "/kong.id"

for _, strategy in helpers.each_strategy() do
  describe("node id persistence", function()

    local control_plane_config = {
      role = "control_plane",
      database = strategy,
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      cluster_listen = "127.0.0.1:9005",
    }

    local data_plane_config = {
      log_levle = "info",
      role = "data_plane",
      prefix = PREFIX,
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      cluster_control_plane = "127.0.0.1:9005",
      proxy_listen = "0.0.0.0:9002",
      database = "off",
    }

    local admin_client
    local db

    local function get_all_data_planes()
      local res = admin_client:get("/clustering/data-planes")
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.is_table(json.data)
      return json.data
    end

    local function get_data_plane(id)
      local dps = get_all_data_planes()

      if #dps == 0 then
        return
      end

      -- all tests assume only one connected DP so that there is no ambiguity
      assert.equals(1, #dps, "unexpected number of connected data planes")

      return dps[1]
    end

    lazy_setup(function()
      local _
      _, db = helpers.get_db_utils(strategy, {
        "clustering_data_planes",
        "consumers",
      }) -- runs migrations

      assert(helpers.start_kong(control_plane_config))

      admin_client = assert(helpers.admin_client())
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong(PREFIX)
      helpers.stop_kong()
    end)

    after_each(function()
      helpers.stop_kong(PREFIX)
    end)

    before_each(function()
      if helpers.path.exists(PREFIX) then
        helpers.clean_prefix(PREFIX)
      end

      -- sanity
      assert.falsy(helpers.path.exists(NODE_ID))

      db.clustering_data_planes:truncate()
    end)

    it("generates a new ID on first start and saves it to a file", function()
      helpers.start_kong(data_plane_config)

      helpers.wait_for_file("file", NODE_ID)

      local node_id = assert(helpers.file.read(NODE_ID))

      assert.truthy(is_valid_uuid(node_id), "id " .. node_id .. " is invalid")

      -- sanity
      helpers.wait_until(function()
        local dps = get_all_data_planes()
        return #dps == 1 and dps[1].id == node_id
      end, 10, 0.5)
    end)

    it("generates a new ID if the existing one is invalid", function()
      helpers.prepare_prefix(PREFIX)

      local invalid = "INVALID"
      assert(helpers.file.write(NODE_ID, invalid))

      helpers.start_kong(data_plane_config)

      local node_id

      helpers.wait_until(function()
        node_id = helpers.file.read(NODE_ID)
        return node_id and is_valid_uuid(node_id)
      end, 5)

      -- sanity
      helpers.wait_until(function()
        return get_data_plane(node_id) ~= nil
      end, 10, 0.5)
    end)

    it("restores the node ID from the filesystem on restart", function()
      assert(helpers.start_kong(data_plane_config))

      local node_id
      helpers.wait_until(function()
        local dps = get_all_data_planes()

        if dps and #dps == 1 then
          node_id = dps[1].id
        end

        return node_id ~= nil
      end, 10, 0.5)

      -- must preserve the prefix directory here
      assert(helpers.stop_kong(PREFIX, true))

      local last_seen
      do
        local node = assert(get_data_plane(node_id))
        last_seen = assert.is_number(node.last_seen)
      end

      -- must preserve the prefix directory here
      assert(helpers.start_kong(data_plane_config, nil, true))

      helpers.wait_until(function()
        local node = get_data_plane(node_id)
        return node and node.last_seen > last_seen
      end, 10, 0.5)

      local id_from_fs = assert(helpers.file.read(NODE_ID))
      assert.equals(node_id, id_from_fs)
    end)
  end)
end
