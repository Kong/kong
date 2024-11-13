local helpers = require "spec.helpers"

local is_valid_uuid = require("kong.tools.uuid").is_valid_uuid

local PREFIX = "servroot.dp"
local NODE_ID = PREFIX .. "/kong.id"
local ERRLOG = PREFIX .. "/logs/error.log"

local write_node_id = [[
  local id = assert(kong.node.get_id())
  local dest = kong.configuration.prefix .. "/"
               .. "kong.id."
               .. ngx.config.subsystem
  local fh = assert(io.open(dest, "w+"))
  assert(fh:write(id))
  fh:close()
]]


local function get_http_node_id()
  local client = helpers.proxy_client(nil, 9002)
  finally(function() client:close() end)
  helpers.wait_until(function()
    local res = client:get("/request", {
      headers = { host = "http.node-id.test" },
    })

    if res then
      res:read_body()
    end
    return res and res.status == 200
  end, 5, 0.5)

  helpers.wait_for_file("file", PREFIX .. "/kong.id.http")
  return helpers.file.read(PREFIX .. "/kong.id.http")
end


local function get_stream_node_id()
  helpers.wait_until(function()
    local sock = assert(ngx.socket.tcp())

    sock:settimeout(1000)

    if not sock:connect("127.0.0.1", 9003) then
      return
    end

    local msg = "HELLO\n"
    if not sock:send(msg) then
      sock:close()
      return
    end

    if not sock:receive(msg:len()) then
      sock:close()
      return
    end

    sock:close()
    return true
  end, 5, 0.5)

  helpers.wait_for_file("file", PREFIX .. "/kong.id.stream")
  return helpers.file.read(PREFIX .. "/kong.id.stream")
end

local function start_kong_debug(env)
  env = env or {}
  local prefix = env.prefix or helpers.test_conf.prefix

  local ok, err = helpers.prepare_prefix(prefix)
  if not ok then
    return nil, err
  end

  local nginx_conf = ""
  if env.nginx_conf then
    nginx_conf = " --nginx-conf " .. env.nginx_conf
  end

  return helpers.kong_exec("start --vv --conf " .. helpers.test_conf_path .. nginx_conf, env)
end


--- XXX FIXME: enable inc_sync = on
for _, inc_sync in ipairs { "off" } do
for _, strategy in helpers.each_strategy() do
  describe("node id persistence " .. " inc_sync=" .. inc_sync, function()

    local control_plane_config = {
      role = "control_plane",
      database = strategy,
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      cluster_listen = "127.0.0.1:9005",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      cluster_incremental_sync = inc_sync,
    }

    local data_plane_config = {
      log_level = "debug",
      role = "data_plane",
      prefix = PREFIX,
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      cluster_control_plane = "127.0.0.1:9005",
      proxy_listen = "0.0.0.0:9002",
      stream_listen = "0.0.0.0:9003",
      database = "off",
      untrusted_lua = "on",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      cluster_incremental_sync = inc_sync,
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

      return dps[1].id == id and dps[1]
    end

    lazy_setup(function()
      local bp
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "clustering_data_planes",
        "consumers",
      })

      bp.plugins:insert({
        name = "pre-function",
        config = {
          log = { write_node_id },
        },
        protocols = { "http", "tcp" },
      })

      bp.routes:insert({
        name = "http.node-id.test",
        protocols = { "http" },
        hosts = { "http.node-id.test" },
      })

      bp.routes:insert({
        name = "stream.node-id.test",
        protocols = { "tcp" },
        destinations = {
          { ip = "0.0.0.0/0", port = 9003 }
        },
        service = bp.services:insert({
          name = "stream.node-id.test",
          protocol = "tcp",
          port = helpers.mock_upstream_stream_port,
        })
      })


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

      helpers.prepare_prefix(PREFIX)

      -- sanity
      assert.falsy(helpers.path.exists(NODE_ID))

      db.clustering_data_planes:truncate()
    end)

    it("generates a new ID on first start and saves it to a file", function()
      local ok, _, stdout = start_kong_debug(data_plane_config)
      assert.truthy(ok)

      helpers.wait_for_file("file", NODE_ID)

      local node_id = assert(helpers.file.read(NODE_ID))

      assert.truthy(is_valid_uuid(node_id), "id " .. node_id .. " is invalid")

      -- sanity
      helpers.wait_until(function()
        return get_data_plane(node_id) ~= nil
      end, 10, 0.5)

      -- node id file was initialized by cmd, which is before OpenResty its initialization.
      -- hence, this line("restored node_id from the filesystem") will be outputted
      --assert.logfile(ERRLOG).has.no.line("restored node_id from the filesystem", true, 1)

      -- assert the cmd log
      assert.matches("persisting node_id (" .. node_id .. ") to", stdout, nil, true)

      assert.logfile(ERRLOG).has.no.line("failed to restore node_id from the filesystem:", true, 1)
    end)

    it("generates a new ID if the existing one is invalid", function()
      assert(helpers.file.write(NODE_ID, "INVALID"))

      -- must preserve the prefix directory here or our invalid file
      -- will be removed and replaced
      local ok, _, stdout = start_kong_debug(data_plane_config)
      assert.truthy(ok)

      local node_id

      helpers.wait_until(function()
        node_id = helpers.file.read(NODE_ID)
        return node_id and is_valid_uuid(node_id)
      end, 5)

      -- assert the cmd log
      assert.matches("file .* contains invalid uuid: INVALID", stdout, nil)
      assert.matches("persisting node_id (" .. node_id .. ") to", stdout, nil, true)

      assert.logfile(ERRLOG).has.line("restored node_id from the filesystem: " .. node_id, true, 5)
      assert.logfile(ERRLOG).has.no.line("failed to access file", true, 5)
      assert.logfile(ERRLOG).has.no.line("failed to delete file", true, 5)

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

      assert.logfile(ERRLOG).has.line("restored node_id from the filesystem: " .. node_id, true, 5)

      local id_from_fs = assert(helpers.file.read(NODE_ID))
      assert.equals(node_id, id_from_fs)
    end)

    it("uses generated node_id is used for both subsystems", function()
      helpers.start_kong(data_plane_config)

      local http_id = get_http_node_id()
      local stream_id = get_stream_node_id()
      assert.equals(http_id, stream_id, "http node_id does not match stream node_id")
    end)

    it("uses restored node_id is used for both subsystems", function()
      helpers.start_kong(data_plane_config)

      local node_id

      helpers.wait_until(function()
        node_id = helpers.file.read(NODE_ID)
        return node_id and is_valid_uuid(node_id)
      end, 5)

      helpers.stop_kong(PREFIX, true)

      helpers.start_kong(data_plane_config, nil, true)

      local http_id = get_http_node_id()
      local stream_id = get_stream_node_id()
      assert.equals(node_id, stream_id, "node_id does not match stream node_id")
      assert.equals(node_id, http_id, "node_id does not match http node_id")
    end)

  end)
end -- for _, strategy
end -- for inc_sync
