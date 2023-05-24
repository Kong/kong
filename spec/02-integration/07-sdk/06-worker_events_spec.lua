local helpers = require "spec.helpers"

describe("worker_events", function()
  local strategy = "off"
  local business_port

  lazy_setup(function()
    business_port = helpers.get_available_port()
    local fixtures = {
      http_mock = {
        worker_events = [[
          server {
            server_name example.com;
            listen %s;

            location = /test {
              content_by_lua_block {
                local PAYLOAD_TOO_BIG_ERR = "failed to publish event: payload too big"
                local DEFAULT_TRUNCATED_PAYLOAD = ", truncated payload: not a serialized object"
                local SOURCE, EVENT = "foo", "bar"
                local payload_received = ""
                local worker_events = kong.worker_events
                local cjson = require "cjson.safe"

                local function generate_data()
                  return string.rep("X", 70000)
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

                -- we look forward to receiving the payload even if 
                -- the size of the payload exceeds the limit

                -- when payload is a string
                local PAYLOAD = generate_data()
                local ok, err = worker_events.post(SOURCE, EVENT, PAYLOAD)
                if not ok then
                  ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
                  ngx.say("post string failed, err: " .. cjson.encode(err))
                  ngx.exit(ngx.OK)
                end

                assert(wait_until(function()
                  return #payload_received > 60000
                end, 1))

                -- when payload is a table
                PAYLOAD = {
                  ['data'] = generate_data()
                }
                local ok, err = worker_events.post(SOURCE, EVENT, PAYLOAD)
                if not ok then
                  ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
                  ngx.say("post table failed, err: " .. cjson.encode(err))
                  ngx.exit(ngx.OK)
                end

                assert(wait_until(function()
                  return payload_received == PAYLOAD_TOO_BIG_ERR .. DEFAULT_TRUNCATED_PAYLOAD
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

    fixtures.http_mock.worker_events = string.format(fixtures.http_mock.worker_events, business_port)

    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }, nil, nil, fixtures))
  end)

  lazy_teardown(function ()
    assert(helpers.stop_kong())
  end)

  it("payload too big", function()
    local res = helpers.proxy_client(nil, business_port):get("/test", {
      headers = {
        host = "example.com"
      }
    })
    assert.res_status(200, res)
  end)
end)
