local utils = require "kong.tools.utils"

describe("Utils", function()

  describe("get_hostname()", function()
    it("should retrieve the hostname", function()
      assert.is_string(utils.get_hostname())
    end)
  end)

  describe("get_system_infos()", function()
    it("retrieves various host infos", function()
      local infos = utils.get_system_infos()
      assert.is_number(infos.cores)
      assert.is_string(infos.hostname)
      assert.is_string(infos.uname)
      assert.not_matches("\n$", infos.hostname)
      assert.not_matches("\n$", infos.uname)
    end)
    it("caches the result", function()
      assert.equal(
        utils.get_system_infos(),
        utils.get_system_infos()
      )
    end)
  end)

  describe("is_valid_uuid()", function()
    it("validates UUIDs from jit-uuid", function()
      assert.True (utils.is_valid_uuid("cbb297c0-a956-486d-ad1d-f9b42df9465a"))
      assert.False(utils.is_valid_uuid("cbb297c0-a956486d-ad1d-f9b42df9465a"))
    end)
    pending("invalidates UUIDs with invalid variants", function()
      -- this is disabled because existing uuids in the database fail the check upon migrations
      -- see https://github.com/thibaultcha/lua-resty-jit-uuid/issues/8
      assert.False(utils.is_valid_uuid("cbb297c0-a956-486d-dd1d-f9b42df9465a")) -- invalid variant
    end)
    it("validates UUIDs with invalid variants for backwards-compatibility reasons", function()
      -- See pending test just above  ^^
      -- see https://github.com/thibaultcha/lua-resty-jit-uuid/issues/8
      assert.True(utils.is_valid_uuid("cbb297c0-a956-486d-dd1d-f9b42df9465a"))
    end)
    it("considers the null UUID a valid one", function()
      -- we use the null UUID for plugins' consumer_id when none is set
      assert.True(utils.is_valid_uuid("00000000-0000-0000-0000-000000000000"))
    end)
  end)

  describe("https_check", function()
    local old_ngx
    local headers = {}

    setup(function()
      old_ngx = ngx
      _G.ngx = {
        var = {
          scheme = nil
        },
        req = {
          get_headers = function() return headers end
        }
      }
    end)

    teardown(function()
      _G.ngx = old_ngx
    end)

    describe("without X-Forwarded-Proto header", function()
      setup(function()
        headers["x-forwarded-proto"] = nil
      end)

      it("should validate an HTTPS scheme", function()
        ngx.var.scheme = "hTTps" -- mixed casing to ensure case insensitiveness
        assert.is.truthy(utils.check_https())
      end)

      it("should invalidate non-HTTPS schemes", function()
        ngx.var.scheme = "hTTp"
        assert.is.falsy(utils.check_https())
        ngx.var.scheme = "something completely different"
        assert.is.falsy(utils.check_https())
      end)

      it("should invalidate non-HTTPS schemes with proto header allowed", function()
        ngx.var.scheme = "hTTp"
        assert.is.falsy(utils.check_https(true))
      end)
    end)

    describe("with X-Forwarded-Proto header", function()

      teardown(function()
        headers["x-forwarded-proto"] = nil
      end)

      it("should validate any scheme with X-Forwarded_Proto as HTTPS", function()
        headers["x-forwarded-proto"] = "hTTPs"  -- check mixed casing for case insensitiveness
        ngx.var.scheme = "hTTps"
        assert.is.truthy(utils.check_https(true))
        ngx.var.scheme = "hTTp"
        assert.is.truthy(utils.check_https(true))
        ngx.var.scheme = "something completely different"
        assert.is.truthy(utils.check_https(true))
      end)

      it("should validate only https scheme with X-Forwarded_Proto as non-HTTPS", function()
        headers["x-forwarded-proto"] = "hTTP"
        ngx.var.scheme = "hTTps"
        assert.is.truthy(utils.check_https(true))
        ngx.var.scheme = "hTTp"
        assert.is.falsy(utils.check_https(true))
        ngx.var.scheme = "something completely different"
        assert.is.falsy(utils.check_https(true))
      end)

      it("should return an error with multiple X-Forwarded_Proto headers", function()
        headers["x-forwarded-proto"] = { "hTTP", "https" }
        ngx.var.scheme = "hTTps"
        assert.is.truthy(utils.check_https(true))
        ngx.var.scheme = "hTTp"
        assert.are.same({ nil, "Only one X-Forwarded-Proto header allowed" }, { utils.check_https(true) })
      end)
    end)
  end)

  describe("string", function()
    it("checks valid UTF8 values", function()
      assert.True(utils.validate_utf8("hello"))
      assert.True(utils.validate_utf8(123))
      assert.True(utils.validate_utf8(true))
      assert.False(utils.validate_utf8(string.char(105, 213, 205, 149)))
    end)
    describe("random_string()", function()
      it("should return a random string", function()
        local first = utils.random_string()
        assert.truthy(first)
        assert.falsy(first:find("-"))

        local second = utils.random_string()
        assert.not_equal(first, second)
      end)
    end)

    describe("encode_args()", function()
      it("should encode a Lua table to a querystring", function()
        local str = utils.encode_args {
          foo = "bar",
          hello = "world"
        }
        assert.equal("foo=bar&hello=world", str)
      end)
      it("should encode multi-value query args", function()
        local str = utils.encode_args {
          foo = {"bar", "zoo"},
          hello = "world"
        }
        assert.equal("foo=bar&foo=zoo&hello=world", str)
      end)
      it("should percent-encode given values", function()
        local str = utils.encode_args {
          encode = {"abc|def", ",$@|`"}
        }
        assert.equal("encode=abc%7cdef&encode=%2c%24%40%7c%60", str)
      end)
      it("should percent-encode given query args keys", function()
        local str = utils.encode_args {
          ["hello world"] = "foo"
        }
        assert.equal("hello%20world=foo", str)
      end)
      it("should support Lua numbers", function()
        local str = utils.encode_args {
          a = 1,
          b = 2
        }
        assert.equal("a=1&b=2", str)
      end)
      it("should support a boolean argument", function()
        local str = utils.encode_args {
          a = true,
          b = 1
        }
        assert.equal("a&b=1", str)
      end)
      it("should ignore nil and false values", function()
        local str = utils.encode_args {
          a = nil,
          b = false
        }
        assert.equal("", str)
      end)
      it("should encode complex query args", function()
        local str = utils.encode_args {
          multiple = {"hello, world"},
          hello = "world",
          ignore  = false,
          ["multiple values"] = true
        }
        assert.equal("hello=world&multiple=hello%2c%20world&multiple%20values", str)
      end)
      it("should not interpret the `%` character followed by 2 characters in the [0-9a-f] group as an hexadecimal value", function()
        local str = utils.encode_args {
          foo = "%bar%"
        }
        assert.equal("foo=%25bar%25", str)
      end)
      it("should not percent-encode if given a `raw` option", function()
        -- this is useful for kong.tools.http_client
        local str = utils.encode_args({
          ["hello world"] = "foo, bar"
        }, true)
        assert.equal("hello world=foo, bar", str)
      end)
      -- while this method's purpose is to mimic 100% the behavior of ngx.encode_args,
      -- it is also used by Kong specs' http_client, to encode both querystrings and *bodies*.
      -- Hence, a `raw` parameter allows encoding for bodies.
      describe("raw", function()
        it("should not percent-encode values", function()
          local str = utils.encode_args({
            foo = "hello world"
          }, true)
          assert.equal("foo=hello world", str)
        end)
        it("should not percent-encode keys", function()
          local str = utils.encode_args({
            ["hello world"] = "foo"
          }, true)
          assert.equal("hello world=foo", str)
        end)
        it("should plainly include true and false values", function()
          local str = utils.encode_args({
            a = true,
            b = false
          }, true)
          assert.equal("a=true&b=false", str)
        end)
        it("should prevent double percent-encoding", function()
          local str = utils.encode_args({
            foo = "hello%20world"
          }, true)
          assert.equal("foo=hello%20world", str)
        end)
      end)
    end)
  end)

  describe("table", function()
    describe("table_contains()", function()
      it("should return false if a value is not contained in a nil table", function()
        assert.False(utils.table_contains(nil, "foo"))
      end)
      it("should return true if a value is contained in a table", function()
        local t = { foo = "hello", bar = "world" }
        assert.True(utils.table_contains(t, "hello"))
      end)
      it("should return false if a value is not contained in a table", function()
        local t = { foo = "hello", bar = "world" }
        assert.False(utils.table_contains(t, "foo"))
      end)
    end)

    describe("is_array()", function()
      it("should know when an array ", function()
        assert.True(utils.is_array({ "a", "b", "c", "d" }))
        assert.True(utils.is_array({ ["1"] = "a", ["2"] = "b", ["3"] = "c", ["4"] = "d" }))
        assert.False(utils.is_array({ "a", "b", "c", foo = "d" }))
        assert.False(utils.is_array())
        assert.False(utils.is_array(false))
        assert.False(utils.is_array(true))
      end)
    end)

    describe("add_error()", function()
      local add_error = utils.add_error

      it("should create a table if given `errors` is nil", function()
        assert.same({hello = "world"}, add_error(nil, "hello", "world"))
      end)
      it("should add a key/value when the key does not exists", function()
        local errors = {hello = "world"}
        assert.same({
          hello = "world",
          foo = "bar"
        }, add_error(errors, "foo", "bar"))
      end)
      it("should transform previous values to a list if the same key is given again", function()
        local e = nil -- initialize for luacheck
        e = add_error(e, "key1", "value1")
        e = add_error(e, "key2", "value2")
        assert.same({key1 = "value1", key2 = "value2"}, e)

        e = add_error(e, "key1", "value3")
        e = add_error(e, "key1", "value4")
        assert.same({key1 = {"value1", "value3", "value4"}, key2 = "value2"}, e)

        e = add_error(e, "key1", "value5")
        e = add_error(e, "key1", "value6")
        e = add_error(e, "key2", "value7")
        assert.same({key1 = {"value1", "value3", "value4", "value5", "value6"}, key2 = {"value2", "value7"}}, e)
      end)
      it("should also list tables pushed as errors", function()
        local e = nil -- initialize for luacheck
        e = add_error(e, "key1", "value1")
        e = add_error(e, "key2", "value2")
        e = add_error(e, "key1", "value3")
        e = add_error(e, "key1", "value4")

        e = add_error(e, "keyO", {message = "some error"})
        e = add_error(e, "keyO", {message = "another"})

        assert.same({
          key1 = {"value1", "value3", "value4"},
          key2 = "value2",
          keyO = {{message = "some error"}, {message = "another"}}
        }, e)
      end)
    end)

    describe("load_module_if_exists()", function()
      it("should return false if the module does not exist", function()
        local loaded, mod
        assert.has_no.errors(function()
          loaded, mod = utils.load_module_if_exists("kong.does.not.exist")
        end)
        assert.False(loaded)
        assert.is.string(mod)
      end)
      it("should throw an error if the module is invalid", function()
        assert.has.errors(function()
          utils.load_module_if_exists("spec.fixtures.invalid-module")
        end)
      end)
      it("should load a module if it was found and valid", function()
        local loaded, mod
        assert.has_no.errors(function()
          loaded, mod = utils.load_module_if_exists("spec.fixtures.valid-module")
        end)
        assert.True(loaded)
        assert.truthy(mod)
        assert.are.same("All your base are belong to us.", mod.exposed)
      end)
    end)
  end)

  describe("hostnames and ip addresses", function()
    describe("hostname_type", function()
      -- no check on "name" type as anything not ipv4 and not ipv6 will be labelled as 'name' anyway
      it("checks valid IPv4 address types", function()
        assert.are.same("ipv4", utils.hostname_type("123.123.123.123"))
        assert.are.same("ipv4", utils.hostname_type("1.2.3.4"))
      end)
      it("checks valid IPv6 address types", function()
        assert.are.same("ipv6", utils.hostname_type("::1"))
        assert.are.same("ipv6", utils.hostname_type("2345::6789"))
        assert.are.same("ipv6", utils.hostname_type("0001:0001:0001:0001:0001:0001:0001:0001"))
      end)
    end)
    describe("parsing", function()
      it("normalizes IPv4 address types", function()
        assert.are.same({"123.123.123.123"}, {utils.normalize_ipv4("123.123.123.123")})
        assert.are.same({"123.123.123.123", 80}, {utils.normalize_ipv4("123.123.123.123:80")})
        assert.are.same({"1.1.1.1"}, {utils.normalize_ipv4("1.1.1.1")})
        assert.are.same({"1.1.1.1", 80}, {utils.normalize_ipv4("001.001.001.001:00080")})
      end)
      it("fails normalizing bad IPv4 address types", function()
        assert.is_nil(utils.normalize_ipv4("123.123:80"))
        assert.is_nil(utils.normalize_ipv4("123.123.123.999"))
        assert.is_nil(utils.normalize_ipv4("123.123.123.123:80a"))
        assert.is_nil(utils.normalize_ipv4("123.123.123.123.123:80"))
        assert.is_nil(utils.normalize_ipv4("localhost:80"))
        assert.is_nil(utils.normalize_ipv4("[::1]:80"))
      end)
      it("normalizes IPv6 address types", function()
        assert.are.same({"0000:0000:0000:0000:0000:0000:0000:0001"}, {utils.normalize_ipv6("::1")})
        assert.are.same({"0000:0000:0000:0000:0000:0000:0000:0001"}, {utils.normalize_ipv6("[::1]")})
        assert.are.same({"0000:0000:0000:0000:0000:0000:0000:0001", 80}, {utils.normalize_ipv6("[::1]:80")})
        assert.are.same({"0000:0000:0000:0000:0000:0000:0000:0001", 80}, {utils.normalize_ipv6("[0000:0000:0000:0000:0000:0000:0000:0001]:80")})
      end)
      it("fails normalizing bad IPv6 address types", function()
        assert.is_nil(utils.normalize_ipv6("123.123.123.123"))
        assert.is_nil(utils.normalize_ipv6("localhost:80"))
        assert.is_nil(utils.normalize_ipv6("::x"))
        assert.is_nil(utils.normalize_ipv6("[::x]:80"))
        assert.is_nil(utils.normalize_ipv6("[::1]:80a"))
        assert.is_nil(utils.normalize_ipv6("1"))
      end)
      it("validates hostnames", function()
        local valids = {"hello.com", "hello.fr", "test.hello.com", "1991.io", "hello.COM",
                        "HELLO.com", "123helloWORLD.com", "mockbin.123", "mockbin-api.com",
                        "hello.abcd", "mockbin_api.com", "localhost",
                        -- punycode examples from RFC3492; https://tools.ietf.org/html/rfc3492#page-14
                        -- specifically the japanese ones as they mix ascii with escaped characters
                        "3B-ww4c5e180e575a65lsy2b", "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n",
                        "Hello-Another-Way--fc4qua05auwb3674vfr0b", "2-u9tlzr9756bt3uc0v",
                        "MajiKoi5-783gue6qz075azm5e", "de-jg4avhby1noc0d", "d9juau41awczczp",
                        }
        local invalids = {"/mockbin", ".mockbin", "mockbin.", "mock;bin",
                          "mockbin.com/org",
                          "mockbin-.org", "mockbin.org-",
                          "hello..mockbin.com", "hello-.mockbin.com"}
        for _, name in ipairs(valids) do
          assert.are.same(name, (utils.check_hostname(name)))
        end
        for _, name in ipairs(valids) do
          assert.are.same({ [1] = name, [2] = 80}, { utils.check_hostname(name..":80")})
        end
        for _, name in ipairs(valids) do
          assert.is_nil((utils.check_hostname(name..":xx")))
        end
        for _, name in ipairs(invalids) do
          assert.is_nil((utils.check_hostname(name)))
          assert.is_nil((utils.check_hostname(name..":80")))
        end
      end)
      it("validates addresses", function()
        assert.are.same({host = "1.2.3.4", type = "ipv4", port = 80}, utils.normalize_ip("1.2.3.4:80"))
        assert.are.same({host = "1.2.3.4", type = "ipv4", port = nil}, utils.normalize_ip("1.2.3.4"))
        assert.are.same({host = "0000:0000:0000:0000:0000:0000:0000:0001", type = "ipv6", port = 80}, utils.normalize_ip("[::1]:80"))
        assert.are.same({host = "0000:0000:0000:0000:0000:0000:0000:0001", type = "ipv6", port = nil}, utils.normalize_ip("::1"))
        assert.are.same({host = "localhost", type = "name", port = 80}, utils.normalize_ip("localhost:80"))
        assert.are.same({host = "mashape.com", type = "name", port = nil}, utils.normalize_ip("mashape.com"))
      
        assert.is_nil((utils.normalize_ip("1.2.3.4:8x0")))
        assert.is_nil((utils.normalize_ip("1.2.3.400")))
        assert.is_nil((utils.normalize_ip("[::1]:8x0")))
        assert.is_nil((utils.normalize_ip(":x:1")))
        assert.is_nil((utils.normalize_ip("localhost:8x0")))
        assert.is_nil((utils.normalize_ip("mashape..com")))
      end)
    end)
    describe("formatting", function()
      it("correctly formats addresses", function()
        assert.are.equal("1.2.3.4", utils.format_host("1.2.3.4"))
        assert.are.equal("1.2.3.4:80", utils.format_host("1.2.3.4", 80))
        assert.are.equal("[::1]", utils.format_host("::1"))
        assert.are.equal("[::1]:80", utils.format_host("::1", 80))
        assert.are.equal("localhost", utils.format_host("localhost"))
        assert.are.equal("mashape.com:80", utils.format_host("mashape.com", 80))
        -- passthrough (string)
        assert.are.equal("1.2.3.4", utils.format_host(utils.normalize_ipv4("1.2.3.4")))
        assert.are.equal("1.2.3.4:80", utils.format_host(utils.normalize_ipv4("1.2.3.4:80")))
        assert.are.equal("[0000:0000:0000:0000:0000:0000:0000:0001]", utils.format_host(utils.normalize_ipv6("::1")))
        assert.are.equal("[0000:0000:0000:0000:0000:0000:0000:0001]:80", utils.format_host(utils.normalize_ipv6("[::1]:80")))
        assert.are.equal("localhost", utils.format_host(utils.check_hostname("localhost")))
        assert.are.equal("mashape.com:80", utils.format_host(utils.check_hostname("mashape.com:80")))
        -- passthrough general (table)
        assert.are.equal("1.2.3.4", utils.format_host(utils.normalize_ip("1.2.3.4")))
        assert.are.equal("1.2.3.4:80", utils.format_host(utils.normalize_ip("1.2.3.4:80")))
        assert.are.equal("[0000:0000:0000:0000:0000:0000:0000:0001]", utils.format_host(utils.normalize_ip("::1")))
        assert.are.equal("[0000:0000:0000:0000:0000:0000:0000:0001]:80", utils.format_host(utils.normalize_ip("[::1]:80")))
        assert.are.equal("localhost", utils.format_host(utils.normalize_ip("localhost")))
        assert.are.equal("mashape.com:80", utils.format_host(utils.normalize_ip("mashape.com:80")))
        -- passthrough errors
        local one, two = utils.format_host(utils.normalize_ipv4("1.2.3.4.5"))
        assert.are.equal("nilstring", type(one)..type(two))
        local one, two = utils.format_host(utils.normalize_ipv6("not ipv6 ..."))
        assert.are.equal("nilstring", type(one)..type(two))
        local one, two = utils.format_host(utils.check_hostname("//bad..name\\:123"))
        assert.are.equal("nilstring", type(one)..type(two))
        local one, two = utils.format_host(utils.normalize_ip("m a s h a p e.com:80"))
        assert.are.equal("nilstring", type(one)..type(two))
      end)
    end)
  end)
  
end)
