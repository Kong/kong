local helpers = require "spec.helpers"
local Errors = require "kong.db.errors"
local defaults = require "kong.db.strategies.connector".defaults

local fmt      = string.format
local unindent = helpers.unindent


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
    local e = Errors.new("some_strategy")

    describe("INVALID_PRIMARY_KEY", function()
      local pk = {
        id = "missing",
        id2 = "missing2",
      }

      local err_t = e:invalid_primary_key(pk)

      it("creates", function()
        assert.same({
          code = Errors.codes.INVALID_PRIMARY_KEY,
          name = "invalid primary key",
          strategy = "some_strategy",
          message = [[invalid primary key: '{id="missing",id2="missing2"}']],
          fields = pk,
        }, err_t)
      end)

      it("__tostring", function()
        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)
    end)


    describe("INVALID_FOREIGN_KEY", function()
      local pk = {
        id = "missing",
        id2 = "missing2",
      }

      local err_t = e:invalid_foreign_key(pk)

      it("creates", function()
        assert.same({
          code = Errors.codes.INVALID_FOREIGN_KEY,
          name = "invalid foreign key",
          strategy = "some_strategy",
          message = [[invalid foreign key: '{id="missing",id2="missing2"}']],
          fields = pk,
        }, err_t)
      end)

      it("__tostring", function()
        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)
    end)


    describe("SCHEMA_VIOLATION", function()
      local schema_errors = {
        foo = "expected an integer",
        bar = "length must be 5",
        baz = "unknown field",
        ["@entity"] = {
          "at least one of plim or plum is needed",
          "the check function errored out",
          "an extra error",
        },
        external_entity = {
          id = "missing primary key",
        }
      }

      local err_t = e:schema_violation(schema_errors)

      it("creates with multiple errors", function()
        assert.same({
          code = Errors.codes.SCHEMA_VIOLATION,
          name = "schema violation",
          strategy = "some_strategy",
          message = unindent([[
            7 schema violations
            (at least one of plim or plum is needed;
            the check function errored out;
            an extra error;
            bar: length must be 5;
            baz: unknown field;
            external_entity.id: missing primary key;
            foo: expected an integer)
          ]], true, true),
          fields = schema_errors,
        }, err_t)
      end)

      it("creates with a single error", function()
        local schema_errors = {
          ["@entity"] = {
            "the check function errored out",
          },
        }

        local err_t = e:schema_violation(schema_errors)

        assert.same({
          code = Errors.codes.SCHEMA_VIOLATION,
          name = "schema violation",
          strategy = "some_strategy",
          message = "schema violation (the check function errored out)",
          fields = schema_errors,
        }, err_t)
      end)

      it("__tostring", function()
        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
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
          strategy = "some_strategy",
          message = [[primary key violation on key '{id="already exists"}']],
          fields = pk,
        }, err_t)
      end)

      it("__tostring", function()
        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
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
          strategy = "some_strategy",
          message = unindent([[
            the foreign key '{foreign_id="0000-00-00-00000000"}' does not
            reference an existing 'services' entity.
          ]], true, true),
          fields = entity,
        }, err_t)

        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)

      it("creates a delete error message", function()
        local err_t = e:foreign_key_violation_restricted(parent_name, child_name)

        assert.same({
          code = Errors.codes.FOREIGN_KEY_VIOLATION,
          name = "foreign key violation",
          strategy = "some_strategy",
          message = "an existing 'routes' entity references this 'services' entity",
          fields = {
            ["@referenced_by"] = child_name,
          },
        }, err_t)

        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)

    end)


    describe("NOT_FOUND", function()
      local pk = { id = "0000-00-00-00-00000000" }
      local err_t = e:not_found(pk)

      it("creates", function()
        assert.same({
          code = Errors.codes.NOT_FOUND,
          name = "not found",
          strategy = "some_strategy",
          message = unindent([[
            could not find the entity with primary key
            '{id="0000-00-00-00-00000000"}'
          ]], true, true),
          fields = pk,
        }, err_t)
      end)

      it("__tostring", function()
        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)
    end)

    describe("UNIQUE_VIOLATION", function()
      local pk = { id = "0000-00-00-00-00000000" }
      local err_t = e:unique_violation(pk)

      it("creates", function()
        assert.same({
          code = Errors.codes.UNIQUE_VIOLATION,
          name = "unique constraint violation",
          strategy = "some_strategy",
          message =
            [[UNIQUE violation detected on '{id="0000-00-00-00-00000000"}']],
          fields = pk,
        }, err_t)
      end)

      it("__tostring", function()
        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)
    end)


    describe("INVALID_OFFSET", function()
      local err_t = e:invalid_offset("bad offset", "decoding error")

      it("creates", function()
        assert.same({
          code = Errors.codes.INVALID_OFFSET,
          name = "invalid offset",
          strategy = "some_strategy",
          message = "'bad offset' is not a valid offset: decoding error",
        }, err_t)
      end)

      it("__tostring", function()
        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)
    end)


    describe("DATABASE_ERROR", function()
      it("creates", function()
        local err_t = e:database_error()
        assert.same({
          code = Errors.codes.DATABASE_ERROR,
          name = "database error",
          strategy = "some_strategy",
          message = "database error",
        }, err_t)

        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)

      it("creates with error string as message", function()
        local err_t = e:database_error("timeout")
        assert.same({
          code = Errors.codes.DATABASE_ERROR,
          name = "database error",
          strategy = "some_strategy",
          message = "timeout",
        }, err_t)

        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)
    end)


    describe("TRANSFORMATION_ERROR", function()
      it("creates", function()
        local err_t = e:transformation_error()
        assert.same({
          code = Errors.codes.TRANSFORMATION_ERROR,
          name = "transformation error",
          strategy = "some_strategy",
          message = "transformation error",
        }, err_t)

        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)

      it("creates with error string as message", function()
        local err_t = e:transformation_error("timeout")
        assert.same({
          code = Errors.codes.TRANSFORMATION_ERROR,
          name = "transformation error",
          strategy = "some_strategy",
          message = "timeout",
        }, err_t)

        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)
    end)


    describe("INVALID_SIZE", function()
      local err_t = e:invalid_size("size must be an integer between 1 and " .. defaults.pagination.max_page_size)

      it("creates", function()
        assert.same({
          code = Errors.codes.INVALID_SIZE,
          name = "invalid size",
          strategy = "some_strategy",
          message = "size must be an integer between 1 and " .. defaults.pagination.max_page_size,
        }, err_t)
      end)

      it("__tostring", function()
        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)
    end)

    describe("INVALID_UNIQUE", function()
      local err_t = e:invalid_unique("name", "name must be a string")

      it("creates", function()
        assert.same({
          code = Errors.codes.INVALID_UNIQUE,
          name = "invalid unique name",
          strategy = "some_strategy",
          message = "name must be a string",
        }, err_t)
      end)

      it("__tostring", function()
        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)
    end)


    describe("INVALID_OPTIONS", function()
      local options_errors = {
        ttl = "option can only be used with inserts, updates and upserts, not with 'deletes'",
        bar = {
          "must be a string",
          "must contain 'foo'"
        }
      }

      local err_t = e:invalid_options(options_errors)

      it("creates with multiple errors", function()
        assert.same({
          code = Errors.codes.INVALID_OPTIONS,
          name = "invalid options",
          strategy = "some_strategy",
          message = unindent([[
            3 option violations
            (bar.1: must be a string;
            bar.2: must contain 'foo';
            ttl: option can only be used with inserts, updates and upserts, not with 'deletes')
          ]], true, true),
          options = options_errors,
        }, err_t)
      end)

      it("creates with a single error", function()
        local options_errors = {
          ttl = "option can only be used with inserts, updates and upserts, not with 'deletes'",
        }

        local err_t = e:invalid_options(options_errors)

        assert.same({
          code = Errors.codes.INVALID_OPTIONS,
          name = "invalid options",
          strategy = "some_strategy",
          message = "invalid option (ttl: option can only be used with inserts, updates and upserts, not with 'deletes')",
          options = options_errors,
        }, err_t)
      end)

      it("__tostring", function()
        local s = fmt("[%s] %s", err_t.strategy, err_t.message)
        assert.equals(s, tostring(err_t))
      end)
    end)
  end)
end)
