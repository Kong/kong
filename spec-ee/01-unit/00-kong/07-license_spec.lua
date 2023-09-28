-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"

local lic_helper = require "kong.enterprise_edition.license_helpers"
local licensing = require "kong.enterprise_edition.licensing"

local match = require "luassert.match"

describe("licensing", function()

  local kong_conf = {}

  lazy_setup(function()
    _G.kong = {}
    _G.kong.response = mock(setmetatable({}, { __index = function() return function() end end }))
    _G.kong.licensing = licensing(kong_conf)
  end)

  before_each(function()
    stub(ngx, "log")
  end)

  after_each(function()
    ngx.log:revert() -- luacheck: ignore
  end)

  it("does not alert before 90 days from expiration date", function()
    lic_helper.log_license_state(os.time()+91*3600*24, os.time())
    assert.stub(ngx.log).was.called(0)
  end)

  it("does WARN from 90 days on from expiration date", function()
    lic_helper.log_license_state(os.time()+89*3600*24, os.time())
    assert.stub(ngx.log).was.called(1)
    assert.stub(ngx.log).was.called_with(ngx.WARN, match._)
  end)

  it("does ERR from 30 days on from expiration date", function()
    lic_helper.log_license_state(os.time()+29*3600*24, os.time())
    assert.stub(ngx.log).was.called(1)
    assert.stub(ngx.log).was.called_with(ngx.ERR, match._)
  end)

  it("does CRIT from -1 days on from expiration date", function()
    lic_helper.log_license_state(os.time()-3600*24, os.time())
    assert.stub(ngx.log).was.called(1)
    assert.stub(ngx.log).was.called_with(ngx.CRIT, match._)
  end)

  it("does CRIT in grace period from expiration date", function()
    lic_helper.log_license_state(os.time()-3600*24*30, os.time())
    assert.stub(ngx.log).was.called(1)
    assert.stub(ngx.log).was.called_with(ngx.CRIT, match._)
  end)

  it("does ERR from 16 days on from expiration date if konnect mode", function ()
    lic_helper.log_license_state(os.time()+15*3600*24, os.time(), true)
    assert.stub(ngx.log).was.called(1)
    assert.stub(ngx.log).was.called_with(ngx.ERR, match._)
  end)

  it("doesn't ERR above 16 days from expiration date if konnect mode", function ()
    lic_helper.log_license_state(os.time()+17*3600*24, os.time(), true)
    assert.stub(ngx.log).was.called(0)
  end)

  it("does CRIT from -1 days on from expiration date if konnect mode", function()
    lic_helper.log_license_state(os.time()-3600*24, os.time(), true)
    assert.stub(ngx.log).was.called(1)
    assert.stub(ngx.log).was.called_with(ngx.CRIT, match._)
  end)

  it("does validate license using ffi", function()
    local file = assert(io.open("spec-ee/fixtures/expired_license.json"))
    local validation_pass = file:read("*a")
    file:close()
    validation_pass = validation_pass

    local rc = lic_helper.validate_kong_license(validation_pass)
    assert.is_truthy(rc == "ERROR_VALIDATION_PASS")
  end)

  it("does not validate license using ffi", function()
    local validation_fail = [[{
      "license": {
        "payload": {
          "admin_seats" :"",
          "customer": "",
          "dataplanes": "",
          "license_creation_date": "",
          "license_expiration_date": "",
          "license_key": "",
          "product_subscription": "",
          "support_plan": ""
        },
        "signature": "",
        "version": 1
      }
    }]]

    local rc = lic_helper.validate_kong_license(validation_fail)
    assert.is_truthy(rc == "ERROR_VALIDATION_FAIL")
  end)

  it("does not validate license using ffi - missing signature field", function()
    local invalid_license_format = [[{
      "license": {
        "payload": {
          "admin_seats" :"",
          "customer": "",
          "dataplanes": "",
          "license_creation_date": "",
          "license_expiration_date": "",
          "license_key": "",
          "product_subscription": "",
          "support_plan": ""
        },
        "version": 1
      }
    }]]

    local rc = lic_helper.validate_kong_license(invalid_license_format)
    assert.is_truthy(rc == "ERROR_INVALID_LICENSE_FORMAT")
  end)

  it("does not validate license using ffi - missing payload fields", function()
    local invalid_license_format = [[{
      "license": {
        "payload": {
          "admin_seats" :""
        },
        "signature": "",
        "version": 1
      }
    }]]

    local rc = lic_helper.validate_kong_license(invalid_license_format)
    assert.is_truthy(rc == "ERROR_INVALID_LICENSE_FORMAT")
  end)

  it("does not validate license using ffi - missing payload subfield", function()
    local invalid_license_format = [[{
      "license": {
        "signature": "",
        "version": 1
      }
    }]]

    local rc = lic_helper.validate_kong_license(invalid_license_format)
    assert.is_truthy(rc == "ERROR_INVALID_LICENSE_FORMAT")
  end)

  it("does not validate license using ffi - missing license field", function()
    local invalid_license_format = '{}'

    local rc = lic_helper.validate_kong_license(invalid_license_format)
    assert.is_truthy(rc == "ERROR_INVALID_LICENSE_FORMAT")
  end)

  it("does not validate license using ffi - invalid JSON", function()
    local invalid_license_json = '{"": '

    local rc = lic_helper.validate_kong_license(invalid_license_json)
    assert.is_truthy(rc == "ERROR_INVALID_LICENSE_JSON")
  end)

  describe("license_can_proceed", function()
    local featureset

    before_each(function()
      assert(stub(lic_helper, "get_featureset").returns(featureset))
      assert(stub(kong.response, "exit"))
      kong.licensing:update()
    end)

    after_each(function()
      assert(lic_helper.get_featureset:revert())
      assert(mock.revert(ngx.req.get_method))
      assert(kong.response.exit:revert())
    end)

    describe("deny_admin_api", function()
      setup(function()
        featureset = {
          deny_admin_api = {
            ["/workspaces"] = { GET = true, OPTION = true },
            ["/workspaces/:workspaces"] = { ["*"] = true },
          },
          allow_admin_api = {},
        }
      end)

      it("denies defined methods", function()
        for _, method in ipairs({ "GET", "OPTION" }) do
          -- clean up calls
          assert(stub(kong.response, "exit"))
          assert(stub(ngx.req, "get_method").returns(method))
          assert.is_nil(lic_helper.license_can_proceed({route_name = "/workspaces"}))
          assert.stub(kong.response.exit).was.called_with(403,  { message = "Enterprise license missing or expired" })
        end
      end)

      it("allows anything else", function()
        for _, method in ipairs({ "POST", "PUT", "PATCH" }) do
          assert(stub(ngx.req, "get_method").returns(method))
          assert.is_nil(lic_helper.license_can_proceed({route_name = "/workspaces"}))
        end
        assert.stub(kong.response.exit).was_called(0)
      end)

      it("can deny any method by *", function()
        for _, method in ipairs({"GET", "OPTION", "POST", "PUT", "PATCH", "DELETE"}) do
          -- clean up calls
          assert(stub(kong.response, "exit"))
          assert(stub(ngx.req, "get_method").returns(method))
          assert.is_nil(lic_helper.license_can_proceed({route_name = "/workspaces/:workspaces"}))
          assert.stub(kong.response.exit).was.called_with(403,  { message = "Enterprise license missing or expired" })
        end
      end)
    end)

    describe("allow_admin_api + deny_admin_api", function()
      setup(function()
        featureset = {
          allow_admin_api = {
            ["/workspaces"] = { GET = true, OPTION = true},
            ["/identity"] = { ["*"] = true },
          },
          deny_admin_api = {
            ["/workspaces"] = { ["*"] = true },
            ["/identity"] = { ["*"] = true },
          },
        }
      end)

      it("granular allows defined methods", function()
        for _, method in ipairs({ "GET", "OPTION" }) do
          assert(stub(ngx.req, "get_method").returns(method))
          assert.is_nil(lic_helper.license_can_proceed({route_name = "/workspaces"}))
        end
        assert.stub(kong.response.exit).was_called(0)
      end)

      it("deny_admin_api still denies any other method", function()
        for _, method in ipairs({ "POST", "PUT", "PATCH", "DELETE"}) do
          -- clean up calls
          assert(stub(kong.response, "exit"))
          assert(stub(ngx.req, "get_method").returns(method))
          assert.is_nil(lic_helper.license_can_proceed({route_name = "/workspaces"}))
          assert.stub(kong.response.exit).was.called_with(403,  { message = "Enterprise license missing or expired" })
        end
      end)

      it("does not affect other routes", function()
        assert(stub(ngx.req, "get_method").returns("GET"))
        assert.is_nil(lic_helper.license_can_proceed({route_name = "/amazeballs"}))
      end)

      it("identity", function()
        for _, method in ipairs({ "GET", "OPTION", "POST", "PUT", "PATCH", "DELETE" }) do
          assert(stub(ngx.req, "get_method").returns(method))
          assert.is_nil(lic_helper.license_can_proceed({route_name = "/identity"}))
        end
        assert.stub(kong.response.exit).was_called(0)
      end)
    end)
  end)

  describe("deny_entity", function()
    local ee = require "kong.enterprise_edition"
    local Entity = require "kong.db.schema.entity"

    local featureset, SomeEntity, AnotherEntity
    local config

    lazy_setup(function()
      config = {}
      featureset = {
        deny_entity = { ["some_entity"] = true, },
      }

      assert(stub(lic_helper, "get_featureset").returns(featureset))
      kong.licensing:update()

      ee.license_hooks(config)

      SomeEntity = assert(Entity.new({
        name = "some_entity",
        fields = {},
      }))

      AnotherEntity = assert(Entity.new({
        name = "another_entity",
        fields = {},
      }))
    end)

    lazy_teardown(function()
      assert(lic_helper.get_featureset:revert())
    end)

    it("makes denied entities never validate", function()
      local ok, err = SomeEntity:validate({})
      assert.is_falsy(ok)
      assert.same({
        licensing = "'some_entity' is an enterprise only entity",
      }, err)
    end)

    it("leaves non denied entities alone", function()
      assert(AnotherEntity:validate({}))
    end)

    pending("does not allow API calls on entity level")
  end)

  pending("ee_plugins = false")

  describe("licensing module", function()

    -- some initial configuration
    local kong_conf = {
      enforce_rbac = 'on',
      flux_percolator = 'off',
      hard_stuff = { foo = 'bar' },
      removeme = 'i am here',
    }

    local whatever_spy = spy.new(function()
      return "hello world"
    end)

    local some_function = function() return 'exists' end

    local NOOP = function() end

    -- Some license overrides and feature flags
    local featureset = {
      conf = {
        enforce_rbac = 'off',
        gravity_override = 'on',
        magic = some_function,
        removeme = NOOP,
      },
      some_stuff = { "neato" },
      boolean_flag = true,
      hascheezburger = false,
      boolean_function = function()
        return true
      end,
      whatever_function = function()
        return whatever_spy()
      end,
    }

    local expected_conf = {
      enforce_rbac = 'off',
      gravity_override = 'on',
      flux_percolator = 'off',
      magic = 'exists',
      hard_stuff = { foo = 'bar' },
    }

    local lic
    local license = { some = "license_data" }

    lazy_setup(function()
      assert(stub(lic_helper, "get_featureset").returns(featureset))
      assert(stub(lic_helper, "read_license_info").returns(license))

      lic = licensing(kong_conf)
    end)

    describe("new", function()
      it("tries to read license", function()
        assert.stub(lic_helper.read_license_info).was.called()
      end)

      it("sets kong.license to the read license", function()
        assert.same(license, kong.license)
      end)

      it("sets license type on the module", function()
        assert.same("free", lic.l_type)
        assert.same("free", lic:license_type())
      end)
    end)

    describe("configuration", function()
      it("returns things in kong_conf", function()
        assert.equal("off", lic.configuration.flux_percolator)
      end)

      it("returns things in featureset", function()
        assert.equal("on", lic.configuration.gravity_override)
      end)

      it("overrides kong_conf using featureset", function()
        assert.equal("off", lic.configuration.enforce_rbac)
      end)

      it("evaluates functions on featureset", function()
        assert.equal("exists", lic.configuration.magic)
      end)

      it("a NOOP evaluates removing the key", function()
        assert.is_nil(lic.configuration.removeme)
      end)

      it("cannot be modified", function()
        assert.error(function() lic.configuration.foo = "bar" end)
      end)

      it("can be deep_copied, dumped, etc", function()
        -- Decode the deep copied tables for easier comparison
        -- Note: Not all strings are created equal after encoding; order of JSON
        assert.same(cjson.decode(cjson.encode((expected_conf))),
                    cjson.decode(cjson.encode(lic.configuration)))

      end)

      it("is kong_conf + features.conf", function()
        assert.same(expected_conf, lic.configuration)
      end)

      it("leaves kong_conf alone", function()
        lic.configuration.hard_stuff.waaat = "lol"
        assert.is_nil(kong_conf.hard_stuff.waaat)
        finally(function() lic.configuration.hard_stuff.waaat = nil end)
      end)
    end)

    describe("features", function()

      local expected = {
        conf = {
          enforce_rbac = 'off',
          gravity_override = 'on',
          magic = some_function,
          removeme = NOOP,
        },
        some_stuff = { "neato" },
        boolean_flag = true,
        hascheezburger = false,
        boolean_function = true,
        whatever_function = "hello world",
      }

      it("gets stuff from the featureset", function()
        assert.same(expected, lic.features)
      end)

      it("executes functions and stores their value", function()
        assert.equal(true, lic.features.boolean_function)
        assert.equal("hello world", lic.features.whatever_function)
      end)

      it("executes functions only once", function()
        assert.equal("hello world", lic.features.whatever_function)
        assert.equal("hello world", lic.features.whatever_function)
        assert.equal("hello world", lic.features.whatever_function)
        assert.equal("hello world", lic.features.whatever_function)
        assert.spy(whatever_spy).was.called(1)
      end)

      describe("when things change", function()
        local another_set = {
          hey = {
            "girls",
            "boys",
          },
          superstar = "djs",
          here = "we go",
        }

        lazy_setup(function()
          assert(stub(lic_helper, "get_featureset").returns(another_set))
        end)

        it("does keep the stuff that was before", function()
          assert.same(expected, lic.features)
        end)

        it("until it gets reloaded", function()
          lic:update()
          assert.same(another_set, lic.features)
        end)

        lazy_teardown(function()
          assert(stub(lic_helper, "get_featureset").returns(featureset))
          lic:update()
        end)

      end)

    end)

    describe("licensing:can boolean shortcut", function()
      it("returns true if it's not set", function()
        assert.is_true(lic:can("dothisthingthatwasneverset"))
      end)

      it("returns false only when feature is false", function()
        -- retired memes are calling, they are asking you to visit them
        assert.is_false(lic:can("hascheezburger"))
      end)
    end)

    describe("MagicTable™", function()
      local magic_table

      describe("lazy = true", function()
        lazy_setup(function()
          local some_data = {
            foo = "bar",
            bar = "baz",
            whatever = function()
              return "hello world"
            end,
          }
          magic_table = lic.MagicTable({}, { lazy = true })
          magic_table:update(some_data)
        end)

        it("lazily evaluates a particular source of data", function()
          assert.equal("bar", magic_table.foo)
          assert.same({ foo = "bar"} , magic_table)
          assert.equal("baz", magic_table.bar)
          assert.same({ foo = "bar", bar = "baz" } , magic_table)
        end)

        it("evaluates functions", function()
          assert.equal("hello world", magic_table.whatever)
        end)
      end)

      describe("lazy = false", function()
        local some_data = {
          foo = "bar",
          bar = "baz",
          hard = { stuff = "hey" },
        }

        before_each(function()
          magic_table = lic.MagicTable({}, { lazy = false })
          magic_table:update(some_data)
        end)

        it("updates itself data", function()
          assert.same({
            foo = "bar",
            bar = "baz",
            hard = { stuff = "hey" },
          }, magic_table)
        end)

        it("can be progressively updated", function()
          magic_table:update({ bar = "hey there" })
          assert.same({
            foo = "bar",
            bar = "hey there",
            hard = { stuff = "hey" },
          }, magic_table)
          assert.equal("hey there", magic_table.bar)
        end)

        it("a progressive update can evaluate functions", function()
          magic_table:update({
            something = "normal",
            -- NOOP removes values
            foo = function() end,
            hey_there = function() return "hello world" end
          }, true)
          assert.same({
            bar = "baz",
            hard = { stuff = "hey" },
            something = "normal",
            hey_there = "hello world",
          }, magic_table)
        end)
      end)

    end)

  end)

  describe("#rbac", function()
    local featureset

    setup(function()
      featureset = {
        allow_admin_api = {
          ["/rbac/users"] = { GET = true, OPTION = true },
          ["/rbac/users/:rbac_users"] = { GET = true, OPTION = true },
        },
        deny_admin_api = {
          ["/rbac/users"] = { ["*"] = true },
          ["/rbac/users/:rbac_users"] = { ["*"] = true },
        },
      }
    end)

    local license = { some = "some_invalid_license" }

    lazy_setup(function()
      assert(stub(lic_helper, "get_featureset").returns(featureset))
      assert(stub(lic_helper, "read_license_info").returns(license))
      kong.licensing:update()
    end)

    it("should allow rbac endpoints with defined methods", function()
      for _, method in ipairs({ "GET", "OPTION" }) do
        assert(stub(ngx.req, "get_method").returns(method))

        -- clean up calls
        assert(stub(kong.response, "exit"))
        assert.is_nil(lic_helper.license_can_proceed({ route_name = "/rbac/users" }))
        assert.stub(kong.response.exit).was_called(0)

        -- clean up calls
        assert(stub(kong.response, "exit"))
        assert.is_nil(lic_helper.license_can_proceed({ route_name = "/rbac/users/:rbac_users" }))
        assert.stub(kong.response.exit).was_called(0)
      end
    end)

    it("should deny rbac endpoints with undefined methods", function()
      for _, method in ipairs({ "POST", "PUT", "PATCH", "DELETE" }) do
        assert(stub(ngx.req, "get_method").returns(method))

        -- clean up calls
        assert(stub(kong.response, "exit"))
        assert.is_nil(lic_helper.license_can_proceed({ route_name = "/rbac/users" }))
        assert.stub(kong.response.exit).was.called_with(403, { message = "Enterprise license missing or expired" })

        -- clean up calls
        assert(stub(kong.response, "exit"))
        assert.is_nil(lic_helper.license_can_proceed({ route_name = "/rbac/users/:rbac_users" }))
        assert.stub(kong.response.exit).was.called_with(403, { message = "Enterprise license missing or expired" })
      end
    end)
  end)
end)
