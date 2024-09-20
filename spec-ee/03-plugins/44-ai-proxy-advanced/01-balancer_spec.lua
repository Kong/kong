-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local state = require "kong.plugins.ai-proxy-advanced.balancer.state"
local llm_state = require "kong.llm.state"

describe("[round robin balancer]", function()
  local function new_balancer(targets)
    return require "kong.plugins.ai-proxy-advanced.balancer.round-robin".new(targets)
  end

  setup(function()
    _G.kong = {
      log = {
        debug = function() end,
      },
      ctx = {
        plugin = {},
      }
    }
  end)

  teardown(function()
    _G.kong = nil
  end)

  before_each(function()
    _G.kong.ctx.plugin = {}
  end)

  it("respect wights", function()
    local b = new_balancer {
      {name = "mashape.test", weight = 100, id = "1"},
      {name = "getkong.test", weight = 50, id = "2"},
    }
    -- run down the wheel twice
    local res = {}
    for _ = 1, 15*2 do
      local target = b:getPeer()
      res[target.name] = (res[target.name] or 0) + 1
    end
    assert.equal(20, res["mashape.test"])
    assert.equal(10, res["getkong.test"])
  end)

  it("respect tried state", function()
    local target_1 = {name = "mashape.test", weight = 100, id = "1"}
    local target_2 = {name = "getkong.test", weight = 50, id = "2"}
    local b = new_balancer {
      target_1,
      target_2,
    }
    state.set_tried_target(target_1)
    -- run down the wheel twice
    local res = {}
    for _ = 1, 15*2 do
      local target = b:getPeer()
      res[target.name] = (res[target.name] or 0) + 1
    end
    assert.equal(nil, res["mashape.test"])
    assert.equal(30, res["getkong.test"])

    state.set_tried_target(target_2)
    local target, err = b:getPeer()
    assert.is_nil(target)
    assert.matches("No peers are available", err)
  end)
end)


