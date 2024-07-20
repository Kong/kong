local sleep = ngx.sleep

describe("[DNS client stats]", function()
  local resolver, client, query_func

  local function client_new(opts)
    opts = opts or {}
    opts.hosts = {}
    opts.nameservers = { "198.51.100.0" } -- placeholder, not used
    return client.new(opts)
  end

  before_each(function()
    -- inject r.query
    package.loaded["resty.dns.resolver"] = nil
    resolver = require("resty.dns.resolver")
    resolver.query = function(...)
      if not query_func then
        return nil
      end
      return query_func(...)
    end

    -- restore its API overlapped by the compatible layer
    package.loaded["kong.dns.client"] = nil
    client = require("kong.dns.client")
    client.resolve = client._resolve
  end)

  after_each(function()
    package.loaded["resty.dns.resolver"] = nil
    resolver = nil
    query_func = nil

    package.loaded["kong.resty.dns.client"] = nil
    client = nil
  end)

  describe("stats", function()
    local mock_records
    before_each(function()
      query_func = function(self, qname, opts)
        local records = mock_records[qname..":"..opts.qtype]
        if type(records) == "string" then
          return nil, records -- as error message
        end
        return records or { errcode = 3, errstr = "name error" }
      end
    end)

    it("resolve SRV", function()
      mock_records = {
        ["_ldaps._tcp.srv.test:" .. resolver.TYPE_SRV] = {{
          type = resolver.TYPE_SRV,
          target = "srv.test",
          port = 636,
          weight = 10,
          priority = 10,
          class = 1,
          name = "_ldaps._tcp.srv.test",
          ttl = 10,
        }},
        ["srv.test:" .. resolver.TYPE_A] = {{
          type = resolver.TYPE_A,
          address = "1.2.3.4",
          class = 1,
          name = "srv.test",
          ttl = 30,
        }},
      }

      local cli = assert(client_new())
      cli:resolve("_ldaps._tcp.srv.test")

      local query_last_time
      for k, v in pairs(cli.stats.stats) do
        if v.query_last_time then
          query_last_time = v.query_last_time
          v.query_last_time = nil
        end
      end
      assert.match("^%d+$", query_last_time)

      assert.same({
        ["_ldaps._tcp.srv.test:33"] = {
          ["query"] = 1,
          ["query_succ"] = 1,
          ["miss"] = 1,
          ["runs"] = 1,
        },
      }, cli.stats.stats)
    end)

    it("resolve all types", function()
      mock_records = {
        ["hit.test:" .. resolver.TYPE_A] = {{
          type = resolver.TYPE_A,
          address = "1.2.3.4",
          class = 1,
          name = "hit.test",
          ttl = 30,
        }},
        ["nameserver_fail.test:" .. resolver.TYPE_A] = "nameserver failed",
        ["stale.test:" .. resolver.TYPE_A] = {{
          type = resolver.TYPE_A,
          address = "1.2.3.4",
          class = 1,
          name = "stale.test",
          ttl = 0.1,
        }},
        ["empty_result_not_stale.test:" .. resolver.TYPE_A] = {{
          type = resolver.TYPE_CNAME, -- will be ignored compared to type A
          cname = "stale.test",
          class = 1,
          name = "empty_result_not_stale.test",
          ttl = 0.1,
        }},
      }

      local cli = assert(client_new({
        order = { "A" },
        error_ttl = 0.1,
        empty_ttl = 0.1,
        stale_ttl = 1,
      }))

      -- "hit_lru"
      cli:resolve("hit.test")
      cli:resolve("hit.test")
      -- "hit_shm"
      cli.cache.lru:delete("hit.test:all")
      cli:resolve("hit.test")

      -- "query_err:nameserver failed"
      cli:resolve("nameserver_fail.test")

      -- "stale"
      cli:resolve("stale.test")
      sleep(0.2)
      cli:resolve("stale.test")

      cli:resolve("empty_result_not_stale.test")
      sleep(0.2)
      cli:resolve("empty_result_not_stale.test")

      local query_last_time
      for k, v in pairs(cli.stats.stats) do
        if v.query_last_time then
          query_last_time = v.query_last_time
          v.query_last_time = nil
        end
      end
      assert.match("^%d+$", query_last_time)

      assert.same({
        ["hit.test:1"] = {
          ["query"] = 1,
          ["query_succ"] = 1,
        },
        ["hit.test:-1"] = {
          ["hit_lru"] = 2,
          ["miss"] = 1,
          ["runs"] = 3,
        },
        ["nameserver_fail.test:-1"] = {
          ["fail"] = 1,
          ["runs"] = 1,
        },
        ["nameserver_fail.test:1"] = {
          ["query"] = 1,
          ["query_fail_nameserver"] = 1,
        },
        ["stale.test:-1"] = {
          ["miss"] = 2,
          ["runs"] = 2,
          ["stale"] = 1,
        },
        ["stale.test:1"] = {
          ["query"] = 2,
          ["query_succ"] = 2,
        },
        ["empty_result_not_stale.test:-1"] = {
          ["miss"] = 2,
          ["runs"] = 2,
        },
        ["empty_result_not_stale.test:1"] = {
          ["query"] = 2,
          ["query_fail:empty record received"] = 2,
        },
        ["empty_result_not_stale.test:28"] = {
          ["query"] = 2,
          ["query_fail:name error"] = 2,
        },
      }, cli.stats.stats)
    end)
  end)
end)
