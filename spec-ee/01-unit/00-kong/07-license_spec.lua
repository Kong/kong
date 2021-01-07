-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local lic_helper = require "kong.enterprise_edition.license_helpers"

local match = require 'luassert.match'
describe("licensing", function()
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

  it("does ERR from -1 days on from expiration date", function()
    lic_helper.log_license_state(os.time()-3600*24, os.time())
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

    setup(function()
      _G.kong = {
        response = mock(setmetatable({}, { __index = function() return function() end end })),
      }
    end)

    teardown(function()
      assert(mock.revert(kong))
    end)

    before_each(function()
      assert(stub(lic_helper, "featureset").returns(featureset))
      assert(stub(kong.response, "exit"))
    end)

    after_each(function()
      assert(lic_helper.featureset:revert())
      assert(mock.revert(ngx.req.get_method))
      assert(kong.response.exit:revert())
    end)

    describe("deny_admin_api", function()
      setup(function()
        featureset = {
          abilities = {
            deny_admin_api = {
              ["/workspaces"] = { GET = true, OPTION = true },
              ["/workspaces/:workspaces"] = { ["*"] = true },
            },
            allow_admin_api = {},
          }
        }
      end)

      it("denies defined methods", function()
        for _, method in ipairs({ "GET", "OPTION" }) do
          -- clean up calls
          assert(stub(kong.response, "exit"))
          assert(stub(ngx.req, "get_method").returns(method))
          assert.is_nil(lic_helper.license_can_proceed({route_name = "/workspaces"}))
          assert.stub(kong.response.exit).was.called_with(403,  { message = "Forbidden" })
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
          assert.stub(kong.response.exit).was.called_with(403,  { message = "Forbidden" })
        end
      end)
    end)

    describe("allow_admin_api + deny_admin_api", function()
      setup(function()
        featureset = {
          abilities = {
            allow_admin_api = {
              ["/workspaces"] = { GET = true, OPTION = true},
              ["/identity"] = { ["*"] = true },
            },
            deny_admin_api = {
              ["/workspaces"] = { ["*"] = true },
              ["/identity"] = { ["*"] = true },
            },
          }
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
          assert.stub(kong.response.exit).was.called_with(403,  { message = "Forbidden" })
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

    describe("write_admin_api", function()
      describe("false", function()
        setup(function()
          featureset = {
            abilities = {
              deny_admin_api = {},
              allow_admin_api = {
                ["/workspaces"] = { ["*"] = true },
              },
              write_admin_api = false,
            }
          }
        end)

        for _, method in ipairs({"POST", "PUT", "PATCH", "DELETE"}) do
          it("denies ".. method, function()
            assert(stub(ngx.req, "get_method").returns(method))
            assert.is_nil(lic_helper.license_can_proceed({route_name = "/foo"}))
            assert.stub(kong.response.exit).was.called_with(403,  { message = "Forbidden" })
          end)
        end

        for _, method in ipairs({"GET", "OPTION"}) do
          it("allows ".. method, function()
            assert(stub(ngx.req, "get_method").returns(method))
            assert.is_nil(lic_helper.license_can_proceed({route_name = "/foo"}))
            assert.stub(kong.response.exit).was_called(0)
          end)
        end

        for _, method in ipairs({"POST", "PUT", "PATCH", "DELETE"}) do
          it("+ allow_admin_api allows " .. method .. " anyway", function()
            assert(stub(ngx.req, "get_method").returns(method))
            assert.is_nil(lic_helper.license_can_proceed({route_name = "/workspaces"}))
            assert.stub(kong.response.exit).was_called(0)
          end)
        end
      end)

      describe("true", function()
        setup(function()
          featureset = {
            abilities = {
              deny_admin_api = {},
              allow_admin_api = {},
              write_admin_api = true,
            }
          }
        end)

        for _, method in ipairs({"GET", "OPTION", "POST", "PUT", "PATCH", "DELETE"}) do
          it("allows ".. method, function()
            assert(stub(ngx.req, "get_method").returns(method))
            assert.is_nil(lic_helper.license_can_proceed({route_name = "/foo"}))
            assert.stub(kong.response.exit).was_called(0)
          end)
        end
      end)
    end)
  end)
end)
