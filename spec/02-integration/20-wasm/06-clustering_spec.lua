local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson.safe"
local STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS
local admin = require "spec.fixtures.admin_api"

local HEADER = "X-Proxy-Wasm"

local json = cjson.encode

local function get_node_id(prefix)
  local data = helpers.wait_for_file_contents(prefix .. "/kong.id")
  data = data:gsub("%s*(.-)%s*", "%1")
  assert(utils.is_valid_uuid(data), "invalid kong node ID found in " .. prefix)
  return data
end


local function expect_status(prefix, exp)
  local id = get_node_id(prefix)
  local msg = "waiting for clustering sync status to equal"
              .. " '" .. exp .. "' for data plane"

  assert
    .eventually(function()
      local cp_client = helpers.admin_client()

      local res = cp_client:get("/clustering/data-planes/")
      res:read_body()

      cp_client:close()

      local body = assert.response(res).has.jsonbody()

      if res.status ~= 200 then
        return nil, {
          msg = "bad http status",
          exp = 200,
          got = res.status,
        }
      end

      assert.is_table(body.data)
      local found
      for _, dp in ipairs(body.data) do
        if dp.id == id then
          found = dp
          break
        end
      end

      if not found then
        return nil, {
          msg = "dp with id " .. id .. " not found in response",
          res = body,
        }

      elseif found.sync_status ~= exp then
        return nil, {
          msg = "unexpected sync_status",
          exp = exp,
          got = found.sync_status,
          dp  = found,
        }
      end

      return true
    end)
    .is_truthy(msg)
end


describe("#wasm - hybrid mode", function()
  local cp_prefix = "cp"
  local cp_errlog = cp_prefix .. "/logs/error.log"

  local dp_prefix = "dp"

  lazy_setup(function()
    local _, db = helpers.get_db_utils("postgres", {
      "services",
      "routes",
      "filter_chains",
      "clustering_data_planes",
    })

    db.clustering_data_planes:truncate()

    assert(helpers.start_kong({
      role                = "control_plane",
      database            = "postgres",
      prefix              = cp_prefix,
      cluster_cert        = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key    = "spec/fixtures/kong_clustering.key",
      db_update_frequency = 0.1,
      cluster_listen      = "127.0.0.1:9005",
      nginx_conf          = "spec/fixtures/custom_nginx.template",
      wasm                = true,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong(cp_prefix, true)
  end)

  describe("[happy path]", function()
    local client

    lazy_setup(function()
      assert(helpers.start_kong({
        role                  = "data_plane",
        database              = "off",
        prefix                = dp_prefix,
        cluster_cert          = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key      = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        admin_listen          = "off",
        nginx_conf            = "spec/fixtures/custom_nginx.template",
        wasm                  = true,
      }))

      client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if client then client:close() end
      helpers.stop_kong(dp_prefix)
    end)

    it("syncs wasm filter chains to the data plane", function()
      local service = admin.services:insert({})
      local host = "wasm-" .. utils.random_string() .. ".test"

      admin.routes:insert({
        service = service,
        hosts = { host },
      })

      local params = {
        headers = {
          host = host,
        }
      }

      assert
        .eventually(function()
          local res = client:get("/status/200", params)
          return res.status == 200, {
            exp = 200,
            got = res.status,
            res = res:read_body(),
          }
        end)
        .is_truthy("service/route are ready on the data plane")

      local value = utils.random_string()

      local filter = admin.filter_chains:insert({
        service = { id = service.id },
        filters = {
          {
            name = "response_transformer",
            config = json {
              append = {
                headers = {
                  HEADER .. ":" .. value,
                },
              },
            }
          }
        }
      })

      assert
        .eventually(function()
          local res = client:get("/status/200", params)
          res:read_body()

          if res.status ~= 200 then
            return {
              msg = "bad http status",
              exp = 200,
              got = res.status,
              res = res:read_body(),
            }
          end

          if res.headers[HEADER] ~= value then
            return nil, {
              msg = "missing/incorrect " .. HEADER .. " header",
              exp = value,
              got = res.headers[HEADER] or "<NIL>",
            }
          end

          return true
        end)
        .is_truthy("wasm filter is configured on the data plane")

      admin.filter_chains:remove({ id = filter.id })

      assert
        .eventually(function()
          local res = client:get("/status/200", params)
          res:read_body()

          if res.status ~= 200 then
            return {
              msg = "bad http status",
              exp = 200,
              got = res.status,
              res = res:read_body(),
            }
          end

          if res.headers[HEADER] ~= nil then
            return nil, {
              msg = "expected " .. HEADER .. " header to be absent",
              exp = "<NIL>",
              got = res.headers[HEADER],
            }
          end

          return true
        end)
        .is_truthy("wasm filter has been removed from the data plane")

      expect_status(dp_prefix, STATUS.NORMAL)
    end)
  end)

  describe("data planes with wasm disabled", function()
    lazy_setup(function()
      helpers.clean_logfile(cp_errlog)

      assert(helpers.start_kong({
        role                  = "data_plane",
        database              = "off",
        prefix                = dp_prefix,
        cluster_cert          = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key      = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        admin_listen          = "off",
        nginx_conf            = "spec/fixtures/custom_nginx.template",
        wasm                  = "off",
      }))
    end)


    lazy_teardown(function()
      helpers.stop_kong(dp_prefix, true)
    end)

    it("does not sync configuration", function()
      assert.logfile(cp_errlog).has.line(
        [[unable to send updated configuration to data plane: data plane is missing one or more wasm filters]],
        true, 5)

      expect_status(dp_prefix, STATUS.FILTER_SET_INCOMPATIBLE)
    end)
  end)
end)
