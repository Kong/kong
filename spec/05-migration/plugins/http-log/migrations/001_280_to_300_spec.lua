
local cjson = require "cjson"
local tablex = require "pl.tablex"

local uh = require "spec/upgrade_helpers"

local HTTP_PORT = 29100

-- Copied from 3.x helpers.lua

local function http_server(port, opts)
  local threads = require "llthreads2.ex"
  opts = opts or {}
  local thread = threads.new(
    {
      function(port, opts)
        local socket = require "socket"
        local server = assert(socket.tcp())
        server:settimeout(opts.timeout or 60)
        assert(server:setoption('reuseaddr', true))
        assert(server:bind("*", port))
        assert(server:listen())
        local client = assert(server:accept())

        local lines = {}
        local line, err
        repeat
          line, err = client:receive("*l")
          if err then
            break
          else
            table.insert(lines, line)
          end
        until line == ""

        if #lines > 0 and lines[1] == "GET /delay HTTP/1.0" then
          ngx.sleep(2)
        end

        if err then
          server:close()
          error(err)
        end

        local body, _ = client:receive("*a")

        client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
        client:close()
        server:close()

        return lines, body
      end
    },
    port, opts)
  return thread:start()
end

describe("http-log plugin migration", function()

    lazy_setup(uh.start_kong)
    lazy_teardown(uh.stop_kong)

    local log_server_url = "http://localhost:" .. HTTP_PORT .. "/"

    local custom_header_name = "X-Test-Header"
    local custom_header_content = "this is it"

    uh.setup(function ()
        local admin_client = assert(uh.admin_client())
        local res = assert(admin_client:send {
            method = "POST",
            path = "/plugins/",
            body = {
              name = "http-log",
              config = {
                http_endpoint = log_server_url,
                headers = { [custom_header_name] = {custom_header_content} }
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
        })
        assert.res_status(201, res)
        admin_client:close()

        uh.create_example_service()
    end)

    uh.all_phases("expected log header is added", function ()
        local thread = http_server(HTTP_PORT, { timeout = 10 })

        uh.send_proxy_get_request()

        local ok, headers = thread:join()
        assert.truthy(ok)

        -- verify that the log HTTP request had the configured header
        local idx = tablex.find(headers, custom_header_name .. ": " .. custom_header_content)
        assert.not_nil(idx, headers)
    end)

    uh.new_after_finish("has updated http-log configuration", function ()
        local admin_client = assert(uh.admin_client())
        local res = assert(admin_client:send {
            method = "GET",
            path = "/plugins/"
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(1, #body.data)
        assert.equal(custom_header_content, body.data[1].config.headers[custom_header_name])
        admin_client:close()
    end)
end)
