local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson.safe"
local pl_tablex = require "pl.tablex"
local _VERSION_TABLE = require "kong.meta" ._VERSION_TABLE
local MAJOR = _VERSION_TABLE.major
-- make minor version always larger-equal than 3 so test cases are happy
if _VERSION_TABLE.minor < 3 then
  _VERSION_TABLE.minor = 3
end
local MINOR = _VERSION_TABLE.minor
local PATCH = _VERSION_TABLE.patch
local CLUSTERING_SYNC_STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS


for _, strategy in helpers.each_strategy() do
  describe("CP/DP sync works with #" .. strategy .. " backend", function()

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "clustering_data_planes",
        "upstreams",
        "targets",
        "certificates",
      }) -- runs migrations

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("status API", function()
      it("shows DP status", function()
        helpers.wait_until(function()
          local admin_client = helpers.admin_client()
          finally(function()
            admin_client:close()
          end)

          local res = assert(admin_client:get("/clustering/data-planes"))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          for _, v in pairs(json.data) do
            if v.ip == "127.0.0.1" then
              assert.near(14 * 86400, v.ttl, 3)
              assert.matches("^(%d+%.%d+)%.%d+", v.version)
              assert.equal(CLUSTERING_SYNC_STATUS.NORMAL, v.sync_status)

              assert.is_not_nil(v.plugin_versions)

              local dp_dummy_plugin
              for _, plugin in ipairs(v.plugin_versions) do
                if plugin.name == "dummy" then
                  dp_dummy_plugin = plugin
                end
              end

              assert.same({
                name = "dummy",
                version = "9.9.9",
              }, dp_dummy_plugin)

              return true
            end
          end
        end, 5)
      end)

      it("shows DP status (#deprecated)", function()
        helpers.wait_until(function()
          local admin_client = helpers.admin_client()
          finally(function()
            admin_client:close()
          end)

          local res = assert(admin_client:get("/clustering/status"))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          for _, v in pairs(json) do
            if v.ip == "127.0.0.1" then
              return true
            end
          end
        end, 5)
      end)

      it("disallow updates on the status endpoint", function()
        helpers.wait_until(function()
          local admin_client = helpers.admin_client()
          finally(function()
            admin_client:close()
          end)

          local res = assert(admin_client:get("/clustering/data-planes"))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          local id
          for _, v in pairs(json.data) do
            if v.ip == "127.0.0.1" then
              id = v.id
            end
          end

          if not id then
            return nil
          end

          res = assert(admin_client:delete("/clustering/data-planes/" .. id))
          assert.res_status(404, res)
          res = assert(admin_client:patch("/clustering/data-planes/" .. id))
          assert.res_status(404, res)

          return true
        end, 5)
      end)

      it("disables the auto-generated collection endpoints", function()
        local admin_client = helpers.admin_client(10000)
        finally(function()
          admin_client:close()
        end)

        local res = assert(admin_client:get("/clustering_data_planes"))
        assert.res_status(404, res)
      end)
    end)

    describe("sync works", function()
      local route_id

      it("proxy on DP follows CP config", function()
        local admin_client = helpers.admin_client(10000)
        finally(function()
          admin_client:close()
        end)

        local res = assert(admin_client:post("/services", {
          body = { name = "mockbin-service", url = "https://127.0.0.1:15556/request", },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, res)

        res = assert(admin_client:post("/services/mockbin-service/routes", {
          body = { paths = { "/" }, },
          headers = {["Content-Type"] = "application/json"}
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        route_id = json.id

        helpers.wait_until(function()
          local proxy_client = helpers.http_client("127.0.0.1", 9002)

          res = proxy_client:send({
            method  = "GET",
            path    = "/",
          })

          local status = res and res.status
          proxy_client:close()
          if status == 200 then
            return true
          end
        end, 10)
      end)

      it("cache invalidation works on config change", function()
        local admin_client = helpers.admin_client()
        finally(function()
          admin_client:close()
        end)

        local res = assert(admin_client:send({
          method = "DELETE",
          path   = "/routes/" .. route_id,
        }))
        assert.res_status(204, res)

        helpers.wait_until(function()
          local proxy_client = helpers.http_client("127.0.0.1", 9002)

          res = proxy_client:send({
            method  = "GET",
            path    = "/",
          })

          -- should remove the route from DP
          local status = res and res.status
          proxy_client:close()
          if status == 404 then
            return true
          end
        end, 5)
      end)

      it("local cached config file has correct permission", function()
        local handle = io.popen("ls -l servroot2/config.cache.json.gz")
        local result = handle:read("*a")
        handle:close()

        assert.matches("-rw-------", result, nil, true)
      end)
    end)
  end)

  describe("CP/DP version check works with #" .. strategy, function()
    -- for these tests, we do not need a real DP, but rather use the fake DP
    -- client so we can mock various values (e.g. node_version)
    describe("relaxed compatibility check:", function()
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
          database = strategy,
          db_update_frequency = 3,
          cluster_listen = "127.0.0.1:9005",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          cluster_version_check = "major_minor",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      -- STARTS allowed cases
      local allowed_cases = {
        ["CP and DP version and plugins matches"] = {},
        ["CP and DP patch version mismatches"] = {
          dp_version = string.format("%d.%d.%d", MAJOR, MINOR, 4),
        },
        ["CP and DP suffix mismatches"] = {
          dp_version = tostring(_VERSION_TABLE) .. "-enterprise-version",
        },
        ["0 <= CP.minor - DP.minor <= 2"] = {
          dp_version = tostring(_VERSION_TABLE) ,
        },
      }

      local pl1 = pl_tablex.deepcopy(helpers.get_plugins_list())
      table.insert(pl1, 2, { name = "banana", version = "1.1.1" })
      table.insert(pl1, { name = "pineapple", version = "1.1.2" })
      allowed_cases["DP plugin set is a superset of CP"] = {
        plugins_list = pl1
      }

      local pl2 = pl_tablex.deepcopy(helpers.get_plugins_list())
      for i, p in ipairs(pl2) do
        local v = pl2[i].version
        local patch = v and v:match("%d+%.%d+%.(%d+)")
        -- find a plugin that has patch version mismatch
        -- we hardcode `dummy` plugin to be 9.9.9 so there must be at least one
        if patch and tonumber(patch) and tonumber(patch) > 2 then
          pl2[i].version = string.format("%d.%d.%d",
            tonumber(v:match("(%d+)")),
            tonumber(v:match("%d+%.(%d+)")),
            tonumber(patch - 2)
          )
          break
        end
      end
      allowed_cases["CP and DP plugin version matches to major.minor"] = {
        plugins_list = pl2
      }

      for desc, harness in pairs(allowed_cases) do
        it(desc .. ", sync is allowed", function()
          local uuid = utils.uuid()

          local res = assert(helpers.clustering_client({
            host = "127.0.0.1",
            port = 9005,
            cert = "spec/fixtures/kong_clustering.crt",
            cert_key = "spec/fixtures/kong_clustering.key",
            node_id = uuid,
            node_version = harness.dp_version,
            node_plugins_list = harness.plugins_list,
          }))

          assert.equals("reconfigure", res.type)
          assert.is_table(res.config_table)

          -- needs wait_until for C* convergence
          helpers.wait_until(function()
            local admin_client = helpers.admin_client()

            res = assert(admin_client:get("/clustering/data-planes"))
            local body = assert.res_status(200, res)

            admin_client:close()
            local json = cjson.decode(body)

            for _, v in pairs(json.data) do
              if v.id == uuid then
                assert.equal(harness.dp_version or tostring(_VERSION_TABLE),
                              v.version)
                assert.equal(CLUSTERING_SYNC_STATUS.NORMAL, v.sync_status)
                return true
              end
            end
          end, 5)
        end)
      end
      -- ENDS allowed cases

      -- STARTS blocked cases
      local blocked_cases = {
        ["CP and DP major version mismatches"] = {
          dp_version = "1.0.0",
          expected = CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE,
        },
        ["CP.minor - DP.minor > 2"] = {
          dp_version = string.format("%d.%d.%d", MAJOR, MINOR-3, PATCH),
          expected = CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE,
        },
        ["CP.minor - DP.minor < 0"] = {
          dp_version = string.format("%d.%d.%d", MAJOR, MINOR+1, PATCH),
          expected = CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE,
        },
      }

      local pl1 = pl_tablex.deepcopy(helpers.get_plugins_list())
      for i, p in ipairs(pl1) do
        local v = pl1[i].version
        local minor = v and v:match("%d+%.(%d+)")
        -- find a plugin that has minor larger than 1 :joy:
        -- we hardcode `dummy` plugin to be 9.9.9 so there must be at least one
        if minor and tonumber(minor) and tonumber(minor) > 1 then
          pl1[i].version = string.format("%d.%d.%d",
            tonumber(v:match("(%d+)")),
            tonumber(v:match("%d+%.(%d+)")) - 1,
            tonumber(v:match("%d+%.%d+%.(%d+)"))
          )
          break
        end
      end
      blocked_cases["CP and DP plugin minor version mismatch"] = {
        plugins_list = pl1,
        expected = CLUSTERING_SYNC_STATUS.PLUGIN_VERSION_INCOMPATIBLE,
      }

      local pl2 = pl_tablex.deepcopy(helpers.get_plugins_list())
      for i, p in ipairs(pl2) do
        local v = pl2[i].version
        local major = v and v:match("(%d+)")
        -- find a plugin that has major larger than 1 :joy:
        -- we hardcode `dummy` plugin to be 9.9.9 so there must be at least one
        if major and tonumber(major) and tonumber(major) > 1 then
          pl2[i].version = string.format("%d.%d.%d",
            tonumber(major - 1),
            tonumber(v:match("%d+%.(%d+)")),
            tonumber(v:match("%d+%.%d+%.(%d+)"))
          )
          break
        end
      end
      blocked_cases["CP and DP plugin major version mismatch"] = {
        plugins_list = pl2,
        expected = CLUSTERING_SYNC_STATUS.PLUGIN_VERSION_INCOMPATIBLE,
      }

      local pl3 = pl_tablex.deepcopy(helpers.get_plugins_list())
      table.remove(pl3, #pl3/2)
      blocked_cases["DP plugin set is subset of CP"] = {
        plugins_list = pl3,
        expected = CLUSTERING_SYNC_STATUS.PLUGIN_SET_INCOMPATIBLE,
      }

      local pl4 = pl_tablex.deepcopy(helpers.get_plugins_list())
      table.remove(pl4, 2)
      table.insert(pl4, 4, { name = "banana", version = "1.1.1" })
      table.insert(pl4, { name = "pineapple", version = "1.1.1" })
      blocked_cases["CP and DP plugin set mismatch"] = {
        plugins_list = pl4,
        expected = CLUSTERING_SYNC_STATUS.PLUGIN_SET_INCOMPATIBLE,
      }

      for desc, harness in pairs(blocked_cases) do
        it(desc ..", sync is blocked", function()
          local uuid = utils.uuid()

          local res = assert(helpers.clustering_client({
            host = "127.0.0.1",
            port = 9005,
            cert = "spec/fixtures/kong_clustering.crt",
            cert_key = "spec/fixtures/kong_clustering.key",
            node_id = uuid,
            node_version = harness.dp_version,
            node_plugins_list = harness.plugins_list,
          }))

          assert.equals("PONG", res)

          -- needs wait_until for c* convergence
          helpers.wait_until(function()
            local admin_client = helpers.admin_client()

            res = assert(admin_client:get("/clustering/data-planes"))
            local body = assert.res_status(200, res)

            admin_client:close()
            local json = cjson.decode(body)

            for _, v in pairs(json.data) do
              if v.id == uuid then
                assert.equal(harness.dp_version or tostring(_VERSION_TABLE),
                              v.version)
                assert.equal(harness.expected, v.sync_status)
                return true
              end
            end
          end, 5)
        end)
      end
      -- ENDS blocked cases
    end)
  end)

  describe("CP/DP sync works with #" .. strategy .. " backend", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }) -- runs migrations

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        db_update_frequency = 3,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("sync works", function()
      it("pushes first change asap and following changes in a batch", function()
        local admin_client = helpers.admin_client(10000)
        local proxy_client = helpers.http_client("127.0.0.1", 9002)
        finally(function()
          admin_client:close()
          proxy_client:close()
        end)

        local res = admin_client:put("/routes/1", {
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            paths = { "/1" },
          },
        })

        assert.res_status(200, res)

        helpers.wait_until(function()
          local proxy_client = helpers.http_client("127.0.0.1", 9002)
          -- serviceless route should return 503 instead of 404
          res = proxy_client:get("/1")
          proxy_client:close()
          if res and res.status == 503 then
            return true
          end
        end, 2)

        for i = 2, 5 do
          res = admin_client:put("/routes/" .. i, {
            headers = {
              ["Content-Type"] = "application/json",
            },
            body = {
              paths = { "/" .. i },
            },
          })

          assert.res_status(200, res)
        end

        helpers.wait_until(function()
          local proxy_client = helpers.http_client("127.0.0.1", 9002)
          -- serviceless route should return 503 instead of 404
          res = proxy_client:get("/2")
          proxy_client:close()
          if res and res.status == 503 then
            return true
          end
        end, 5)

        for i = 5, 3, -1 do
          res = proxy_client:get("/" .. i)
          assert.res_status(503, res)
        end

        for i = 1, 5 do
          local res = admin_client:delete("/routes/" .. i)
          assert.res_status(204, res)
        end

        helpers.wait_until(function()
          local proxy_client = helpers.http_client("127.0.0.1", 9002)
          -- deleted route should return 404
          res = proxy_client:get("/1")
          proxy_client:close()
          if res and res.status == 404 then
            return true
          end
        end, 5)

        for i = 5, 2, -1 do
          res = proxy_client:get("/" .. i)
          assert.res_status(404, res)
        end
      end)
    end)
  end)
end
