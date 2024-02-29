-- This test case file originates from the old version of the DNS client and has
-- been modified to adapt to the new version of the DNS client.

local utils = require("kong.tools.utils")
local _writefile = require("pl.utils").writefile
local tmpname = require("pl.path").tmpname
local cycle_aware_deep_copy = require("kong.tools.utils").cycle_aware_deep_copy

-- hosted in Route53 in the AWS sandbox
local TEST_NS = "198.51.100.0"

local TEST_NSS = { TEST_NS }

local gettime = ngx.now
local sleep = ngx.sleep

local function assert_same_answers(a1, a2)
  a1 = cycle_aware_deep_copy(a1)
  a1.ttl = nil
  a1.expire = nil

  a2 = cycle_aware_deep_copy(a2)
  a2.ttl = nil
  a2.expire = nil

  assert.same(a1, a2)
end

describe("[DNS client cache]", function()
  local resolver, client, query_func, old_udp, receive_func

  local resolv_path, hosts_path

  local function writefile(path, text)
    _writefile(path, type(text) == "table" and table.concat(text, "\n") or text)
  end

  local function client_new(opts)
    opts = opts or {}
    opts.resolv_conf = resolv_path
    opts.hosts = hosts_path
    opts.nameservers = opts.nameservers or TEST_NSS
    opts.cache_purge = true
    return client.new(opts)
  end

  lazy_setup(function()
    -- create temp resolv.conf and hosts
    resolv_path = tmpname()
    hosts_path = tmpname()
    ngx.log(ngx.DEBUG, "create temp resolv.conf:", resolv_path,
                       " hosts:", hosts_path)

    -- hook sock:receive to do timeout test
    old_udp = ngx.socket.udp

    _G.ngx.socket.udp = function (...)
      local sock = old_udp(...)

      local old_receive = sock.receive

      sock.receive = function (...)
        if receive_func then
          receive_func(...)
        end
        return old_receive(...)
      end

      return sock
    end

  end)

  lazy_teardown(function()
    if resolv_path then
      os.remove(resolv_path)
    end
    if hosts_path then
      os.remove(hosts_path)
    end

    _G.ngx.socket.udp = old_udp
  end)

  before_each(function()
    -- inject r.query
    package.loaded["resty.dns.resolver"] = nil
    resolver = require("resty.dns.resolver")

    -- replace this `query_func` upvalue to spy on resolver query calls.
    query_func = function(self, original_query_func, name, options)
      return original_query_func(self, name, options)
    end

    local old_new = resolver.new
    resolver.new = function(...)
      local r, err = old_new(...)
      if not r then
        return nil, err
      end
      local original_query_func = r.query
      r.query = function(self, ...)
        return query_func(self, original_query_func, ...)
      end
      return r
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

    receive_func = nil
  end)

  describe("shortnames caching", function()

    local cli, mock_records, config
    before_each(function()
      writefile(resolv_path, "search domain.com")
      config = {
        nameservers = { "198.51.100.0" },
        ndots = 1,
        search = { "domain.com" },
        hosts = {},
        order = { "LAST", "SRV", "A", "AAAA", "CNAME" },
        error_ttl = 0.5,
        stale_ttl = 0.5,
        enable_ipv6 = false,
      }
      cli = assert(client_new(config))

      query_func = function(self, original_query_func, qname, opts)
        return mock_records[qname..":"..opts.qtype] or { errcode = 3, errstr = "name error" }
      end
    end)

    it("are stored in cache without type", function()
      mock_records = {
        ["myhost1.domain.com:"..resolver.TYPE_A] = {{
          type = resolver.TYPE_A,
          address = "1.2.3.4",
          class = 1,
          name = "myhost1.domain.com",
          ttl = 30,
        }}
      }

      local answers = cli:resolve("myhost1")
      assert.equal(answers, cli.cache:get("short:myhost1:all"))
    end)

    it("are stored in cache with type", function()
      mock_records = {
        ["myhost2.domain.com:"..resolver.TYPE_A] = {{
          type = resolver.TYPE_A,
          address = "1.2.3.4",
          class = 1,
          name = "myhost2.domain.com",
          ttl = 30,
        }}
      }

      local answers = cli:resolve("myhost2", { qtype = resolver.TYPE_A })
      assert.equal(answers, cli.cache:get("short:myhost2:" .. resolver.TYPE_A))
    end)

    it("are resolved from cache without type", function()
      mock_records = {}
      cli.cache:set("short:myhost3:all", {ttl=30+4}, {{
          type = resolver.TYPE_A,
          address = "1.2.3.4",
          class = 1,
          name = "myhost3.domain.com",
          ttl = 30,
        },
        ttl = 30,
        expire = gettime() + 30,
      })

      local answers = cli:resolve("myhost3")
      assert.same(answers, cli.cache:get("short:myhost3:all"))
    end)

    it("are resolved from cache with type", function()
      mock_records = {}
      local cli = client_new()
      cli.cache:set("short:myhost4:" .. resolver.TYPE_A, {ttl=30+4}, {{
          type = resolver.TYPE_A,
          address = "1.2.3.4",
          class = 1,
          name = "myhost4.domain.com",
          ttl = 30,
        },
        ttl = 30,
        expire = gettime() + 30,
      })

      local answers = cli:resolve("myhost4", { qtype = resolver.TYPE_A })
      assert.equal(answers, cli.cache:get("short:myhost4:" .. resolver.TYPE_A))
    end)

    it("of dereferenced CNAME are stored in cache", function()
      mock_records = {
        ["myhost5.domain.com:"..resolver.TYPE_CNAME] = {{
          type = resolver.TYPE_CNAME,
          class = 1,
          name = "myhost5.domain.com",
          cname = "mytarget.domain.com",
          ttl = 30,
        }},
        ["mytarget.domain.com:"..resolver.TYPE_A] = {{
          type = resolver.TYPE_A,
          address = "1.2.3.4",
          class = 1,
          name = "mytarget.domain.com",
          ttl = 30,
        }}
      }
      local answers = cli:resolve("myhost5")
      assert_same_answers(mock_records["mytarget.domain.com:"..resolver.TYPE_A], answers) -- not the test, intermediate validation

      -- the type un-specificc query was the CNAME, so that should be in the
      -- shorname cache
      answers = cli.cache:get("short:myhost5:all")
      assert_same_answers(mock_records["myhost5.domain.com:"..resolver.TYPE_CNAME], answers)
    end)

    it("ttl in cache is honored for short name entries", function()
      -- in the short name case the same record is inserted again in the cache
      -- and the lru-ttl has to be calculated, make sure it is correct
      mock_records = {
        ["myhost6.domain.com:"..resolver.TYPE_A] = {{
          type = resolver.TYPE_A,
          address = "1.2.3.4",
          class = 1,
          name = "myhost6.domain.com",
          ttl = 0.1,
        }}
      }
      local mock_copy = utils.cycle_aware_deep_copy(mock_records)

      -- resolve and check whether we got the mocked record
      local answers = cli:resolve("myhost6")
      assert_same_answers(answers, mock_records["myhost6.domain.com:"..resolver.TYPE_A])

      -- replace our mocked list with the copy made (new table, so no equality)
      mock_records = mock_copy

      -- wait for expiring
      sleep(0.1 + config.stale_ttl / 2)

      -- fresh result, but it should not affect answers2
      mock_records["myhost6.domain.com:"..resolver.TYPE_A][1].tag = "new"

      -- resolve again, now getting same record, but stale, this will trigger
      -- background refresh query
      local answers2 = cli:resolve("myhost6")
      assert.falsy(answers2[1].tag)
      assert.is_true(answers2.expired)  -- stale; marked as expired
      answers2.expired = nil
      assert_same_answers(answers2, answers)
      answers2.expired = true

      -- wait for refresh to complete
      sleep(0.1)

      -- resolve and check whether we got the new record from the mock copy
      local answers3 = cli:resolve("myhost6")
      assert.equal(answers3[1].tag, "new")
      assert.falsy(answers3.expired)
      assert.not_equal(answers, answers3)  -- must be a different record now
      assert_same_answers(answers3, mock_records["myhost6.domain.com:"..resolver.TYPE_A])

      -- the 'answers3' resolve call above will also trigger a new background query
      -- (because the sleep of 0.1 equals the records ttl of 0.1)
      -- so let's yield to activate that background thread now. If not done so,
      -- the `after_each` will clear `query_func` and an error will appear on the
      -- next test after this one that will yield.
      sleep(0.1)
    end)

    it("errors are not stored", function()
      local rec = {
        errcode = 4,
        errstr = "server failure",
      }
      mock_records = {
        ["myhost7.domain.com:"..resolver.TYPE_A] = rec,
        ["myhost7:"..resolver.TYPE_A] = rec,
      }

      local answers, err = cli:resolve("myhost7", { qtype = resolver.TYPE_A })
      assert.is_nil(answers)
      assert.equal("dns server error: 4 server failure", err)
      assert.is_nil(cli.cache:get("short:myhost7:" .. resolver.TYPE_A))
    end)

    it("name errors are not stored", function()
      local rec = {
        errcode = 3,
        errstr = "name error",
      }
      mock_records = {
        ["myhost8.domain.com:"..resolver.TYPE_A] = rec,
        ["myhost8:"..resolver.TYPE_A] = rec,
      }

      local answers, err = cli:resolve("myhost8", { qtype = resolver.TYPE_A })
      assert.is_nil(answers)
      assert.equal("dns server error: 3 name error", err)
      assert.is_nil(cli.cache:get("short:myhost8:" .. resolver.TYPE_A))
    end)

  end)


  describe("fqdn caching", function()

    local cli, mock_records, config
    before_each(function()
      writefile(resolv_path, "search domain.com")
      config = {
        nameservers = { "198.51.100.0" },
        ndots = 1,
        search = { "domain.com" },
        hosts = {},
        resolvConf = {},
        order = { "LAST", "SRV", "A", "AAAA", "CNAME" },
        error_ttl = 0.5,
        stale_ttl = 0.5,
        enable_ipv6 = false,
      }
      cli = assert(client_new(config))

      query_func = function(self, original_query_func, qname, opts)
        return mock_records[qname..":"..opts.qtype] or { errcode = 3, errstr = "name error" }
      end
    end)

    it("errors do not replace stale records", function()
      local rec1 = {{
        type = resolver.TYPE_A,
        address = "1.2.3.4",
        class = 1,
        name = "myhost9.domain.com",
        ttl = 0.1,
      }}
      mock_records = {
        ["myhost9.domain.com:"..resolver.TYPE_A] = rec1,
      }

      local answers, err = cli:resolve("myhost9", { qtype = resolver.TYPE_A })
      assert.is_nil(err)
      -- check that the cache is properly populated
      assert_same_answers(rec1, answers)
      answers = cli.cache:get("myhost9.domain.com:" .. resolver.TYPE_A)
      assert_same_answers(rec1, answers)

      sleep(0.15) -- make sure we surpass the ttl of 0.1 of the record, so it is now stale.
      -- new mock records, such that we return server failures installed of records
      local rec2 = {
        errcode = 4,
        errstr = "server failure",
      }
      mock_records = {
        ["myhost9.domain.com:"..resolver.TYPE_A] = rec2,
        ["myhost9:"..resolver.TYPE_A] = rec2,
      }
      -- doing a resolve will trigger the background query now
      answers = cli:resolve("myhost9", { qtype = resolver.TYPE_A })
      assert.is_true(answers.expired)  -- we get the stale record, now marked as expired
      -- wait again for the background query to complete
      sleep(0.1)
      -- background resolve is now complete, check the cache, it should still have the
      -- stale record, and it should not have been replaced by the error
      --
      answers = cli.cache:get("myhost9.domain.com:" .. resolver.TYPE_A)
      assert.is_true(answers.expired)
      answers.expired = nil
      assert_same_answers(rec1, answers)
    end)

    it("name errors do replace stale records", function()
      local rec1 = {{
        type = resolver.TYPE_A,
        address = "1.2.3.4",
        class = 1,
        name = "myhost9.domain.com",
        ttl = 0.1,
      }}
      mock_records = {
        ["myhost9.domain.com:"..resolver.TYPE_A] = rec1,
      }

      local answers, err = cli:resolve("myhost9", { qtype = resolver.TYPE_A })
      assert.is_nil(err)
      -- check that the cache is properly populated
      assert_same_answers(rec1, answers)
      answers = cli.cache:get("myhost9.domain.com:" .. resolver.TYPE_A)
      assert_same_answers(rec1, answers)

      sleep(0.15) -- make sure we surpass the ttl of 0.1 of the record, so it is now stale.
      -- clear mock records, such that we return name errors instead of records
      local rec2 = {
        errcode = 3,
        errstr = "name error",
      }
      mock_records = {
        ["myhost9.domain.com:"..resolver.TYPE_A] = rec2,
        ["myhost9:"..resolver.TYPE_A] = rec2,
      }
      -- doing a resolve will trigger the background query now
      answers = cli:resolve("myhost9", { qtype = resolver.TYPE_A })
      assert.is_true(answers.expired)  -- we get the stale record, now marked as expired
      -- wait again for the background query to complete
      sleep(0.1)
      -- background resolve is now complete, check the cache, it should now have been
      -- replaced by `nil` value (the name error is saved into mlcache miss_shm)
      assert.equal(nil, cli.cache:get("myhost9.domain.com:" .. resolver.TYPE_A))
    end)

    it("empty records do not replace stale records", function()
      local rec1 = {{
        type = resolver.TYPE_A,
        address = "1.2.3.4",
        class = 1,
        name = "myhost9.domain.com",
        ttl = 0.1,
      }}
      mock_records = {
        ["myhost9.domain.com:"..resolver.TYPE_A] = rec1,
      }

      local answers = cli:resolve("myhost9", { qtype = resolver.TYPE_A })
      -- check that the cache is properly populated
      assert_same_answers(rec1, answers)
      assert_same_answers(rec1, cli.cache:get("myhost9.domain.com:" .. resolver.TYPE_A))

      sleep(0.15) -- stale
      -- clear mock records, such that we return name errors instead of records
      local rec2 = {}
      mock_records = {
        ["myhost9.domain.com:"..resolver.TYPE_A] = rec2,
        ["myhost9:"..resolver.TYPE_A] = rec2,
      }
      -- doing a resolve will trigger the background query now
      answers = cli:resolve("myhost9", { qtype = resolver.TYPE_A })
      assert.is_true(answers.expired)  -- we get the stale record, now marked as expired
      -- wait again for the background query to complete
      sleep(0.1)
      -- background resolve is now complete, check the cache, it should still have the
      -- stale record, and it should not have been replaced by the empty record
      answers = cli.cache:get("myhost9.domain.com:" .. resolver.TYPE_A)
      assert.is_true(answers.expired)  -- we get the stale record, now marked as expired
      answers.expired = nil
      assert_same_answers(rec1, answers)
    end)

    it("AS records do replace stale records", function()
      -- when the additional section provides recordds, they should be stored
      -- in the cache, as in some cases lookups of certain types (eg. CNAME) are
      -- blocked, and then we rely on the A record to get them in the AS
      -- (additional section), but then they must be stored obviously.
      local CNAME1 = {
        type = resolver.TYPE_CNAME,
        cname = "myotherhost.domain.com",
        class = 1,
        name = "myhost9.domain.com",
        ttl = 0.1,
      }
      local A2 = {
        type = resolver.TYPE_A,
        address = "1.2.3.4",
        class = 1,
        name = "myotherhost.domain.com",
        ttl = 60,
      }
      mock_records = setmetatable({
        ["myhost9.domain.com:"..resolver.TYPE_CNAME] = { utils.cycle_aware_deep_copy(CNAME1) },  -- copy to make it different
        ["myhost9.domain.com:"..resolver.TYPE_A] = { CNAME1, A2 },  -- not there, just a reference and target
        ["myotherhost.domain.com:"..resolver.TYPE_A] = { A2 },
      }, {
        -- do not do lookups, return empty on anything else
        __index = function(self, key)
          --print("looking for ",key)
          return {}
        end,
      })

      assert(cli:resolve("myhost9", { qtype = resolver.TYPE_CNAME }))
      ngx.sleep(0.2)  -- wait for it to become stale
      assert(cli:resolve("myhost9"), { return_random = true })

      local cached = cli.cache:get("myhost9.domain.com:" .. resolver.TYPE_CNAME)
      assert.same(nil, cached)
    end)

  end)

-- ==============================================
--    success type caching
-- ==============================================


  describe("success types", function()

    local cli
    local mock_records
    before_each(function()
      writefile(resolv_path, "search domain.com")
      local config = {
        ndots = 1,
        search = { "domain.com" },
        hosts = {},
        resolvConf = {},
        order = { "LAST", "SRV", "A", "AAAA", "CNAME" },
        error_ttl = 0.5,
        stale_ttl = 0.5,
        enable_ipv6 = false,
      }
      cli = assert(client_new(config))

      query_func = function(self, original_query_func, qname, opts)
        return mock_records[qname..":"..opts.qtype] or { errcode = 3, errstr = "name error" }
      end
    end)

    it("in add. section are not stored for non-listed types", function()
      mock_records = {
        ["demo.service.consul:" .. resolver.TYPE_SRV] = {
          {
            type = resolver.TYPE_SRV,
            class = 1,
            name = "demo.service.consul",
            target = "192.168.5.232.node.api_test.consul",
            priority = 1,
            weight = 1,
            port = 32776,
            ttl = 0,
          }, {
            type = resolver.TYPE_TXT,  -- Not in the `order` as configured !
            class = 1,
            name = "192.168.5.232.node.api_test.consul",
            txt = "consul-network-segment=",
            ttl = 0,
          },
        }
      }
      cli:resolve("demo.service.consul", { return_random = true })
      local success = cli.cache:get("192.168.5.232.node.api_test.consul")
      assert.not_equal(resolver.TYPE_TXT, success)
    end)

    it("in add. section are stored for listed types", function()
      mock_records = {
        ["demo.service.consul:" .. resolver.TYPE_SRV] = {
          {
            type = resolver.TYPE_SRV,
            class = 1,
            name = "demo.service.consul",
            target = "192.168.5.232.node.api_test.consul",
            priority = 1,
            weight = 1,
            port = 32776,
            ttl = 0,
          }, {
            type = resolver.TYPE_A,    -- In configured `order` !
            class = 1,
            name = "192.168.5.232.node.api_test.consul",
            address = "192.168.5.232",
            ttl = 0,
          }, {
            type = resolver.TYPE_TXT,  -- Not in the `order` as configured !
            class = 1,
            name = "192.168.5.232.node.api_test.consul",
            txt = "consul-network-segment=",
            ttl = 0,
          },
        }
      }
      local _, err, tries = cli:resolve("demo.service.consul", { return_random = true })
      assert.same(err, "dns server error: 3 name error")
      assert.same({
        {
          "192.168.5.232.node.api_test.consul:SRV",
          "dns server error: 3 name error",
        },
        {
          "192.168.5.232.node.api_test.consul:A",
          "dns server error: 3 name error",
        },
        {
          "192.168.5.232.node.api_test.consul:AAAA",
          "dns server error: 3 name error",
        },
        {
          "192.168.5.232.node.api_test.consul:CNAME",
          "dns server error: 3 name error",
        }
      }, tries)
    end)

    it("are not overwritten by add. section info", function()
      mock_records = {
        ["demo.service.consul:" .. resolver.TYPE_SRV] = {
          {
            type = resolver.TYPE_SRV,
            class = 1,
            name = "demo.service.consul",
            target = "192.168.5.232.node.api_test.consul",
            priority = 1,
            weight = 1,
            port = 32776,
            ttl = 0,
          }, {
            type = resolver.TYPE_A,    -- In configured `order` !
            class = 1,
            name = "another.name.consul",
            address = "192.168.5.232",
            ttl = 0,
          },
        }
      }
      cli:insert_last_type("another.name.consul", resolver.TYPE_AAAA)
      cli:resolve("demo.service.consul", { return_random = true })
      local success = cli:get_last_type("another.name.consul")
      assert.equal(resolver.TYPE_AAAA, success)
    end)

  end)


  describe("hosts entries", function()
    -- hosts file names are cached for 10 years, verify that
    -- it is not overwritten with valid_ttl settings.
    -- Regressions reported in https://github.com/Kong/kong/issues/7444
    local cli, mock_records, config  -- luacheck: ignore
    writefile(resolv_path, "")
    writefile(hosts_path, "127.0.0.1 myname.lan")
    before_each(function()
      config = {
        nameservers = { "198.51.100.0" },
        --hosts = {"127.0.0.1 myname.lan"},
        --resolvConf = {},
        valid_ttl = 0.1,
        stale_ttl = 0,
      }

      cli = assert(client_new(config))
    end)

    it("entries from hosts file ignores valid_ttl overrides, Kong/kong #7444", function()
      ngx.sleep(0.2) -- must be > valid_ttl + stale_ttl

      local record = cli.cache:get("myname.lan:1")
      assert.equal("127.0.0.1", record[1].address)
    end)
  end)

end)
