local helpers = require "spec.helpers"
local Errors = require "kong.db.errors"

local fmt      = string.format


describe("DB Errors", function()
  describe("error types", function()
    local e = Errors.new("some_strategy")

    describe("DATABASE_ERROR", function()
      describe("RBAC_ERROR", function()
        local err_t = e:unauthorized_operation({
          username = "alice",
          action = "read"
        })

        it("creates", function()
          assert.same({
            code = Errors.codes.RBAC_ERROR,
            name = "unauthorized access",
            strategy = "some_strategy",
            message = "alice, you do not have permissions to read this resource",
          }, err_t)

          local s = fmt("[%s] %s", err_t.strategy, err_t.message)
          assert.equals(s, tostring(err_t))
        end)
      end)
    end)
  end)
end)
