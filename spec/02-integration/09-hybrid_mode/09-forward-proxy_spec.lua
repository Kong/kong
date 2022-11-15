local helpers = require "spec.helpers"
local pl_path      = require "pl.path"
local pl_file      = require "pl.file"


local fixtures = {
  stream_mock = {
    forward_proxy = [[
    server {
      listen 16797;
      error_log logs/proxy.log debug;

      content_by_lua_block {
        require("spec.fixtures.forward-proxy-server").connect()
      }
    }

    server {
      listen 16796;
      error_log logs/proxy_auth.log debug;

      content_by_lua_block {
        require("spec.fixtures.forward-proxy-server").connect({
          basic_auth = ngx.encode_base64("test:konghq"),
        })
      }
    }

    ]],
  },
}


local confs = helpers.get_clustering_protocols()

local auth_confgs = {
  ["auth off"] = "http://127.0.0.1:16797",
  ["auth on"] = "http://test:konghq@127.0.0.1:16796",
}


for _, strategy in helpers.each_strategy() do
  for auth_desc, proxy_url in pairs(auth_confgs) do
  for cluster_protocol, conf in pairs(confs) do
    describe("CP/DP sync through proxy (" .. auth_desc .. ") works with #" .. strategy .. " backend, protocol " .. cluster_protocol, function()
      lazy_setup(function()
        helpers.get_db_utils(strategy) -- runs migrations

        assert(helpers.start_kong({
          role = "control_plane",
          --legacy_hybrid_protocol = (cluster_protocol == "json (by switch)"),
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          database = strategy,
          db_update_frequency = 0.1,
          cluster_listen = "127.0.0.1:9005",
          nginx_conf = conf,
        }))

        assert(helpers.start_kong({
          role = "data_plane",
          --legacy_hybrid_protocol = (cluster_protocol == "json (by switch)"),
          cluster_protocol = cluster_protocol,
          database = "off",
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          cluster_control_plane = "127.0.0.1:9005",
          proxy_listen = "0.0.0.0:9002",
          log_level = "debug",

          -- cluster_use_proxy = "on",
          proxy_server = proxy_url,

          -- this is unused, but required for the the template to include a stream {} block
          stream_listen = "0.0.0.0:5555",
        }, nil, nil, fixtures))

        for _, plugin in ipairs(helpers.get_plugins_list()) do
        end
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
          end, 10)

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
            res = proxy_client:get("/5")
            proxy_client:close()
            if res and res.status == 503 then
              return true
            end
          end, 5)

          for i = 4, 2, -1 do
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

          -- ensure this goes through proxy
          local path = pl_path.join("servroot2", "logs", "proxy.log")
          local contents = pl_file.read(path)
          assert.matches("CONNECT 127.0.0.1:9005", contents)
        end)
      end)
    end)

  end -- cluster protocols
  end -- auth configs 
end
