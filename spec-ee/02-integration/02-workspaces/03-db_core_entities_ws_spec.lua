local Errors  = require "kong.db.errors"
local utils   = require "kong.tools.utils"
local helpers = require "spec.helpers"

local fmt      = string.format
local with_current_ws = helpers.with_current_ws


local a_blank_uuid = "00000000-0000-0000-0000-000000000000"

local function add_ws(db, ws_name)
  return db.workspaces:select_by_name(ws_name) or
    assert(db.workspaces:insert({name = ws_name}))
end


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp, _

    lazy_setup(function()
      ngx.ctx.workspaces = nil
      bp, db, _ = helpers.get_db_utils(strategy)
    end)

    lazy_teardown(function()
      db:truncate()
    end)

    describe("Routes", function()
      describe(":insert()", function()
        it("joider creates a Route in default workspace", function()
          local route, err_t, err = db.routes:insert({
            protocols = { "http" },
            hosts = { "example.com" },
            service = assert(db.services:insert({ host = "service.com" })),
          })

          assert.is_nil(err_t)
          assert.is_nil(err)

          assert.is_table(route)
          assert.is_number(route.created_at)
          assert.is_number(route.updated_at)
          assert.is_true(utils.is_valid_uuid(route.id))

          assert.same({
            id              = route.id,
            created_at      = route.created_at,
            updated_at      = route.updated_at,
            protocols       = { "http" },
            hosts           = { "example.com" },
            regex_priority  = 0,
            preserve_host   = false,
            strip_path      = true,
            service         = route.service,
          }, route)

          local ws = db.workspaces:select_by_name("default")
          local default_ws = ws
          local rel = db.workspace_entities:select({
            workspace_id = default_ws.id,
            entity_id = route.id,
            unique_field_name = "id"
          })

          assert.is_not_nil(rel)
          assert.same({
            entity_id = route.id,
            entity_type = "routes",
            unique_field_name = "id",
            unique_field_value = route.id,
            workspace_id = default_ws.id,
            workspace_name = "default"
          }, rel)
        end)

        it("creates a Route in non-default workspacess", function()
          local foo_ws = assert(add_ws(db, "foo"))

          with_current_ws({ foo_ws }, function ()
            -- add route in foo workspace
            local service = assert(db.services:insert({ host = "service.com" }))
            local route, err_t, err = db.routes:insert({
              protocols = { "http" },
              hosts = { "example.com" },
              service = service,
            })

            assert.is_nil(err_t)
            assert.is_nil(err)

            assert.is_table(route)
            assert.is_number(route.created_at)
            assert.is_number(route.updated_at)
            assert.is_true(utils.is_valid_uuid(route.id))

            assert.same({
              id              = route.id,
              created_at      = route.created_at,
              updated_at      = route.updated_at,
              protocols       = { "http" },
              hosts           = { "example.com" },
              regex_priority  = 0,
              preserve_host   = false,
              strip_path      = true,
              service         = route.service,
            }, route)

            -- validate relationship
            local rel = db.workspace_entities:select({
              workspace_id = foo_ws.id,
              entity_id = route.id,
              unique_field_name = "id"
            })

            assert.is_not_nil(rel)
            assert.same({
              entity_id = route.id,
              entity_type = "routes",
              unique_field_name = "id",
              unique_field_value = route.id,
              workspace_id = foo_ws.id,
              workspace_name = "foo"
            }, rel)
          end, db)
        end)

        it("shouldn't allow insert of route with service from other workspace", function()
          local service_default
          with_current_ws(nil, function()
            local err_t, err
            service_default, err_t, err = db.services:insert({ host = "service.com" })
            assert.is_nil(err_t)
            assert.is_nil(err)

          end, db)
          local foo_ws = add_ws(db, "foo")
          with_current_ws({ foo_ws }, function ()
            -- add route in foo workspace
            local route, err_t, err = db.routes:insert({
              protocols = { "http" },
              hosts = { "example.com" },
              service = service_default,
            })
            assert.is_nil(route)
            assert.is_not_nil(err_t)
            assert.is_not_nil(err)
          end)
        end)
      end)

      describe(":select()", function()
        lazy_setup(function()
          db:truncate()
        end)

        it("returns an existing Route from default workspace", function()
          with_current_ws( nil,function ()
            local route_inserted = bp.routes:insert({
            hosts = { "example.com" },
            })
            local route, err, err_t = db.routes:select({ id = route_inserted.id })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same(route_inserted, route)
          end, db)
        end)

        it("returns an existing Route from foo workspace", function()
          local foo_ws = add_ws(db, "foo")
          with_current_ws( {foo_ws},function()
            local route_inserted = bp.routes:insert({
              hosts = { "example.com" },
              service = assert(db.services:insert({ host = "service.com" }))
            })
            local route, err, err_t = db.routes:select({ id = route_inserted.id })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same(route_inserted, route)
          end, db)
        end)

        it("should not return foo service from default workspace", function()
          local foo_ws = add_ws(db, "foo")
          local service_inserted
          with_current_ws( {foo_ws},function()
            service_inserted = db.services:insert({ host = "service.com" })
            local service, err, err_t = db.services:select({ id = service_inserted.id })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same(service_inserted, service)
          end, db)

          local service, err, err_t = db.services:select({ id = service_inserted.id })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.is_nil(service)
        end)
      end)

      describe(":update() in non-default workspace", function()
        lazy_setup(function()
          db:truncate()
        end)

        -- I/O
        it("returns not found error", function()
          local foo_ws = add_ws(db, "foo")
          with_current_ws( {foo_ws},function()
            local pk = { id = utils.uuid() }
            local new_route, err, err_t = db.routes:update(pk, {
              protocols = { "https" }
            })
            assert.is_nil(new_route)
            assert.is_not_nil(err_t)
            assert.is_not_nil(err)
          end, db)
        end)

        it("updates an existing Route", function()
          local foo_ws = add_ws(db, "foo")
          with_current_ws( {foo_ws},function()
            local route = db.routes:insert({
              protocols = { "http" },
              hosts = { "example.com" },
              service = assert(db.services:insert({ host = "service.com" })),
            })

            ngx.sleep(1)

            local new_route, err, err_t = db.routes:update({ id = route.id }, {
              protocols = { "https" },
              regex_priority = 5,
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same({
              id              = route.id,
              created_at      = route.created_at,
              updated_at      = new_route.updated_at,
              protocols       = { "https" },
              methods         = route.methods,
              hosts           = route.hosts,
              paths           = route.paths,
              regex_priority  = 5,
              strip_path      = route.strip_path,
              preserve_host   = route.preserve_host,
              service         = route.service,
            }, new_route)
          end, db)
        end)

        it("shouldn't allow to update route with service from other workspace", function()
          local service_default
          with_current_ws(nil, function()
            local err_t, err
            service_default, err_t, err = db.services:insert({ host = "service.com" })
            assert.is_nil(err_t)
            assert.is_nil(err)

          end, db)
          local foo_ws = add_ws(db, "foo")

          with_current_ws({ foo_ws }, function ()
            -- add route in foo workspace
            local route = db.routes:insert({
              protocols = { "http" },
              hosts = { "example.com" },
              service = assert(db.services:insert({ host = "service.com" })),
            })

            ngx.sleep(1)

            local new_route, err, err_t = db.routes:update({ id = route.id }, {
              protocols = { "https" },
              regex_priority = 5,
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same({
              id              = route.id,
              created_at      = route.created_at,
              updated_at      = new_route.updated_at,
              protocols       = { "https" },
              methods         = route.methods,
              hosts           = route.hosts,
              paths           = route.paths,
              regex_priority  = 5,
              strip_path      = route.strip_path,
              preserve_host   = route.preserve_host,
              service         = route.service,
            }, new_route)

            local new_route, err, err_t = db.routes:update({ id = route.id }, {
              service = service_default,
            })

            assert.is_nil(new_route)
            assert.is_not_nil(err_t)
            assert.is_not_nil(err)
          end)
        end)
      end)

      describe(":delete()", function()
        lazy_setup(function()
          db:truncate()
        end)

        it("deletes an existing Route", function()
          local foo_ws = add_ws(db, "foo")
          with_current_ws( {foo_ws},function()
            local route = bp.routes:insert({
              hosts = { "example.com" },
            })

            local ok, err, err_t = db.routes:delete({
              id = route.id
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.is_true(ok)

            local route_in_db, err, err_t = db.routes:select({
              id = route.id
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.is_nil(route_in_db)
          end, db)
        end)

        -- I/O
        it("returns nothing if the Route does not exist", function()
          local foo_ws = add_ws(db, "foo")
          with_current_ws( {foo_ws},function()
            local u = utils.uuid()
            local ok, err, err_t = db.routes:delete({
              id = u
            })
            assert.is_true(ok)
            assert.is_nil(err_t)
            assert.is_nil(err)
          end, db)
        end)
      end)

      describe(":page()", function()
        lazy_setup(function()
          db:truncate()
        end)

        it("invokes schema post-processing", function()
          assert(db:truncate())
          local foo_ws = add_ws(db, "foo")
          with_current_ws( {foo_ws},function()
            bp.routes:insert {
              methods = { "GET" },
            }

            local rows, err, err_t = db.routes:page()
            assert.is_nil(err_t)
            assert.is_nil(err)

            for i = 1, #rows do
              assert.is_truthy(rows[i].methods.GET)
            end
          end, db)
        end)

        describe("page size", function()
          local foo_ws
          lazy_setup(function()

            db:truncate()

            foo_ws = add_ws(db, "foo")
            with_current_ws( {foo_ws},function()
              for i = 1, 1002 do
                bp.routes:insert({ hosts = { "example-" .. i .. ".com" } })
              end
            end, db)
          end)

          it("defaults page_size = 100", function()
            with_current_ws( {foo_ws},function()
              local rows, err, err_t = db.routes:page()
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)
              assert.equal(100, #rows)
            end, db)
          end)

          it("max page_size = 1000", function()
            with_current_ws( {foo_ws},function()
              local rows, err, err_t = db.routes:page(1002)
              assert.is_nil(rows)
              assert.not_nil(err_t)
              assert.not_nil(err)
              assert.equal("size must be an integer between 1 and 1000",
                err_t.message)
            end, db)
          end)
        end)

        describe("page offset", function()
          local foo_ws
          lazy_setup(function()
            db:truncate()

            foo_ws = add_ws(db, "foo")
            with_current_ws( {foo_ws},function()
              for i = 1, 10 do
                bp.routes:insert({
                  hosts = { "example-" .. i .. ".com" },
                  methods = { "GET" },
                })
              end
            end, db)
          end)


          it("fetches all rows in one page", function()
            with_current_ws( {foo_ws},function()
              local rows, err, err_t, offset = db.routes:page()
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)
              assert.equal(10, #rows)
              assert.is_nil(offset)
            end, db)
          end)

          it("fetched rows are returned in a table without hash part", function()
            with_current_ws( {foo_ws},function()
              local rows, err, err_t = db.routes:page()
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)

              local keys = {}

              for k in pairs(rows) do
                table.insert(keys, k)
              end

              assert.equal(#rows, #keys) -- no hash part in rows
            end, db)
          end)

          it("fetches rows always in same order", function()
            with_current_ws( {foo_ws},function()
              local rows1 = db.routes:page()
              local rows2 = db.routes:page()
              assert.is_table(rows1)
              assert.is_table(rows2)
              assert.same(rows1, rows2)
            end, db)
          end)

          it("returns offset when page_size < total", function()
            with_current_ws( {foo_ws},function()
              local rows, err, err_t, offset = db.routes:page(5)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)
              assert.equal(5, #rows)
              assert.is_string(offset)
            end, db)
          end)

          it("fetches subsequent pages with offset", function()
            with_current_ws( {foo_ws},function()
              local rows_1, err, err_t, offset = db.routes:page(5)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows_1)
              assert.equal(5, #rows_1)
              assert.is_string(offset)

              local page_size = 5
              if strategy == "cassandra" then
                -- 5 + 1: cassandra only detects the end of a pagination when
                -- we go past the number of rows in the iteration - it doesn't
                -- seem to detect the pages ending at the limit
                page_size = page_size + 1
              end

              local rows_2, err, err_t, offset = db.routes:page(page_size, offset)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows_2)
              assert.equal(5, #rows_2)
              assert.is_nil(offset) -- last page reached

              for i = 1, 5 do
                local row_1 = rows_1[i]
                for j = 1, 5 do
                  local row_2 = rows_2[j]
                  assert.not_same(row_1, row_2)
                end
              end
            end, db)
          end)

          it("fetches same page with same offset", function()
            with_current_ws( {foo_ws},function()
              local _, err, err_t, offset = db.routes:page(3)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_string(offset)

              local rows_a, err, err_t = db.routes:page(3, offset)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows_a)
              assert.equal(3, #rows_a)

              local rows_b, err, err_t = db.routes:page(3, offset)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows_b)
              assert.equal(3, #rows_b)

              for i = 1, #rows_a do
                assert.same(rows_a[i], rows_b[i])
              end
            end, db)
          end)

          it("fetches pages with last page having a single row", function()
            with_current_ws( {foo_ws},function()
              local rows, offset

              repeat
                local err, err_t

                rows, err, err_t, offset = db.routes:page(3, offset)
                assert.is_nil(err_t)
                assert.is_nil(err)

                if offset then
                  assert.equal(3, #rows)
                end
              until offset == nil

              assert.equal(1, #rows) -- last page
            end, db)
          end)

          it("fetches first page with invalid offset", function()
            with_current_ws( {foo_ws},function()
              local rows, err, err_t = db.routes:page(3, "hello")
              assert.is_nil(rows)
              local message  = "'hello' is not a valid offset: bad base64 encoding"
              assert.equal(fmt("[%s] %s", strategy, message), err)
              assert.same({
                code     = Errors.codes.INVALID_OFFSET,
                name     = "invalid offset",
                message  = message,
                strategy = strategy,
              }, err_t)
            end, db)
          end)
        end)
      end)

      describe(":each()", function()
        local foo_ws
        lazy_setup(function()
          db:truncate()

          foo_ws = add_ws(db, "foo")
          with_current_ws( {foo_ws},function()
            for i = 1, 100 do
              bp.routes:insert({
                hosts   = { "example-" .. i .. ".com" },
                methods = { "GET" }
              })
            end
          end, db)
        end)

        -- I/O
        it("iterates over all rows and its sets work as sets", function()
          with_current_ws( {foo_ws},function()
            local n_rows = 0

            for row, err, page in db.routes:each() do
              assert.is_nil(err)
              assert.equal(1, page)
              n_rows = n_rows + 1
              -- check that sets work like sets
              assert.is_truthy(row.methods.GET)
            end

            assert.equal(100, n_rows)
          end, db)
        end)

        it("page is smaller than total rows", function()
          with_current_ws( {foo_ws},function()
            local n_rows = 0
            local pages = {}

            for row, err, page in db.routes:each(10) do
              assert.is_nil(err)
              pages[page] = true
              n_rows = n_rows + 1
            end

            assert.equal(100, n_rows)
            assert.same({
              [1] = true,
              [2] = true,
              [3] = true,
              [4] = true,
              [5] = true,
              [6] = true,
              [7] = true,
              [8] = true,
              [9] = true,
              [10] = true,
            }, pages)
          end, db)
        end)
      end)
    end)

    --[[
	 -- Services entity

	 db.services:insert(entity)
	 db.services:select(primary_key)
	 db.services:update(primary_key, entity)
	 db.services:delete(primary_key)
	 --]]

    describe("Services", function()
      lazy_setup(function()
        db:truncate()
      end)

      describe(":insert() in non-default workspace", function()
        local foo_ws = add_ws(db, "foo")
        it("creates a Service with user-specified values", function()
          with_current_ws( {foo_ws},function()
            local service, err, err_t = db.services:insert({
              name            = "example_service",
              protocol        = "http",
              host            = "example.com",
              port            = 443,
              path            = "/foo",
              connect_timeout = 10000,
              write_timeout   = 10000,
              read_timeout    = 10000,
              retries         = 6,
            })
            assert.is_nil(err_t)
            assert.is_nil(err)

            assert.is_table(service)
            assert.is_number(service.created_at)
            assert.is_number(service.updated_at)
            assert.is_true(utils.is_valid_uuid(service.id))

            assert.same({
              id              = service.id,
              created_at      = service.created_at,
              updated_at      = service.updated_at,
              name            = "example_service",
              protocol        = "http",
              host            = "example.com",
              port            = 443,
              path            = "/foo",
              connect_timeout = 10000,
              write_timeout   = 10000,
              read_timeout    = 10000,
              retries         = 6,
            }, service)
          end, db)
        end)


        it("cannot create a Service with an existing name", function()
          with_current_ws( {foo_ws},function()
            -- insert 1
            local _, _, err_t = db.services:insert {
              name = "my_service",
              protocol = "http",
              host = "example.com",
            }
            assert.is_nil(err_t)

            -- insert 2
            local service, _, err_t = db.services:insert {
              name = "my_service",
              protocol = "http",
              host = "other-example.com",
            }
            assert.is_nil(service)
            assert.same({
              code     = Errors.codes.UNIQUE_VIOLATION,
              name     = "unique constraint violation",
              message  = "UNIQUE violation detected on '{name=\"my_service\"}'",
              strategy = strategy,
              fields   = {
                name = "my_service",
              }
            }, err_t)
          end, db)
        end)
      end)

      describe(":select_by_name() in non-default workspace", function()
        local foo_ws = add_ws(db, "foo")
        lazy_setup(function()
          db:truncate()

          with_current_ws( {foo_ws},function()
            for i = 1, 5 do
              assert(db.services:insert({
                name = "service_" .. i,
                host = "service" .. i .. ".com",
              }))
            end
          end, db)
        end)

        -- I/O
        it("returns existing Service", function()
          with_current_ws( {foo_ws},function()
            local service = assert(db.services:select_by_name("service_1"))
            assert.equal("service1.com", service.host)
          end, db)
        end)

        it("returns nothing on non-existing Service", function()
          with_current_ws( {foo_ws},function()
            local service, err, err_t = db.services:select_by_name("non-existing")
            assert.is_nil(err)
            assert.is_nil(err_t)
            assert.is_nil(service)
          end, db)
        end)
      end)

      describe(":update() in non-default workspace", function()
        local foo_ws
        lazy_setup(function()
          db:truncate()
          foo_ws = add_ws(db, "foo")
        end)

        it("cannot update a Service to bear an already existing name", function()
            with_current_ws( {foo_ws},function()
              -- insert 1
              local _, _, err_t = db.services:insert {
                name = "service",
                protocol = "http",
                host = "example.com",
              }
              assert.is_nil(err_t)

              -- insert 2
              local service, _, err_t = db.services:insert {
                name = "service_bis",
                protocol = "http",
                host = "other-example.com",
              }
              assert.is_nil(err_t)

              -- update insert 2 with insert 1 name
              local updated_service, _, err_t = db.services:update({
                id = service.id,
              }, { name = "service" })
              assert.is_nil(updated_service)
              assert.same({
                code     = Errors.codes.UNIQUE_VIOLATION,
                name     = "unique constraint violation",
                message  = "UNIQUE violation detected on '{name=\"service\"}'",
                strategy = strategy,
                fields   = {
                  name = "service",
                }
              }, err_t)
          end, db)
        end)
      end)

      describe(":update_by_name() in non-default workspace", function()
        local foo_ws
        before_each(function()
          db:truncate()

          foo_ws = add_ws(db, "foo")
          with_current_ws( {foo_ws},function()
            assert(db.services:insert({
              name = "test-service",
              host = "test-service.com",
            }))

            assert(db.services:insert({
              name = "existing-service",
              host = "existing-service.com",
            }))
          end, db)
        end)

        -- I/O
        it("returns not found error", function()
          with_current_ws( {foo_ws},function()
            local service, err, err_t = db.services:update_by_name("inexisting-service", { protocol = "http" })
            assert.is_nil(service)
            local message = fmt(
              [[[%s] could not find the entity with '{name="inexisting-service"}']],
              strategy)
            assert.equal(message, err)
            assert.equal(Errors.codes.NOT_FOUND, err_t.code)
          end, db)
        end)

        it("updates an existing Service", function()
          with_current_ws( {foo_ws},function()
            local service = assert(db.services:insert({
              host = "service.com"
            }))

            local updated_service, err, err_t = db.services:update({
              id = service.id
            }, { protocol = "https" })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.equal("https", updated_service.protocol)

            local service_in_db, err, err_t = db.services:select({
              id = service.id
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.equal("https", service_in_db.protocol)
          end, db)
        end)

        it("updates an existing Service", function()
          local service_default
          -- add a service to default workspace
          with_current_ws(nil, function ()
            local err, err_t
            service_default, err, err_t = db.services:insert({
              name = "test-service",
              host = "test-service.com",
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
          end, db)

          with_current_ws( {foo_ws},function()
            local updated_service, err, err_t = db.services:update_by_name("test-service", {
              protocol = "https"
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.equal("https", updated_service.protocol)

            local service_in_db, err, err_t = db.services:select({
              id = updated_service.id
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.equal("https", service_in_db.protocol)
          end, db)

          -- validate service in default is still same
          with_current_ws(nil,function ()
            local service_default_db, err, err_t = db.services:select({
              id = service_default.id
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same(service_default, service_default_db)
          end, db)
        end)

        it("cannot update a Service to an already existing name", function()
          with_current_ws( {foo_ws},function()
            local updated_service, err, err_t = db.services:update_by_name("test-service", {
              name = "existing-service"
            })
            assert.is_not_nil(err_t)
            assert.is_not_nil(err)
            assert.is_nil(updated_service)
            assert.same({
              code     = Errors.codes.UNIQUE_VIOLATION,
              name     = "unique constraint violation",
              message  = "UNIQUE violation detected on '{name=\"existing-service\"}'",
              strategy = strategy,
              fields   = {
                name = "existing-service",
              }
            }, err_t)
          end, db)
        end)
      end)

      describe(":delete_by_name() in non-default workspace", function()
        local service, foo_ws

        lazy_setup(function()
          db:truncate()

          foo_ws = add_ws(db, "foo")
          with_current_ws( {foo_ws},function()
            service = assert(db.services:insert({
              name = "service_1",
              host = "service1.com",
            }))
          end, db)
        end)

        -- I/O
        it("returns nothing if the Service does not exist", function()
          with_current_ws( {foo_ws},function()
            local ok, err, err_t = db.services:delete_by_name("service_10")
            assert.is_true(ok)
            assert.is_nil(err_t)
            assert.is_nil(err)
          end, db)
        end)

        it("deletes an existing Service", function()
          with_current_ws( {foo_ws},function()
            -- validate relationship deleted
            local rel, err = db.workspace_entities:select({
              workspace_id = foo_ws.id,
              entity_id = service.id,
              unique_field_name = "name"
            })
            assert.is_nil(err)
            assert.is_not_nil(rel)

            local ok, err, err_t = db.services:delete_by_name("service_1")
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.is_true(ok)

            local service_in_db, err, err_t = db.services:select({
              id = service.id
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.is_nil(service_in_db)

            -- validate relationship deleted
            local rel, err = db.workspace_entities:select({
              workspace_id = foo_ws.id,
              entity_id = service.id,
              unique_field_name = "name"
            })
            assert.is_nil(err)
            assert.is_nil(rel)

          end, db)
        end)
      end)
    end)

    --[[
    -- Services and Routes relationships
    --
    --]]

    describe("Services and Routes association in non-default workspace", function()
      local foo_ws

      lazy_setup(function()
        db:truncate()
        foo_ws = add_ws(db, "foo")
      end)

      it(":insert() a Route with a relation to a Service", function()
        with_current_ws( {foo_ws},function()
          local service = assert(db.services:insert({
            protocol = "http",
            host     = "service.com"
          }))

          local route, err, err_t = db.routes:insert({
            protocols = { "http" },
            hosts     = { "example.com" },
            service   = service,
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.same({
            id               = route.id,
            created_at       = route.created_at,
            updated_at       = route.updated_at,
            protocols        = { "http" },
            hosts            = { "example.com" },
            regex_priority   = 0,
            strip_path       = true,
            preserve_host    = false,
            service          = {
              id = service.id
            },
          }, route)

          local route_in_db, err, err_t = db.routes:select({ id = route.id })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.same(route, route_in_db)
        end, db)
      end)

      it(":update() attaches a Route to an existing Service", function()
        with_current_ws( {foo_ws},function()
          local service1 = bp.services:insert({ host = "service1.com" })
          local service2 = bp.services:insert({ host = "service2.com" })

          local route = bp.routes:insert({ service = service1, methods = { "GET" } })

          local new_route, err, err_t = db.routes:update({ id = route.id }, {
            service = service2
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.same(new_route.service, { id = service2.id })
        end, db)
      end)

      it(":delete() a Service is not allowed if a Route is associated to it", function()
        with_current_ws( {foo_ws},function()
          local service = bp.services:insert({
            host = "example.com",
          })

          bp.routes:insert({ service = service, methods = { "GET" } })

          local ok, err, err_t = db.services:delete({ id = service.id })
          assert.is_nil(ok)
          local message  = "an existing 'routes' entity references this 'services' entity"
          assert.equal(fmt("[%s] %s", strategy, message), err)
          assert.same({
            code     = Errors.codes.FOREIGN_KEY_VIOLATION,
            name     = "foreign key violation",
            strategy = strategy,
            message  = message,
            fields   = {
              ["@referenced_by"] = "routes",
            },
          }, err_t)
        end, db)
      end)

      it(":delete() a Route without deleting the associated Service", function()
        with_current_ws( {foo_ws},function()
          local service = bp.services:insert({
            host = "example.com",
          })

          local route = bp.routes:insert({ service = service, methods = { "GET" } })

          local ok, err, err_t = db.routes:delete({ id = route.id })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.is_true(ok)

          local service_in_db, err, err_t = db.services:select({
            id = service.id
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.same(service, service_in_db)
        end, db)
      end)

      describe("routes:each_for_service()", function()
        -- I/O
        it("lists no Routes associated to an inexsistent Service", function()
          with_current_ws( {foo_ws},function()
            local rows = {}
            for row, err in db.routes:each_for_service({
              id = a_blank_uuid,
            }) do
              rows[rows+1] = row
              assert.is_nil(err)
            end
            assert.same({}, rows)
          end, db)
        end)

        it("lists Routes associated to a Service", function()
          with_current_ws( {foo_ws},function()
            local service = bp.services:insert()

            local route1 = bp.routes:insert {
              methods = { "GET" },
              service = service,
            }

            bp.routes:insert {
              hosts = { "example.com" },
              -- different service
            }

            local rows = {}
            for row, err in db.routes:each_for_service {
              id = service.id,
            } do
              rows[#rows+1] = row
              assert.is_nil(err)
            end
            assert.same({ route1 }, rows)
            ngx.sleep(50)
          end, db)
        end)

        it("invokes schema post-processing", function()
          with_current_ws( {foo_ws},function()
            local service = bp.services:insert {
              host = "example.com",
            }

            bp.routes:insert {
              service = service,
              methods = { "GET" },
            }

            local rows = {}
            for row, err in db.routes:each_for_service {
              id = service.id,
            } do
              rows[#rows+1] = row
              assert.is_nil(err)
            end

            if #rows ~= 1 then
              error("should have returned exactly 1 row")
            end

            -- check that post_processing is invoked
            -- our post-processing function will use a "set" metatable to alias
            -- the values for shorthand accesses.
            assert.is_truthy(rows[1].methods.GET)
          end, db)
        end)
      end) -- routes:each_for_service()
    end) -- Services and Routes association
  end) -- kong.db [strategy]
end
