local helpers = require "spec.helpers"
local pl_path = require "pl.path"
local pl_file = require "pl.file"


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


local auth_confgs = {
  ["auth off"] = "http://127.0.0.1:16797",
  ["auth on"] = "http://test:konghq@127.0.0.1:16796",
}


for _, strategy in helpers.each_strategy() do
  for auth_desc, proxy_url in pairs(auth_confgs) do
    describe("CP/DP sync through proxy (" .. auth_desc .. ") works with #" .. strategy .. " backend", function()
      lazy_setup(function()
        helpers.get_db_utils(strategy) -- runs migrations

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
          log_level = "debug",

          -- used to render the mock fixture
          nginx_conf = "spec/fixtures/custom_nginx.template",

          cluster_use_proxy = "on",
          proxy_server = proxy_url,

          -- this is unused, but required for the the template to include a stream {} block
          stream_listen = "0.0.0.0:5555",
        }, nil, nil, fixtures))

      end)

      lazy_teardown(function()
        helpers.stop_kong("servroot2")
        helpers.stop_kong()
      end)

      describe("sync works", function()
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
          assert.res_status(201, res)

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

          -- ensure this goes through proxy
          local path = pl_path.join("servroot2", "logs",
                      (auth_desc == "auth on") and "proxy_auth.log" or "proxy.log")
          local contents = pl_file.read(path)
          assert.matches("CONNECT 127.0.0.1:9005", contents)

          if auth_desc == "auth on" then
            assert.matches("accepted basic proxy%-authorization", contents)
          end
        end)
      end)
    end)

  end -- auth configs 
end
