-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local election = require("kong.clustering.config_sync_backup.election")
local uuid = require("kong.tools.utils").uuid

describe("kong.clustering.config_sync_backup.election", function()
  local old_kong
  lazy_setup(function()
    if _G.kong then
      old_kong = _G.kong
    else
      _G.kong = {
        node = {
          get_id = function()
            return "test_node_id"
          end,
        },
      }
    end
  end)

  lazy_teardown(function()
    if old_kong then
      _G.kong = old_kong
    end
  end)

  describe("to_file_name and parse_file_name", function()
    local prefix = "s3://test_prefix/"
    local e

    lazy_setup(function()
      e = election:new()
    end)

    it("sanity", function()
      for _ = 1, 100 do
        e.register_time = os.time() + math.random(1000)/100
        e.node_id = uuid()

        local filename = e:to_file_name(prefix)
        local parsed = e.parse_node_information(prefix, filename)

        assert.same({
          node_id = e.node_id,
          register_time = e.register_time,
        }, parsed)
      end
    end)

    it("parses integer timestamps", function()
      e.register_time = 1704921469
      e.node_id = "30128332-39a4-4bc5-8435-9230693f4bec"
      local filename = e:to_file_name(prefix)
      local parsed = e.parse_node_information(prefix, filename)
      assert.same({
        node_id = e.node_id,
        register_time = e.register_time,
      }, parsed)
    end)

    it("parses float timestamps", function()
      e.register_time = 1704921469.1
      e.node_id = "30128332-39a4-4bc5-8435-9230693f4bec"
      local filename = e:to_file_name(prefix)
      local parsed = e.parse_node_information(prefix, filename)
      assert.same({
        node_id = e.node_id,
        register_time = e.register_time,
      }, parsed)
    end)
  end)

  it("is_fresh", function()
    local e = election.new({
      election_interval = 10
    })
    local now = os.time()
    e.register_time = now

    assert.is_true(e:is_fresh(now, now))
    assert.is_true(e:is_fresh(now, now + 9))
    assert.is_true(e:is_fresh(now, now + 10))
    assert.is_true(e:is_fresh(now, now + 13))
    assert.is_false(e:is_fresh(now, now + 16))
  end)
end)