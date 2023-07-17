local helpers = require "spec.helpers"

local worker_events_mock = [[
  server {
    server_name example.com;
    listen %d;

    location = /payload_string {
      content_by_lua_block {
        local SOURCE, EVENT    = "foo", "string"
        local worker_events    = kong.worker_events
        local payload_received

        local function wait_until(validator, timeout)
          local deadline = ngx.now() + (timeout or 5)
          local res
          repeat
            worker_events.poll()
            res = validator()
          until res or ngx.now() >= deadline
          return res
        end

        -- subscribe
        local ok, err = worker_events.register(function(data)
          payload_received = data
        end, SOURCE, EVENT)

        -- when payload is a string
        local PAYLOAD = string.rep("X", %d)
        local ok, err = worker_events.post(SOURCE, EVENT, PAYLOAD)
        if not ok then
          ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
          ngx.say("post string failed, err: " .. err)
          ngx.exit(ngx.OK)
        end

        assert(wait_until(function()
          return PAYLOAD == payload_received
        end, 1))

        ngx.status = ngx.HTTP_OK
        ngx.say("ok")
        ngx.exit(200)
      }
    }

    location = /payload_table {
      content_by_lua_block {
        local SOURCE, EVENT    = "foo", "table"
        local worker_events    = kong.worker_events
        local deepcompare      = require("pl.tablex").deepcompare
        local payload_received

        local function wait_until(validator, timeout)
          local deadline = ngx.now() + (timeout or 5)
          local res
          repeat
            worker_events.poll()
            res = validator()
          until res or ngx.now() >= deadline
          return res
        end

        -- subscribe
        local ok, err = worker_events.register(function(data)
          payload_received = data
        end, SOURCE, EVENT)

        -- when payload is a table
        local PAYLOAD = {
          foo = 'bar',
          data = string.rep("X", %d)
        }

        local ok, err = worker_events.post(SOURCE, EVENT, PAYLOAD)
        if not ok then
          ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
          ngx.say("post table failed, err: " .. err)
          ngx.exit(ngx.OK)
        end

        assert(wait_until(function()
          return deepcompare(PAYLOAD, payload_received)
        end, 1))

        ngx.status = ngx.HTTP_OK
        ngx.say("ok")
        ngx.exit(200)
      }
    }
  }
]]


local strategy = "off"
local test_cases = {"string", "table", }
local payload_size = 70 * 1024
local max_payloads = { 60 * 1024, 140 * 1024 }
local business_port = 34567


for _, max_payload in ipairs(max_payloads) do
  local fixtures = {
    http_mock = {},
  }

  local size_allowed = max_payload > payload_size
  local less_or_greater = size_allowed and ">" or "<"

  describe("worker_events [when max_payload " .. less_or_greater .. " payload_size] ", function()

    lazy_setup(function()
      fixtures.http_mock.worker_events = string.format(
        worker_events_mock, business_port, payload_size, payload_size)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        worker_events_max_payload = max_payload,
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function ()
      assert(helpers.stop_kong())
    end)

    for _, payload_type in ipairs(test_cases) do
      it("max_payload = " .. max_payload .. ", type = " .. payload_type, function()

        local res = helpers.proxy_client(nil, business_port):get(
          "/payload_" .. payload_type, {
          headers = {
            host = "example.com",
          }
        })

        local status_code = 200
        local msg = "ok"

        if not size_allowed then
          status_code = 500
          msg = "post " .. payload_type .." failed, err: " ..
                "failed to publish event: payload exceeds the limitation (".. max_payload .. ")"
        end

        local body = assert.res_status(status_code, res)
        assert.equal(body, msg)
      end)
    end
  end)
end
