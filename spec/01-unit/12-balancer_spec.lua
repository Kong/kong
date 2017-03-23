describe("Balancer", function()
  local singletons, balancer
  local UPSTREAMS_FIXTURES
  local TARGETS_FIXTURES
  --local uuid = require("kong.tools.utils").uuid

  
  setup(function()
    balancer = require "kong.core.balancer"
    singletons = require "kong.singletons"
    singletons.dao = {}
    singletons.dao.upstreams = {
      find_all = function(self)
        return UPSTREAMS_FIXTURES
      end
    }

    UPSTREAMS_FIXTURES = {
      {id = "a", name = "mashape", slots = 10, orderlist = {1,2,3,4,5,6,7,8,9,10} },
      {id = "b", name = "kong",    slots = 10, orderlist = {10,9,8,7,6,5,4,3,2,1} },
      {id = "c", name = "gelato",  slots = 20, orderlist = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20} },
      {id = "d", name = "galileo", slots = 20, orderlist = {20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1} },
    }
    
    singletons.dao.targets = {
      find_all = function(self, match_on)
        local ret = {}
        for _, rec in ipairs(TARGETS_FIXTURES) do
          for key, val in pairs(match_on or {}) do
            if rec[key] ~= val then
              rec = nil
              break
            end
          end
          if rec then table.insert(ret, rec) end
        end
        return ret
      end
    }

    TARGETS_FIXTURES = {
      -- 1st upstream; a
      {
        id = "a1",
        created_at = "003",
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
      },
      {
        id = "a2",
        created_at = "002",
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
      },
      {
        id = "a3",
        created_at = "001",
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
      },
      {
        id = "a4",
        created_at = "002",  -- same timestamp as "a2"
        upstream_id = "a",
        target = "mashape.com:80",
        weight = 10,
      },
      -- 2nd upstream; b
      {
        id = "b1",
        created_at = "003",
        upstream_id = "b",
        target = "mashape.com:80",
        weight = 10,
      },
    }
  end)

  describe("load_upstreams_dict_into_memory()", function()
    local upstreams_dict
    setup(function()
      upstreams_dict = balancer._load_upstreams_dict_into_memory()
    end)

    it("retrieves all upstreams as a dictionary", function()
      assert.is.table(upstreams_dict)
      for _, u in ipairs(UPSTREAMS_FIXTURES) do
        assert.equal(upstreams_dict[u.name], u.id)
        upstreams_dict[u.name] = nil -- remove each match
      end
      assert.is_nil(next(upstreams_dict)) -- should be empty now
    end)
  end)

  describe("load_targets_into_memory()", function()
    local targets
    local upstream
    setup(function()
      upstream = "a"
      targets = balancer._load_targets_into_memory(upstream)
    end)

    it("retrieves all targets per upstream, ordered", function()
      assert.equal(4, #targets)
      assert(targets[1].id == "a3")
      assert(targets[2].id == "a2")
      assert(targets[3].id == "a4")
      assert(targets[4].id == "a1")
    end)
  end)
end)
