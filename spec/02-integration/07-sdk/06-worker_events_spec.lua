local helpers = require "spec.helpers"

local worker_events_mock = [[
  server {
    server_name example.com;
    listen %d;

    location = /payload {
      content_by_lua_block {
        local SOURCE = "foo"
        local EVENT  = ngx.var.http_payload_type

        local worker_events = kong.worker_events
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

        -- when payload is a table
        if EVENT == "table" then
          PAYLOAD = {
            foo = "bar",
            data = PAYLOAD,
          }
        end

        local ok, err = worker_events.post(SOURCE, EVENT, PAYLOAD)
        if not ok then
          ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
          ngx.say("post failed, err: " .. err)
          return
        end

        assert(wait_until(function()
          if EVENT == "string" then
            return PAYLOAD == payload_received
          else
            return require("pl.tablex").deepcompare(PAYLOAD, payload_received)
          end
        end, 1))

        ngx.status = ngx.HTTP_OK
        ngx.say("ok")
      }
    }
  }
]]


local max_payloads = { 60 * 1024, 140 * 1024, }


for _, max_payload in ipairs(max_payloads) do
  local business_port = 34567
  local payload_size = 70 * 1024

  local fixtures = {
    http_mock = {
      worker_events = string.format(worker_events_mock,
                                    business_port, payload_size)
    },
  }

  local size_allowed = max_payload > payload_size
  local less_or_greater = size_allowed and ">" or "<"

  describe("worker_events [when max_payload " .. less_or_greater .. " payload_size]", function()
    local strategy = "off"
    local test_cases = {"string", "table", }

    lazy_setup(function()
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
          "/payload", {
          headers = {
            host = "example.com",
            payload_type = payload_type,
          }
        })

        local status_code = 200
        local msg = "ok"

        if not size_allowed then
          status_code = 500
          msg = "post failed, err: " ..
                "failed to publish event: payload exceeds the limitation (".. max_payload .. ")"
        end

        local body = assert.res_status(status_code, res)
        assert.equal(body, msg)
      end)
    end
  end)
end