describe("[ewma based balancer]", function()
  local function new_balancer(targets)
    return require "kong.plugins.ai-proxy-advanced.balancer.ewma".new(targets)
  end

  setup(function()
    _G.kong = {
      log = {
        debug = function() end,
      },
      ctx = {
        plugin = {},
        shared = {},
      }
    }
  end)

  teardown(function()
    _G.kong = nil
  end)

  before_each(function()
    _G.kong.ctx.plugin = {}
    _G.kong.ctx.shared = {}
  end)

  it("select the target with smaller datapoint", function()
    local b = new_balancer {
      {name = "mashape.test", weight = 100, id = "1"},
      {name = "getkong.test", weight = 100, id = "2"},
      {name = "konghq.test",   weight = 100, id = "3"},
    }
    -- put some datapoints
    for _=1, 3 do
      b:afterBalance({ id = "1" }, 10)
      b:afterBalance({ id = "2" }, 1)
      b:afterBalance({ id = "3" }, 2)
      ngx.sleep(0.001)
      ngx.update_time()
    end

    local res = {}
    for _ = 1, 10 do
      local target = b:getPeer()
      res[target.name] = (res[target.name] or 0) + 1
    end
    assert.equal(nil, res["mashape.test"])
    assert.equal(10, res["getkong.test"])
    assert.equal(nil, res["konghq.test"])
  end)

  it("respect weight", function()
    local b = new_balancer {
      {name = "mashape.test", weight = 100, id = "1"},
      {name = "getkong.test", weight = 1, id = "2"},
      {name = "konghq.test",  weight = 100, id = "3"},
    }
    -- put some datapoints
    for _=1, 3 do
      b:afterBalance({ id = "1" }, 10)
      b:afterBalance({ id = "2" }, 1)
      b:afterBalance({ id = "3" }, 1000)
      ngx.sleep(0.001)
      ngx.update_time()
    end

    local res = {}
    for _ = 1, 10 do
      local target = b:getPeer()
      res[target.name] = (res[target.name] or 0) + 1
    end
    -- 10/ 100 < 1/1 < 1000/100, so we should select mashape.test now
    assert.equal(10, res["mashape.test"])
    assert.equal(nil, res["getkong.test"])
    assert.equal(nil, res["konghq.test"])
  end)

  it("use relatively newer datapoints", function()
    local b = new_balancer {
      {name = "mashape.test", weight = 100, id = "1"},
      {name = "getkong.test", weight = 100, id = "2"},
      {name = "konghq.test",  weight = 100, id = "3"},
    }
    -- put some datapoints
    for _=1, 3 do
      b:afterBalance({ id = "1" }, 10)
      b:afterBalance({ id = "2" }, 1)
      b:afterBalance({ id = "3" }, 1000)
      ngx.sleep(0.001)
      ngx.update_time()
    end
    ngx.sleep(0.1)
    ngx.update_time()
    -- flip it
    for _=1, 3 do
      b:afterBalance({ id = "1" }, 1)
      b:afterBalance({ id = "2" }, 10)
      b:afterBalance({ id = "3" }, 1)
      ngx.sleep(0.001)
      ngx.update_time()
    end

    local res = {}
    for _ = 1, 10 do
      local target = b:getPeer()
      res[target.name] = (res[target.name] or 0) + 1
    end
    assert.equal(10, res["mashape.test"])
    assert.equal(nil, res["getkong.test"])
    -- recent result is same as mashape.test, but previous result is smaller, so no picked
    assert.equal(nil, res["konghq.test"])
  end)

  it("respect tried state", function()
    local target_1 = {name = "mashape.test", weight = 100, id = "1"}
    local target_2 = {name = "getkong.test", weight = 1, id = "2"}
    local target_3 = {name = "konghq.test", weight = 100, id = "3"}
    local b = new_balancer {
      target_1,
      target_2,
      target_3,
    }
    -- put some datapoints
    for _=1, 3 do
      b:afterBalance({ id = "1" }, 10)
      b:afterBalance({ id = "2" }, 1)
      b:afterBalance({ id = "3" }, 1000)
      ngx.sleep(0.001)
      ngx.update_time()
    end

    state.set_tried_target(target_1)

    local res = {}
    for _ = 1, 10 do
      local target = b:getPeer()
      res[target.name] = (res[target.name] or 0) + 1
    end
    -- 1/1 < 1000/100, so we should select mashape.test now
    assert.equal(nil, res["mashape.test"])
    assert.equal(10, res["getkong.test"])
    assert.equal(nil, res["konghq.test"])

    state.set_tried_target(target_2)
    state.set_tried_target(target_3)

    local target, err = b:getPeer()
    assert.is_nil(target)
    assert.matches("No peers are available", err)
  end)

  for _, strategy in ipairs({"total-tokens", "prompt-tokens", "completion-tokens"}) do
    it("lowest-usage datapoints: " .. strategy, function()
      local b = require "kong.plugins.ai-proxy-advanced.balancer.lowest-usage".new {
        {name = "mashape.test", weight = 100, id = "1"},
        {name = "getkong.test", weight = 100, id = "2"},
        {name = "konghq.test",   weight = 100, id = "3"},
      }
      local conf = {
        balancer = {
          tokens_count_strategy = strategy,
        },
      }
      -- put some datapoints
      for _=1, 3 do
        llm_state.increase_prompt_tokens_count(10)
        llm_state.increase_response_tokens_count(10)
        b:afterBalance(conf, { id = "1" })
        kong.ctx.shared = {}

        llm_state.increase_prompt_tokens_count(1)
        llm_state.increase_response_tokens_count(1)
        b:afterBalance(conf, { id = "2" })
        kong.ctx.shared = {}

        llm_state.increase_prompt_tokens_count(2)
        llm_state.increase_response_tokens_count(2)
        b:afterBalance(conf, { id = "3" })
        kong.ctx.shared = {}

        ngx.sleep(0.001)
        ngx.update_time()
      end

      local res = {}
      for _ = 1, 10 do
        local target = b:getPeer()
        res[target.name] = (res[target.name] or 0) + 1
      end
      assert.equal(nil, res["mashape.test"])
      assert.equal(10, res["getkong.test"])
      assert.equal(nil, res["konghq.test"])
    end)
  end

  for _, strategy in ipairs({"tpot", "e2e"}) do
    it("lowest-latency datapoints", function()
      local b = require "kong.plugins.ai-proxy-advanced.balancer.lowest-latency".new {
        {name = "mashape.test", weight = 100, id = "1"},
        {name = "getkong.test", weight = 100, id = "2"},
        {name = "konghq.test",   weight = 100, id = "3"},
      }
      local conf = {
        balancer = {
          latency_strategy = strategy,
        },
      }
      -- put some datapoints
      for _=1, 3 do
        llm_state.set_metrics("tpot_latency", 10)
        llm_state.set_metrics("e2e_latency", 10)
        b:afterBalance(conf, { id = "1" })
        llm_state.set_metrics("tpot_latency", 1)
        llm_state.set_metrics("e2e_latency", 1)
        b:afterBalance(conf, { id = "2" })
        llm_state.set_metrics("tpot_latency", 2)
        llm_state.set_metrics("e2e_latency", 2)
        b:afterBalance(conf, { id = "3" })
        ngx.sleep(0.001)
        ngx.update_time()
      end

      local res = {}
      for _ = 1, 10 do
        local target = b:getPeer()
        res[target.name] = (res[target.name] or 0) + 1
      end
      assert.equal(nil, res["mashape.test"])
      assert.equal(10, res["getkong.test"])
      assert.equal(nil, res["konghq.test"])
    end)
  end

end)


