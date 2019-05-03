local cache_warmup = require("kong.cache_warmup")


local function mock_entity(db_data, entity_name, cache_key)
  return {
    schema = {
      name = entity_name,
    },
    each = function()
      local i = 0
      return function()
        i = i + 1
        return db_data[entity_name][i]
      end
    end,
    cache_key = function(self, value)
      return tostring(value[cache_key])
    end
  }
end


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


local function mock_log(logged_warnings, logged_notices)
  return {
    warn = function(...)
      table.insert(logged_warnings, table.concat({...}))
    end,
    notice = function(...)
      table.insert(logged_notices, table.concat({...}))
    end,
  }
end


describe("cache_warmup", function()

  it("caches entities", function()
    local cache_table = {}
    local db_data = {
      ["my_entity"] = {
        { aaa = 111, bbb = 222 },
        { aaa = 333, bbb = 444 },
      },
      ["another_entity"] = {
        { xxx = 555, yyy = 666 },
        { xxx = 777, yyy = 888 },
      }
    }

    local kong = {
      db = {
        my_entity = mock_entity(db_data, "my_entity", "aaa"),
        another_entity = mock_entity(db_data, "another_entity", "xxx"),
      },
      cache = mock_cache(cache_table),
    }

    cache_warmup._mock_kong(kong)

    assert.truthy(cache_warmup.execute({"my_entity", "another_entity"}))

    assert.same(kong.cache:get("111").bbb, 222)
    assert.same(kong.cache:get("333").bbb, 444)
    assert.same(kong.cache:get("555").yyy, 666)
    assert.same(kong.cache:get("777").yyy, 888)
  end)

  it("does not cache routes", function()
    local cache_table = {}
    local logged_notices = {}
    local db_data = {
      ["my_entity"] = {
        { aaa = 111, bbb = 222 },
        { aaa = 333, bbb = 444 },
      },
      ["routes"] = {
        { xxx = 555, yyy = 666 },
        { xxx = 777, yyy = 888 },
      }
    }

    local kong = {
      db = {
        my_entity = mock_entity(db_data, "my_entity", "aaa"),
        routes = mock_entity(db_data, "routes", "xxx"),
      },
      cache = mock_cache(cache_table),
      log = mock_log(nil, logged_notices),
    }

    cache_warmup._mock_kong(kong)

    assert.truthy(cache_warmup.execute({"my_entity", "routes"}))

    assert.match("the 'routes' entry is ignored", logged_notices[1], 1, true)

    assert.same(kong.cache:get("111").bbb, 222)
    assert.same(kong.cache:get("333").bbb, 444)
    assert.same(kong.cache:get("555", nil, function() return "nope" end), "nope")
    assert.same(kong.cache:get("777", nil, function() return "nope" end), "nope")
  end)

  it("warms up DNS when caching services", function()
    local cache_table = {}
    local db_data = {
      ["my_entity"] = {
        { aaa = 111, bbb = 222 },
        { aaa = 333, bbb = 444 },
      },
      ["services"] = {
        { name = "a", host = "example.com", },
        { name = "b", host = "1.2.3.4", }, -- should be skipped by DNS caching
        { name = "c", host = "example.test", },
      }
    }
    local dns_queries = {}

    local kong = {
      db = {
        my_entity = mock_entity(db_data, "my_entity", "aaa"),
        services = mock_entity(db_data, "services", "name"),
      },
      cache = mock_cache(cache_table),
      dns = {
        toip = function(query)
          table.insert(dns_queries, query)
        end,
      }
    }

    cache_warmup._mock_kong(kong)

    assert.truthy(cache_warmup.execute({"my_entity", "services"}))

    ngx.sleep(0) -- yield so that async DNS caching happens

    assert.same(kong.cache:get("111").bbb, 222)
    assert.same(kong.cache:get("333").bbb, 444)
    assert.same(kong.cache:get("a").host, "example.com")
    assert.same(kong.cache:get("b").host, "1.2.3.4")
    assert.same(kong.cache:get("c").host, "example.test")

    -- skipped IP entry
    assert.same({ "example.com", "example.test" }, dns_queries)
  end)

  it("logs a warning on bad entities", function()
    local logged_warnings = {}

    local kong = {
      db = {},
      cache = {},
      log = mock_log(logged_warnings),
    }

    cache_warmup._mock_kong(kong)

    assert.truthy(cache_warmup.execute({"invalid_entity"}))

    assert.match("invalid_entity is not a valid entity name", logged_warnings[1], 1, true)
  end)

  it("halts warmup and logs when cache is full", function()
    local logged_warnings = {}
    local cache_table = {}
    local db_data = {
      ["my_entity"] = {
        { aaa = 111, bbb = 222 },
        { aaa = 333, bbb = 444 },
      },
      ["another_entity"] = {
        { xxx = 555, yyy = 666 },
        { xxx = 777, yyy = 888 },
        { xxx = 999, yyy = 000 },
      }
    }

    local kong = {
      db = {
        my_entity = mock_entity(db_data, "my_entity", "aaa"),
        another_entity = mock_entity(db_data, "another_entity", "xxx"),
      },
      cache = mock_cache(cache_table, 3),
      log = mock_log(logged_warnings),
      configuration = {
        mem_cache_size = 12345,
      },
    }

    cache_warmup._mock_kong(kong)

    assert.truthy(cache_warmup.execute({"my_entity", "another_entity"}))

    assert.match("cache warmup has been stopped", logged_warnings[1], 1, true)

    assert.same(kong.cache:get("111").bbb, 222)
    assert.same(kong.cache:get("333").bbb, 444)
    assert.same(kong.cache:get("555").yyy, 666)
    assert.same(kong.cache:get("777", nil, function() return "nope" end), "nope")
    assert.same(kong.cache:get("999", nil, function() return "nope" end), "nope")
  end)

end)
