local utils = require "kong.tools.utils"
local pl_path = require "pl.path"

describe("Utils", function()

  describe("get_system_infos()", function()
    it("retrieves various host infos", function()
      local infos = utils.get_system_infos()
      assert.is_number(infos.cores)
      assert.is_string(infos.uname)
      assert.not_matches("\n$", infos.uname)
    end)
    it("caches the result", function()
      assert.equal(
        utils.get_system_infos(),
        utils.get_system_infos()
      )
    end)
  end)

  describe("get_system_trusted_certs_filepath()", function()
    local old_exists = pl_path.exists
    after_each(function()
      pl_path.exists = old_exists
    end)
    local tests = {
      Debian = "/etc/ssl/certs/ca-certificates.crt",
      Fedora = "/etc/pki/tls/certs/ca-bundle.crt",
      OpenSuse = "/etc/ssl/ca-bundle.pem",
      OpenElec = "/etc/pki/tls/cacert.pem",
      CentOS = "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",
      Alpine = "/etc/ssl/cert.pem",
    }

    for distro, test_path in pairs(tests) do
      it("retrieves the default filepath in " .. distro, function()
        pl_path.exists = function(path)
          return path == test_path
        end
        assert.same(test_path, utils.get_system_trusted_certs_filepath())
      end)
    end

    it("errors if file is somewhere else", function()
      pl_path.exists = function(path)
        return path == "/some/unknown/location.crt"
      end

      local ok, err = utils.get_system_trusted_certs_filepath()
      assert.is_nil(ok)
      assert.matches("Could not find trusted certs file", err)
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

    lazy_setup(function()
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

    lazy_teardown(function()
      _G.ngx = old_ngx
    end)

    describe("without X-Forwarded-Proto header", function()
      lazy_setup(function()
        headers["x-forwarded-proto"] = nil
      end)

      it("should validate an HTTPS scheme", function()
        ngx.var.scheme = "hTTps" -- mixed casing to ensure case insensitiveness
        assert.is.truthy(utils.check_https(true, false))
      end)

      it("should invalidate non-HTTPS schemes", function()
        ngx.var.scheme = "hTTp"
        assert.is.falsy(utils.check_https(true, false))
        ngx.var.scheme = "something completely different"
        assert.is.falsy(utils.check_https(true, false))
      end)

      it("should invalidate non-HTTPS schemes with proto header allowed", function()
        ngx.var.scheme = "hTTp"
        assert.is.falsy(utils.check_https(true, true))
      end)
    end)

    describe("with X-Forwarded-Proto header", function()

      lazy_teardown(function()
        headers["x-forwarded-proto"] = nil
      end)

      it("should validate any scheme with X-Forwarded_Proto as HTTPS", function()
        headers["x-forwarded-proto"] = "hTTPs"  -- check mixed casing for case insensitiveness
        ngx.var.scheme = "hTTps"
        assert.is.truthy(utils.check_https(true, true))
        ngx.var.scheme = "hTTp"
        assert.is.truthy(utils.check_https(true, true))
        ngx.var.scheme = "something completely different"
        assert.is.truthy(utils.check_https(true, true))
      end)

      it("should validate only https scheme with X-Forwarded_Proto as non-HTTPS", function()
        headers["x-forwarded-proto"] = "hTTP"
        ngx.var.scheme = "hTTps"
        assert.is.truthy(utils.check_https(true, true))
        ngx.var.scheme = "hTTp"
        assert.is.falsy(utils.check_https(true, true))
        ngx.var.scheme = "something completely different"
        assert.is.falsy(utils.check_https(true, true))
      end)

      it("should return an error with multiple X-Forwarded_Proto headers", function()
        headers["x-forwarded-proto"] = { "hTTP", "https" }
        ngx.var.scheme = "hTTps"
        assert.is.truthy(utils.check_https(true, true))
        ngx.var.scheme = "hTTp"
        assert.are.same({ nil, "Only one X-Forwarded-Proto header allowed" },
                        { utils.check_https(true, true) })
      end)

      it("should not use X-Forwarded-Proto when the client is untrusted", function()
        headers["x-forwarded-proto"] = "https"
        ngx.var.scheme = "http"
        assert.is_false(utils.check_https(false, false))
        assert.is_false(utils.check_https(false, true))

        headers["x-forwarded-proto"] = "https"
        ngx.var.scheme = "https"
        assert.is_true(utils.check_https(false, false))
        assert.is_true(utils.check_https(false, true))
      end)

      it("should use X-Forwarded-Proto when the client is trusted", function()
        headers["x-forwarded-proto"] = "https"
        ngx.var.scheme = "http"

        -- trusted client but do not allow terminated
        assert.is_false(utils.check_https(true, false))

        assert.is_true(utils.check_https(true, true))

        headers["x-forwarded-proto"] = "https"
        ngx.var.scheme = "https"
        assert.is_true(utils.check_https(true, false))
        assert.is_true(utils.check_https(true, true))
      end)
    end)
  end)

  describe("string", function()
    it("checks valid UTF8 values", function()
      assert.True(utils.validate_utf8("hello"))
      assert.True(utils.validate_utf8(123))
      assert.True(utils.validate_utf8(true))
      assert.False(utils.validate_utf8(string.char(105, 213, 205, 149)))
      assert.False(utils.validate_utf8(string.char(128))) -- unexpected continuation byte
      assert.False(utils.validate_utf8(string.char(192, 32))) -- 2-byte sequence 0xc0 followed by space
      assert.False(utils.validate_utf8(string.char(192))) -- 2-byte sequence with last byte missing
      assert.False(utils.validate_utf8(string.char(254))) -- impossible byte
      assert.False(utils.validate_utf8(string.char(255))) -- impossible byte
      assert.False(utils.validate_utf8(string.char(237, 160, 128))) -- Single UTF-16 surrogate
    end)
    describe("random_string()", function()
      it("should return a random string", function()
        local first = utils.random_string()
        assert.is_string(first)

        -- build the same length string as previous implementations
        assert.equals(32, #first)

        -- ensure we don't find anything that isnt alphanumeric
        assert.not_matches("^[^%a%d]+$", first)

        -- at some point in the universe this test will fail ;)
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
        assert.equal("foo%5b1%5d=bar&foo%5b2%5d=zoo&hello=world", str)
      end)
      it("should percent-encode given values", function()
        local str = utils.encode_args {
          encode = {"abc|def", ",$@|`"}
        }
        assert.equal("encode%5b1%5d=abc%7cdef&encode%5b2%5d=%2c%24%40%7c%60", str)
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
        assert.equal("a=true&b=1", str)
      end)
      it("should ignore nil and false values", function()
        local str = utils.encode_args {
          a = nil,
          b = false
        }
        assert.equal("b=false", str)
      end)
      it("should encode complex query args", function()
        local encode = utils.encode_args
        assert.equal("falsy=false",
                     encode({ falsy = false }))
        assert.equal("multiple%20values=true",
                     encode({ ["multiple values"] = true }))
        assert.equal("array%5b1%5d=hello%2c%20world",
                     encode({ array = {"hello, world"} }))
        assert.equal("hash%2eanswer=42",
                     encode({ hash = { answer = 42 } }))
        assert.equal("hash_array%2earr%5b1%5d=one&hash_array%2earr%5b2%5d=two",
                     encode({ hash_array = { arr = { "one", "two" } } }))
        assert.equal("array_hash%5b1%5d%2ename=peter",
                     encode({ array_hash = { { name = "peter" } } }))
        assert.equal("array_array%5b1%5d%5b1%5d=x&array_array%5b1%5d%5b2%5d=y",
                     encode({ array_array = { { "x", "y" } } }))
        assert.equal("hybrid%5b1%5d=1&hybrid%5b2%5d=2&hybrid%2en=3",
                     encode({ hybrid = { 1, 2, n = 3 } }))
      end)
      it("should not interpret the `%` character followed by 2 characters in the [0-9a-f] group as an hexadecimal value", function()
        local str = utils.encode_args {
          foo = "%bar%"
        }
        assert.equal("foo=%25bar%25", str)
      end)
      it("does not percent-encode if given a `raw` option", function()
        local encode = utils.encode_args
        -- this is useful for kong.tools.http_client
        assert.equal("hello world=foo, bar",
                     encode({ ["hello world"] = "foo, bar" }, true))
        assert.equal("hash.answer=42",
                     encode({ hash = { answer = 42 } }, true))
        assert.equal("hash_array.arr[1]=one&hash_array.arr[2]=two",
                     encode({ hash_array = { arr = { "one", "two" } } }, true))
        assert.equal("array_hash[1].name=peter",
                     encode({ array_hash = { { name = "peter" } } }, true))
        assert.equal("array_array[1][1]=x&array_array[1][2]=y",
                     encode({ array_array = { { "x", "y" } } }, true))
        assert.equal("hybrid[1]=1&hybrid[2]=2&hybrid.n=3",
                     encode({ hybrid = { 1, 2, n = 3 } }, true))
      end)
      it("does not include index numbers in arrays if given the `no_array_indexes` flag", function()
        local encode = utils.encode_args
        assert.equal("falsy=false",
                     encode({ falsy = false }, nil, true))
        assert.equal("multiple%20values=true",
                     encode({ ["multiple values"] = true }, nil, true))
        assert.equal("array%5b%5d=hello%2c%20world",
                     encode({ array = {"hello, world"} }, nil, true))
        assert.equal("hash%2eanswer=42",
                     encode({ hash = { answer = 42 } }, nil, true))
        assert.equal("hash_array%2earr%5b%5d=one&hash_array%2earr%5b%5d=two",
                     encode({ hash_array = { arr = { "one", "two" } } }, nil, true))
        assert.equal("array_hash%5b%5d%2ename=peter",
                     encode({ array_hash = { { name = "peter" } } }, nil, true))
        assert.equal("array_array%5b%5d%5b%5d=x&array_array%5b%5d%5b%5d=y",
                     encode({ array_array = { { "x", "y" } } }, nil, true))
        assert.equal("hybrid%5b%5d=1&hybrid%5b%5d=2&hybrid%2en=3",
                     encode({ hybrid = { 1, 2, n = 3 } }, nil, true))
      end)
      it("does not percent-encode and does not add index numbers if both `raw` and `no_array_indexes` are active", function()
        local encode = utils.encode_args
        -- this is useful for kong.tools.http_client
        assert.equal("hello world=foo, bar",
                     encode({ ["hello world"] = "foo, bar" }, true, true))
        assert.equal("hash.answer=42",
                     encode({ hash = { answer = 42 } }, true, true))
        assert.equal("hash_array.arr[]=one&hash_array.arr[]=two",
                     encode({ hash_array = { arr = { "one", "two" } } }, true, true))
        assert.equal("array_hash[].name=peter",
                     encode({ array_hash = { { name = "peter" } } }, true, true))
        assert.equal("array_array[][]=x&array_array[][]=y",
                     encode({ array_array = { { "x", "y" } } }, true, true))
        assert.equal("hybrid[]=1&hybrid[]=2&hybrid.n=3",
                     encode({ hybrid = { 1, 2, n = 3 } }, true, true))
      end)
      it("transforms ngx.null into empty string", function()
        local str = utils.encode_args({ x = ngx.null, y = "foo" })
        assert.equal("x=&y=foo", str)
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
      it("should know when an array (strict)", function()
        assert.True(utils.is_array({ "a", "b", "c", "d" }))
        assert.False(utils.is_array({ "a", "b", nil, "c", "d" }))
        assert.False(utils.is_array({ [-1] = "a", [0] = "b", [1] = "c", [2] = "d" }))
        assert.False(utils.is_array({ [0] = "a", [1] = "b", [2] = "c", [3] = "d" }))
        assert.True(utils.is_array({ [1] = "a", [2] = "b", [3] = "c", [4] = "d" }))
        assert.True(utils.is_array({ [1.0] = "a", [2.0] = "b", [3.0] = "c", [4.0] = "d" }))
        assert.False(utils.is_array({ [1] = "a", [2] = "b", nil, [3] = "c", [4] = "d" })) --luacheck: ignore
        assert.False(utils.is_array({ [1] = "a", [2] = "b", nil, [4] = "c", [5] = "d" })) --luacheck: ignore
        assert.False(utils.is_array({ [1.1] = "a", [2.1] = "b", [3.1] = "c", [4.1] = "d" }))
        assert.False(utils.is_array({ ["1"] = "a", ["2"] = "b", ["3"] = "c", ["4"] = "d" }))
        assert.False(utils.is_array({ "a", "b", "c", foo = "d" }))
        assert.False(utils.is_array())
        assert.False(utils.is_array(false))
        assert.False(utils.is_array(true))
      end)

      it("should know when an array (fast)", function()
        assert.True(utils.is_array({ "a", "b", "c", "d" }, "fast"))
        assert.True(utils.is_array({ "a", "b", nil, "c", "d" }, "fast"))
        assert.True(utils.is_array({ [-1] = "a", [0] = "b", [1] = "c", [2] = "d" }, "fast"))
        assert.True(utils.is_array({ [0] = "a", [1] = "b", [2] = "c", [3] = "d" }, "fast"))
        assert.True(utils.is_array({ [1] = "a", [2] = "b", [3] = "c", [4] = "d" }, "fast"))
        assert.True(utils.is_array({ [1.0] = "a", [2.0] = "b", [3.0] = "c", [4.0] = "d" }, "fast"))
        assert.True(utils.is_array({ [1] = "a", [2] = "b", nil, [3] = "c", [4] = "d" }, "fast")) --luacheck: ignore
        assert.True(utils.is_array({ [1] = "a", [2] = "b", nil, [4] = "c", [5] = "d" }, "fast")) --luacheck: ignore
        assert.False(utils.is_array({ [1.1] = "a", [2.1] = "b", [3.1] = "c", [4.1] = "d" }, "fast"))
        assert.False(utils.is_array({ ["1"] = "a", ["2"] = "b", ["3"] = "c", ["4"] = "d" }, "fast"))
        assert.False(utils.is_array({ "a", "b", "c", foo = "d" }, "fast"))
        assert.False(utils.is_array(nil, "fast"))
        assert.False(utils.is_array(false, "fast"))
        assert.False(utils.is_array(true, "fast"))
      end)

      it("should know when an array (lapis)", function()
        assert.True(utils.is_array({ "a", "b", "c", "d" }, "lapis"))
        assert.False(utils.is_array({ "a", "b", nil, "c", "d" }, "lapis"))
        assert.False(utils.is_array({ [-1] = "a", [0] = "b", [1] = "c", [2] = "d" }, "lapis"))
        assert.False(utils.is_array({ [0] = "a", [1] = "b", [2] = "c", [3] = "d" }, "lapis"))
        assert.True(utils.is_array({ [1] = "a", [2] = "b", [3] = "c", [4] = "d" }, "lapis"))
        assert.True(utils.is_array({ [1.0] = "a", [2.0] = "b", [3.0] = "c", [4.0] = "d" }, "lapis"))
        assert.False(utils.is_array({ [1] = "a", [2] = "b", nil, [3] = "c", [4] = "d" }, "lapis")) --luacheck: ignore
        assert.False(utils.is_array({ [1] = "a", [2] = "b", nil, [4] = "c", [5] = "d" }, "lapis")) --luacheck: ignore
        assert.False(utils.is_array({ [1.1] = "a", [2.1] = "b", [3.1] = "c", [4.1] = "d" }, "lapis"))
        assert.True(utils.is_array({ ["1"] = "a", ["2"] = "b", ["3"] = "c", ["4"] = "d" }, "lapis"))
        assert.False(utils.is_array({ "a", "b", "c", foo = "d" }, "lapis"))
        assert.False(utils.is_array(nil, "lapis"))
        assert.False(utils.is_array(false, "lapis"))
        assert.False(utils.is_array(true, "lapis"))
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
      local load_module_if_exists = require "kong.tools.module".load_module_if_exists

      it("should return false if the module does not exist", function()
        local loaded, mod
        assert.has_no.errors(function()
          loaded, mod = load_module_if_exists("kong.does.not.exist")
        end)
        assert.False(loaded)
        assert.is.string(mod)
      end)
      it("should throw an error with a traceback if the module is invalid", function()
        local pok, perr = pcall(load_module_if_exists, "spec.fixtures.invalid-module")
        assert.falsy(pok)
        assert.match("error loading module 'spec.fixtures.invalid-module'", perr, 1, true)
        assert.match("./spec/fixtures/invalid-module.lua:", perr, 1, true)
      end)
      it("should load a module if it was found and valid", function()
        local loaded, mod
        assert.has_no.errors(function()
          loaded, mod = load_module_if_exists("spec.fixtures.valid-module")
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
        assert.are.same("ipv4", utils.hostname_type("1.2.3.4:80"))
      end)
      it("checks valid IPv6 address types", function()
        assert.are.same("ipv6", utils.hostname_type("::1"))
        assert.are.same("ipv6", utils.hostname_type("2345::6789"))
        assert.are.same("ipv6", utils.hostname_type("0001:0001:0001:0001:0001:0001:0001:0001"))
        assert.are.same("ipv6", utils.hostname_type("[2345::6789]:80"))
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
        assert.is_nil(utils.normalize_ipv4("123.123.123.123:99999"))
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
        assert.is_nil(utils.normalize_ipv6("[::1]:99999"))
      end)
      it("validates hostnames", function()
        local valids = {"hello.com", "hello.fr", "test.hello.com", "1991.io", "hello.COM",
                        "HELLO.com", "123helloWORLD.com", "example.123", "example-api.com",
                        "hello.abcd", "example_api.com", "localhost", "example.",
                        -- punycode examples from RFC3492; https://tools.ietf.org/html/rfc3492#page-14
                        -- specifically the japanese ones as they mix ascii with escaped characters
                        "3B-ww4c5e180e575a65lsy2b", "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n",
                        "Hello-Another-Way--fc4qua05auwb3674vfr0b", "2-u9tlzr9756bt3uc0v",
                        "MajiKoi5-783gue6qz075azm5e", "de-jg4avhby1noc0d", "d9juau41awczczp",
                        }
        local invalids = {"/example", ".example", "exam;ple",
                          "example.com/org",
                          "example-.org", "example.org-",
                          "hello..example.com", "hello-.example.com",
                         }
        for _, name in ipairs(valids) do
          assert.are.same(name, (utils.check_hostname(name)))
        end
        for _, name in ipairs(valids) do
          assert.are.same({ [1] = name, [2] = 80}, { utils.check_hostname(name .. ":80")})
        end
        for _, name in ipairs(valids) do
          assert.is_nil((utils.check_hostname(name .. ":xx")))
          assert.is_nil((utils.check_hostname(name .. ":99999")))
        end
        for _, name in ipairs(invalids) do
          assert.is_nil((utils.check_hostname(name)))
          assert.is_nil((utils.check_hostname(name .. ":80")))
        end
      end)
      it("validates addresses", function()
        assert.are.same({host = "1.2.3.4", type = "ipv4", port = 80}, utils.normalize_ip("1.2.3.4:80"))
        assert.are.same({host = "1.2.3.4", type = "ipv4", port = nil}, utils.normalize_ip("1.2.3.4"))
        assert.are.same({host = "0000:0000:0000:0000:0000:0000:0000:0001", type = "ipv6", port = 80}, utils.normalize_ip("[::1]:80"))
        assert.are.same({host = "0000:0000:0000:0000:0000:0000:0000:0001", type = "ipv6", port = nil}, utils.normalize_ip("::1"))
        assert.are.same({host = "localhost", type = "name", port = 80}, utils.normalize_ip("localhost:80"))
        assert.are.same({host = "mashape.test", type = "name", port = nil}, utils.normalize_ip("mashape.test"))

        assert.is_nil((utils.normalize_ip("1.2.3.4:8x0")))
        assert.is_nil((utils.normalize_ip("1.2.3.400")))
        assert.is_nil((utils.normalize_ip("[::1]:8x0")))
        assert.is_nil((utils.normalize_ip(":x:1")))
        assert.is_nil((utils.normalize_ip("localhost:8x0")))
        assert.is_nil((utils.normalize_ip("mashape..test")))
      end)
    end)
    describe("formatting", function()
      it("correctly formats addresses", function()
        assert.are.equal("1.2.3.4", utils.format_host("1.2.3.4"))
        assert.are.equal("1.2.3.4:80", utils.format_host("1.2.3.4", 80))
        assert.are.equal("[0000:0000:0000:0000:0000:0000:0000:0001]", utils.format_host("::1"))
        assert.are.equal("[0000:0000:0000:0000:0000:0000:0000:0001]:80", utils.format_host("::1", 80))
        assert.are.equal("localhost", utils.format_host("localhost"))
        assert.are.equal("mashape.test:80", utils.format_host("mashape.test", 80))
        -- passthrough (string)
        assert.are.equal("1.2.3.4", utils.format_host(utils.normalize_ipv4("1.2.3.4")))
        assert.are.equal("1.2.3.4:80", utils.format_host(utils.normalize_ipv4("1.2.3.4:80")))
        assert.are.equal("[0000:0000:0000:0000:0000:0000:0000:0001]", utils.format_host(utils.normalize_ipv6("::1")))
        assert.are.equal("[0000:0000:0000:0000:0000:0000:0000:0001]:80", utils.format_host(utils.normalize_ipv6("[::1]:80")))
        assert.are.equal("localhost", utils.format_host(utils.check_hostname("localhost")))
        assert.are.equal("mashape.test:80", utils.format_host(utils.check_hostname("mashape.test:80")))
        -- passthrough general (table)
        assert.are.equal("1.2.3.4", utils.format_host(utils.normalize_ip("1.2.3.4")))
        assert.are.equal("1.2.3.4:80", utils.format_host(utils.normalize_ip("1.2.3.4:80")))
        assert.are.equal("[0000:0000:0000:0000:0000:0000:0000:0001]", utils.format_host(utils.normalize_ip("::1")))
        assert.are.equal("[0000:0000:0000:0000:0000:0000:0000:0001]:80", utils.format_host(utils.normalize_ip("[::1]:80")))
        assert.are.equal("localhost", utils.format_host(utils.normalize_ip("localhost")))
        assert.are.equal("mashape.test:80", utils.format_host(utils.normalize_ip("mashape.test:80")))
        -- passthrough errors
        local one, two = utils.format_host(utils.normalize_ipv4("1.2.3.4.5"))
        assert.are.equal("nilstring", type(one) .. type(two))
        local one, two = utils.format_host(utils.normalize_ipv6("not ipv6..."))
        assert.are.equal("nilstring", type(one) .. type(two))
        local one, two = utils.format_host(utils.check_hostname("//bad..name\\:123"))
        assert.are.equal("nilstring", type(one) .. type(two))
        local one, two = utils.format_host(utils.normalize_ip("m a s h a p e.test:80"))
        assert.are.equal("nilstring", type(one) .. type(two))
      end)
    end)
  end)

  it("validate_header_name() validates header names", function()
    local header_chars = [[_-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz]]

    for i = 1, 255 do
      local c = string.char(i)

      if string.find(header_chars, c, nil, true) then
        assert(utils.validate_header_name(c) == c,
          "ascii character '" .. c .. "' (" .. i .. ") should have been allowed")
      else
        assert(utils.validate_header_name(c) == nil,
          "ascii character " .. i .. " should not have been allowed")
      end
    end
  end)
  it("validate_cookie_name() validates cookie names", function()
    local cookie_chars = [[~`|!#$%&'*+-._-^0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz]]

    for i = 1, 255 do
      local c = string.char(i)

      if string.find(cookie_chars, c, nil, true) then
        assert(utils.validate_cookie_name(c) == c,
          "ascii character '" .. c .. "' (" .. i .. ") should have been allowed")
      else
        assert(utils.validate_cookie_name(c) == nil,
          "ascii character " .. i .. " should not have been allowed")
      end
    end
  end)
  it("pack() stores results, including nils, properly", function()
    assert.same({ n = 0 }, utils.pack())
    assert.same({ n = 1 }, utils.pack(nil))
    assert.same({ n = 3, "1", "2", "3" }, utils.pack("1", "2", "3"))
    assert.same({ n = 3, [1] = "1", [3] = "3" }, utils.pack("1", nil, "3"))
  end)
  it("unpack() unwraps results, including nils, properly", function()
    local a,b,c
    a,b,c = utils.unpack({})
    assert.is_nil(a)
    assert.is_nil(b)
    assert.is_nil(c)

    a,b,c = unpack({ n = 1 })
    assert.is_nil(a)
    assert.is_nil(b)
    assert.is_nil(c)

    a,b,c = utils.unpack({ n = 3, "1", "2", "3" })
    assert.equal("1", a)
    assert.equal("2", b)
    assert.equal("3", c)

    a,b,c = utils.unpack({ n = 3, [1] = "1", [3] = "3" })
    assert.equal("1", a)
    assert.is_nil(b)
    assert.equal("3", c)
  end)

  describe("bytes_to_str()", function()
    it("converts bytes to the desired unit", function()
      assert.equal("5497558", utils.bytes_to_str(5497558, "b"))
      assert.equal("5368.71 KiB", utils.bytes_to_str(5497558, "k"))
      assert.equal("5.24 MiB", utils.bytes_to_str(5497558, "m"))
      assert.equal("0.01 GiB", utils.bytes_to_str(5497558, "g"))
      assert.equal("5.12 GiB", utils.bytes_to_str(5497558998, "g"))
    end)

    it("defaults unit arg to bytes", function()
      assert.equal("5497558", utils.bytes_to_str(5497558))
      assert.equal("5497558", utils.bytes_to_str(5497558, ""))
    end)

    it("unit arg is case-insensitive", function()
      assert.equal("5497558", utils.bytes_to_str(5497558, "B"))
      assert.equal("5368.71 KiB", utils.bytes_to_str(5497558, "K"))
      assert.equal("5.24 MiB", utils.bytes_to_str(5497558, "M"))
      assert.equal("0.01 GiB", utils.bytes_to_str(5497558, "G"))
      assert.equal("5.12 GiB", utils.bytes_to_str(5497558998, "G"))
    end)

    it("scale arg", function()
      -- 3
      assert.equal("5497558", utils.bytes_to_str(5497558, "b", 3))
      assert.equal("5368.709 KiB", utils.bytes_to_str(5497558, "k", 3))
      assert.equal("5.243 MiB", utils.bytes_to_str(5497558, "m", 3))
      assert.equal("0.005 GiB", utils.bytes_to_str(5497558, "g", 3))
      assert.equal("5.120 GiB", utils.bytes_to_str(5497558998, "g", 3))

      -- 0
      assert.equal("5 GiB", utils.bytes_to_str(5497558998, "g", 0))

      -- decimals
      assert.equal("5.12 GiB", utils.bytes_to_str(5497558998, "g", 2.2))
    end)

    it("errors on invalid unit arg", function()
      assert.has_error(function()
        utils.bytes_to_str(1234, "V")
      end, "invalid unit 'V' (expected 'k/K', 'm/M', or 'g/G')")
    end)

    it("errors on invalid scale arg", function()
      assert.has_error(function()
        utils.bytes_to_str(1234, "k", -1)
      end, "scale must be equal or greater than 0")

      assert.has_error(function()
        utils.bytes_to_str(1234, "k", "")
      end, "scale must be equal or greater than 0")
    end)
  end)

  describe("gzip_[de_in]flate()", function()
    local utils = require "kong.tools.gzip"

    it("empty string", function()
      local gz = assert(utils.deflate_gzip(""))
      assert.equal(utils.inflate_gzip(gz), "")
    end)

    it("small string (< 1 buffer)", function()
      local gz = assert(utils.deflate_gzip("aabbccddeeffgg"))
      assert.equal(utils.inflate_gzip(gz), "aabbccddeeffgg")
    end)

    it("long string (> 1 buffer)", function()
      local s = string.rep("a", 70000) -- > 64KB

      local gz = assert(utils.deflate_gzip(s))

      assert(#gz < #s)

      assert.equal(utils.inflate_gzip(gz), s)
    end)

    it("bad gzipped data", function()
      local res, err = utils.inflate_gzip("bad")
      assert.is_nil(res)
      assert.equal(err, "INFLATE: data error")
    end)
  end)

  describe("get_mime_type()", function()
    it("with valid mime types", function()
      assert.equal("application/json; charset=utf-8", utils.get_mime_type("application/json"))
      assert.equal("application/json; charset=utf-8", utils.get_mime_type("application/json; charset=utf-8"))
      assert.equal("application/json; charset=utf-8", utils.get_mime_type("application/*"))
      assert.equal("application/json; charset=utf-8", utils.get_mime_type("application/*; charset=utf-8"))
      assert.equal("text/html; charset=utf-8", utils.get_mime_type("text/html"))
      assert.equal("text/plain; charset=utf-8", utils.get_mime_type("text/plain"))
      assert.equal("text/plain; charset=utf-8", utils.get_mime_type("text/*"))
      assert.equal("text/plain; charset=utf-8", utils.get_mime_type("text/*; charset=utf-8"))
      assert.equal("application/xml; charset=utf-8", utils.get_mime_type("application/xml"))
      assert.equal("application/json; charset=utf-8", utils.get_mime_type("*/*; charset=utf-8"))
      assert.equal("application/json; charset=utf-8", utils.get_mime_type("*/*"))
      assert.equal("", utils.get_mime_type("application/grpc"))
    end)

    it("with unsupported or invalid mime types", function()
      assert.equal("application/json; charset=utf-8", utils.get_mime_type("audio/*", true))
      assert.equal("application/json; charset=utf-8", utils.get_mime_type("text/css"))
      assert.equal("application/json; charset=utf-8", utils.get_mime_type("default"))
      assert.is_nil(utils.get_mime_type("video/json", false))
      assert.is_nil(utils.get_mime_type("text/javascript", false))
    end)
  end)

  describe("nginx_conf_time_to_seconds()", function()
    it("returns value in seconds", function()
      assert.equal(5, utils.nginx_conf_time_to_seconds("5"))
      assert.equal(5, utils.nginx_conf_time_to_seconds("5s"))
      assert.equal(60, utils.nginx_conf_time_to_seconds("60s"))
      assert.equal(60, utils.nginx_conf_time_to_seconds("1m"))
      assert.equal(120, utils.nginx_conf_time_to_seconds("2m"))
      assert.equal(7200, utils.nginx_conf_time_to_seconds("2h"))
      assert.equal(172800, utils.nginx_conf_time_to_seconds("2d"))
      assert.equal(1209600, utils.nginx_conf_time_to_seconds("2w"))
      assert.equal(5184000, utils.nginx_conf_time_to_seconds("2M"))
      assert.equal(63072000, utils.nginx_conf_time_to_seconds("2y"))
    end)

    it("throws an error on bad argument", function()
      assert.has_error(function()
        utils.nginx_conf_time_to_seconds("abcd")
      end, "bad argument #1 'str'")
    end)
  end)

  describe("topological_sort", function()
    local get_neighbors = function(x) return x end
    local ts = require("kong.db.utils").topological_sort

    it("it puts destinations first", function()
      local a = { id = "a" }
      local b = { id = "b", a }
      local c = { id = "c", a, b }
      local d = { id = "d", c }

      local x = ts({ c, d, a, b }, get_neighbors)
      assert.same({ a, b, c, d }, x)
    end)

    it("returns an error if cycles are found", function()
      local a = { id = "a" }
      local b = { id = "b", a }
      a[1] = b
      local x, err = ts({ a, b }, get_neighbors)
      assert.is_nil(x)
      assert.equals("Cycle detected, cannot sort topologically", err)
    end)
  end)

  local function count_keys(t, n)
    n = n or 0
    if type(t) ~= "table" then
      return n
    end
    for k, v in pairs(t) do
      n = count_keys(k, n)
      n = count_keys(v, n)
      n = n + 1
    end
    return n
  end

  describe("deep_copy(t)", function()
    it("copies values, keys and metatables and sets metatables", function()
      local meta = {}
      local meta2 = {}
      local ref = {}
      local ref2 = setmetatable({}, meta)

      ref[1] = 1
      ref[2] = ref2
      ref[3] = nil
      ref[4] = 4

      local a = setmetatable({
        a = setmetatable({
          a = "clone",
        }, meta2),
        b = ref,
      }, meta)

      local b = {
        [a] = a,
        a = a,
        b = ref,
      }

      local c = utils.deep_copy(b)

      assert.not_same(b, c)
      assert.not_equal(b, c)

      assert.equal(b[a], b.a)
      assert.not_equal(c[a], c.a)

      assert.equal(b.b, ref)
      assert.not_equal(c.b, ref)

      assert.equal(b.b[1], 1)
      assert.equal(c.b[1], 1)

      assert.equal(b.b[2], ref2)
      assert.not_equal(c.b[2], ref2)

      assert.equal(getmetatable(b.b[2]), meta)
      assert.not_equal(getmetatable(c.b[2]), meta)

      assert.equal(b.b[3], nil)
      assert.equal(c.b[3], nil)

      assert.equal(b.b[4], 4)
      assert.equal(c.b[4], 4)

      assert.equal(getmetatable(b[a]), meta)
      assert.is_nil(getmetatable(c[a]))

      assert.equal(getmetatable(b.a), meta)
      assert.not_equal(getmetatable(c.a), meta)
      assert.is_table(getmetatable(c.a), meta)

      assert.not_equal(getmetatable(b[a]), getmetatable(c[a]))
      assert.not_equal(getmetatable(b.a), getmetatable(c.a))

      assert.is_table(getmetatable(b[a]))
      assert.is_nil(getmetatable(c[a]))

      assert.is_table(getmetatable(b.a))
      assert.is_table(getmetatable(c.a))

      assert.equal(getmetatable(b[a].a), meta2)
      assert.is_nil(getmetatable(c[a] and c[a].a or nil))
      assert.not_equal(getmetatable(b[a].a), getmetatable(c[a] and c[a].a or nil))

      assert.equal(getmetatable(b.a.a), meta2)
      assert.not_equal(getmetatable(c.a.a), meta2)
      assert.not_equal(getmetatable(b.a.a), getmetatable(c.a.a))

      assert.not_equal(b[a], c[a])
      assert.not_equal(b.a, c.a)
      assert.not_equal(b[a].a, c[a] and c[a].a or nil)
      assert.not_equal(b.a.a, c.a.a)
      assert.not_equal(b[a].a.a, c[a] and c[a].a and c[a].a.a or nil)
      assert.equal(b.a.a.a, c.a.a.a)

      local key_found
      for k in pairs(b) do
        key_found = nil
        for k2 in pairs(c) do
          if k == k2 then
            key_found = true
            break
          end
        end
        if type(k) == "table" then
          assert.is_nil(key_found)
        else
          assert.is_true(key_found)
        end
      end

      key_found = nil
      for k in pairs(b) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_true(key_found)

      key_found = nil
      for k in pairs(c) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_nil(key_found)

      assert.equal(count_keys(b), 24)
      assert.equal(count_keys(c), 24)
    end)
  end)

  describe("deep_copy(t, false)", function()
    it("copies values and keys and removes metatables", function()
      local meta = {}
      local meta2 = {}
      local ref = {}
      local ref2 = setmetatable({}, meta)

      ref[1] = 1
      ref[2] = ref2
      ref[3] = nil
      ref[4] = 4

      local a = setmetatable({
        a = setmetatable({
          a = "clone",
        }, meta2),
        b = ref,
      }, meta)

      local b = {
        [a] = a,
        a = a,
        b = ref,
      }

      local c = utils.deep_copy(b, false)

      assert.not_same(b, c)
      assert.not_equal(b, c)

      assert.equal(b[a], b.a)
      assert.not_equal(c[a], c.a)

      assert.equal(b.b, ref)
      assert.not_equal(c.b, ref)

      assert.equal(b.b[1], 1)
      assert.equal(c.b[1], 1)

      assert.equal(b.b[2], ref2)
      assert.not_equal(c.b[2], ref2)

      assert.equal(getmetatable(b.b[2]), meta)
      assert.not_equal(getmetatable(c.b[2]), meta)

      assert.equal(b.b[3], nil)
      assert.equal(c.b[3], nil)

      assert.equal(b.b[4], 4)
      assert.equal(c.b[4], 4)

      assert.equal(getmetatable(b[a]), meta)
      assert.is_nil(getmetatable(c[a]))

      assert.equal(getmetatable(b.a), meta)
      assert.not_equal(getmetatable(c.a), meta)
      assert.is_nil(getmetatable(c.a), meta)

      assert.not_equal(getmetatable(b[a]), getmetatable(c[a]))
      assert.not_equal(getmetatable(b.a), getmetatable(c.a))

      assert.is_table(getmetatable(b[a]))
      assert.is_nil(getmetatable(c[a]))

      assert.is_table(getmetatable(b.a))
      assert.is_nil(getmetatable(c.a))

      assert.equal(getmetatable(b[a].a), meta2)
      assert.is_nil(getmetatable(c[a] and c[a].a or nil))
      assert.not_equal(getmetatable(b[a].a), getmetatable(c[a] and c[a].a or nil))

      assert.equal(getmetatable(b.a.a), meta2)
      assert.not_equal(getmetatable(c.a.a), meta2)
      assert.not_equal(getmetatable(b.a.a), getmetatable(c.a.a))

      assert.not_equal(b[a], c[a])
      assert.not_equal(b.a, c.a)
      assert.not_equal(b[a].a, c[a] and c[a].a or nil)
      assert.not_equal(b.a.a, c.a.a)
      assert.not_equal(b[a].a.a, c[a] and c[a].a and c[a].a.a or nil)
      assert.equal(b.a.a.a, c.a.a.a)

      local key_found
      for k in pairs(b) do
        key_found = nil
        for k2 in pairs(c) do
          if k == k2 then
            key_found = true
            break
          end
        end
        if type(k) == "table" then
          assert.is_nil(key_found)
        else
          assert.is_true(key_found)
        end
      end

      key_found = nil
      for k in pairs(b) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_true(key_found)

      key_found = nil
      for k in pairs(c) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_nil(key_found)

      assert.equal(count_keys(b), 24)
      assert.equal(count_keys(c), 24)
    end)
  end)

  describe("cycle_aware_deep_copy(t)", function()
    it("cycle aware copies values and sets the metatables but does not copy keys or metatables", function()
      local meta = {}
      local meta2 = {}
      local ref = {}
      local ref2 = setmetatable({}, meta)

      ref[1] = 1
      ref[2] = ref2
      ref[3] = nil
      ref[4] = 4

      local a = setmetatable({
        a = setmetatable({
          a = "clone",
        }, meta2),
        b = ref,
      }, meta)

      local b = {
        [a] = a,
        a = a,
        b = ref,
      }

      local c = utils.cycle_aware_deep_copy(b)

      assert.same(b, c)
      assert.not_equal(b, c)

      assert.equal(b[a], b.a)
      assert.equal(c[a], c.a)

      assert.equal(b.b, ref)
      assert.not_equal(c.b, ref)

      assert.equal(b.b[1], 1)
      assert.equal(c.b[1], 1)

      assert.equal(b.b[2], ref2)
      assert.not_equal(c.b[2], ref2)

      assert.equal(getmetatable(b.b[2]), meta)
      assert.equal(getmetatable(c.b[2]), meta)

      assert.equal(b.b[3], nil)
      assert.equal(c.b[3], nil)

      assert.equal(b.b[4], 4)
      assert.equal(c.b[4], 4)

      assert.equal(getmetatable(b[a]), meta)
      assert.equal(getmetatable(c[a]), meta)

      assert.equal(getmetatable(b.a), meta)
      assert.equal(getmetatable(c.a), meta)

      assert.equal(getmetatable(b[a]), getmetatable(c[a]))
      assert.equal(getmetatable(b.a), getmetatable(c.a))

      assert.equal(getmetatable(b[a].a), meta2)
      assert.equal(getmetatable(c[a].a), meta2)
      assert.equal(getmetatable(b[a].a), getmetatable(c[a].a))

      assert.equal(getmetatable(b.a.a), meta2)
      assert.equal(getmetatable(c.a.a), meta2)
      assert.equal(getmetatable(b.a.a), getmetatable(c.a.a))

      assert.not_equal(b[a], c[a])
      assert.not_equal(b.a, c.a)
      assert.not_equal(b[a].a, c[a].a)
      assert.not_equal(b.a.a, c.a.a)
      assert.equal(b[a].a.a, c[a].a.a)
      assert.equal(b.a.a.a, c.a.a.a)

      local key_found
      for k in pairs(b) do
        key_found = nil
        for k2 in pairs(c) do
          if k == k2 then
            key_found = true
            break
          end
        end
        assert.is_true(key_found)
      end

      key_found = nil
      for k in pairs(b) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_true(key_found)

      key_found = nil
      for k in pairs(c) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_true(key_found)

      assert.equal(count_keys(b), 24)
      assert.equal(count_keys(c), 24)
    end)
  end)

  describe("cycle_aware_deep_copy(t, true)", function()
    it("cycle aware copies values and removes metatables but does not copy keys", function()
      local meta = {}
      local meta2 = {}
      local ref = {}
      local ref2 = setmetatable({}, meta)

      ref[1] = 1
      ref[2] = ref2
      ref[3] = nil
      ref[4] = 4

      local a = setmetatable({
        a = setmetatable({
          a = "clone",
        }, meta2),
        b = ref,
      }, meta)

      local b = {
        [a] = a,
        a = a,
        b = ref,
      }

      local c = utils.cycle_aware_deep_copy(b, true)

      assert.same(b, c)
      assert.not_equal(b, c)

      assert.equal(b[a], b.a)
      assert.equal(c[a], c.a)

      assert.equal(b.b, ref)
      assert.not_equal(c.b, ref)

      assert.equal(b.b[1], 1)
      assert.equal(c.b[1], 1)

      assert.equal(b.b[2], ref2)
      assert.not_equal(c.b[2], ref2)

      assert.equal(getmetatable(b.b[2]), meta)
      assert.is_nil(getmetatable(c.b[2]))

      assert.equal(b.b[3], nil)
      assert.equal(c.b[3], nil)

      assert.equal(b.b[4], 4)
      assert.equal(c.b[4], 4)

      assert.equal(getmetatable(b[a]), meta)
      assert.is_nil(getmetatable(c[a]), meta)

      assert.equal(getmetatable(b.a), meta)
      assert.is_nil(getmetatable(c.a))

      assert.not_equal(getmetatable(b[a]), getmetatable(c[a]))
      assert.not_equal(getmetatable(b.a), getmetatable(c.a))

      assert.equal(getmetatable(b[a].a), meta2)
      assert.is_nil(getmetatable(c[a].a))
      assert.not_equal(getmetatable(b[a].a), getmetatable(c[a].a))

      assert.equal(getmetatable(b.a.a), meta2)
      assert.is_nil(getmetatable(c.a.a))
      assert.not_equal(getmetatable(b.a.a), getmetatable(c.a.a))

      assert.not_equal(b[a], c[a])
      assert.not_equal(b.a, c.a)
      assert.not_equal(b[a].a, c[a].a)
      assert.not_equal(b.a.a, c.a.a)
      assert.equal(b[a].a.a, c[a].a.a)
      assert.equal(b.a.a.a, c.a.a.a)

      local key_found
      for k in pairs(b) do
        key_found = nil
        for k2 in pairs(c) do
          if k == k2 then
            key_found = true
            break
          end
        end
        assert.is_true(key_found)
      end

      key_found = nil
      for k in pairs(b) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_true(key_found)

      key_found = nil
      for k in pairs(c) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_true(key_found)

      assert.equal(count_keys(b), 24)
      assert.equal(count_keys(c), 24)
    end)
  end)

  describe("cycle_aware_deep_copy(t, nil, true)", function()
    it("cycle aware copies values and keys, and sets metatables", function()
      local meta = {}
      local meta2 = {}
      local ref = {}
      local ref2 = setmetatable({}, meta)

      ref[1] = 1
      ref[2] = ref2
      ref[3] = nil
      ref[4] = 4

      local a = setmetatable({
        a = setmetatable({
          a = "clone",
        }, meta2),
        b = ref,
      }, meta)

      local b = {
        [a] = a,
        a = a,
        b = ref,
      }

      local c = utils.cycle_aware_deep_copy(b, nil, true)

      assert.not_same(b, c)
      assert.not_equal(b, c)

      assert.equal(b[a], b.a)
      assert.is_nil(c[a])

      assert.equal(b.b, ref)
      assert.not_equal(c.b, ref)

      assert.equal(b.b[1], 1)
      assert.equal(c.b[1], 1)

      assert.equal(b.b[2], ref2)
      assert.not_equal(c.b[2], ref2)

      assert.equal(getmetatable(b.b[2]), meta)
      assert.equal(getmetatable(c.b[2]), meta)

      assert.equal(b.b[3], nil)
      assert.equal(c.b[3], nil)

      assert.equal(b.b[4], 4)
      assert.equal(c.b[4], 4)

      assert.equal(getmetatable(b[a]), meta)
      assert.is_nil(getmetatable(c[a]))

      assert.equal(getmetatable(b.a), meta)
      assert.equal(getmetatable(c.a), meta)

      assert.not_equal(getmetatable(b[a]), getmetatable(c[a]))
      assert.equal(getmetatable(b.a), getmetatable(c.a))

      assert.equal(getmetatable(b[a].a), meta2)
      assert.is_nil(getmetatable(c[a] and c[a].a))
      assert.not_equal(getmetatable(b[a].a), getmetatable(c[a] and c[a].a or nil))

      assert.equal(getmetatable(b.a.a), meta2)
      assert.equal(getmetatable(c.a.a), meta2)
      assert.equal(getmetatable(b.a.a), getmetatable(c.a.a))

      assert.not_equal(b[a], c[a])
      assert.not_equal(b.a, c.a)
      assert.not_equal(b[a].a, c[a] and c[a].a or nil)
      assert.not_equal(b.a.a, c.a.a)
      assert.not_equal(b[a].a.a, c[a] and c[a].a and c[a].a.a or nil)
      assert.equal(b.a.a.a, c.a.a.a)

      local key_found
      for k in pairs(b) do
        key_found = nil
        for k2 in pairs(c) do
          if k == k2 then
            key_found = true
            break
          end
        end
        if type(k) == "table" then
          assert.is_nil(key_found)
        else
          assert.is_true(key_found)
        end
      end

      key_found = nil
      for k in pairs(b) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_true(key_found)

      key_found = nil
      for k in pairs(c) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_nil(key_found)

      assert.equal(count_keys(b), 24)
      assert.equal(count_keys(c), 24)
    end)
  end)

  describe("cycle_aware_deep_copy(t, nil, nil, cache)", function()
    it("cycle aware copies values that are not already cached and sets metatables but does not copy keys or metatables", function()
      local cache = {}
      local meta = {}
      local meta2 = {}
      local ref = {}
      local ref2 = setmetatable({}, meta)

      cache[ref] = ref
      cache[ref2] = ref2

      ref[1] = 1
      ref[2] = ref2
      ref[3] = nil
      ref[4] = 4

      local a = setmetatable({
        a = setmetatable({
          a = "clone",
        }, meta2),
        b = ref,
      }, meta)

      cache[a] = a

      local b = {
        [a] = a,
        a = a,
        b = ref,
      }

      local c = utils.cycle_aware_deep_copy(b, nil, nil, cache)

      assert.same(b, c)
      assert.not_equal(b, c)

      assert.equal(b[a], b.a)
      assert.equal(c[a], c.a)

      assert.equal(b.b, ref)
      assert.equal(c.b, ref)

      assert.equal(b.b[1], 1)
      assert.equal(c.b[1], 1)

      assert.equal(b.b[2], ref2)
      assert.equal(c.b[2], ref2)

      assert.equal(getmetatable(b.b[2]), meta)
      assert.equal(getmetatable(c.b[2]), meta)

      assert.equal(b.b[3], nil)
      assert.equal(c.b[3], nil)

      assert.equal(b.b[4], 4)
      assert.equal(c.b[4], 4)

      assert.equal(getmetatable(b[a]), meta)
      assert.equal(getmetatable(c[a]), meta)

      assert.equal(getmetatable(b.a), meta)
      assert.equal(getmetatable(c.a), meta)

      assert.equal(getmetatable(b[a]), getmetatable(c[a]))
      assert.equal(getmetatable(b.a), getmetatable(c.a))

      assert.equal(getmetatable(b[a].a), meta2)
      assert.equal(getmetatable(c[a].a), meta2)
      assert.equal(getmetatable(b[a].a), getmetatable(c[a].a))

      assert.equal(getmetatable(b.a.a), meta2)
      assert.equal(getmetatable(c.a.a), meta2)
      assert.equal(getmetatable(b.a.a), getmetatable(c.a.a))

      assert.equal(b[a], c[a])
      assert.equal(b.a, c.a)
      assert.equal(b[a].a, c[a].a)
      assert.equal(b.a.a, c.a.a)
      assert.equal(b[a].a.a, c[a].a.a)
      assert.equal(b.a.a.a, c.a.a.a)

      local key_found
      for k in pairs(b) do
        key_found = nil
        for k2 in pairs(c) do
          if k == k2 then
            key_found = true
            break
          end
        end
        assert.is_true(key_found)
      end

      key_found = nil
      for k in pairs(b) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_true(key_found)

      key_found = nil
      for k in pairs(c) do
        if k == a then
          key_found = true
          break
        end
      end
      assert.is_true(key_found)

      assert.equal(count_keys(b), 24)
      assert.equal(count_keys(c), 24)
    end)
  end)

  describe("deep_merge(t1, t2)", function()
    it("deep merges t2 into copy of t1", function()
      local meta = {}
      local ref = setmetatable({
        a = "ref",
      }, meta)

      local t1 = {
        a = "t1",
        b = {
          a = ref,
        },
        c = {
          a = "t1",
        },
      }

      local t2 = {
        a = "t2",
        b = {
          a = ref,
          b = "t2",
        },
        c = "t2",
      }

      local t3 = utils.deep_merge(t1, t2)

      assert.not_equal(t3, t1)
      assert.not_equal(t3, t2)

      assert.same({
        a = "t2",
        b = {
          a = ref,
          b = "t2",
        },
        c = "t2",
      }, t3)

      assert.not_equal(meta, getmetatable(t3.b.a))
      assert.is_table(getmetatable(t3.b.a))
    end)
  end)

  describe("cycle_aware_deep_merge(t1, t2)", function()
    it("cycle aware deep merges t2 into copy of t1", function()
      local meta = {}
      local ref = setmetatable({
        a = "ref",
      }, meta)

      local t1 = {
        a = "t1",
        b = {
          a = ref,
        },
        c = {
          a = "t1",
        },
      }

      local t2 = {
        a = "t2",
        b = {
          a = ref,
          b = "t2",
        },
        c = "t2",
      }

      local t3 = utils.cycle_aware_deep_merge(t1, t2)

      assert.not_equal(t3, t1)
      assert.not_equal(t3, t2)

      assert.same({
        a = "t2",
        b = {
          a = ref,
          b = "t2",
        },
        c = "t2",
      }, t3)

      assert.equal(meta, getmetatable(t3.b.a))
    end)
  end)

  describe("table_path(t, path)", function()
    local t = {
      x = 1,
      a = {
        b = {
          c = 200
        },
      },
      z = 2
    }

    it("retrieves value from table based on path - single level", function()
      local path = { "x" }

      assert.equal(1, utils.table_path(t, path))
    end)

    it("retrieves value from table based on path - deep value", function()
      local path = { "a", "b", "c" }

      assert.equal(200, utils.table_path(t, path))
    end)

    it("returns nil if element is not found - leaf not found", function()
      local path = { "a", "b", "x" }

      assert.equal(nil, utils.table_path(t, path))
    end)

    it("returns nil if element is not found - root branch not found", function()
      local path = { "o", "j", "k" }

      assert.equal(nil, utils.table_path(t, path))
    end)
  end)
end)
