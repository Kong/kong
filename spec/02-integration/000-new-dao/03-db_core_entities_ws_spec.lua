local Errors  = require "kong.db.errors"
local utils   = require "kong.tools.utils"
local helpers = require "spec.helpers"
local cjson   = require "cjson"
local singletons = require "kong.singletons"

local fmt      = string.format
local unindent = helpers.unindent


local a_blank_uuid = "00000000-0000-0000-0000-000000000000"


local function run_with_ws(cb, scope, dao)
  scope = scope or dao.workspaces:find_all({name = "default"})
  local old_ctx = ngx.ctx.workspaces
  ngx.ctx.workspaces = scope
  cb()
  ngx.ctx.workspaces = old_ctx
end

local function add_ws(dao, ws_name)
  local old_ctx
  old_ctx, ngx.ctx.workspaces = ngx.ctx.workspaces, nil
  ngx.ctx.workspaces = dao.workspaces:find_all({name = "default"})

  -- create another workspace in default workspace
  local foo_ws, err, err_t = dao.workspaces:insert({
    name = ws_name,
  })

  ngx.ctx.workspaces = old_ctx
  return foo_ws
end


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp, dao

    setup(function()
      ngx.ctx.workspaces = nil
      bp, db, dao = helpers.get_db_utils(strategy, true)
      singletons.dao = dao
    end)

    teardown(function()
      db:truncate()
    end)

    describe("Routes", function()
      describe(":insert()", function()
        it("creates a Route in default workspace", function()
          local old_ctx = ngx.ctx.workspaces
          ngx.ctx.workspaces = dao.workspaces:find_all({name = "default"})
          local route, err, err_t = db.routes:insert({
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
            methods         = ngx.null,
            hosts           = { "example.com" },
            paths           = ngx.null,
            regex_priority  = 0,
            preserve_host   = false,
            strip_path      = true,
            service         = route.service,
          }, route)

          local default_ws = ngx.ctx.workspaces[1]
          local rel, err = dao.workspace_entities:find({
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
          }, rel)
          ngx.ctx.workspaces = old_ctx
        end)

        it("creates a Route in non-default workspace", function()
          local foo_ws = add_ws(dao, "foo")

          run_with_ws(function ()
            -- add route in foo workspace
            local route, err, err_t = db.routes:insert({
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
              methods         = ngx.null,
              hosts           = { "example.com" },
              paths           = ngx.null,
              regex_priority  = 0,
              preserve_host   = false,
              strip_path      = true,
              service         = route.service,
            }, route)

            -- validate relationship
            local rel, err = dao.workspace_entities:find({
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
            }, rel)
          end, {foo_ws})
        end)
      end)

      describe(":select()", function()
        setup(function()
          db:truncate()
        end)

        it("returns an existing Route from default workspace", function()
          run_with_ws( function ()
            local route_inserted = bp.routes:insert({
            hosts = { "example.com" },
            })
            local route, err, err_t = db.routes:select({ id = route_inserted.id })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same(route_inserted, route)
          end, nil, dao)
        end)

        it("returns an existing Route from foo worksoace", function()
          local foo_ws = add_ws(dao, "foo")
          run_with_ws( function ()
            local route_inserted = bp.routes:insert({
              hosts = { "example.com" },
            })
            local route, err, err_t = db.routes:select({ id = route_inserted.id })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same(route_inserted, route)
          end, {foo_ws})
        end)
      end)

      describe(":update() in non-default workspace", function()
        setup(function()
          db:truncate()
        end)

        -- I/O
        it("returns not found error", function()
          local foo_ws = add_ws(dao, "foo")
          run_with_ws( function ()
            local pk = { id = utils.uuid() }
            local new_route, err, err_t = db.routes:update(pk, {
            protocols = { "https" }
            })
            assert.is_nil(new_route)
          end, {foo_ws})
        end)

        it("updates an existing Route", function()
          local foo_ws = add_ws(dao, "foo")
          run_with_ws( function ()
            local route = bp.routes:insert({
              hosts = { "example.com" },
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
          end, {foo_ws})
        end)
      end)

      describe(":delete()", function()
        setup(function()
          db:truncate()
        end)

        -- I/O
        it("returns nothing if the Route does not exist", function()
          local foo_ws = add_ws(dao, "foo")
          run_with_ws( function ()
            local u = utils.uuid()
            local ok, err, err_t = db.routes:delete({
              id = u
            })
            assert.is_true(ok)
            assert.is_nil(err_t)
            assert.is_nil(err)
          end, {foo_ws})
        end)

        it("deletes an existing Route", function()
          local foo_ws = add_ws(dao, "foo")
          run_with_ws( function ()
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
          end, {foo_ws})
        end)
      end)

      describe(":page()", function()
        setup(function()
          db:truncate()
        end)

        it("invokes schema post-processing", function()
          assert(db:truncate())
          local foo_ws = add_ws(dao, "foo")
          run_with_ws( function ()
            bp.routes:insert {
              methods = { "GET" },
            }

            local rows, err, err_t = db.routes:page()
            assert.is_nil(err_t)
            assert.is_nil(err)

            for i = 1, #rows do
              assert.is_truthy(rows[i].methods.GET)
            end
          end, {foo_ws})
        end)

        describe("page size", function()
          local foo_ws
          setup(function()

            db:truncate()

            foo_ws = add_ws(dao, "foo")
            run_with_ws( function ()
              for i = 1, 1002 do
                bp.routes:insert({ hosts = { "example-" .. i .. ".com" } })
              end
            end, {foo_ws})
          end)

          it("defaults page_size = 100", function()
            run_with_ws( function ()
              local rows, err, err_t = db.routes:page()
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)
              assert.equal(100, #rows)
            end, {foo_ws})
          end)

          it("max page_size = 1000", function()
            run_with_ws( function ()
              local rows, err, err_t = db.routes:page(1002)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)
              assert.equal(1000, #rows)
            end, {foo_ws})
          end)
        end)

        describe("page offset", function()
          local foo_ws
          setup(function()
            db:truncate()

            foo_ws = add_ws(dao, "foo")
            run_with_ws( function ()
              for i = 1, 10 do
                bp.routes:insert({
                  hosts = { "example-" .. i .. ".com" },
                  methods = { "GET" },
                })
              end
            end, {foo_ws})
          end)


          it("fetches all rows in one page", function()
            run_with_ws( function ()
              local rows, err, err_t, offset = db.routes:page()
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)
              assert.equal(10, #rows)
              assert.is_nil(offset)
            end, {foo_ws})
          end)

          it("fetched rows are returned in a table without hash part", function()
            run_with_ws( function ()
              local rows, err, err_t = db.routes:page()
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)

              local keys = {}

              for k in pairs(rows) do
                table.insert(keys, k)
              end

              assert.equal(#rows, #keys) -- no hash part in rows
            end, {foo_ws})
          end)

          it("fetches rows always in same order", function()
            run_with_ws( function ()
              local rows1 = db.routes:page()
              local rows2 = db.routes:page()
              assert.is_table(rows1)
              assert.is_table(rows2)
              assert.same(rows1, rows2)
            end, {foo_ws})
          end)

          it("returns offset when page_size < total", function()
            run_with_ws( function ()
              local rows, err, err_t, offset = db.routes:page(5)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)
              assert.equal(5, #rows)
              assert.is_string(offset)
            end, {foo_ws})
          end)

          it("fetches subsequent pages with offset", function()
            run_with_ws( function ()
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
            end, {foo_ws})
          end)

          it("fetches same page with same offset", function()
            run_with_ws( function ()
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
            end, {foo_ws})
          end)

          it("fetches pages with last page having a single row", function()
            run_with_ws( function ()
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
            end, {foo_ws})
          end)

          it("fetches first page with invalid offset", function()
            run_with_ws( function ()
              local rows, err, err_t = db.routes:page(3, "hello")
              assert.is_nil(rows)
              local message  = "'hello' is not a valid offset for this strategy: bad base64 encoding"
              assert.equal(fmt("[%s] %s", strategy, message), err)
              assert.same({
                code     = Errors.codes.INVALID_OFFSET,
                name     = "invalid offset",
                message  = message,
                strategy = strategy,
              }, err_t)
            end, {foo_ws})
          end)
        end)
      end)

      describe(":each()", function()
        local foo_ws
        setup(function()
          db:truncate()

          foo_ws = add_ws(dao, "foo")
          run_with_ws( function ()
            for i = 1, 100 do
              bp.routes:insert({
                hosts   = { "example-" .. i .. ".com" },
                methods = { "GET" }
              })
            end
          end, {foo_ws})
        end)

        teardown(function ()
          ngx.ctx.workspaces = old_ctx
        end)

        -- I/O
        it("iterates over all rows and its sets work as sets", function()
          run_with_ws( function ()
            local n_rows = 0

            for row, err, page in db.routes:each() do
              assert.is_nil(err)
              assert.equal(1, page)
              n_rows = n_rows + 1
              -- check that sets work like sets
              assert.is_truthy(row.methods.GET)
            end

            assert.equal(100, n_rows)
          end, {foo_ws})
        end)

        it("page is smaller than total rows", function()
          run_with_ws( function ()
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
          end, {foo_ws})
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
      setup(function()
        db:truncate()
      end)

      describe(":insert() in non-default workspace", function()
        local foo_ws = add_ws(dao, "foo")
        it("creates a Service with user-specified values", function()
          run_with_ws( function ()
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
          end, {foo_ws})
        end)


        it("cannot create a Service with an existing name", function()
          run_with_ws( function ()
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
          end, {foo_ws})
        end)
      end)

      describe(":select_by_name() in non-default workspace", function()
        local foo_ws = add_ws(dao, "foo")
        setup(function()
          db:truncate()

          run_with_ws( function ()
            for i = 1, 5 do
              assert(db.services:insert({
                name = "service_" .. i,
                host = "service" .. i .. ".com",
              }))
            end
          end, {foo_ws})
        end)

        -- I/O
        it("returns existing Service", function()
          run_with_ws( function ()
            local service = assert(db.services:select_by_name("service_1"))
            assert.equal("service1.com", service.host)
          end, {foo_ws})
        end)

        it("returns nothing on non-existing Service", function()
          run_with_ws( function ()
            local service, err, err_t = db.services:select_by_name("non-existing")
            assert.is_nil(err)
            assert.is_nil(err_t)
            assert.is_nil(service)
          end, {foo_ws})
        end)
      end)

      describe(":update() in non-default workspace", function()
        local foo_ws
        setup(function()
          db:truncate()
          foo_ws = add_ws(dao, "foo")
        end)

        it("cannot update a Service to bear an already existing name", function()
            run_with_ws( function ()
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
          end, {foo_ws})
        end)
      end)

      describe(":update_by_name() in non-default workspace", function()
        local foo_ws
        before_each(function()
          db:truncate()

          foo_ws = add_ws(dao, "foo")
          run_with_ws( function ()
            assert(db.services:insert({
              name = "test-service",
              host = "test-service.com",
            }))

            assert(db.services:insert({
              name = "existing-service",
              host = "existing-service.com",
            }))
          end, {foo_ws})
        end)

        -- I/O
        it("returns not found error", function()
          run_with_ws( function ()
            local service, err, err_t = db.services:update_by_name("inexisting-service", { protocol = "http" })
            assert.is_nil(service)
            local message = fmt(
              [[[%s] could not find the entity with '{name="inexisting-service"}']],
              strategy)
            assert.equal(message, err)
            assert.equal(Errors.codes.NOT_FOUND, err_t.code)
          end, {foo_ws})
        end)

        it("updates an existing Service", function()
          run_with_ws( function ()
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
          end, {foo_ws})
        end)

        it("updates an existing Service", function()
          local service_default
          -- add a service to default workspace
          run_with_ws( function ()
            local err, err_t
            service_default, err, err_t = db.services:insert({
              name = "test-service",
              host = "test-service.com",
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
          end, nil, dao)

          run_with_ws( function ()
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
          end, {foo_ws})

          -- validate service in default is still same
          run_with_ws( function ()
            local service_default_db, err, err_t = db.services:select({
              id = service_default.id
            })
            assert.same(service_default, service_default_db)
          end, nil, dao)
        end)

        it("cannot update a Service to bear an already existing name", function()
          run_with_ws( function ()
            local service, err, err_t = db.services:select_by_name("non-existing")
            local updated_service, _, err_t = db.services:update_by_name("test-service", {
              name = "existing-service"
            })
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
          end, {foo_ws})
        end)
      end)

      describe(":delete_by_name() in non-default workspace", function()
        local service, foo_ws

        setup(function()
          db:truncate()

          foo_ws = add_ws(dao, "foo")
          run_with_ws( function ()
            service = assert(db.services:insert({
              name = "service_1",
              host = "service1.com",
            }))
          end, {foo_ws})
        end)

        -- I/O
        it("returns nothing if the Service does not exist", function()
          run_with_ws( function ()
            local ok, err, err_t = db.services:delete_by_name("service_10")
            assert.is_true(ok)
            assert.is_nil(err_t)
            assert.is_nil(err)
          end, {foo_ws})
        end)

        it("deletes an existing Service", function()
          run_with_ws( function ()
            -- validate relationship deleted
            local rel, err = dao.workspace_entities:find({
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
            local rel, err = dao.workspace_entities:find({
              workspace_id = foo_ws.id,
              entity_id = service.id,
              unique_field_name = "name"
            })
            assert.is_nil(err)
            assert.is_nil(rel)

          end, {foo_ws})
        end)
      end)
    end)

    --[[
    -- Services and Routes relationships
    --
    --]]

    describe("Services and Routes association in non-default workspace", function()
      local foo_ws

      setup(function()
        db:truncate()
        foo_ws = add_ws(dao, "foo")
      end)

      it(":insert() a Route with a relation to a Service", function()
        run_with_ws( function ()
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
            methods          = ngx.null,
            hosts            = { "example.com" },
            paths            = ngx.null,
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
        end, {foo_ws})
      end)

      it(":update() attaches a Route to an existing Service", function()
        run_with_ws( function ()
          local service1 = bp.services:insert({ host = "service1.com" })
          local service2 = bp.services:insert({ host = "service2.com" })

          local route = bp.routes:insert({ service = service1, methods = { "GET" } })

          local new_route, err, err_t = db.routes:update({ id = route.id }, {
            service = service2
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.same(new_route.service, { id = service2.id })
        end, {foo_ws})
      end)

      it(":delete() a Service is not allowed if a Route is associated to it", function()
        run_with_ws( function ()
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
        end, {foo_ws})
      end)

      it(":delete() a Route without deleting the associated Service", function()
        run_with_ws( function ()
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
        end, {foo_ws})
      end)

      describe("routes:for_service()", function()
        -- I/O
        it("lists no Routes associated to an inexsistent Service", function()
          run_with_ws( function ()
            local rows, err, err_t = db.routes:for_service {
              id = a_blank_uuid,
            }
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same({}, rows)
          end, {foo_ws})
        end)

        it("lists Routes associated to a Service", function()
          run_with_ws( function ()
            local service = bp.services:insert()

            local route1 = bp.routes:insert {
              methods = { "GET" },
              service = service,
            }

            bp.routes:insert {
              hosts = { "example.com" },
              -- different service
            }

            local rows, err, err_t = db.routes:for_service {
              id = service.id,
            }
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same({ route1 }, rows)
            ngx.sleep(50)
          end, {foo_ws})
        end)

        it("invokes schema post-processing", function()
          run_with_ws( function ()
            local service = bp.services:insert {
              host = "example.com",
            }

            bp.routes:insert {
              service = service,
              methods = { "GET" },
            }

            local rows, err, err_t = db.routes:for_service {
              id = service.id,
            }
            assert.is_nil(err_t)
            assert.is_nil(err)

            if #rows ~= 1 then
              error("should have returned exactly 1 row")
            end

            -- check that post_processing is invoked
            -- our post-processing function will use a "set" metatable to alias
            -- the values for shorthand accesses.
            assert.is_truthy(rows[1].methods.GET)
          end, {foo_ws})
        end)
      end) -- routes:for_service()
    end) -- Services and Routes association
  end) -- kong.db [strategy]
end
