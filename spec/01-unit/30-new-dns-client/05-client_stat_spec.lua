local helpers = require "spec.helpers"
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
    package.loaded["kong.resty.dns_client"] = nil
    client = require("kong.resty.dns_client")
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
    local cli, mock_records, config
    before_each(function()
      config = {
        order = { "LAST", "A", "CNAME" },
        error_ttl = 0.1,
        empty_ttl = 0.1,
        stale_ttl = 1,
      }
      cli = assert(client_new(config))

      query_func = function(self, qname, opts)
        local records = mock_records[qname..":"..opts.qtype]
        if type(records) == "string" then
          return nil, records -- as error message
        end
        return records or { errcode = 3, errstr = "name error" }
      end
    end)

    it("stats", function()
      mock_records = {
        ["hit.com:"..resolver.TYPE_A] = {{
          type = resolver.TYPE_A,
          address = "1.2.3.4",
          class = 1,
          name = "hit.com",
          ttl = 30,
        }},
        ["nameserver_fail.com:" .. resolver.TYPE_A] = "nameserver failed",
        ["recursion.com:" .. resolver.TYPE_CNAME] = {{
          type = resolver.TYPE_CNAME,
          cname = "recursion.com",
          class = 1,
          name = "recursion.com",
          ttl = 30,
        }},
        ["stale.com" .. resolver.TYPE_A] = {{
          type = resolver.TYPE_CNAME,
          address = "stale.com",
          class = 1,
          name = "stale.com",
          ttl = 0.1,
        }},
      }

      -- "hit_lru"
      cli:resolve("hit.com")
      cli:resolve("hit.com")
      -- "hit_shm"
      cli.cache.lru:delete("short:hit.com:all")
      cli:resolve("hit.com")

      -- "query_err:nameserver failed"
      cli:resolve("nameserver_fail.com")

      -- "fail_recur"
      cli:resolve("recursion.com")

      -- "stale"
      cli:resolve("stale.com")
      sleep(0.2)
      cli:resolve("stale.com")

      assert.same({
        ["hit.com"] = {
          ["hit_lru"] = 1,
          ["runs"] = 3,
          ["miss"] = 1,
          ["hit_shm"] = 1
        },
        ["hit.com:1"] = {
          ["query"] = 1,
          ["query_succ"] = 1
        },
        ["recursion.com"] = {
          ["fail_recur"] = 1,
          ["runs"] = 2,
          ["miss"] = 1,
          ["cname"] = 1
        },
        ["recursion.com:1"] = {
          ["query"] = 1,
          ["query_fail:name error"] = 1
        },
        ["recursion.com:5"] = {
          ["query"] = 1,
          ["query_succ"] = 1
        },
        ["nameserver_fail.com"] = {
          ["fail"] = 1,
          ["runs"] = 1
        },
        ["nameserver_fail.com:1"] = {
          ["query"] = 1,
          ["query_fail_nameserver"] = 1
        },
        ["stale.com"] = {
          ["fail"] = 2,
          ["runs"] = 2
        },
        ["stale.com:1"] = {
          ["query"] = 1,
          ["query_fail:name error"] = 1,
          ["stale"] = 1
        },
        ["stale.com:5"] = {
          ["query"] = 1,
          ["query_fail:name error"] = 1,
          ["stale"] = 1
        }
      }, cli.stats)
    end)
  end)
end)