describe("[consistent hashing balancer]", function()
  local function new_balancer(targets, conf)
    return require "kong.plugins.ai-proxy-advanced.balancer.consistent-hashing".new(targets, conf)
  end

  setup(function()
    _G.kong = {
      log = {
        debug = function() end,
      },
      ctx = {
        plugin = {},
      }
    }
  end)

  teardown(function()
    _G.kong = nil
  end)

  before_each(function()
    _G.kong.ctx.plugin = {}
  end)

  it("respect wights", function()
    math.randomseed(os.time())
    local b = new_balancer({
      {name = "mashape.test", weight = 10, id = "1"},
      {name = "some.test", weight = 5, id = "2"},
    }, { balancer = { slots = 1000 } })
    -- run down the wheel, hitting all indices once
    local res = {}
    for n = 1, 1500 do
      local target = b:getPeer(nil, nil, tostring(n))
      res[target.name] = (res[target.name] or 0) + 1
    end
    -- weight distribution may vary up to 15% (why?)
    assert.is_true(res["mashape.test"] > 850)
    assert.is_true(res["mashape.test"] < 1150)
    assert.is_true(res["some.test"] > 425)
    assert.is_true(res["some.test"] < 575)

    -- hit one index 15 times
    res = {}
    local hash = tostring(6)  -- just pick one
    for _ = 1, 15 do
      local target = b:getPeer(nil, nil, hash)
      res[target.name] = (res[target.name] or 0) + 1
    end
    assert(15 == res["mashape.test"] or nil == res["mashape.test"], "mismatch")
    assert(15 == res["some.test"] or nil == res["some.test"], "mismatch")
  end)

  it("evaluate the change in the continuum", function()
    local res1 = {}
    local res2 = {}
    local res3 = {}
    local targets = {
      {name = "10.0.0.1", weight = 100, id = "1"},
      {name = "10.0.0.2", weight = 100, id = "2"},
      {name = "10.0.0.3", weight = 100, id = "3"},
      {name = "10.0.0.4", weight = 100, id = "4"},
      {name = "10.0.0.5", weight = 100, id = "5"},
    }
    local b = new_balancer(targets, { balancer = { slots = 5000 } })
    for n = 1, 10000 do
      local target = b:getPeer(false, nil, n)
      res1[n] = target.id
    end

    table.insert(targets, {name = "10.0.0.6", weight = 100, id = "6"})
    b = new_balancer(targets, { balancer = { slots = 5000 } })
    for n = 1, 10000 do
      local target = b:getPeer(false, nil, n)
      res2[n] = target.id
    end

    local dif = 0
    for n = 1, 10000 do
      if res1[n] ~= res2[n] then
        dif = dif + 1
      end
    end

    -- increasing the number of addresses from 5 to 6 should change 49% of
    -- targets if we were using a simple distribution, like an array.
    -- anyway, we should be below than 20%.
    assert((dif/100) < 49, "it should be better than a simple distribution")
    assert((dif/100) < 20, "it is still to much change ")


    table.insert(targets, {name = "10.0.0.7", weight = 100, id = "7"})
    table.insert(targets, {name = "10.0.0.8", weight = 100, id = "8"})
    b = new_balancer(targets, { balancer = { slots = 5000 } })
    for n = 1, 10000 do
      local target = b:getPeer(false, nil, n)
      res3[n] = target.id
    end

    dif = 0
    local dif2 = 0
    for n = 1, 10000 do
      if res1[n] ~= res2[n] then
        dif = dif + 1
      end
      if res2[n] ~= res3[n] then
        dif2 = dif2 + 1
      end
    end
    -- increasing the number of addresses from 5 to 8 should change 83% of
    -- targets, and from 6 to 8, 76%, if we were using a simple distribution,
    -- like an array.
    -- either way, we should be below than 40% and 25%.
    assert((dif/100) < 83, "it should be better than a simple distribution")
    assert((dif/100) < 40, "it is still to much change ")
    assert((dif2/100) < 76, "it should be better than a simple distribution")
    assert((dif2/100) < 25, "it is still to much change ")
  end)


  it("respect tried state", function()
    local target_1 = {name = "mashape.test", weight = 100, id = "1"}
    local target_2 = {name = "getkong.test", weight = 50, id = "2"}
    local b = new_balancer({
      target_1,
      target_2,
    }, { balancer = { slots = 1000 } })
    -- mark node tried
    state.set_tried_target(target_1)
    -- do a few requests
    local res = {}
    for n = 1, 160 do
      local target = b:getPeer(nil, nil, n)
      res[target.name] = (res[target.name] or 0) + 1
    end
    assert.equal(nil, res["mashape.test"])
    assert.equal(160, res["getkong.test"])
  end)
end)

