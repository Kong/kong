-- This test case file originates from the old version of the DNS client and has
-- been modified to adapt to the new version of the DNS client.

local _writefile = require("pl.utils").writefile
local tmpname = require("pl.path").tmpname
local cycle_aware_deep_copy = require("kong.tools.utils").cycle_aware_deep_copy

-- hosted in Route53 in the AWS sandbox
local TEST_DOMAIN = "kong-gateway-testing.link"
local TEST_NS = "192.51.100.0"

local TEST_NSS = { TEST_NS }

local NOT_FOUND_ERROR = 'dns server error: 3 name error'

local function assert_same_answers(a1, a2)
  a1 = cycle_aware_deep_copy(a1)
  a1.ttl = nil
  a1.expire = nil

  a2 = cycle_aware_deep_copy(a2)
  a2.ttl = nil
  a2.expire = nil

  assert.same(a1, a2)
end

describe("[DNS client]", function()

  local resolver, client, query_func, old_udp, receive_func

  local resolv_path, hosts_path

  local function writefile(path, text)
    _writefile(path, type(text) == "table" and table.concat(text, "\n") or text)
  end

  local function client_new(opts)
    opts = opts or {}
    opts.resolv_conf = opts.resolv_conf or resolv_path
    opts.hosts = hosts_path
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

    local original_query_func = resolver.query
    query_func = function(self, original_query_func, name, options)
      return original_query_func(self, name, options)
    end
    resolver.query = function(self, ...)
      return query_func(self, original_query_func, ...)
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


  describe("initialization", function()

    it("succeeds if hosts/resolv.conf fails", function()
      local cli, err = client.new({
          nameservers = TEST_NSS,
          hosts = "non/existent/file",
          resolv_conf = "non/exitent/file",
      })
      assert.is.Nil(err)
      assert.same(cli.r_opts.nameservers, TEST_NSS)
    end)

    describe("inject localhost", function()

      it("if absent", function()
        writefile(resolv_path, "")
        writefile(hosts_path, "") -- empty hosts

        local cli = assert(client_new())
        local answers = cli.cache:get("localhost:28")
        assert.equal("[::1]", answers[1].address)

        answers = cli.cache:get("localhost:1")
        assert.equal("127.0.0.1", answers[1].address)

        answers = cli:resolve("localhost")
        assert.equal("127.0.0.1", answers[1].address)
      end)

      it("not if ipv4 exists", function()
        writefile(hosts_path, "1.2.3.4 localhost")
        local cli = assert(client_new())

        -- IPv6 is not defined
        local answers = cli.cache:get("localhost:28")
        assert.is_nil(answers)

        -- IPv4 is not overwritten
        answers = cli.cache:get("localhost:1")
        assert.equal("1.2.3.4", answers[1].address)
      end)

      it("not if ipv6 exists", function()
        writefile(hosts_path, "::1:2:3:4 localhost")
        local cli = assert(client_new())

        -- IPv6 is not overwritten
        local answers = cli.cache:get("localhost:28")
        assert.equal("[::1:2:3:4]", answers[1].address)

        -- IPv4 is not defined
        answers = cli.cache:get("localhost:1")
        assert.is_nil(answers)
      end)
    end)
  end)


  describe("iterating searches", function()
    local function hook_query_func_get_list()
      local list = {}
      query_func = function(self, original_query_func, name, options)
        table.insert(list, name .. ":" .. options.qtype)
        return {} -- empty answers
      end
      return list
    end

    describe("without type", function()
      it("works with a 'search' option", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "search one.com two.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new())
        local answers, err = cli:resolve("host")

        assert.same(answers, nil)
        assert.same(err, "dns client error: 101 empty record received")
        assert.same({
          'host.one.com:33',
          'host.two.com:33',
          'host:33',
          'host.one.com:1',
          'host.two.com:1',
          'host:1',
          'host.one.com:28',
          'host.two.com:28',
          'host:28',
          'host.one.com:5',
          'host.two.com:5',
          'host:5',
        }, list)
      end)

      it("works with a 'search .' option", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "search .",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new())
        local answers, err = cli:resolve("host")

        assert.same(answers, nil)
        assert.same(err, "dns client error: 101 empty record received")
        assert.same({
          'host:33',
          'host:1',
          'host:28',
          'host:5',
        }, list)
      end)

      it("works with a 'domain' option", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "domain local.domain.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new())
        local answers, err = cli:resolve("host")

        assert.same(answers, nil)
        assert.same(err, "dns client error: 101 empty record received")
        assert.same({
          'host.local.domain.com:33',
          'host:33',
          'host.local.domain.com:1',
          'host:1',
          'host.local.domain.com:28',
          'host:28',
          'host.local.domain.com:5',
          'host:5',
        }, list)
      end)

      it("handles last successful type", function()
        writefile(resolv_path, {
            "nameserver 198.51.100.0",
            "search one.com two.com",
            "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new())
        cli:insert_last_type("host", resolver.TYPE_CNAME)

        cli:resolve("host")

        assert.same({
          'host.one.com:5',
          'host.two.com:5',
          'host:5',
          'host.one.com:33',
          'host.two.com:33',
          'host:33',
          'host.one.com:1',
          'host.two.com:1',
          'host:1',
          'host.one.com:28',
          'host.two.com:28',
          'host:28',
        }, list)
      end)
    end)

    describe("FQDN without type", function()
      it("works with a 'search' option", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "search one.com two.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new())
        cli:resolve("host.")

        assert.same({
            'host.:33',
            'host.:1',
            'host.:28',
            'host.:5',
          }, list)
      end)

      it("works with a 'search .' option", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "search .",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new())
        cli:resolve("host.")

        assert.same({
            'host.:33',
            'host.:1',
            'host.:28',
            'host.:5',
          }, list)
      end)

      it("works with a 'domain' option", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "domain local.domain.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new())
        cli:resolve("host.")

        assert.same({
          'host.:33',
          'host.:1',
          'host.:28',
          'host.:5',
        }, list)
      end)

      it("handles last successful type", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "search one.com two.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new())
        cli:insert_last_type("host.", resolver.TYPE_CNAME)

        cli:resolve("host.")
        assert.same({
            'host.:5',
            'host.:33',
            'host.:1',
            'host.:28',
          }, list)
      end)

    end)

    describe("with type", function()
      it("works with a 'search' option", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "search one.com two.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new({ order = { "AAAA" } }))  -- IPv6 type
        cli:resolve("host")

        assert.same({
            'host.one.com:28',
            'host.two.com:28',
            'host:28',
          }, list)
      end)

      it("works with a 'domain' option", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "domain local.domain.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new({ order = { "AAAA" } }))  -- IPv6 type
        cli:resolve("host")

        assert.same({
          'host.local.domain.com:28',
          'host:28',
        }, list)
      end)

      it("ignores last successful type", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "search one.com two.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new({ order = { "AAAA" } }))  -- IPv6 type
        cli:insert_last_type("host", resolver.TYPE_CNAME)

        cli:resolve("host")
        assert.same({
            'host.one.com:28',
            'host.two.com:28',
            'host:28',
          }, list)
      end)

    end)

    describe("FQDN with type", function()
      it("works with a 'search' option", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "search one.com two.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new({ order = { "AAAA" } }))  -- IPv6 type
        cli:resolve("host.")
        assert.same({
            'host.:28',
          }, list)
      end)

      it("works with a 'domain' option", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "domain local.domain.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new({ order = { "AAAA" } }))  -- IPv6 type
        cli:resolve("host.")

        assert.same({
          'host.:28',
        }, list)
      end)

      it("ignores last successful type", function()
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "search one.com two.com",
          "options ndots:1",
        })

        local list = hook_query_func_get_list()
        local cli = assert(client_new({ order = { "AAAA" } }))  -- IPv6 type
        cli:insert_last_type("host", resolver.TYPE_CNAME)

        cli:resolve("host.")

        assert.same({
            'host.:28',
          }, list)
      end)
    end)

    it("honours 'ndots'", function()
      writefile(resolv_path, {
        "nameserver 198.51.100.0",
        "search one.com two.com",
        "options ndots:1",
      })

      local list = hook_query_func_get_list()
      local cli = assert(client_new())
      cli:resolve("local.host")

      assert.same({
        'local.host:33',
        'local.host:1',
        'local.host:28',
        'local.host:5',
      }, list)
    end)

    it("hosts file always resolves first, overriding `ndots`", function()
      writefile(resolv_path, {
        "nameserver 198.51.100.0",
        "search one.com two.com",
        "options ndots:1",
      })
      writefile(hosts_path, {
        "127.0.0.1 host",
        "::1 host",
      })

      local list = hook_query_func_get_list()
      -- perferred IP type: IPv4 (A takes priority in order)
      local cli = assert(client_new({ order = { "LAST", "SRV", "A", "AAAA" } }))
      local answers = cli:resolve("host")
      assert.same(answers[1].address, "127.0.0.1")
      assert.same({}, list) -- hit on cache, so no query to the nameserver

      -- perferred IP type: IPv6 (AAAA takes priority in order)
      local cli = assert(client_new({ order = { "LAST", "SRV", "AAAA", "A" } }))
      local answers = cli:resolve("host")
      assert.same(answers[1].address, "[::1]")
      assert.same({}, list)
    end)
  end)

  -- This test will report an alert-level error message, ignore it.
  it("low-level callback error", function()
    receive_func = function(...)
      error("CALLBACK")
    end

    local cli = assert(client_new())

    local orig_log = ngx.log
    _G.ngx.log = function (...) end -- mute ALERT log
    local answers, err = cli:resolve("srv.timeout.com")
    _G.ngx.log = orig_log
    assert.is_nil(answers)
    assert.match("callback threw an error:.*CALLBACK", err)
  end)

  describe("timeout", function ()
    it("dont try other types with the low-level error", function()
      -- KAG-2300 https://github.com/Kong/kong/issues/10182
      -- When timed out, don't keep trying with other answers types.
      writefile(resolv_path, {
        "nameserver 198.51.100.0",
        "options timeout:1",
        "options attempts:3",
      })

      local query_count = 0
      query_func = function(self, original_query_func, name, options)
        assert(options.qtype == resolver.TYPE_SRV)
        query_count = query_count + 1
        return original_query_func(self, name, options)
      end

      local receive_count = 0
      receive_func = function(...)
        receive_count = receive_count + 1
        return nil, "timeout"
      end

      local cli = assert(client_new())
      assert.same(cli.r_opts.retrans, 3)
      assert.same(cli.r_opts.timeout, 1)

      local answers, err = cli:resolve("srv.timeout.com")
      assert.is_nil(answers)
      assert.match("DNS server error: failed to receive reply from UDP server .*: timeout", err)
      assert.same(receive_count, 3)
      assert.same(query_count, 1)
    end)

    -- KAG-2300 - https://github.com/Kong/kong/issues/10182
    -- If we encounter a timeout while talking to the DNS server,
    -- expect the total timeout to be close to timeout * attemps parameters
    for _, attempts in ipairs({1, 2}) do
    for _, timeout in ipairs({1, 2}) do
      it("options: timeout: " .. timeout .. " seconds, attempts: " .. attempts .. " times", function()
        query_func = function(self, original_query_func, name, options)
          ngx.sleep(math.min(timeout, 5))
          return nil, "timeout" .. timeout .. attempts
        end
        writefile(resolv_path, {
          "nameserver 198.51.100.0",
          "options timeout:" .. timeout,
          "options attempts:" .. attempts,
        })
        local cli = assert(client_new())
        assert.same(cli.r_opts.retrans, attempts)
        assert.same(cli.r_opts.timeout, timeout)

        local start_time = ngx.now()
        local answers = cli:resolve("timeout.com")
        assert.is.Nil(answers)
        assert.is("DNS server error: timeout" .. timeout .. attempts)
        local duration = ngx.now() - start_time
        assert.truthy(duration < (timeout * attempts + 1))
      end)
    end
    end
  end)

  it("fetching answers without nameservers errors", function()
    writefile(resolv_path, "")
    local host = TEST_DOMAIN
    local typ = resolver.TYPE_A

    local cli = assert(client_new())
    local answers, err = cli:resolve(host, { qtype = typ })
    assert.is_nil(answers)
    assert.same(err, "failed to instantiate the resolver: no nameservers specified")
  end)

  it("fetching CNAME answers", function()
    local host = "smtp."..TEST_DOMAIN
    local typ = resolver.TYPE_CNAME

    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
    local answers = cli:resolve(host, { qtype = typ })

    assert.are.equal(host, answers[1].name)
    assert.are.equal(typ, answers[1].type)
    assert.are.equal(#answers, 1)
  end)

  it("fetching CNAME answers FQDN", function()
    local host = "smtp."..TEST_DOMAIN
    local typ = resolver.TYPE_CNAME

    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
    local answers = cli:resolve(host .. ".", { qtype = typ })

    assert.are.equal(host, answers[1].name) -- answers name does not contain "."
    assert.are.equal(typ, answers[1].type)
    assert.are.equal(#answers, 1)
  end)

  it("cache hit and ttl", function()
    -- TOOD: The special 0-ttl record may cause this test failed
    -- [{"name":"kong-gateway-testing.link","class":1,"address":"198.51.100.0",
    --   "ttl":0,"type":1,"section":1}]
    local host = TEST_DOMAIN

    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
    local answers = cli:resolve(host)
    assert.are.equal(host, answers[1].name)

    local wait_time = 1
    ngx.sleep(wait_time)

    -- fetch again, now from cache
    local answers2 = assert(cli:resolve(host))
    assert.are.equal(answers, answers2) -- same table from L1 cache

    local ttl, _, value = cli.cache:peek("short:" .. host .. ":all")
    assert.same(answers, value)
    local ttl_diff = answers.ttl - ttl
    assert(math.abs(ttl_diff - wait_time) < 1,
    ("ttl diff:%s s should be near to %s s"):format(ttl_diff, wait_time))
  end)

  it("fetching names case insensitive", function()
    query_func = function(self, original_query_func, name, options)
      return {{
        name = "some.UPPER.case",
        type = resolver.TYPE_A,
        ttl = 30,
      }}
    end
    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
    local answers = cli:resolve("some.upper.CASE")

    assert.equal(1, #answers)
    assert.equal("some.upper.case", answers[1].name)
  end)

  it("fetching multiple A answers", function()
    local host = "atest."..TEST_DOMAIN
    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf", order = {"LAST", "A"}}))
    local answers = assert(cli:resolve(host))
    assert.are.equal(#answers, 2)
    assert.are.equal(host, answers[1].name)
    assert.are.equal(resolver.TYPE_A, answers[1].type)
    assert.are.equal(host, answers[2].name)
    assert.are.equal(resolver.TYPE_A, answers[2].type)
  end)

  it("fetching multiple A answers FQDN", function()
    local host = "atest."..TEST_DOMAIN
    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf", order = {"LAST", "A"}}))
    local answers = assert(cli:resolve(host .. "."))
    assert.are.equal(#answers, 2)
    assert.are.equal(host, answers[1].name)
    assert.are.equal(resolver.TYPE_A, answers[1].type)
    assert.are.equal(host, answers[2].name)
    assert.are.equal(resolver.TYPE_A, answers[2].type)
  end)

  it("fetching A answers redirected through 2 CNAME answerss (un-typed)", function()
    writefile(resolv_path, "")  -- search {} empty

    local host = "smtp."..TEST_DOMAIN

    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))
    local answers = assert(cli:resolve(host))

    -- check first CNAME
    local key1 = host .. ":" .. resolver.TYPE_CNAME
    local entry1 = cli.cache:get(key1)
    assert.same(nil, entry1)

    assert.same({
      ["kong-gateway-testing.link"] = {
	miss = 1,
	runs = 1,
	succ = 1
      },
      ["kong-gateway-testing.link:1"] = {
	query = 1,
	query_succ = 1
      },
      ["kong-gateway-testing.link:33"] = {
	query = 1,
	["query_err:empty record received"] = 1
      },
      ["smtp.kong-gateway-testing.link"] = {
	cname = 1,
	miss = 1,
	runs = 1
      },
      ["smtp.kong-gateway-testing.link:33"] = {
	query = 1,
	query_succ = 1
      }
    }, cli.stats)

    -- check last successful lookup references
    local lastsuccess = cli:get_last_type(answers[1].name)
    assert.are.equal(resolver.TYPE_A, lastsuccess)
  end)

  it("fetching multiple SRV answerss (un-typed)", function()
    local host = "srvtest."..TEST_DOMAIN
    local typ = resolver.TYPE_SRV

    -- un-typed lookup
    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))
    local answers = assert(cli:resolve(host))
    assert.are.equal(host, answers[1].name)
    assert.are.equal(typ, answers[1].type)
    assert.are.equal(host, answers[2].name)
    assert.are.equal(typ, answers[2].type)
    assert.are.equal(host, answers[3].name)
    assert.are.equal(typ, answers[3].type)
    assert.are.equal(#answers, 3)
  end)

  it("fetching multiple SRV answerss through CNAME (un-typed)", function()
    writefile(resolv_path, "")  -- search {} empty
    local host = "cname2srv."..TEST_DOMAIN
    local typ = resolver.TYPE_SRV

    -- un-typed lookup
    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))
    local answers = assert(cli:resolve(host))

    -- first check CNAME
    local key = host .. ":" .. resolver.TYPE_CNAME
    local entry = cli.cache:get(key)
    assert.same(nil, entry)

    assert.same({
      ["cname2srv.kong-gateway-testing.link"] = {
        miss = 1,
        runs = 1,
        succ = 1
      },
      ["cname2srv.kong-gateway-testing.link:33"] = {
        query = 1,
        query_succ = 1
      }
    }, cli.stats)

    -- check final target
    assert.are.equal(typ, answers[1].type)
    assert.are.equal(typ, answers[2].type)
    assert.are.equal(typ, answers[3].type)
    assert.are.equal(#answers, 3)
  end)

  it("fetching non-type-matching answerss", function()
    local host = "srvtest."..TEST_DOMAIN
    local typ = resolver.TYPE_A   --> the entry is SRV not A

    writefile(resolv_path, "")  -- search {} empty
    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))
    local answers, err = cli:resolve(host, { qtype = typ })
    assert.is_nil(answers)  -- returns nil
    assert.equal("dns client error: 101 empty record received", err)
  end)

  it("fetching non-existing answerss", function()
    local host = "IsNotHere."..TEST_DOMAIN

    writefile(resolv_path, "")  -- search {} empty
    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))
    local answers, err = cli:resolve(host)
    assert.is_nil(answers)
    assert.equal("dns server error: 3 name error", err)
  end)

  it("fetching IP address", function()
    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))

    local host = "1.2.3.4"
    local answers = cli:resolve(host)
    assert.same(answers[1].address, host)

    local host = "[1:2::3:4]"
    local answers = cli:resolve(host)
    assert.same(answers[1].address, host)

    local host = "1:2::3:4"
    local answers = cli:resolve(host)
    assert.same(answers[1].address, "[" .. host .. "]")

    -- ignore ipv6 format error, it only check ':'
    local host = "[invalid ipv6 address:::]"
    local answers = cli:resolve(host)
    assert.same(answers[1].address, host)
  end)

  it("fetching IPv6 in an SRV answers adds brackets",function()
    local host = "hello.world"
    local address = "::1"
    local entry = {{
      type = resolver.TYPE_SRV,
      target = address,
      port = 321,
      weight = 10,
      priority = 10,
      class = 1,
      name = host,
      ttl = 10,
    }}

    query_func = function(self, original_query_func, name, options)
      if name == host and options.qtype == resolver.TYPE_SRV then
        return entry
      end
      return original_query_func(self, name, options)
    end

    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))
    local answers = cli:resolve( host, { qtype = resolver.TYPE_SRV })
    assert.equal("["..address.."]", answers[1].target)
  end)

  it("recursive lookups failure - single resolve", function()
    query_func = function(self, original_query_func, name, opts)
      if name ~= "hello.world" and (opts or {}).qtype ~= resolver.TYPE_CNAME then
        return original_query_func(self, name, opts)
      end
      return {{
        type = resolver.TYPE_CNAME,
        cname = "hello.world",
        class = 1,
        name = "hello.world",
        ttl = 30,
      }}
    end

    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
    local answers, err, _ = cli:resolve("hello.world")
    assert.is_nil(answers)
    assert.are.equal("recursion detected for name: hello.world", err)
  end)

  it("recursive lookups failure - single", function()
    local entry1 = {{
      type = resolver.TYPE_CNAME,
      cname = "hello.world",
      class = 1,
      name = "hello.world",
      ttl = 0,
    }}

    -- Note: the bad case would be that the below lookup would hang due to round-robin on an empty table
    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
    -- insert in the cache
    cli.cache:set(entry1[1].name .. ":" .. entry1[1].type, { ttl = 0 }, entry1)
    local answers, err, _ = cli:resolve("hello.world", { cache_only = true })
    assert.is_nil(answers)
    assert.are.equal("recursion detected for name: hello.world", err)
  end)

  it("recursive lookups failure - multi", function()
    local entry1 = {{
      type = resolver.TYPE_CNAME,
      cname = "bye.bye.world",
      class = 1,
      name = "hello.world",
      ttl = 0,
    }}
    local entry2 = {{
      type = resolver.TYPE_CNAME,
      cname = "hello.world",
      class = 1,
      name = "bye.bye.world",
      ttl = 0,
    }}

    -- Note: the bad case would be that the below lookup would hang due to round-robin on an empty table
    local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
    -- insert in the cache
    cli.cache:set(entry1[1].name .. ":" .. entry1[1].type, { ttl = 0 }, entry1)
    cli.cache:set(entry2[1].name .. ":" .. entry2[1].type, { ttl = 0 }, entry2)
    local answers, err, _ = cli:resolve("hello.world", { cache_only = true })
    assert.is_nil(answers)
    assert.are.equal("recursion detected for name: hello.world", err)
  end)

  it("resolving from the /etc/hosts file; preferred A or AAAA order", function()
    writefile(hosts_path, {
      "127.3.2.1 localhost",
      "1::2 localhost",
    })
    local cli = assert(client_new({
      resolv_conf = "/etc/resolv.conf",
      order = {"SRV", "CNAME", "A", "AAAA"}
    }))
    assert.equal(resolver.TYPE_A, cli:get_last_type("localhost")) -- success set to A as it is the preferred option

    local cli = assert(client_new({
      resolv_conf = "/etc/resolv.conf",
      order = {"SRV", "CNAME", "AAAA", "A"}
    }))
    assert.equal(resolver.TYPE_AAAA, cli:get_last_type("localhost")) -- success set to AAAA as it is the preferred option
  end)


  it("resolving from the /etc/hosts file", function()
    writefile(hosts_path, {
      "127.3.2.1 localhost",
      "1::2 localhost",
      "123.123.123.123 mashape",
      "1234::1234 kong.for.president",
    })

    local cli = assert(client_new({ nameservers = TEST_NSS }))

    local answers, err = cli:resolve("localhost", {qtype = resolver.TYPE_A})
    assert.is.Nil(err)
    assert.are.equal(answers[1].address, "127.3.2.1")

    answers, err = cli:resolve("localhost", {qtype = resolver.TYPE_AAAA})
    assert.is.Nil(err)
    assert.are.equal(answers[1].address, "[1::2]")

    answers, err = cli:resolve("mashape", {qtype = resolver.TYPE_A})
    assert.is.Nil(err)
    assert.are.equal(answers[1].address, "123.123.123.123")

    answers, err = cli:resolve("kong.for.president", {qtype = resolver.TYPE_AAAA})
    assert.is.Nil(err)
    assert.are.equal(answers[1].address, "[1234::1234]")
  end)

  describe("toip() function", function()
    it("A/AAAA-answers, round-robin",function()
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
      local host = "atest."..TEST_DOMAIN
      local answers = assert(cli:resolve(host))
      answers.last = nil -- make sure to clean
      local ips = {}
      for _,answers in ipairs(answers) do ips[answers.address] = true end
      local order = {}
      for n = 1, #answers do
        local ip = cli:resolve(host, { return_random = true })
        ips[ip] = nil
        order[n] = ip
      end
      -- this table should be empty again
      assert.is_nil(next(ips))
      -- do again, and check same order
      for n = 1, #order do
        local ip = cli:resolve(host, { return_random = true })
        assert.same(order[n], ip)
      end
    end)
    it("SRV-answers, round-robin on lowest prio",function()
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
      local host = "hello.world.test"
      local entry = {
        {
          type = resolver.TYPE_SRV,
          target = "1.2.3.4",
          port = 8000,
          weight = 5,
          priority = 10,
          class = 1,
          name = host,
          ttl = 10,
        },
        {
          type = resolver.TYPE_SRV,
          target = "1.2.3.4",
          port = 8001,
          weight = 5,
          priority = 20,
          class = 1,
          name = host,
          ttl = 10,
        },
        {
          type = resolver.TYPE_SRV,
          target = "1.2.3.4",
          port = 8002,
          weight = 5,
          priority = 10,
          class = 1,
          name = host,
          ttl = 10,
        },
      }
      -- insert in the cache
      cli.cache:set(entry[1].name .. ":" .. entry[1].type, {ttl=0}, entry)

      local results = {}
      for _ = 1,20 do
        local _, port = cli:resolve(host, { return_random = true })
        results[port] = (results[port] or 0) + 1
      end

      -- 20 passes, each should get 10
      assert.equal(0, results[8001] or 0) --priority 20, no hits
      assert.equal(10, results[8000] or 0) --priority 10, 50% of hits
      assert.equal(10, results[8002] or 0) --priority 10, 50% of hits
    end)
    it("SRV-answers with 1 entry, round-robin",function()
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
      local host = "hello.world"
      local entry = {{
        type = resolver.TYPE_SRV,
        target = "1.2.3.4",
        port = 321,
        weight = 10,
        priority = 10,
        class = 1,
        name = host,
        ttl = 10,
      }}
      -- insert in the cache
      cli.cache:set(entry[1].name .. ":" .. entry[1].type, { ttl=0 }, entry)

      -- repeated lookups, as the first will simply serve the first entry
      -- and the only second will setup the round-robin scheme, this is
      -- specific for the SRV answers type, due to the weights
      for _ = 1 , 10 do
        local ip, port = cli:resolve(host, { return_random = true })
        assert.same("1.2.3.4", ip)
        assert.same(321, port)
      end
    end)
    it("SRV-answers with 0-weight, round-robin",function()
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))
      local host = "hello.world"
      local entry = {
        {
          type = resolver.TYPE_SRV,
          target = "1.2.3.4",
          port = 321,
          weight = 0,   --> weight 0
          priority = 10,
          class = 1,
          name = host,
          ttl = 10,
        },
        {
          type = resolver.TYPE_SRV,
          target = "1.2.3.5",
          port = 321,
          weight = 50,   --> weight 50
          priority = 10,
          class = 1,
          name = host,
          ttl = 10,
        },
        {
          type = resolver.TYPE_SRV,
          target = "1.2.3.6",
          port = 321,
          weight = 50,   --> weight 50
          priority = 10,
          class = 1,
          name = host,
          ttl = 10,
        },
      }
      -- insert in the cache
      cli.cache:set(entry[1].name .. ":" .. entry[1].type, { ttl = 0 }, entry)

      -- weight 0 will be weight 1, without any reduction in weight
      -- of the other ones.
      local track = {}
      for _ = 1 , 2002 do  --> run around twice
        local ip, _ = assert(cli:resolve(host, { return_random = true }))
        track[ip] = (track[ip] or 0) + 1
      end
      assert.equal(1000, track["1.2.3.5"])
      assert.equal(1000, track["1.2.3.6"])
      assert.equal(2, track["1.2.3.4"])
    end)
    it("port passing",function()
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))
      local entry_a = {{
        type = resolver.TYPE_A,
        address = "1.2.3.4",
        class = 1,
        name = "a.answers.test",
        ttl = 10,
      }}
      local entry_srv = {{
        type = resolver.TYPE_SRV,
        target = "a.answers.test",
        port = 8001,
        weight = 5,
        priority = 20,
        class = 1,
        name = "srv.answers.test",
        ttl = 10,
      }}
      -- insert in the cache
      cli.cache:set(entry_a[1].name..":"..entry_a[1].type, { ttl = 0 }, entry_a)
      cli.cache:set(entry_srv[1].name..":"..entry_srv[1].type, { ttl = 0 }, entry_srv)
      local ip, port
      local host = "a.answers.test"
      ip,port = cli:resolve(host, { return_random = true })
      assert.is_string(ip)
      assert.is_nil(port)

      ip, port = cli:resolve(host, { return_random = true, port = 1234 })
      assert.is_string(ip)
      assert.equal(1234, port)

      host = "srv.answers.test"
      ip, port = cli:resolve(host, { return_random = true })
      assert.is_string(ip)
      assert.is_number(port)

      ip, port = cli:resolve(host, { return_random = true, port = 0 })
      assert.is_string(ip)
      assert.is_number(port)
      assert.is_not.equal(0, port)
    end)

    it("port passing if SRV port=0",function()
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))
      local ip, port, host

      host = "srvport0."..TEST_DOMAIN
      ip, port = cli:resolve(host, { return_random = true, port = 10 })
      assert.is_string(ip)
      assert.is_number(port)
      assert.is_equal(10, port)

      ip, port = cli:resolve(host, { return_random = true })
      assert.is_string(ip)
      assert.is_nil(port)
    end)

    it("recursive SRV pointing to itself",function()
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf"}))
      local ip, answers, port, host, err, _
      host = "srvrecurse."..TEST_DOMAIN

      -- resolve SRV specific should _not_ return the answers including its
      -- recursive entry
      answers, err, _ = cli:resolve(host, { qtype = resolver.TYPE_SRV })
      assert.same(answers, nil)
      assert.same(err, "dns client error: 101 empty record received")

      -- default order, SRV, A; the recursive SRV answers fails, and it falls
      -- back to the IP4 address
      ip, port, _ = cli:resolve(host, { return_random = true })
      assert.is_string(ip)
      assert.is_equal("10.0.0.44", ip)
      assert.is_nil(port)
    end)

    it("resolving in correct answers-type order",function()
      local function config(cli)
        -- function to insert 2 answerss in the cache
        local A_entry = {{
          type = resolver.TYPE_A,
          address = "5.6.7.8",
          class = 1,
          name = "hello.world",
          ttl = 10,
        }}
        local AAAA_entry = {{
          type = resolver.TYPE_AAAA,
          address = "::1",
          class = 1,
          name = "hello.world",
          ttl = 10,
        }}
        -- insert in the cache
        cli.cache:set(A_entry[1].name..":"..A_entry[1].type, { ttl=0 }, A_entry)
        cli.cache:set(AAAA_entry[1].name..":"..AAAA_entry[1].type, { ttl=0 }, AAAA_entry)
      end
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf", order = {"AAAA", "A"} }))
      config(cli)
      local ip,err = cli:resolve("hello.world", { return_random = true })
      assert.same(err, nil)
      assert.equals(ip, "::1")
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf", order = {"A", "AAAA"} }))
      config(cli)
      ip = cli:resolve("hello.world", { return_random = true })
      assert.equals(ip, "5.6.7.8")
    end)
    it("handling of empty responses", function()
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
      local empty_entry = {
        touch = 0,
        expire = 0,
      }
      -- insert in the cache
      cli.cache[resolver.TYPE_A..":".."hello.world"] = empty_entry

      -- Note: the bad case would be that the below lookup would hang due to round-robin on an empty table
      local ip, port = cli:resolve("hello.world", { return_random = true, port = 123, cache_only = true })
      assert.is_nil(ip)
      assert.is.string(port)  -- error message
    end)
    it("recursive lookups failure", function()
      local cli = assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
      local entry1 = {{
        type = resolver.TYPE_CNAME,
        cname = "bye.bye.world",
        class = 1,
        name = "hello.world",
        ttl = 10,
      }}
      local entry2 = {{
        type = resolver.TYPE_CNAME,
        cname = "hello.world",
        class = 1,
        name = "bye.bye.world",
        ttl = 10,
      }}
      -- insert in the cache
      cli.cache:set(entry1[1].name..":"..entry1[1].type, { ttl = 0 }, entry1)
      cli.cache:set(entry2[1].name..":"..entry2[1].type, { ttl = 0 }, entry2)

      -- Note: the bad case would be that the below lookup would hang due to round-robin on an empty table
      local ip, port, _ = cli:resolve("hello.world", { return_random = true, port = 123, cache_only = true })
      assert.is_nil(ip)
      assert.are.equal("recursion detected for name: hello.world", port)
    end)
  end)

  it("verifies valid_ttl", function()
    local valid_ttl = 0.1
    local empty_ttl = 0.1
    local stale_ttl = 0.1
    local qname = "konghq.com"
    local cli = assert(client_new({
      resolv_conf = "/etc/resolv.conf",
      empty_ttl = empty_ttl,
      stale_ttl = stale_ttl,
      valid_ttl = valid_ttl,
    }))
    -- mock query function to return a default answers
    query_func = function(self, original_query_func, name, options)
      return  {{
        type = resolver.TYPE_A,
        address = "5.6.7.8",
        class = 1,
        name = qname,
        ttl = 10,
      }}  -- will add new field .ttl = valid_ttl
    end

    local answers, _, _ = cli:resolve(qname, { qtype = resolver.TYPE_A })
    assert.equal(valid_ttl, answers.ttl)

    local ttl = cli.cache:peek("short:" .. qname .. ":1")
    assert.is_near(valid_ttl, ttl, 0.1)
  end)

  it("verifies ttl and caching of empty responses and name errors", function()
    --empty/error responses should be cached for a configurable time
    local empty_ttl = 0.1
    local stale_ttl = 0.1
    local qname = "really.really.really.does.not.exist."..TEST_DOMAIN
    local cli = assert(client_new({
      resolv_conf = "/etc/resolv.conf",
      empty_ttl = empty_ttl,
      stale_ttl = stale_ttl,
    }))

    -- mock query function to count calls
    local call_count = 0
    query_func = function(self, original_query_func, name, options)
      call_count = call_count + 1
      return original_query_func(self, name, options)
    end

    -- make a first request, populating the cache
    local answers1, answers2, err1, err2, _
    answers1, err1, _ = cli:resolve(qname, { qtype = resolver.TYPE_A })
    assert.is_nil(answers1)
    assert.are.equal(1, call_count)
    assert.are.equal(NOT_FOUND_ERROR, err1)
    answers1 = assert(cli.cache:get(qname .. ":" .. resolver.TYPE_A))

    -- make a second request, result from cache, still called only once
    answers2, err2, _ = cli:resolve(qname, { qtype = resolver.TYPE_A })
    assert.is_nil(answers2)
    assert.are.equal(1, call_count)
    assert.are.equal(NOT_FOUND_ERROR, err2)
    answers2 = assert(cli.cache:get(qname .. ":" .. resolver.TYPE_A))
    assert.equal(answers1, answers2)
    assert.falsy(answers2.expired)

    -- wait for expiry of ttl and retry, still called only once
    ngx.sleep(empty_ttl+0.5 * stale_ttl)
    answers2, err2 = cli:resolve(qname, { qtype = resolver.TYPE_A })
    assert.is_nil(answers2)
    assert.are.equal(1, call_count)
    assert.are.equal(NOT_FOUND_ERROR, err2)

    answers2 = assert(cli.cache:get(qname .. ":" .. resolver.TYPE_A))
    assert.is_true(answers2.expired)  -- by now, record is marked as expired

    -- wait for expiry of stale_ttl and retry, should be called twice now
    ngx.sleep(0.75 * stale_ttl)
    assert.are.equal(2, call_count)
    answers2, err2 = cli:resolve(qname, { qtype = resolver.TYPE_A })
    assert.is_nil(answers2)
    assert.are.equal(NOT_FOUND_ERROR, err2)
    assert.are.equal(2, call_count)

    answers2 = assert(cli.cache:get(qname .. ":" .. resolver.TYPE_A))
    assert.not_equal(answers1, answers2)
    assert.falsy(answers2.expired)  -- new answers, not expired
  end)

  it("verifies ttl and caching of (other) dns errors", function()
    --empty responses should be cached for a configurable time
    local error_ttl = 0.1
    local stale_ttl = 0.1
    local qname = "realname.com"
    local cli = assert(client_new({
      resolv_conf = "/etc/resolv.conf",
      error_ttl = error_ttl,
      stale_ttl = stale_ttl,
    }))

    -- mock query function to count calls, and return errors
    local call_count = 0
    query_func = function(self, original_query_func, name, options)
      call_count = call_count + 1
      return { errcode = 5, errstr = "refused" }
    end

    -- initial request to populate the cache
    local answers1, answers2, err1, err2, _
    answers1, err1, _ = cli:resolve(qname, { qtype = resolver.TYPE_A })
    assert.is_nil(answers1)
    assert.are.equal(call_count, 1)
    assert.are.equal("dns server error: 5 refused", err1)
    answers1 = assert(cli.cache:get(qname .. ":" .. resolver.TYPE_A))

    -- try again, HIT from cache, not stale
    answers2, err2, _ = cli:resolve(qname, { qtype = resolver.TYPE_A })
    assert.is_nil(answers2)
    assert.are.equal(call_count, 1)
    assert.are.equal(err1, err2)
    answers2 = assert(cli.cache:get(qname .. ":" .. resolver.TYPE_A))
    assert.are.equal(answers1, answers2)
    assert.falsy(answers1.expired)

    -- wait for expiry of ttl and retry, HIT and stale
    ngx.sleep(error_ttl + 0.5 * stale_ttl)
    answers2, err2, _ = cli:resolve(qname, { qtype = resolver.TYPE_A })
    assert.is_nil(answers2)
    assert.are.equal(call_count, 1)
    assert.are.equal(err1, err2)

    answers2 = assert(cli.cache:get(qname .. ":" .. resolver.TYPE_A))
    assert.is_true(answers2.expired)
    answers2.expired = nil  -- clear to be same with answers1
    assert_same_answers(answers1, answers2)
    answers2.expired = true

    -- async stale updating task
    ngx.sleep(0.1 * stale_ttl)
    assert.are.equal(call_count, 2)

    -- wait for expiry of stale_ttl and retry, 2 calls, new result
    ngx.sleep(0.75 * stale_ttl)
    assert.are.equal(call_count, 2)

    answers2, err2, _ = cli:resolve(qname, { qtype = resolver.TYPE_A })
    assert.is_nil(answers2)
    assert.are.equal(call_count, 3)
    assert.are.equal(err1, err2)
    answers2 = assert(cli.cache:get(qname .. ":" .. resolver.TYPE_A))
    assert.are_not.equal(answers1, answers2)  -- a new answers
    assert.falsy(answers2.expired)
  end)

  describe("verifies the polling of dns queries, retries, and wait times", function()
    local function threads_resolve(nthreads, name, cli)
      cli = cli or assert(client_new({ resolv_conf = "/etc/resolv.conf" }))
      -- we're going to schedule a whole bunch of queries (lookup & stores answers)
      local coros = {}
      local answers_list = {}
      for _ = 1, nthreads do
        local co = ngx.thread.spawn(function ()
          coroutine.yield(coroutine.running())
          local answers, err = cli:resolve(name, { qtype = resolver.TYPE_A })
          table.insert(answers_list, (answers or err))
        end)
        table.insert(coros, co)
      end
      for _, co in ipairs(coros) do
        ngx.thread.wait(co)
      end
      return answers_list
    end

    it("simultaneous lookups are synchronized to 1 lookup", function()
      local call_count = 0
      query_func = function(self, original_query_func, name, options)
        call_count = call_count + 1
        ngx.sleep(0.5) -- block all other threads
        return original_query_func(self, name, options)
      end

      local answers_list = threads_resolve(10, TEST_DOMAIN)

      assert(call_count == 1)
      for _, answers in ipairs(answers_list) do
        assert.same(answers_list[1], answers)
      end
    end)

    it("timeout while waiting", function()

      local ip = "1.4.2.3"
      local timeout = 500 -- ms
      local name = TEST_DOMAIN
      -- insert a stub thats waits and returns a fixed answers
      query_func = function()
        -- `+ 2` s ensures that the resty-lock expires
        ngx.sleep(timeout / 1000 + 2)
        return {{
          type = resolver.TYPE_A,
          address = ip,
          class = 1,
          name = name,
          ttl = 10,
        }}
      end

      local cli = assert(client_new({
        resolv_conf = "/etc/resolv.conf",
        timeout = timeout,
        retrans = 1,
      }))
      local answers_list = threads_resolve(10, name, cli)

      -- answers[1~9] are equal, as they all will wait for the first response
      for i = 1, 9 do
        assert.equal("could not acquire callback lock: timeout", answers_list[i])
      end
      -- answers[10] comes from synchronous DNS access of the first request
      assert.equal(ip, answers_list[10][1]["address"])
    end)
  end)

end)
