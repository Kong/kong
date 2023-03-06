local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

-- no cassandra support
for _, strategy in helpers.each_strategy({ "postgres" }) do

describe("WASMX DB entities [#" .. strategy .. "]", function()
  local db, dao

  local function reset_db()
    if not db then return end
    db.wasm_filter_chains:truncate()
    db.wasm_filter_chains:load_filters({})
    db.routes:truncate()
    db.services:truncate()
    db.workspaces:truncate()
  end


  lazy_setup(function()
    local _
    _, db = helpers.get_db_utils(strategy, {
      "workspaces",
      "routes",
      "services",
      "wasm_filter_chains",
    })

    dao = db.wasm_filter_chains
    dao:load_filters({
      { name = "test", },
      { name = "other", },
    })
  end)

  lazy_teardown(reset_db)

  describe("wasm_filter_chains", function()
    describe(".id", function()
      it("is auto-generated", function()
        local chain = assert(dao:insert({
          id = nil,
          filters = { { name = "test" } },
        }))

        assert.is_string(chain.id)
        assert.truthy(utils.is_valid_uuid(chain.id))
      end)

      it("can be user-generated", function()
        local id = utils.uuid()
        local chain = assert(dao:insert({
          id = id,
          filters = { { name = "test" } },
        }))

        assert.is_string(chain.id)
        assert.equals(id, chain.id)
        assert.truthy(utils.is_valid_uuid(chain.id))
      end)

      it("must be a valid uuid", function()
        local chain, err, err_t = dao:insert({
          id = "nope!",
          filters = { { name = "test" } },
        })

        assert.is_nil(chain, err)
        assert.is_string(err)
        assert.is_table(err_t)

        assert.same({ id = "expected a valid UUID" }, err_t.fields)
        assert.equals("schema violation", err_t.name)
      end)
    end)

    describe(".name", function()
      it("is optional", function()
        assert(dao:insert({
          name = nil,
          filters = { { name = "test" } },
        }))
      end)

      it("must be a string", function()
        local chain, err, err_t = dao:insert({
          name = 123,
          filters = { { name = "other" } },
        })

        assert.is_nil(chain)
        assert.is_string(err)
        assert.is_table(err_t)

        assert.equals("schema violation", err_t.name)
        assert.same({ name = "expected a string" }, err_t.fields)
      end)

      it("must be unique", function()
        assert(dao:insert({
          name = "not-unique",
          filters = { { name = "test" } },
        }))

        local chain, err, err_t = dao:insert({
          name = "not-unique",
          filters = { { name = "other" } },
        })

        assert.is_nil(chain)
        assert.is_string(err)
        assert.is_table(err_t)

        assert.is_string(err_t.fields.name)
        assert.equals("unique constraint violation", err_t.name)
      end)
    end)

    describe(".enabled", function()
      it("defaults to 'true'", function()
        local chain = assert(dao:insert({
          name = "enabled-test",
          enabled = nil,
          filters = { { name = "test" } },
        }))

        assert.is_true(chain.enabled)
      end)

      it("must be a boolean", function()
        local chain, err, err_t = dao:insert({
          name = "enabled-invalid-test",
          enabled = "nope!",
          filters = { { name = "test" } },
        })

        assert.is_nil(chain)
        assert.is_string(err)
        assert.is_table(err_t)

        assert.equals("schema violation", err_t.name)
        assert.same({ enabled = "expected a boolean" }, err_t.fields)
      end)
    end)

    describe(".route", function()
      it("references a route", function()
        local route = assert(db.routes:insert({
          protocols = { "http" },
          methods = { "GET" },
          paths = { "/" },
        }))

        local chain, err = dao:insert({
          name = "chain-with-route",
          filters = { { name = "test" } },
          route = { id = route.id },
        })

        assert.is_table(chain, err)
        assert.is_nil(err)
        assert.equals(route.id, chain.route.id)
      end)

      it("requires the route to exist", function()
        local chain, err, err_t = dao:insert({
          name = "chain-with-missing-route",
          filters = { { name = "test" } },
          route = { id = utils.uuid() },
        })

        assert.is_nil(chain)
        assert.is_string(err)
        assert.is_table(err_t)

        assert.equals("foreign key violation", err_t.name)
        assert.is_table(err_t.fields)
        assert.is_table(err_t.fields.route)
      end)
    end)

    describe(".service", function()
      it("references a service", function()
        local service = assert(db.services:insert({
          url = "http://wasm.test/",
        }))

        local chain, err = dao:insert({
          name = "chain-with-service",
          filters = { { name = "test" } },
          service = { id = service.id },
        })

        assert.is_table(chain, err)
        assert.is_nil(err)
        assert.equals(service.id, chain.service.id)
      end)

      it("requires the service to exist", function()
        local chain, err, err_t = dao:insert({
          name = "chain-with-missing-service",
          filters = { { name = "test" } },
          service = { id = utils.uuid() },
        })

        assert.is_nil(chain)
        assert.is_string(err)
        assert.is_table(err_t)

        assert.equals("foreign key violation", err_t.name)
        assert.is_table(err_t.fields)
        assert.is_table(err_t.fields.service)
      end)
    end)

    describe(".created_at", function()
      it("is auto-generated", function()
        local chain = assert(dao:insert({
          name = "created-at-test",
          filters = { { name = "test" } },
        }))

        assert.is_number(chain.created_at)
        assert.truthy(math.abs(ngx.now() - chain.created_at) < 5)
      end)
    end)

    describe(".updated_at", function()
      it("is updated when the entity is updated", function()
        local chain = assert(dao:insert({
          name = "updated-at-test",
          filters = { { name = "test" } },
        }))

        assert.is_number(chain.updated_at)

        helpers.wait_until(function()
          local updated = assert(dao:update(
            { id = chain.id },
            { tags = { utils.uuid() } }
          ))

          return updated.updated_at > chain.updated_at
        end, 5, 0.1)
      end)
    end)

    describe(".tags", function()
      it("has tags", function()
        local chain = assert(dao:insert({
          name = "tags-test",
          filters = { { name = "test" } },
        }))

        assert.is_nil(chain.tags)

        chain = assert(dao:update({ id = chain.id }, { tags = { "foo" } }))
        assert.same({ "foo" }, chain.tags)
      end)
    end)

    describe(".filters", function()
      it("are required", function()
        local chain, err, err_t = dao:insert({
          name = "no-filters",
        })

        assert.is_nil(chain)
        assert.is_string(err)
        assert.is_table(err_t)
        assert.same({ filters = "required field missing" }, err_t.fields)
      end)

      it("cannot be empty", function()
        local chain, err, err_t = dao:insert({
          name = "zero-len-filters",
          filters = {},
        })

        assert.is_nil(chain)
        assert.is_string(err)
        assert.is_table(err_t)
        assert.same({ filters = "length must be at least 1" }, err_t.fields)
      end)

      describe(".name", function()
        it("is required", function()
          local chain, err, err_t = dao:insert({
            name = "no-name-filter",
            filters = { { config = "config" } },
          })

          assert.is_nil(chain)
          assert.is_string(err)
          assert.is_table(err_t)
          assert.is_table(err_t.fields)
          assert.is_table(err_t.fields.filters)
          assert.same({ [1] = { name = "required field missing" } }, err_t.fields.filters)
        end)

        it("must be a valid, enabled filter name", function()
          local chain, err, err_t = dao:insert({
            name = "missing-filter-insert-test",
            filters = {
              { name = "test" },
              { name = "missing" },
              { name = "other" },
              { name = "also-missing" },
            },
          })

          assert.is_nil(chain)
          assert.is_string(err)
          assert.is_table(err_t)
          assert.is_table(err_t.fields)
          assert.same({
            filters = {
              [2] = { name = "no such filter: missing" },
              [4] = { name = "no such filter: also-missing" },
            },
          }, err_t.fields)

          assert(dao:insert({
            name = "missing-filter-update-test",
            filters = { { name = "test" } },
          }))

          chain, err, err_t = dao:insert({
            name = "missing-filter-update-test",
            filters = {
              { name = "test" },
              { name = "missing" },
              { name = "other" },
              { name = "also-missing" },
            },
          })

          assert.is_nil(chain)
          assert.is_string(err)
          assert.is_table(err_t)
          assert.is_table(err_t.fields)
          assert.same({
            filters = {
              [2] = { name = "no such filter: missing" },
              [4] = { name = "no such filter: also-missing" },
            },
          }, err_t.fields)

        end)
      end)

      describe(".enabled", function()
        it("defaults to 'true'", function()
          local chain = assert(dao:insert({
            filters = { { name = "test" } },
          }))

          assert.is_true(chain.filters[1].enabled)
        end)
      end)

      describe(".config", function()
        pending("is validated against the filter schema")
      end)
    end)
  end)
end)

end -- each strategy