describe("[least connection balancer]", function()
  local function new_balancer(targets)
    return require "kong.plugins.ai-proxy-advanced.balancer.least-connections".new(targets)
  end

  setup(function()
    _G.kong = {
      log = {
        debug = function() end,
      },
      ctx = {
        plugin = {},
      }
    }
  end)

  teardown(function()
    _G.kong = nil
  end)

  before_each(function()
    _G.kong.ctx.plugin = {}
  end)

  it("respect wights", function()
    math.randomseed(os.time())
    local b = new_balancer({
      {name = "mashape.test", weight = 10, id = "1"},
      {name = "some.test", weight = 5, id = "2"},
    }, 1000)
    -- run down the wheel, hitting all indices once
    local res = {}
    for n = 1, 1500 do
      local target = b:getPeer()
      b:afterBalance(target)
      res[target.name] = (res[target.name] or 0) + 1
    end
    -- weight distribution may vary up to 15% (why?)
    assert.equal(1500, res["mashape.test"])
    assert.equal(nil, res["some.test"])
  end)

  it("respect tried state", function()
    local target_1 = {name = "mashape.test", weight = 100, id = "1"}
    local target_2 = {name = "getkong.test", weight = 100, id = "2"}
    local b = new_balancer({
      target_1,
      target_2,
    }, 1000)
    -- mark node tried
    local real_target_1
    for n = 1, 160 do
      local target = b:getPeer()
      if target.id == "1" then
        real_target_1 = target
      end
    end

    state.set_tried_target(real_target_1)
    -- do a few requests
    local res = {}
    for n = 1, 160 do
      local target = b:getPeer(nil, nil, n)
      res[target.name] = (res[target.name] or 0) + 1
    end
    assert.equal(nil, res["mashape.test"])
    assert.equal(160, res["getkong.test"])
  end)

  it("respect the least connection rule", function()
    local target_1 = {name = "getkong1.test", weight = 50, id = "1"}
    local target_2 = {name = "getkong2.test", weight = 50, id = "2"}
    local b = new_balancer({
      target_1,
      target_2,
    })
    -- do a few requests
    local res = {}

    local real_target_1

    -- normal case, mock target 1 to have less connections
    for n = 1, 160 do
      local target = b:getPeer()
      -- let target 1 have small number of connections
      if target.id == "1" then
        real_target_1 = target
        b:afterBalance(target)
      end
      res[target.name] = (res[target.name] or 0) + 1
    end

    -- most of time we should select target 1
    assert.is_true(res["getkong1.test"] - (res["getkong2.test"] or 0) >= 158)

    -- mark node tried
    res = {}
    state.set_tried_target(real_target_1)
    for n = 1, 160 do
      local target = b:getPeer()
      res[target.name] = (res[target.name] or 0) + 1
    end

    -- all the time we should select target 2
    assert.equal(nil, res["getkong1.test"])
    assert.equal(160, res["getkong2.test"])

    -- mock target 2 to have more connections
    state.clear_tried_targets()
    target_1 = {name = "getkong1.test", weight = 50, id = "1"}
    target_2 = {name = "getkong2.test", weight = 50, id = "2"}
    b = new_balancer({
      target_1,
      target_2,
    })
    res = {}
    for n = 1, 160 do
      local target = b:getPeer()
      if target.id == "2" then
        b:afterBalance(target)
      end
      res[target.name] = (res[target.name] or 0) + 1
    end

    -- -- most of time we should select target 1
    assert.is_true(res["getkong2.test"] - res["getkong1.test"] >= 158)
  end)

  describe("[#semantic based balancer]", function()
    local redis_mock = require("spec.helpers.ai.redis_mock")
    local openai_mock = require("spec.helpers.ai.openai_mock")

    local function new_balancer(targets, conf)
      return require "kong.plugins.ai-proxy-advanced.balancer.semantic".new(targets, conf)
    end

    setup(function()
      _G.ngx.get_phase = function() return "access" end

      _G.kong = {
        log = {
          debug = function() end,
          info = function() end,
          warn = function() end,
        },
        ctx = {
          plugin = {},
        },
        configuration = setmetatable({}, {
          __index = function(_, key)
            return nil
          end
        }),
        request = {
          get_body = function() return { messages = { { role = "user", content = "dog" }}} end
        },
        service = {
          request = {
            enable_buffering = function() return true end
          }
        }
      }
    end)

    teardown(function()
      _G.kong = nil
    end)

    before_each(function()
      _G.kong.ctx.plugin = {}
    end)

    it("select the target with closer similarity", function()
      redis_mock.setup(finally)
      openai_mock.setup(finally)

      local b = assert(new_balancer({
        {name = "cat.test", description = "cat", id = "1"},
        {name = "taco.test", description = "taco", id = "2"},
        {name = "capacitor.test",   description = "capacitor", id = "3"},
      }, {
        __plugin_id = "1123",
        vectordb = {
          dimensions = 4,
          distance_metric = "cosine",
          threshold = 0.4,
          redis = {},
          strategy = "redis",
        },
        embeddings = {
          model = {
            provider = "openai",
            name = "text-embedding-3-small",
          },
        },
      }))
      local res = {}
      for _ = 1, 10 do
        local target = b:getPeer()
        res[target.name] = (res[target.name] or 0) + 1
      end
      -- dog is more similar to cat instead of others
      assert.equal(10, res["cat.test"])
      assert.equal(nil, res["taco.test"])
      assert.equal(nil, res["capacitor.test"])
    end)
  end)
end)
