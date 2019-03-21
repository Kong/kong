local helpers = require "spec.helpers"

-- mocked upstream host
local function http_server(timeout, count, port, ...)
  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(timeout, count, port)
      local socket = require "socket"
      local server = assert(socket.tcp())
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", port))
      assert(server:listen())

      local expire = socket.gettime() + timeout
      assert(server:settimeout(timeout))

      local success = 0
      while count > 0 do
        local client, err, _
        client, err = server:accept()
        if err == "timeout" then
          if socket.gettime() > expire then
            server:close()
            error("timeout")
          end
        elseif not client then
          server:close()
          error(err)
        else
          count = count - 1

          local err
          local line_count = 0
          while line_count < 7 do
            _, err = client:receive()
            if err then
              break
            else
              line_count = line_count + 1
            end
          end

          if err then
            client:close()
            server:close()
            error(err)
          end
          local response_json = '{"vars": {"request_uri": "/requests/path2"}}'
          local s = client:send(
            'HTTP/1.1 200 OK\r\n' ..
              'Connection: close\r\n' ..
              'Content-Length: '.. #response_json .. '\r\n' ..
              '\r\n' ..
              response_json
          )

          client:close()
          if s then
            success = success + 1
          end
        end
      end

      server:close()
      return success
    end
  }, timeout, count, port)

  local server = thread:start(...)
  ngx.sleep(0.2)
  return server
end

for _, strategy in helpers.each_strategy() do
  describe("Plugin: route-by-header (access) [#" .. strategy .. "]", function()
    local proxy_client, admin_client, target_foo, target_bar, plugin2

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local upstream_foo = bp.upstreams:insert({
        name = "foo.domain.com"
      })

      bp.targets:insert({
        upstream = { id = upstream_foo.id },
        target = "127.0.0.1:30001"
      })

      local upstream_bar = bp.upstreams:insert({
        name = "bar.domain.com"
      })

      bp.targets:insert({
        upstream = { id = upstream_bar.id },
        target = "127.0.0.1:30002"
      })

      local service1 = bp.services:insert {
        name = "foo_upstream",
      }

      local route1 = bp.routes:insert({
        hosts = { "routebyheader1.com" },
        preserve_host = false,
        service = service1
      })

      bp.plugins:insert {
        name     = "route-by-header",
        route    = { id = route1.id },
        config = {}
      }

      local service2 = bp.services:insert {
        name = "bar_upstream",
        host = "nowhere.example.com",
        protocol= "http"
      }

      local route2 = bp.routes:insert({
        protocols = { "http" },
        hosts = { "routebyheader2.com" },
        service   = service2,
      })

      plugin2 = bp.plugins:insert {
        name     = "route-by-header",
        route    = { id = route2.id },
        config = {
          rules= {
            {
              condition = {
                header1 =  "value1",
                header2 =  "value2",
              },
              upstream_name = "bar.domain.com",
            },
            {
              condition = {
                header3 = "value3"
              },
              upstream_name = "foo.domain.com",
            }
          }
        }
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = strategy,
        plugins = "bundled,route-by-header",
      }))

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong(nil, true)
    end)

    it("GET requests should route to default upstram server", function()
      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader1.com"
        }
      })
      assert.res_status(200, res)
    end)
    it("GET requests should route to nowhere in case of no match", function()
      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.com"
        }
      })
      assert.res_status(503, res)
    end)
    it("GET requests should route to bar server", function()
      target_bar = http_server(10, 1, 30002)

      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.com",
          header1 =  "value1",
          header2 =  "value2"
        }
      })
      assert.res_status(200, res)
      local _, success = target_bar:join()
      assert.is_equal(1, success)
    end)
    it("GET requests should route to foo server", function()
      target_foo = http_server(10, 1, 30001)

      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.com",
          header3 =  "value3",
        }
      })
      assert.res_status(200, res)
      local _, success = target_foo:join()
      assert.is_equal(1, success)
    end)
    it("GET requests should route to the matched, bar server", function()
      target_bar = http_server(10, 1, 30002)

      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.com",
          header1 =  "value1",
          header2 =  "value2",
          header3 =  "value3",
        }
      })
      assert.res_status(200, res)
      local _, success = target_bar:join()
      assert.is_equal(1, success)
    end)
    it("GET requests should route to the matched, foo server after PATCH", function()
      target_bar = http_server(10, 1, 30002)

      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.com",
          header1 =  "value1",
          header2 =  "value2",
          header3 =  "value3",
        }
      })
      assert.res_status(200, res)
      local _, success = target_bar:join()
      assert.is_equal(1, success)

      local res = assert(admin_client:send{
        method = "PATCH",
        path = "/plugins/" .. plugin2.id,
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          config = {
            rules= {
              {
                condition = {
                  header1 =  "value1",
                  header2 =  "value2",
                },
                upstream_name = "foo.domain.com",
              }
            }
          }
        }
      })
      assert.res_status(200, res)

      target_foo = http_server(10, 1, 30001)

      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.com",
          header1 =  "value1",
          header2 =  "value2"
        }
      })
      assert.res_status(200, res)
      local _, success = target_foo:join()
      assert.is_equal(1, success)

    end)
  end)
end
