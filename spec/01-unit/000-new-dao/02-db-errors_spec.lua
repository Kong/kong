require "spec.helpers"
local Errors = require "kong.db.errors"


describe("DB Errors", function()
  describe(".codes table", function()
    it("is a map of unique error codes", function()
      local seen = {}

      for k, v in pairs(Errors.codes) do
        if seen[v] then
          assert.fail("duplicated error code between " ..
                      k .. " and " .. seen[v])
        end

        seen[v] = k
      end
    end)

    it("all error codes have a name", function()
      for k, v in pairs(Errors.codes) do
        local ok
        for kk, vv in pairs(Errors.names) do
          if kk == v then
            ok = true
          end
        end

        if not ok then
          assert.fail("no name for error code: " .. k)
        end
      end
    end)
  end)

  describe("error types", function()
    local e = Errors.new("some strategy")

    describe("INVALID_PRIMARY_KEY", function()
      local pk = {
        id = "missing",
        id2 = "expected be a uuid",
      }

      local err_t = e:invalid_primary_key(pk)

      it("creates", function()
        assert.same({
          code = Errors.codes.INVALID_PRIMARY_KEY,
          name = "invalid primary key",
          strategy = "some strategy",
          message = ngx.null,
          fields = {
            id = "missing",
            id2 = "expected be a uuid",
          }
        }, err_t)
      end)

      it("__tostring", function()
        assert.equals("invalid primary key", tostring(err_t))
      end)
    end)


    describe("SCHEMA_VIOLATION", function()
      local schema_errors = {
        foo = "expected an integer",
        bar = "length must be 5",
        baz = "unknown field",
      }

      local err_t = e:schema_violation(schema_errors)

      it("creates", function()
        assert.same({
          code = Errors.codes.SCHEMA_VIOLATION,
          name = "schema violation",
          strategy = "some strategy",
          message = ngx.null,
          fields = {
            bar = "length must be 5",
            baz = "unknown field",
            foo = "expected an integer"
          }
        }, err_t)
      end)

      it("creates with a 'check' error", function()
        schema_errors[1] = "check function errored out"

        err_t = e:schema_violation(schema_errors)

        assert.same({
          code = Errors.codes.SCHEMA_VIOLATION,
          name = "schema violation",
          strategy = "some strategy",
          message = ngx.null,
          check = "check function errored out",
          fields = {
            bar = "length must be 5",
            baz = "unknown field",
            foo = "expected an integer"
          }
        }, err_t)
      end)

      pending("__tostring", function()

      end)
    end)


    describe("PRIMARY_KEY_VIOLATION", function()
      local pk = {
        id = "already exists"
      }

      local err_t = e:primary_key_violation(pk)

      it("creates", function()
        assert.same({
          code = Errors.codes.PRIMARY_KEY_VIOLATION,
          name = "primary key violation",
          strategy = "some strategy",
          message = ngx.null,
          fields = {
            id = "already exists",
          }
        }, err_t)
      end)

      pending("__tostring", function()

      end)
    end)


    describe("FOREIGN_KEY_VIOLATION", function()
      local parent_name = "services"
      local child_name = "routes"

      local entity = {
        service = {
          foreign_id = "0000-00-00-00000000"
        }
      }

      it("creates an insert/update error message", function()
        local err_t = e:foreign_key_violation_invalid_reference(entity.service,
                                                                "service",
                                                                parent_name)

        assert.same({
          code = Errors.codes.FOREIGN_KEY_VIOLATION,
          name = "foreign key violation",
          strategy = "some strategy",
          message = "the provided foreign key does not reference an existing 'services' entity",
          fields = {
            service = {
              foreign_id = "0000-00-00-00000000",
            }
          },
        }, err_t)
      end)

      it("creates a delete error message", function()
        local err_t = e:foreign_key_violation_restricted(parent_name, child_name)

        assert.same({
          code = Errors.codes.FOREIGN_KEY_VIOLATION,
          name = "foreign key violation",
          strategy = "some strategy",
          message = "an existing 'routes' entity references this 'services' entity",
          fields = {
            ["@referenced_by"] = child_name,
          },
        }, err_t)
      end)

      pending("__tostring", function()

      end)
    end)


    describe("NOT_FOUND", function()
      local err_t = e:not_found({ id = "0000-00-00-00-00000000" })

      it("creates", function()
        assert.same({
          code = Errors.codes.NOT_FOUND,
          name = "not found",
          strategy = "some strategy",
          message = ngx.null,
          fields = {
            id = "0000-00-00-00-00000000"
          },
        }, err_t)
      end)

      pending("__tostring", function()

      end)
    end)


    describe("INVALID_OFFSET", function()
      it("creates", function()
        local err_t = e:invalid_offset("bad offset", "decoding error")
        assert.same({
          code = Errors.codes.INVALID_OFFSET,
          name = "invalid offset",
          strategy = "some strategy",
          message = "'bad offset' is not a valid offset for this strategy: decoding error",
        }, err_t)
      end)

      pending("__tostring", function()

      end)
    end)


    describe("DATABASE_ERROR", function()
      it("creates", function()
        local err_t = e:database_error()
        assert.same({
          code = Errors.codes.DATABASE_ERROR,
          name = "unknown database error",
          strategy = "some strategy",
          message = ngx.null,
        }, err_t)
      end)

      it("creates with error string as message", function()
        local err_t = e:database_error("timeout")
        assert.same({
          code = Errors.codes.DATABASE_ERROR,
          name = "unknown database error",
          strategy = "some strategy",
          message = "timeout",
        }, err_t)
      end)

      pending("__tostring", function()

      end)
    end)
  end)
end)
