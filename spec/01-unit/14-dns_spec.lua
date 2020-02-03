local mocker = require "spec.fixtures.mocker"
local balancer = require "kong.runloop.balancer"

local function setup_it_block()
  local cache_table = {}

  local function mock_cache(cache_table, limit)
    return {
      safe_set = function(self, k, v)
        if limit then
          local n = 0
          for _, _ in pairs(cache_table) do
            n = n + 1
          end
          if n >= limit then
            return nil, "no memory"
          end
        end
        cache_table[k] = v
        return true
      end,
      get = function(self, k, _, fn, arg)
        if cache_table[k] == nil then
          cache_table[k] = fn(arg)
        end
        return cache_table[k]
      end,
    }
  end

  mocker.setup(finally, {
    kong = {
      configuration = {
        worker_consistency = "strict",
      },
      core_cache = mock_cache(cache_table),
    }
  })
  balancer.init()
end

-- simple debug function
local function dump(...)
  print(require("pl.pretty").write({...}))
end


describe("DNS", function()
  local resolver, query_func, old_new
  local mock_records, singletons, client

  lazy_setup(function()
    stub(ngx, "log")
    singletons = require "kong.singletons"

    singletons.core_cache = {
      get = function() return {} end
    }

    --[[
    singletons.db = {}
    singletons.db.upstreams = {
      find_all = function(self) return {} end
    }
    --]]

    singletons.origins = {}

    resolver = require "resty.dns.resolver"
    client = require "resty.dns.client"
  end)

  lazy_teardown(function()
    if type(ngx.log) == "table" then
      ngx.log:revert() -- luacheck: ignore
    end
  end)

  before_each(function()
    mock_records = {}

    -- you can replace this `query_func` upvalue to spy on resolver query calls.
    -- This default will look for a mock-record and if not found call the
    -- original resolver
    query_func = function(self, original_query_func, name, options)
      if mock_records[name .. ":" .. options.qtype] then
        return mock_records[name .. ":" .. options.qtype]
      end

      print("now looking for: ", name .. ":" .. options.qtype)

      return original_query_func(self, name, options)
    end

    -- patch the resolver lib, such that any new resolver created will query
    -- using the `query_func` upvalue defined above
    old_new = resolver.new
    resolver.new = function(...)
      local r = old_new(...)
      local original_query_func = r.query

      r.query = function(self, ...)
        if not query_func then
          print(debug.traceback("WARNING: query_func is not set"))
          dump(self, ...)
          return
        end

        return query_func(self, original_query_func, ...)
      end

      return r
    end

    client.init {
      hosts = {},
      resolvConf = {},
      nameservers = { "8.8.8.8" },
      enable_ipv6 = true,
      order = { "LAST", "SRV", "A", "CNAME" },
    }
  end)

  after_each(function()
    resolver.new = old_new
  end)

  it("returns an error and 503 on a Name Error (3)", function()
    setup_it_block()
    mock_records = {
      ["konghq.com:" .. resolver.TYPE_A] = { errcode = 3, errstr = "name error" },
      ["konghq.com:" .. resolver.TYPE_AAAA] = { errcode = 3, errstr = "name error" },
      ["konghq.com:" .. resolver.TYPE_CNAME] = { errcode = 3, errstr = "name error" },
      ["konghq.com:" .. resolver.TYPE_SRV] = { errcode = 3, errstr = "name error" },
    }

    local ip, port, code = balancer.execute({
      type = "name",
      port = nil,
      host = "konghq.com",
      try_count = 0,
    })
    assert.is_nil(ip)
    assert.equals("name resolution failed", port)
    assert.equals(503, code)
  end)

  for _, consistency in ipairs({"strict", "eventual"}) do
    it("returns an error and 503 on an empty record", function()
      setup_it_block(consistency)
      mock_records = {
        ["konghq.com:" .. resolver.TYPE_A] = {},
        ["konghq.com:" .. resolver.TYPE_AAAA] = {},
        ["konghq.com:" .. resolver.TYPE_CNAME] = {},
        ["konghq.com:" .. resolver.TYPE_SRV] = {},
      }

      local ip, port, code = balancer.execute({
        type = "name",
        port = nil,
        host = "konghq.com",
        try_count = 0,
      })
      assert.is_nil(ip)
      assert.equals("name resolution failed", port)
      assert.equals(503, code)
    end)
  end
end)
