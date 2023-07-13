local helpers = require "spec.helpers"

local strategy = "off"
local test_cases = {"string", "table", }
local payload_size = 70 * 1024
local max_payloads = { 60 * 1024, 140 * 1024 }
local business_port = 34567

local fixtures = {
  http_mock = {
    worker_events = [[
      server {
        server_name example.com;
        listen %d;

        location = /payload_string {
          content_by_lua_block {
            local SOURCE, EVENT       = "foo", "string"
            local worker_events       = kong.worker_events
            local cjson               = require "cjson.safe"
            local payload_received

            local function generate_data()
              return string.rep("X", %d)
            end

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
            local PAYLOAD = generate_data()
            local ok, err = worker_events.post(SOURCE, EVENT, PAYLOAD)
            if not ok then
              ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
              ngx.say("post string failed, err: " .. cjson.encode(err))
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
            local SOURCE, EVENT             = "foo", "table"
            local worker_events             = kong.worker_events
            local cjson                     = require "cjson.safe"
            local deepcompare               = require("pl.tablex").deepcompare
            local payload_received

            local function generate_data()
              return string.rep("X", %d)
            end

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
            PAYLOAD = {
              foo = 'bar',
              data = generate_data()
            }
            local ok, err = worker_events.post(SOURCE, EVENT, PAYLOAD)
            if not ok then
              ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
              ngx.say("post table failed, err: " .. cjson.encode(err))
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
    ]],
  }
}

for _, max_payload in ipairs(max_payloads) do
  local allowed_size = max_payload > payload_size
  local less_or_greater = allowed_size and ">" or "<"

  describe("worker_events [when max_payload " .. less_or_greater .. " payload_size] ", function()
    lazy_setup(function()
      fixtures.http_mock.worker_events = string.format(
        fixtures.http_mock.worker_events, business_port, payload_size, payload_size)

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
      it("max_payload = " .. max_payload .. ", type = " .. payload_type,
      function()
        local res = helpers.proxy_client(nil, business_port):get(
          "/payload_" .. payload_type, {
          headers = {
            host = "example.com",
          }
        })
        local status_code = allowed_size and 200 or 500
        local msg = allowed_size and "ok" or "post " .. payload_type .. 
          " failed, err: \"failed to publish event: payload exceeds the limitation (".. max_payload .. ")\""
        local body = assert.res_status(status_code, res)
        assert.equal(body, msg)
      end)
    end
  end)
end
