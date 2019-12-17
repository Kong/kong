local helpers = require("spec.helpers")
local x509 = require("resty.openssl.x509")
local pl_file = require("pl.file")


describe("kong hybrid", function()
  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    helpers.prepare_prefix()
  end)

  lazy_teardown(function()
    helpers.clean_prefix()
  end)

  it("help", function()
    local ok, stderr = helpers.kong_exec("hybrid --help")
    assert.falsy(ok)
    assert.not_equal("", stderr)
  end)

  describe("gen_cert", function()
    it("gen_cert", function()
      local cert = helpers.test_conf.prefix .. "/test1.crt"
      local key = helpers.test_conf.prefix .. "/test1.key"

      local ok, _, stdout = helpers.kong_exec("hybrid gen_cert " .. cert .. " " .. key)
      assert.truthy(ok)
      assert.matches("Successfully generated certificate/key pairs, they have been written to: ", stdout, nil, true)

      assert.matches("-----BEGIN CERTIFICATE-----", pl_file.read(cert))
      assert.matches("-----BEGIN PRIVATE KEY-----", pl_file.read(key))
    end)

    it("gen_cert sets correct permission on generated files", function()
      local cert = helpers.test_conf.prefix .. "/test2.crt"
      local key = helpers.test_conf.prefix .. "/test2.key"

      local ok, _, stdout = helpers.kong_exec("hybrid gen_cert " .. cert .. " " .. key)
      assert.truthy(ok)
      assert.matches("Successfully generated certificate/key pairs, they have been written to: ", stdout, nil, true)

      _, _, stdout = helpers.execute("ls -l " .. key)
      assert.matches("-rw-------", stdout, nil, true)

      _, _, stdout = helpers.execute("ls -l " .. cert)
      assert.matches("-rw-r--r--", stdout, nil, true)
    end)

    it("gen_cert does not override existing files", function()
      local cert = helpers.test_conf.prefix .. "/test3.crt"
      local key = helpers.test_conf.prefix .. "/test3.key"

      pl_file.write(cert, "foo")

      local ok, stderr, _ = helpers.kong_exec("hybrid gen_cert " .. cert .. " " .. key)
      assert.falsy(ok)
      assert.matches("already exists", stderr, nil, true)
    end)

    it("gen_cert default produces 3 year certificate", function()
      local cert = helpers.test_conf.prefix .. "/test4.crt"
      local key = helpers.test_conf.prefix .. "/test4.key"

      local ok, _, stdout = helpers.kong_exec("hybrid gen_cert " .. cert .. " " .. key)
      assert.truthy(ok)
      assert.matches("Successfully generated certificate/key pairs, they have been written to: ", stdout, nil, true)

      local crt = x509.new(pl_file.read(cert))

      assert.equals(crt:get_not_after() - crt:get_not_before(), 3 * 365 * 86400)
      assert(crt:get_not_before() >= ngx.time())
    end)

    it("gen_cert cert days can be overwritten with -d", function()
      local cert = helpers.test_conf.prefix .. "/test5.crt"
      local key = helpers.test_conf.prefix .. "/test5.key"

      local ok, _, stdout = helpers.kong_exec("hybrid gen_cert -d 1 " .. cert .. " " .. key)
      assert.truthy(ok)
      assert.matches("Successfully generated certificate/key pairs, they have been written to: ", stdout, nil, true)

      local crt = x509.new(pl_file.read(cert))

      assert.equals(crt:get_not_after() - crt:get_not_before(), 86400)
      assert(crt:get_not_before() >= ngx.time())
    end)

    it("gen_cert cert days can be overwritten with --days", function()
      local cert = helpers.test_conf.prefix .. "/test6.crt"
      local key = helpers.test_conf.prefix .. "/test6.key"

      local ok, _, stdout = helpers.kong_exec("hybrid gen_cert --days 2 " .. cert .. " " .. key)
      assert.truthy(ok)
      assert.matches("Successfully generated certificate/key pairs, they have been written to: ", stdout, nil, true)

      local crt = x509.new(pl_file.read(cert))

      assert.equals(crt:get_not_after() - crt:get_not_before(), 2 * 86400)
      assert(crt:get_not_before() >= ngx.time())
    end)
  end)
end)
