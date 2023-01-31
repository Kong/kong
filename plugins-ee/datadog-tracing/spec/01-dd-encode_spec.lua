-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

require "spec.helpers"
local utils = require "kong.tools.utils"
local encoder = require "kong.plugins.datadog-tracing.encoder"
local msgpack = require "MessagePack"
local bn = require "resty.openssl.bn"
local binstring = require("luassert.formatters.binarystring")

local fmt = string.format
local rand_bytes = utils.get_rand_bytes
local time_ns = utils.time_ns
local insert = table.insert
local tracer = kong.tracing.new("test")
local sub = string.sub

describe("Plugin: datadog tracing (encoder)", function()
  after_each(function ()
    ngx.ctx.KONG_SPANS = nil
  end)

  setup(function()
    assert:add_formatter(binstring)
  end)

  teardown(function()
    assert:remove_formatter(binstring)
  end)

  it("encode/decode dd span", function ()
    local N = 10000

    local test_spans = {
      -- default one
      {
        name = "full-span",
        trace_id = rand_bytes(16),
        span_id = rand_bytes(8),
        parent_id = rand_bytes(8),
        start_time_ns = time_ns(),
        end_time_ns = time_ns() + 1000,
        should_sample = true,
        attributes = {
          foo = "bar",
          test = true,
          version = 0.1,
        },
        events = {
          {
            name = "evt1",
            time_ns = time_ns(),
            attributes = {
              debug = true,
            }
          }
        },
      },
    }

    for i = 1, N do
      local span = tracer.start_span(tostring(i), {
        span_kind = i % 6,
        attributes = {
          str = fmt("tag-%s", i),
          int = i,
          bool = (i % 2 == 0 and true) or false,
          double = i / (N * 1000),
        },
      })

      span:set_status(i % 3)
      span:add_event(tostring(i), span.attributes)
      span:finish()

      insert(test_spans, table.clone(span))
      span:release()
    end

    for _, test_span in ipairs(test_spans) do
      local dd_span = encoder.transform_span(test_span)

      local calculated_values = {
        start = test_span.start_time_ns,
        duration = test_span.end_time_ns - test_span.start_time_ns,
      }

      for _, key in ipairs({"span_id", "parent_id", "trace_id", "start", "duration"}) do
        local msgpack_data = msgpack.pack(dd_span[key])
        local prefix = (key == "start" or key == "duration") and "\xD3" or "\xCF"
        assert.message("testing " .. key).same(9, #msgpack_data)
        assert.message("testing " .. key).same(prefix, msgpack_data:sub(1,1))
        if key == "start" or key == "duration" then -- is number
          local b = bn.new(calculated_values[key]):to_binary()
          b = ("\0"):rep(8 - #b) .. b -- padding
          assert.message("testing " .. key).same(b, msgpack_data:sub(2))
        elseif test_span[key] then -- is bytes
          -- TODO: parent_id is only propogated in the first span
          assert.message("testing " .. key).same(sub(test_span[key], -8), msgpack_data:sub(2))
        end
      end
    end
  end)

end)
