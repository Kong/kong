local utils = require "kong.resty.dns_client.utils"
local tempfilename = require("pl.path").tmpname
local writefile = require("pl.utils").writefile
local splitlines = require("pl.stringx").splitlines

describe("[utils]", function ()

  describe("is_fqdn(name, ndots)", function ()
    it("test @name: end with `.`", function ()
      assert.is_true(utils.is_fqdn("www.", 2))
      assert.is_true(utils.is_fqdn("www.example.", 3))
      assert.is_true(utils.is_fqdn("www.example.com.", 4))
    end)

    it("test @ndots", function ()
      assert.is_true(utils.is_fqdn("www", 0))

      assert.is_false(utils.is_fqdn("www", 1))
      assert.is_true(utils.is_fqdn("www.example", 1))
      assert.is_true(utils.is_fqdn("www.example.com", 1))

      assert.is_false(utils.is_fqdn("www", 2))
      assert.is_false(utils.is_fqdn("www.example", 2))
      assert.is_true(utils.is_fqdn("www.example.com", 2))
      assert.is_true(utils.is_fqdn("www1.www2.example.com", 2))
    end)
  end)

  describe("search_names()", function ()
    it("empty resolv, not apply the search list", function ()
      local resolv = {}
      local names = utils.search_names("www.example.com", resolv)
      assert.same(names, { "www.example.com" })
    end)

    it("FQDN name: end with `.`, not apply the search list", function ()
      local names = utils.search_names("www.example.com.", { ndots = 1 })
      assert.same(names, { "www.example.com." })
      -- name with 3 dots, and ndots=4 > 3
      local names = utils.search_names("www.example.com.", { ndots = 4 })
      assert.same(names, { "www.example.com." })
    end)

    it("name dots number >= ndots, not apply the search list", function ()
      local resolv = {
        ndots = 1,
        search = { "example.net" },
      }
      local names = utils.search_names("www.example.com", resolv)
      assert.same(names, { "www.example.com" })

      local names = utils.search_names("example.com", resolv)
      assert.same(names, { "example.com" })
    end)

    it("name dots number <= ndots, apply the search list", function ()
      local resolv = {
        ndots = 2,
        search = { "example.net" },
      }
      local names = utils.search_names("www", resolv)
      assert.same(names, { "www.example.net", "www" })

      local names = utils.search_names("www1.www2", resolv)
      assert.same(names, { "www1.www2.example.net", "www1.www2" })

      local names = utils.search_names("www1.www2.www3", resolv)
      assert.same(names, { "www1.www2.www3" })  -- not apply

      local resolv = {
        ndots = 2,
        search = { "example.net", "example.com" },
      }
      local names = utils.search_names("www", resolv)
      assert.same(names, { "www.example.net", "www.example.com", "www" })

      local names = utils.search_names("www1.www2", resolv)
      assert.same(names, { "www1.www2.example.net", "www1.www2.example.com", "www1.www2" })

      local names = utils.search_names("www1.www2.www3", resolv)
      assert.same(names, { "www1.www2.www3" })  -- not apply
    end)
  end)

  describe("round robin getion", function ()

    local function get_and_count(answers, n, get_ans)
      local count = {}
      for _ = 1, n do
        local answer = get_ans(answers)
        count[answer.target] = (count[answer.target] or 0) + 1
      end
      return count
    end

    it("rr", function ()
      local answers = {
        { target = "1" },   -- 25%
        { target = "2" },   -- 25%
        { target = "3" },   -- 25%
        { target = "4" },   -- 25%
      }
      local count = get_and_count(answers, 100, utils.get_rr_ans)
      assert.same(count, { ["1"] = 25, ["2"] = 25, ["3"] = 25, ["4"] = 25 })
    end)

    it("swrr", function ()
      -- simple one
      local answers = {
        { target = "w5-p10-a", weight = 5, priority = 10, },  -- hit 100%
      }
      local count = get_and_count(answers, 20, utils.get_wrr_ans)
      assert.same(count, { ["w5-p10-a"] = 20 })

      -- only get the lowest priority
      local answers = {
        { target = "w5-p10-a", weight = 5, priority = 10, },  -- hit 50%
        { target = "w5-p20", weight = 5, priority = 20, },    -- hit 0%
        { target = "w5-p10-b", weight = 5, priority = 10, },  -- hit 50%
        { target = "w0-p10", weight = 0, priority = 10, },    -- hit 0%
      }
      local count = get_and_count(answers, 20, utils.get_wrr_ans)
      assert.same(count, { ["w5-p10-a"] = 10, ["w5-p10-b"] = 10 })

      -- weight: 6, 3, 1
      local answers = {
        { target = "w6", weight = 6, priority = 10, },  -- hit 60%
        { target = "w3", weight = 3, priority = 10, },  -- hit 30%
        { target = "w1", weight = 1, priority = 10, },  -- hit 10%
      }
      local count = get_and_count(answers, 100 * 1000, utils.get_wrr_ans)
      assert.same(count, { ["w6"] = 60000, ["w3"] = 30000, ["w1"] = 10000 })

      -- random start
      _G.math.native_randomseed(9975098)  -- math.randomseed() ignores @seed
      local answers1 = {
        { target = "1", weight = 1, priority = 10, },
        { target = "2", weight = 1, priority = 10, },
        { target = "3", weight = 1, priority = 10, },
        { target = "4", weight = 1, priority = 10, },
      }
      local answers2 = {
        { target = "1", weight = 1, priority = 10, },
        { target = "2", weight = 1, priority = 10, },
        { target = "3", weight = 1, priority = 10, },
        { target = "4", weight = 1, priority = 10, },
      }

      local a1 = utils.get_wrr_ans(answers1)
      local a2 = utils.get_wrr_ans(answers2)
      assert.not_equal(a1.target, a2.target)

      -- weight 0 as 0.1
      local answers = {
        { target = "w0", weight = 0, priority = 10, },
        { target = "w1", weight = 1, priority = 10, },
        { target = "w2", weight = 0, priority = 10, },
        { target = "w3", weight = 0, priority = 10, },
      }
      local count = get_and_count(answers, 100, utils.get_wrr_ans)
      assert.same(count, { ["w0"] = 7, ["w1"] = 77, ["w2"] = 8, ["w3"] = 8 })

      -- weight 0 and lowest priority
      local answers = {
        { target = "w0-a", weight = 0, priority = 0, },
        { target = "w1", weight = 1, priority = 10, },  -- hit 0%
        { target = "w0-b", weight = 0, priority = 0, },
        { target = "w0-c", weight = 0, priority = 0, },
      }
      local count = get_and_count(answers, 100, utils.get_wrr_ans)
      assert.same(count["w1"], nil)

      -- all weights are 0
      local answers = {
        { target = "1", weight = 0, priority = 10, },
        { target = "2", weight = 0, priority = 10, },
        { target = "3", weight = 0, priority = 10, },
        { target = "4", weight = 0, priority = 10, },
      }
      local count = get_and_count(answers, 100, utils.get_wrr_ans)
      assert.same(count, { ["1"] = 25, ["2"] = 25, ["3"] = 25, ["4"] = 25 })
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
      local result, err = utils.parse_resolv_conf("non/existing/file")
      assert.is.Nil(result)
      assert.is.string(err)
    end)

    it("tests parsing when the 'resolv.conf' file is empty", function()
      local filename = tempfilename()
      writefile(filename, "")
      local resolv, err = utils.parse_resolv_conf(filename)
      os.remove(filename)
      assert.is.same({ ndots = 1, options = {} }, resolv)
      assert.is.Nil(err)
    end)

    it("tests parsing 'resolv.conf' with multiple comment types", function()
      local file = splitlines(
[[# this is just a comment line
# at the top of the file

domain myservice.com

nameserver 198.51.100.0
nameserver 2001:db8::1 ; and a comment here
nameserver 198.51.100.0:1234 ; this one has a port number (limited systems support this)
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
      local resolv, err = utils.parse_resolv_conf(file)
      assert.is.Nil(err)
      assert.is.equal("myservice.com", resolv.domain)
      assert.is.same({ "198.51.100.0", "2001:db8::1", "198.51.100.0:1234" }, resolv.nameserver)
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
      local resolv, err = utils.parse_resolv_conf(file)
      assert.is.Nil(err)
      assert.is.Nil(resolv.domain)
      assert.is.same({ "domaina.com", "domainb.com" }, resolv.search)
    end)

    it("tests parsing 'resolv.conf' with max search entries MAXSEARCH", function()
      local file = splitlines(
[[

search domain1.com domain2.com domain3.com domain4.com domain5.com domain6.com domain7.com

]])
      local resolv, err = utils.parse_resolv_conf(file)
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

nameserver 198.51.100.0
nameserver 198.51.100.1 ; and a comment here

options ndots:1
]])
      envvars.LOCALDOMAIN = "domaina.com domainb.com"
      envvars.RES_OPTIONS = "ndots:2 debug"

      local resolv, err = utils.parse_resolv_conf(file)
      assert.is.Nil(err)


      assert.is.Nil(resolv.domain)  -- must be nil, mutually exclusive
      assert.is.same({ "domaina.com", "domainb.com" }, resolv.search)

      assert.is.same({ ndots = 2, debug = true }, resolv.options)
    end)

    it("tests parsing 'resolv.conf' with non-existing environment variables", function()
      local file = splitlines(
[[# this is just a comment line
domain myservice.com

nameserver 198.51.100.0
nameserver 198.51.100.1 ; and a comment here

options ndots:2
]])
      envvars.LOCALDOMAIN = ""
      envvars.RES_OPTIONS = ""
      local resolv, err = utils.parse_resolv_conf(file)
      assert.is.Nil(err)
      assert.is.equals("myservice.com", resolv.domain)  -- must be nil, mutually exclusive
      assert.is.same({ ndots = 2 }, resolv.options)
    end)

    it("skip ipv6 nameservers with scopes", function()
      local file = splitlines(
[[# this is just a comment line
nameserver [fe80::1%enp0s20f0u1u1]
]])
      local resolv, err = utils.parse_resolv_conf(file)
      assert.is.Nil(err)
      assert.is.same({}, resolv.nameservers)
    end)

  end)

  describe("parsing 'hosts':", function()

    it("tests parsing when the 'hosts' file does not exist", function()
      local result, err = utils.parse_hosts("non/existing/file")
      assert.is.Nil(result)
      assert.is.string(err)
    end)

    it("tests parsing when the 'hosts' file is empty", function()
      local filename = tempfilename()
      writefile(filename, "")
      local reverse = utils.parse_hosts(filename)
      os.remove(filename)
      assert.is.same({}, reverse)
    end)

    it("tests parsing 'hosts'", function()
        local hostsfile = splitlines(
[[# The localhost entry should be in every HOSTS file and is used
# to point back to yourself.

127.0.0.1 # only ip address, this one will be ignored

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
      local reverse = utils.parse_hosts(hostsfile)
      assert.is.equal("127.0.0.1", reverse.localhost.ipv4)
      assert.is.equal("[::1]", reverse.localhost.ipv6)

      assert.is.equal("192.168.1.2", reverse["test.computer.com"].ipv4)

      assert.is.equal("192.168.1.3", reverse["ftp.computer.com"].ipv4)
      assert.is.equal("192.168.1.3", reverse["alias1"].ipv4)
      assert.is.equal("192.168.1.3", reverse["alias2"].ipv4)

      assert.is.equal("192.168.1.4", reverse["smtp.computer.com"].ipv4)
      assert.is.equal("192.168.1.4", reverse["alias3"].ipv4)

      assert.is.equal("192.168.1.4", reverse["smtp.computer.com"].ipv4)  -- .1.4; first one wins!
      assert.is.equal("192.168.1.4", reverse["alias3"].ipv4)   -- .1.4; first one wins!

      assert.is.equal("[::1]", reverse["alsolocalhost"].ipv6)
    end)
  end)
end)
