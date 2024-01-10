-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local const = require "spec-ee.fixtures.websocket.constants"

local fmt = string.format

local PORTS = const.ports

local function mock_upstream(root_path)
  if not root_path then
    local str = debug.getinfo(1, "S").source:sub(2)
    local path = str:match("(.*/)")
    if path:sub(1, 1) ~= "/" then -- relative path
      path = lfs.currentdir() .. "/" .. path
    end
    -- spec-ee/fixtures/../../
    root_path = path .. "../../"
  end

  return fmt([[
    lua_shared_dict kong_test_websocket_fixture 64m;

    server {
      listen %s;
      listen %s ssl;

      server_name ws_fixture;

      ssl_certificate        %s/spec/fixtures/mtls_certs/example.com.crt;
      ssl_certificate_key    %s/spec/fixtures/mtls_certs/example.com.key;

      ssl_client_certificate %s/spec/fixtures/mtls_certs/ca.crt;
      ssl_verify_client      optional;

      ssl_session_tickets    off;
      ssl_session_cache      off;
      keepalive_requests     0;

      lua_check_client_abort on;

      # we use sock:receiveany() in the WS session fixture in order to forward
      # bytes blindly, so a large buffer size helps with performance and test
      # reliability
      lua_socket_buffer_size 64k;

      lingering_close off;

      rewrite_by_lua_block {
        require("spec-ee.fixtures.websocket.upstream").rewrite()
      }

      location / {
        content_by_lua_block {
          require("spec-ee.fixtures.websocket.upstream").echo()
        }
      }

      location ~ "^/status/(?<code>\d{3})$" {
        content_by_lua_block {
          local mu   = require "spec.fixtures.mock_upstream"
          local code = tonumber(ngx.var.code)
          if not code then
            return ngx.exit(ngx.HTTP_NOT_FOUND)
          end
          ngx.status = code
          return mu.send_default_json_response({
            code = code,
          })
        }
      }

      location = /session/client {
        content_by_lua_block {
          require("spec-ee.fixtures.websocket.upstream").client()
        }
      }

      location = /session/listen {
        content_by_lua_block {
          require("spec-ee.fixtures.websocket.upstream").listen()
        }
      }

      location ~ ^/log/(?<log_id>.+)$ {
        content_by_lua_block {
          require("spec-ee.fixtures.websocket.upstream").get_log()
        }
      }
    }
  ]], PORTS.ws, PORTS.wss, root_path, root_path, root_path)
end


---@param wc ws.test.client|string
---@param timeout? integer
---@return kong.log.serialized.entry
local function get_session_log(wc, timeout)
  local id = wc
  if type(id) == "table" then
    id = assert(wc.id)
  end
  timeout = timeout or 5

  local httpc = require("resty.http").new()
  assert(httpc:connect({
    scheme = "http",
    host = "127.0.0.1",
    port = PORTS.ws,
  }))

  local res, err = httpc:request({
    method = "GET",
    path = "/log/" .. id,
    query = { timeout = timeout },
  })

  assert(res, err)
  assert(res.status == 200, "non-200 response: " .. (tostring(res.status)))

  return require("cjson").decode(res:read_body())
end


return {
  get_session_log = get_session_log,
  const = const,
  mock_upstream = mock_upstream,
}
