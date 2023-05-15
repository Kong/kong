local kong_global = require "kong.global"
local PAYLOAD_TOO_BIG_ERR = "payload too big"
local DEFAULT_TRUNCATED_PAYLOAD = ", truncated payload: not a serialized object"

describe("worker_events payload too big", function()
  local DATA_SIZE = 70000
  local worker_events
  -- exceeds the limit on the size of the payload
  local payload_received
  local SOURCE, EVENT = "foo", "bar"

  local function generate_data()
    local data = ""
    for _ = 1, DATA_SIZE do
      data = data .. "X"
    end
    return data
  end

  lazy_setup(function()
    worker_events = kong_global.init_worker_events()
    assert(worker_events)

    -- subscribe
    assert(worker_events.register( function(data)
      -- we look forward to receiving the payload even if 
      -- the size of the payload exceeds the limit
      payload_received = data
    end), SOURCE, EVENT)
  end)

  it("when type(payload) == 'string' ", function()
    local PAYLOAD = generate_data()
    worker_events.post(SOURCE, EVENT, PAYLOAD)
    ngx.sleep(0.001)
    --truncated payload
    assert.truthy(#payload_received > 60000)
  end)

  it("when type(payload) == 'table' ", function()
    local PAYLOAD = {
      ['data'] = generate_data()
    }

    worker_events.post(SOURCE, EVENT, PAYLOAD)
    ngx.sleep(0.001)
    --truncated payload
    assert.truthy(payload_received == PAYLOAD_TOO_BIG_ERR .. DEFAULT_TRUNCATED_PAYLOAD)
  end)
end)
