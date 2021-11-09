local dnsutils = require "kong.resty.dns.utils"
local splitlines = require("pl.stringx").splitlines
local writefile = require("pl.utils").writefile
local tempfilename = require("pl.path").tmpname

local sleep
if ngx then
  gettime = ngx.now                -- luacheck: ignore
  sleep = ngx.sleep
else
  local socket = require("socket")
  gettime = socket.gettime         -- luacheck: ignore
  sleep = socket.sleep
end

describe("[utils]", function()

  describe("parsing 'hosts':", function()

    it("tests parsing when the 'hosts' file does not exist", function()
      local result, err = dnsutils.parseHosts("non/existing/file")
      assert.is.Nil(result)
      assert.is.string(err)
    end)

    it("tests parsing when the 'hosts' file is empty", function()
      local filename = tempfilename()
      writefile(filename, "")
      local reverse, hosts = dnsutils.parseHosts(filename)
      os.remove(filename)
      assert.is.same({}, reverse)
      assert.is.same({}, hosts)
    end)

    it("tests parsing 'hosts'", function()
        local hostsfile = splitlines(
[[# The localhost entry should be in every HOSTS file and is used
# to point back to yourself.

127.0.0.1 localhost
::1 localhost

# My test server for the website

192.168.1.2 test.computer.com
192.168.1.3 ftp.COMPUTER.com alias1 alias2
192.168.1.4 smtp.computer.com alias3 #alias4
192.168.1.5 smtp.computer.com alias3 #doubles, first one should win

#Blocking known malicious sites
127.0.0.1  admin.abcsearch.com
127.0.0.2  www3.abcsearch.com #[Browseraid]
127.0.0.3  www.abcsearch.com wwwsearch #[Restricted Zone site]

[::1]        alsolocalhost  #support IPv6 in brackets
]])
      local reverse, hosts = dnsutils.parseHosts(hostsfile)
      assert.is.equal(hosts[1].ip, "127.0.0.1")
      assert.is.equal(hosts[1].canonical, "localhost")
      assert.is.Nil(hosts[1][1])  -- no aliases
      assert.is.Nil(hosts[1][2])
      assert.is.equal("127.0.0.1", reverse.localhost.ipv4)
      assert.is.equal("[::1]", reverse.localhost.ipv6)

      assert.is.equal(hosts[2].ip, "[::1]")
      assert.is.equal(hosts[2].canonical, "localhost")

      assert.is.equal(hosts[3].ip, "192.168.1.2")
      assert.is.equal(hosts[3].canonical, "test.computer.com")
      assert.is.Nil(hosts[3][1])  -- no aliases
      assert.is.Nil(hosts[3][2])
      assert.is.equal("192.168.1.2", reverse["test.computer.com"].ipv4)

      assert.is.equal(hosts[4].ip, "192.168.1.3")
      assert.is.equal(hosts[4].canonical, "ftp.computer.com")   -- converted to lowercase!
      assert.is.equal(hosts[4][1], "alias1")
      assert.is.equal(hosts[4][2], "alias2")
      assert.is.Nil(hosts[4][3])
      assert.is.equal("192.168.1.3", reverse["ftp.computer.com"].ipv4)
      assert.is.equal("192.168.1.3", reverse["alias1"].ipv4)
      assert.is.equal("192.168.1.3", reverse["alias2"].ipv4)

      assert.is.equal(hosts[5].ip, "192.168.1.4")
      assert.is.equal(hosts[5].canonical, "smtp.computer.com")
      assert.is.equal(hosts[5][1], "alias3")
      assert.is.Nil(hosts[5][2])
      assert.is.equal("192.168.1.4", reverse["smtp.computer.com"].ipv4)
      assert.is.equal("192.168.1.4", reverse["alias3"].ipv4)

      assert.is.equal(hosts[6].ip, "192.168.1.5")
      assert.is.equal(hosts[6].canonical, "smtp.computer.com")
      assert.is.equal(hosts[6][1], "alias3")
      assert.is.Nil(hosts[6][2])
      assert.is.equal("192.168.1.4", reverse["smtp.computer.com"].ipv4)  -- .1.4; first one wins!
      assert.is.equal("192.168.1.4", reverse["alias3"].ipv4)   -- .1.4; first one wins!

      assert.is.equal(hosts[10].ip, "[::1]")
      assert.is.equal(hosts[10].canonical, "alsolocalhost")
      assert.is.equal(hosts[10].family, "ipv6")
      assert.is.equal("[::1]", reverse["alsolocalhost"].ipv6)
    end)

  end)

  describe("parsing 'resolv.conf':", function()

    -- override os.getenv to insert env variables
    local old_getenv = os.getenv
    local envvars  -- whatever is in this table, gets served first
    before_each(function()
      envvars = {}
      os.getenv = function(name)     -- luacheck: ignore
        return envvars[name] or old_getenv(name)
      end
    end)

    after_each(function()
      os.getenv = old_getenv         -- luacheck: ignore
      envvars = nil
    end)

    it("tests parsing when the 'resolv.conf' file does not exist", function()
      local result, err = dnsutils.parseResolvConf("non/existing/file")
      assert.is.Nil(result)
      assert.is.string(err)
    end)

    it("tests parsing when the 'resolv.conf' file is empty", function()
      local filename = tempfilename()
      writefile(filename, "")
      local resolv, err = dnsutils.parseResolvConf(filename)
      os.remove(filename)
      assert.is.same({}, resolv)
      assert.is.Nil(err)
    end)

    it("tests parsing 'resolv.conf' with multiple comment types", function()
      local file = splitlines(
[[# this is just a comment line
# at the top of the file

domain myservice.com

nameserver 8.8.8.8
nameserver 2602:306:bca8:1ac0::1 ; and a comment here
nameserver 8.8.8.8:1234 ; this one has a port number (limited systems support this)
nameserver 1.2.3.4 ; this one is 4th, so should be ignored

# search is commented out, test below for a mutually exclusive one
#search domaina.com domainb.com

sortlist list1 list2 #list3 is not part of it

options ndots:2
options timeout:3
options attempts:4

options debug
options rotate ; let's see about a comment here
options no-check-names
options inet6
; here's annother comment
options ip6-bytestring
options ip6-dotint
options no-ip6-dotint
options edns0
options single-request
options single-request-reopen
options no-tld-query
options use-vc
]])
      local resolv, err = dnsutils.parseResolvConf(file)
      assert.is.Nil(err)
      assert.is.equal("myservice.com", resolv.domain)
      assert.is.same({ "8.8.8.8", "2602:306:bca8:1ac0::1", "8.8.8.8:1234" }, resolv.nameserver)
      assert.is.same({ "list1", "list2" }, resolv.sortlist)
      assert.is.same({ ndots = 2, timeout = 3, attempts = 4, debug = true, rotate = true,
          ["no-check-names"] = true, inet6 = true, ["ip6-bytestring"] = true,
          ["ip6-dotint"] = nil,  -- overridden by the next one, mutually exclusive
          ["no-ip6-dotint"] = true, edns0 = true, ["single-request"] = true,
          ["single-request-reopen"] = true, ["no-tld-query"] = true, ["use-vc"] = true},
          resolv.options)
    end)

    it("tests parsing 'resolv.conf' with mutual exclusive domain vs search", function()
      local file = splitlines(
[[domain myservice.com

# search is overriding domain above
search domaina.com domainb.com

]])
      local resolv, err = dnsutils.parseResolvConf(file)
      assert.is.Nil(err)
      assert.is.Nil(resolv.domain)
      assert.is.same({ "domaina.com", "domainb.com" }, resolv.search)
    end)

    it("tests parsing 'resolv.conf' with max search entries MAXSEARCH", function()
      local file = splitlines(
[[

search domain1.com domain2.com domain3.com domain4.com domain5.com domain6.com domain7.com

]])
      local resolv, err = dnsutils.parseResolvConf(file)
      assert.is.Nil(err)
      assert.is.Nil(resolv.domain)
      assert.is.same({
          "domain1.com",
          "domain2.com",
          "domain3.com",
          "domain4.com",
          "domain5.com",
          "domain6.com",
        }, resolv.search)
    end)

    it("tests parsing 'resolv.conf' with environment variables", function()
      local file = splitlines(
[[# this is just a comment line
domain myservice.com

nameserver 8.8.8.8
nameserver 8.8.4.4 ; and a comment here

options ndots:1
]])
      local resolv, err = dnsutils.parseResolvConf(file)
      assert.is.Nil(err)

      envvars.LOCALDOMAIN = "domaina.com domainb.com"
      envvars.RES_OPTIONS = "ndots:2 debug"
      resolv = dnsutils.applyEnv(resolv)

      assert.is.Nil(resolv.domain)  -- must be nil, mutually exclusive
      assert.is.same({ "domaina.com", "domainb.com" }, resolv.search)

      assert.is.same({ ndots = 2, debug = true }, resolv.options)
    end)

    it("tests parsing 'resolv.conf' with non-existing environment variables", function()
      local file = splitlines(
[[# this is just a comment line
domain myservice.com

nameserver 8.8.8.8
nameserver 8.8.4.4 ; and a comment here

options ndots:2
]])
      local resolv, err = dnsutils.parseResolvConf(file)
      assert.is.Nil(err)

      envvars.LOCALDOMAIN = ""
      envvars.RES_OPTIONS = ""
      resolv = dnsutils.applyEnv(resolv)

      assert.is.equals("myservice.com", resolv.domain)  -- must be nil, mutually exclusive

      assert.is.same({ ndots = 2 }, resolv.options)
    end)

    it("tests pass-through error handling of 'applyEnv'", function()
      local fname = "non/existing/file"
      local r1, e1 = dnsutils.parseResolvConf(fname)
      local r2, e2 = dnsutils.applyEnv(dnsutils.parseResolvConf(fname))
      assert.are.same(r1, r2)
      assert.are.same(e1, e2)
    end)

  end)

  describe("cached versions", function()

    local utils = require("pl.utils")
    local oldreadlines = utils.readlines

    before_each(function()
      utils.readlines = function(name)
        if name:match("hosts") then
          return {  -- hosts file
              "127.0.0.1 localhost",
              "192.168.1.2 test.computer.com",
              "192.168.1.3 ftp.computer.com alias1 alias2",
            }
        else
          return {  -- resolv.conf file
              "domain myservice.com",
              "nameserver 8.8.8.8 ",
            }
        end
      end
    end)

    after_each(function()
      utils.readlines = oldreadlines
    end)

    it("tests caching the hosts file", function()
      local val1r, val1 = dnsutils.getHosts()
      local val2r, val2 = dnsutils.getHosts()
      assert.Not.equal(val1, val2) -- no ttl specified, so distinct tables
      assert.Not.equal(val1r, val2r) -- no ttl specified, so distinct tables

      val1r, val1 = dnsutils.getHosts(0.1)
      val2r, val2 = dnsutils.getHosts()
      assert.are.equal(val1, val2)   -- ttl specified, so same tables
      assert.are.equal(val1r, val2r) -- ttl specified, so same tables

      -- wait for cache to expire
      sleep(0.2)

      val2r, val2 = dnsutils.getHosts()
      assert.Not.equal(val1, val2) -- ttl timed out, so distinct tables
      assert.Not.equal(val1r, val2r) -- ttl timed out, so distinct tables
    end)

    it("tests caching the resolv.conf file & variables", function()
      local val1 = dnsutils.getResolv()
      local val2 = dnsutils.getResolv()
      assert.Not.equal(val1, val2) -- no ttl specified, so distinct tables

      val1 = dnsutils.getResolv(0.1)
      val2 = dnsutils.getResolv()
      assert.are.equal(val1, val2)   -- ttl specified, so same tables

      -- wait for cache to expire
      sleep(0.2)

      val2 = dnsutils.getResolv()
      assert.Not.equal(val1, val2)   -- ttl timed out, so distinct tables
    end)

  end)

  describe("hostnameType", function()
    -- no check on "name" type as anything not ipv4 and not ipv6 will be labelled as 'name' anyway
    it("checks valid IPv4 address types", function()
      assert.are.same("ipv4", dnsutils.hostnameType("123.123.123.123"))
      assert.are.same("ipv4", dnsutils.hostnameType("1.2.3.4"))
    end)
    it("checks valid IPv6 address types", function()
      assert.are.same("ipv6", dnsutils.hostnameType("::1"))
      assert.are.same("ipv6", dnsutils.hostnameType("2345::6789"))
      assert.are.same("ipv6", dnsutils.hostnameType("0001:0001:0001:0001:0001:0001:0001:0001"))
    end)
    it("checks valid FQDN address types", function()
      assert.are.same("name", dnsutils.hostnameType("konghq."))
      assert.are.same("name", dnsutils.hostnameType("konghq.com."))
      assert.are.same("name", dnsutils.hostnameType("www.konghq.com."))
    end)
  end)

  describe("parseHostname", function()
    it("parses valid IPv4 address types", function()
      assert.are.same({"123.123.123.123", nil, "ipv4"}, {dnsutils.parseHostname("123.123.123.123")})
      assert.are.same({"1.2.3.4", 567, "ipv4"}, {dnsutils.parseHostname("1.2.3.4:567")})
    end)
    it("parses valid IPv6 address types", function()
      assert.are.same({"[::1]", nil, "ipv6"}, {dnsutils.parseHostname("::1")})
      assert.are.same({"[::1]", nil, "ipv6"}, {dnsutils.parseHostname("[::1]")})
      assert.are.same({"[::1]", 123, "ipv6"}, {dnsutils.parseHostname("[::1]:123")})
      assert.are.same({"[2345::6789]", nil, "ipv6"}, {dnsutils.parseHostname("2345::6789")})
      assert.are.same({"[2345::6789]", nil, "ipv6"}, {dnsutils.parseHostname("[2345::6789]")})
      assert.are.same({"[2345::6789]", 321, "ipv6"}, {dnsutils.parseHostname("[2345::6789]:321")})
    end)
    it("parses valid name address types", function()
      assert.are.same({"somename", nil, "name"}, {dnsutils.parseHostname("somename")})
      assert.are.same({"somename", 123, "name"}, {dnsutils.parseHostname("somename:123")})
      assert.are.same({"somename456", nil, "name"}, {dnsutils.parseHostname("somename456")})
      assert.are.same({"somename456", 123, "name"}, {dnsutils.parseHostname("somename456:123")})
      assert.are.same({"somename456.domain.local789", nil, "name"}, {dnsutils.parseHostname("somename456.domain.local789")})
      assert.are.same({"somename456.domain.local789", 123, "name"}, {dnsutils.parseHostname("somename456.domain.local789:123")})
    end)
    it("parses valid FQDN address types", function()
      assert.are.same({"somename.", nil, "name"}, {dnsutils.parseHostname("somename.")})
      assert.are.same({"somename.", 123, "name"}, {dnsutils.parseHostname("somename.:123")})
      assert.are.same({"somename456.", nil, "name"}, {dnsutils.parseHostname("somename456.")})
      assert.are.same({"somename456.", 123, "name"}, {dnsutils.parseHostname("somename456.:123")})
      assert.are.same({"somename456.domain.local789.", nil, "name"}, {dnsutils.parseHostname("somename456.domain.local789.")})
      assert.are.same({"somename456.domain.local789.", 123, "name"}, {dnsutils.parseHostname("somename456.domain.local789.:123")})
    end)
  end)

end)
