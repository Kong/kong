require "spec.dao.sqlite.configuration"
local dao_factory = require "apenode.dao.sqlite"

describe("DetailedDaos", function()

  setup(function()
    dao_factory.populate()
  end)

  teardown(function()
    dao_factory.drop()
  end)

  describe("AccountsDao", function()

    describe("#get_by_provider_id()", function()
      it("should get an account by provider_id", function()
        local result, err = dao_factory.accounts:get_by_provider_id("provider3")
        assert.truthy(result)
        assert.are.equal("provider3", result.provider_id)
      end)
      it("should return nil if account does not exist", function()
        local result = dao_factory.accounts:get_by_provider_id("nothing")
        assert.falsy(result)
        assert.are.equal(nil, result)
      end)
    end)

  end)

  describe("APIsDao", function()

    describe("#get_by_host()", function()
      it("should get an API by host", function()
        local result, err = dao_factory.apis:get_by_host("apebin20.com")
        assert.truthy(result)
        assert.are.equal("apebin20.com", result.public_dns)
      end)
      it("should return nil if API does not exist", function()
        local result = dao_factory.apis:get_by_host("nothing")
        assert.falsy(result)
        assert.are.equal(nil, result)
      end)
    end)

  end)

  describe("ApplicationsDao", function()

    describe("#get_by_account_id()", function()
      it("should get a list of applications by account_id", function()
        local result, count = dao_factory.applications:get_by_account_id(1)
        assert.truthy(count)
        assert.are.equal(1000, count)
        assert.truthy(result)
      end)
      it("should return an empty list if application does not exist", function()
        local result, count = dao_factory.applications:get_by_account_id("none")
        assert.truthy(count)
        assert.are.equal(0, count)
        assert.are.same({}, result)
      end)
    end)

  end)

end)
