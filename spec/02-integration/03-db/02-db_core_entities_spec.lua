local Errors  = require "kong.db.errors"
local utils   = require "kong.tools.utils"
local helpers = require "spec.helpers"
local cjson   = require "cjson"

local fmt      = string.format
local unindent = helpers.unindent


local a_blank_uuid = "00000000-0000-0000-0000-000000000000"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "basicauth_credentials",
        "upstreams",
        "targets",
      })
    end)

    --[[
    -- Routes entity

    db.routes:insert(entity)
    db.routes:select(primary_key)
    db.routes:update(primary_key, entity)
    db.routes:delete(primary_key)
    db.routes:page_for_service(service_id)
    --]]

    describe("Routes", function()

      describe(":page()", function()
        -- no I/O
        it("errors on invalid size", function()
          assert.has_error(function()
            db.routes:page("")
          end, "size must be a number")
          assert.has_error(function()
            db.routes:page({})
          end, "size must be a number")
          assert.has_error(function()
            db.routes:page(true)
          end, "size must be a number")
          assert.has_error(function()
            db.routes:page(false)
          end, "size must be a number")
        end)

        it("errors on invalid offset", function()
          assert.has_error(function()
            db.routes:page(nil, 0)
          end, "offset must be a string")
          assert.has_error(function()
            db.routes:page(nil, {})
          end, "offset must be a string")
          assert.has_error(function()
            db.routes:page(nil, true)
          end, "offset must be a string")
          assert.has_error(function()
            db.routes:page(nil, false)
          end, "offset must be a string")
        end)

        -- I/O
        it("returns a table encoding to a JSON Array when empty", function()

          local rows, err, err_t, offset = db.routes:page()
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.is_table(rows)
          assert.equal(0, #rows)
          assert.is_nil(offset)
          assert.equals("[]", cjson.encode(rows))
        end)

        describe("page offset", function()
          lazy_setup(function()
            for i = 1, 10 do
              bp.routes:insert({
                hosts = { "example-" .. i .. ".com" },
                methods = { "GET" },
              })
            end
          end)

          lazy_teardown(function()
            db:truncate("routes")
          end)

          it("fetches all rows in one page", function()
            local rows, err, err_t, offset = db.routes:page()
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.is_table(rows)
            assert.equal(10, #rows)
            assert.is_nil(offset)
          end)

          it("fetched rows are returned in a table without hash part", function()
            local rows, err, err_t = db.routes:page()
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.is_table(rows)

            local keys = {}

            for k in pairs(rows) do
              table.insert(keys, k)
            end

            assert.equal(#rows, #keys) -- no hash part in rows
          end)

          it("fetches rows always in same order", function()
            local rows1 = db.routes:page()
            local rows2 = db.routes:page()
            assert.is_table(rows1)
            assert.is_table(rows2)
            assert.same(rows1, rows2)
          end)

          it("returns offset when page_size < total", function()
            local rows, err, err_t, offset = db.routes:page(5)
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.is_table(rows)
            assert.equal(5, #rows)
            assert.is_string(offset)
          end)

          it("fetches subsequent pages with offset", function()
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
          end)

          it("fetches same page with same offset", function()
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
          end)

          it("fetches pages with last page having a single row", function()
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
          end)

          it("returns an error with invalid size", function()
            local rows, err, err_t = db.routes:page(5.5)
            assert.is_nil(rows)
            local message  = "size must be an integer between 1 and 1000"
            assert.equal(fmt("[%s] %s", strategy, message), err)
            assert.same({
              code     = Errors.codes.INVALID_SIZE,
              name     = "invalid size",
              message  = message,
              strategy = strategy,
            }, err_t)
          end)

          it("returns an error with invalid offset", function()
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
          end)
        end)

        describe("page size", function()
          lazy_setup(function()
            for i = 1, 101 do
              bp.routes:insert({
                hosts = { "example-" .. i .. ".com" },
                methods = { "GET" },
              })
            end
          end)

          lazy_teardown(function()
            db:truncate("routes")
          end)

          it("defaults page_size = 100 and invokes schema post-processing", function()
            local rows, err, err_t = db.routes:page()
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.is_table(rows)
            assert.equal(100, #rows)

            -- invokes schema post-processing
            -- which ensures that sets work as sets
            for i = 1, #rows do
              assert.is_truthy(rows[i].methods.GET)
            end
          end)
        end)
      end)

      describe(":each()", function()

        lazy_setup(function()
          for i = 1, 50 do
            bp.routes:insert({
              hosts   = { "example-" .. i .. ".com" },
              methods = { "GET" }
            })
          end
        end)

        lazy_teardown(function()
          db:truncate("routes")
        end)

        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.routes:each(false)
          end, "size must be a number")
        end)

        -- I/O
        it("iterates over all rows and its sets work as sets", function()
          local n_rows = 0

          for row, err, page in db.routes:each() do
            assert.is_nil(err)
            assert.equal(1, page)
            n_rows = n_rows + 1
            -- check that sets work like sets
            assert.is_truthy(row.methods.GET)
          end

          assert.equal(50, n_rows)
        end)

        it("page is smaller than total rows", function()
          local n_rows = 0
          local pages = {}

          for row, err, page in db.routes:each(10) do
            assert.is_nil(err)
            pages[page] = true
            n_rows = n_rows + 1
          end

          assert.same(50, n_rows)
          assert.same({
            [1] = true,
            [2] = true,
            [3] = true,
            [4] = true,
            [5] = true,
          }, pages)
        end)
      end)

      describe(":insert()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.routes:insert()
          end, "entity must be a table")

          assert.has_error(function()
            db.routes:insert({}, "options")
          end, "options must be a table when specified")

        end)

        it("errors on invalid fields", function()
          local route, err, err_t = db.routes:insert({})
          assert.is_nil(route)
          assert.is_string(err)
          assert.is_table(err_t)
          assert.same({
            code     = Errors.codes.SCHEMA_VIOLATION,
            name     = "schema violation",
            strategy = strategy,
            message  = unindent([[
              2 schema violations
              (must set one of 'methods', 'hosts', 'paths' when 'protocols' is 'http' or 'https';
              service: required field missing)
            ]], true, true),
            fields   = {
              service     = "required field missing",
              ["@entity"] = {
                "must set one of 'methods', 'hosts', 'paths' when 'protocols' is 'http' or 'https'",
              }
            },

          }, err_t)
        end)

        it("cannot insert if foreign primary_key is invalid", function()
          local service = {
            protocol = "http"
          }

          local route, err, err_t = db.routes:insert({
            protocols = { "http" },
            hosts = { "example.com" },
            service = service,
          })
          local message = "schema violation (service.id: missing primary key)"
          assert.is_nil(route)
          assert.equal(fmt("[%s] %s", strategy, message), err)
          assert.same({
            code      = Errors.codes.SCHEMA_VIOLATION,
            name      = "schema violation",
            strategy  = strategy,
            message   = message,
            fields    = {
              service = {
                id    = "missing primary key",
              }
            },
          }, err_t)
          --TODO: enable when implemented
          --assert.equal("invalid primary key for Service: id=(missing)", tostring(err_t))
        end)

        it("cannot insert if foreign primary_key is invalid", function()
          local fake_id = utils.uuid()
          local credentials, _, err_t = db.basicauth_credentials:insert({
            username = "peter",
            consumer = { id = fake_id },
          })

          assert.is_nil(credentials)
          assert.equals("foreign key violation", err_t.name)
          assert.same({ consumer = { id = fake_id } }, err_t.fields)
        end)

        -- I/O
        it("cannot insert if foreign Service does not exist", function()
          local u = utils.uuid()
          local service = {
            id = u
          }

          local route, err, err_t = db.routes:insert({
            protocols = { "http" },
            hosts = { "example.com" },
            service = service,
          })
          assert.is_nil(route)
          local message  = fmt(unindent([[
            the foreign key '{id="%s"}' does not reference
            an existing 'services' entity.
          ]], true, true), u)

          assert.equal(fmt("[%s] %s", strategy, message), err)
          assert.same({
            code     = Errors.codes.FOREIGN_KEY_VIOLATION,
            name     = "foreign key violation",
            strategy = strategy,
            message  = message,
            fields   = {
              service = {
                id = u,
              }
            },
          }, err_t)
          -- TODO: enable when done
          --assert.equal("foreign entity Service does not exist: id=( " .. u .. ")", tostring(err_t))
        end)

        it("cannot use ttl option with Routes", function()
          local route, err, err_t = db.routes:insert({
            protocols = { "http" },
            hosts = { "example.com" },
            service = assert(db.services:insert({ host = "service.com" })),
          }, {
            ttl = 100,
          })

          assert.is_nil(route)
          assert.is_string(err)
          assert.is_table(err_t)
          assert.same({
            code     = Errors.codes.INVALID_OPTIONS,
            name     = "invalid options",
            strategy = strategy,
            message  = unindent([[
              invalid option (ttl: cannot be used with 'routes')
            ]], true, true),
            options   = {
              ttl     = "cannot be used with 'routes'",
            }}, err_t)
        end)

        it("creates a Route and injects defaults", function()
          local route, err, err_t = db.routes:insert({
            protocols = { "http" },
            hosts = { "example.com" },
            service = assert(db.services:insert({ host = "service.com" })),
          }, { nulls = true })
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
            name            = ngx.null,
            methods         = ngx.null,
            hosts           = { "example.com" },
            paths           = ngx.null,
            snis            = ngx.null,
            sources         = ngx.null,
            destinations    = ngx.null,
            regex_priority  = 0,
            preserve_host   = false,
            strip_path      = true,
            tags            = ngx.null,
            service         = route.service,
          }, route)
        end)

        it("creates a Route with user-specified values", function()
          local route, err, err_t = db.routes:insert({
            protocols       = { "http" },
            hosts           = { "example.com" },
            paths           = { "/example" },
            regex_priority  = 3,
            strip_path      = true,
            service         = bp.services:insert(),
          }, { nulls = true })
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
            name            = ngx.null,
            methods         = ngx.null,
            hosts           = { "example.com" },
            paths           = { "/example" },
            snis            = ngx.null,
            sources         = ngx.null,
            destinations    = ngx.null,
            regex_priority  = 3,
            strip_path      = true,
            tags            = ngx.null,
            preserve_host   = false,
            service         = route.service,
          }, route)
        end)

        it("created_at/updated_at defaults and formats are respected", function()
          local now = ngx.time()

          local route = assert(db.routes:insert({
            protocols = { "http" },
            hosts = { "example.com" },
            service = bp.services:insert(),
          }))

          local route_in_db = assert(db.routes:select({ id = route.id }))
          assert.truthy(now - route_in_db.created_at < 0.1)
          assert.truthy(now - route_in_db.updated_at < 0.1)
        end)

        it("created_at/updated_at cannot be overriden", function()
          local route, err, err_t = db.routes:insert({
            protocols  = { "http" },
            hosts      = { "example.com" },
            service    = bp.services:insert(),
            created_at = 0,
            updated_at = 0,
          })
          assert.is_nil(err_t)
          assert.is_nil(err)

          assert.is_table(route)
          assert.not_equal(0, route.created_at)
          assert.not_equal(0, route.updated_at)
        end)

        describe("#stream context", function()
          it("creates a Route with 'snis'", function()
            local route, err, err_t = db.routes:insert({
              protocols = { "tcp" },
              snis      = { "example.com" },
              service   = bp.services:insert(),
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.is_table(route)
          end)

          it("creates a Route with 'sources' and 'destinations'", function()
            local route, err, err_t = db.routes:insert({
              protocols  = { "tcp" },
              sources    = {
                { ip = "127.0.0.1" },
                { ip = "127.75.78.72", port = 8000 },
              },
              destinations = {
                { ip = "127.0.0.1" },
                { ip = "127.75.78.72", port = 8000 },
              },
              service = bp.services:insert(),
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.is_table(route)
          end)
        end)

        pending("cannot create a Route with an existing PK", function()
          -- TODO: the uuid type is `auto` for now, so cannot be overidden for
          -- such a test.
          -- We need to test that we receive a primary key violation error in
          -- this case.
        end)
      end)

      describe(":select()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.routes:select()
          end, "primary_key must be a table")
        end)

        -- I/O
        it("return nothing on non-existing Route", function()
          local route, err, err_t = db.routes:select({ id = utils.uuid() })
          assert.is_nil(route)
          assert.is_nil(err_t)
          assert.is_nil(err)
        end)

        it("returns an existing Route", function()
          local route_inserted = bp.routes:insert({
            hosts = { "example.com" },
          })
          local route, err, err_t = db.routes:select({ id = route_inserted.id })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.same(route_inserted, route)
        end)

        describe("#stream context", function()
          it("returns a Route with L4 matching properties", function()
            local route_inserted, err = db.routes:insert({
              protocols  = { "tcp" },
              snis       = { "example.com" },
              sources    = {
                { ip = "127.0.0.1" },
                { ip = "127.75.78.72", port = 8000 },
              },
              destinations = {
                { ip = "127.0.0.1" },
                { ip = "127.75.78.72", port = 8000 },
              },
              service = bp.services:insert(),
            })
            assert.is_nil(err)
            local route, err, err_t = db.routes:select({
              id = route_inserted.id
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same(route_inserted, route)
          end)
        end)
      end)

      describe(":update()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.routes:update()
          end, "primary_key must be a table")
        end)

        it("errors on invalid values", function()
          local route = bp.routes:insert({ hosts = { "example.com" } })
          local pk = { id = route.id }
          local new_route, err, err_t = db.routes:update(pk, {
            protocols = { 123 },
          })
          assert.is_nil(new_route)
          local message  = "schema violation (protocols: expected a string)"
          assert.equal(fmt("[%s] %s", strategy, message), err)
          assert.same({
            code        = Errors.codes.SCHEMA_VIOLATION,
            name        = "schema violation",
            message     = message,
            strategy    = strategy,
            fields      = {
              protocols  = "expected a string",
            }
          }, err_t)
        end)

        -- I/O
        it("returns not found error", function()
          local pk = { id = utils.uuid() }
          local new_route, err, err_t = db.routes:update(pk, {
            protocols = { "https" },
            hosts = { "example.com" },
          })
          assert.is_nil(new_route)
          local message = fmt(
            [[could not find the entity with primary key '{id="%s"}']],
            pk.id
          )
          assert.equal(fmt("[%s] %s", strategy, message), err)
          assert.same({
            code        = Errors.codes.NOT_FOUND,
            name        = "not found",
            strategy    = strategy,
            message     = message,
            fields      = pk,
          }, err_t)
          --TODO: enable when done
          --assert.equal("no such route: id=(" .. u .. ")", tostring(err_t))
        end)

        it("updates an existing Route", function()
          local route = bp.routes:insert({
            hosts = { "example.com" },
          })

          -- ngx.sleep(1)

          local new_route, err, err_t = db.routes:update({ id = route.id }, {
            protocols = { "https" },
            hosts = { "example.com" },
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
            tags            = route.tags,
            service         = route.service,
          }, new_route)


          --TODO: enable when it works again
          --assert.not_equal(new_route.created_at, new_route.updated_at)
        end)

        pending("created_at/updated_at cannot be overriden", function()
          local route = bp.routes:insert {
            hosts = { "example.com" },
          }

          local new_route, err, err_t = db.routes:update({ id = route.id }, {
            protocols = { "https" },
            created_at = 1,
            updated_at = 1,
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.not_equal(1, new_route.created_at)
          assert.not_equal(1, new_route.updated_at)
        end)

        describe("unsetting with ngx.null", function()
          it("succeeds if all routing criteria explicitely given are null", function()
            local route = bp.routes:insert({
              hosts   = { "example.com" },
              methods = { "GET" },
            })

            local new_route, err, err_t = db.routes:update({ id = route.id }, {
              methods = ngx.null
            })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same({
              id              = route.id,
              created_at      = route.created_at,
              updated_at      = new_route.updated_at,
              protocols       = route.protocols,
              hosts           = route.hosts,
              regex_priority  = route.regex_priority,
              strip_path      = route.strip_path,
              preserve_host   = route.preserve_host,
              tags            = route.tags,
              service         = route.service,
            }, new_route)
          end)

          it("fails if all routing criteria would be null", function()
            local route = bp.routes:insert({
              hosts   = { "example.com" },
              methods = { "GET" },
            })

            local new_route, _, err_t = db.routes:update({ id = route.id }, {
              hosts   = ngx.null,
              methods = ngx.null,
            })
            assert.is_nil(new_route)
            assert.same({
              code        = Errors.codes.SCHEMA_VIOLATION,
              name = "schema violation",
              strategy    = strategy,
              message  = unindent([[
                schema violation
                (must set one of 'methods', 'hosts', 'paths' when 'protocols' is 'http' or 'https')
              ]], true, true),
              fields   = {
                ["@entity"] = {
                  "must set one of 'methods', 'hosts', 'paths' when 'protocols' is 'http' or 'https'",
                }
              },
            }, err_t)
          end)

          it("accepts a partial update to routing criteria when at least one of the required fields it not null", function()
            local route = bp.routes:insert({
              hosts   = { "example.com" },
              methods = { "GET" },
              paths   = ngx.null,
            }, { nulls = true })

            local new_route, err, err_t = db.routes:update({ id = route.id }, {
              hosts   = { "example2.com" },
            }, { nulls = true })
            assert.is_nil(err_t)
            assert.is_nil(err)
            assert.same({ "example2.com" }, new_route.hosts)
            assert.same({ "GET" }, new_route.methods)
            assert.same(ngx.null, new_route.paths)
            assert.same(ngx.null, route.paths)
            route.hosts     = nil
            new_route.hosts = nil
            assert(new_route.updated_at >= new_route.updated_at)
            route.updated_at = new_route.updated_at
            assert.same(route, new_route)
          end)

          it("errors when unsetting a required field with ngx.null", function()
            local route = bp.routes:insert({
              hosts   = { "example.com" },
              methods = { "GET" },
            })

            local new_route, _, err_t = db.routes:update({ id = route.id }, {
              hosts   = ngx.null,
              methods = ngx.null,
            })
            assert.is_nil(new_route)
            assert.same({
              code        = Errors.codes.SCHEMA_VIOLATION,
              name = "schema violation",
              strategy    = strategy,
              message  = unindent([[
                schema violation
                (must set one of 'methods', 'hosts', 'paths' when 'protocols' is 'http' or 'https')
              ]], true, true),
              fields   = {
                ["@entity"] = {
                  "must set one of 'methods', 'hosts', 'paths' when 'protocols' is 'http' or 'https'",
                }
              },
            }, err_t)
          end)
        end)
      end)

      describe(":delete()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.routes:delete()
          end, "primary_key must be a table")
        end)

        -- I/O
        it("returns nothing if the Route does not exist", function()
          local u = utils.uuid()
          local ok, err, err_t = db.routes:delete({
            id = u
          })
          assert.is_true(ok)
          assert.is_nil(err_t)
          assert.is_nil(err)
        end)

        it("deletes an existing Route", function()
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
      describe(":insert()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.services:insert()
          end, "entity must be a table")
        end)

        it("errors on invalid fields", function()
          local route, err, err_t = db.services:insert({})
          assert.is_nil(route)
          assert.is_string(err)
          assert.is_table(err_t)
          assert.same({
            code        = Errors.codes.SCHEMA_VIOLATION,
            name        = "schema violation",
            message     = "schema violation (host: required field missing)",
            strategy    = strategy,
            fields      = {
              host = "required field missing",
            }
          }, err_t)
        end)

        -- I/O
        it("creates a Service and injects defaults", function()
          local service, err, err_t = db.services:insert({
            --name     = "example service",
            host = "example.com",
          }, { nulls = true })
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
            name            = ngx.null,
            protocol        = "http",
            host            = "example.com",
            port            = 80,
            path            = ngx.null,
            connect_timeout = 60000,
            write_timeout   = 60000,
            read_timeout    = 60000,
            retries         = 5,
            tags            = ngx.null,
          }, service)
        end)

        it("creates a Service with user-specified values", function()
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
        end)

        it("created_at/updated_at cannot be overriden", function()
          local service, err, err_t = db.services:insert({
            name       = "example_service_overriding_created_at",
            protocol   = "http",
            host       = "example.com",
            created_at = 0,
            updated_at = 0,
          })
          assert.is_nil(err_t)
          assert.is_nil(err)

          assert.is_table(service)
          assert.not_equal(0, service.created_at)
          assert.not_equal(0, service.updated_at)
        end)

        pending("cannot create a Service with an existing id", function()
          -- This test is marked as pending because it will be failing for the
          -- same reasons as its equivalent test for Routes. That is:
          -- TODO: the uuid type is `auto` for now, so cannot be overidden for
          -- such a test.

          -- insert 1
          local _, _, err_t = db.services:insert {
            id = a_blank_uuid,
            name = "my_service",
            protocol = "http",
            host = "example.com",
          }
          assert.is_nil(err_t)

          -- insert 2
          local service, _, err_t = db.services:insert {
            id = a_blank_uuid,
            name = "my_other_service",
            protocol = "http",
            host = "other-example.com",
          }
          assert.is_nil(service)
          assert.same({
            code     = Errors.codes.PRIMARY_KEY_VIOLATION,
            name     = "primary key violation",
            message  = "primary key violation on key '{id=\"" .. a_blank_uuid .. "\"}'",
            strategy = strategy,
            fields   = {
              id = a_blank_uuid,
            }
          }, err_t)
        end)

        it("cannot create a Service with an existing name", function()
          -- insert 1
          local _, _, err_t = db.services:insert {
            name = "my_service_name",
            protocol = "http",
            host = "example.com",
          }
          assert.is_nil(err_t)

          -- insert 2
          local service, _, err_t = db.services:insert {
            name = "my_service_name",
            protocol = "http",
            host = "other-example.com",
          }
          assert.is_nil(service)
          assert.same({
            code     = Errors.codes.UNIQUE_VIOLATION,
            name     = "unique constraint violation",
            message  = "UNIQUE violation detected on '{name=\"my_service_name\"}'",
            strategy = strategy,
            fields   = {
              name = "my_service_name",
            }
          }, err_t)
        end)
      end)

      describe(":select()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.services:select()
          end, "primary_key must be a table")
        end)

        -- I/O
        it("returns nothing on non-existing Service", function()
          local service, err, err_t = db.services:select({
            id = utils.uuid()
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.is_nil(service)
        end)

        it("returns existing Service", function()
          local service = assert(db.services:insert({
            host = "example.com"
          }))

          local service_in_db, err, err_t = db.services:select({
            id = service.id
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.equal("example.com", service_in_db.host)
        end)
      end)

      describe(":select_by_name()", function()
        lazy_setup(function()
          for i = 1, 5 do
            assert(db.services:insert({
              name = "service_" .. i,
              host = "service" .. i .. ".com",
            }))
          end
        end)

        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.services:select_by_name(123)
          end, "name must be a string")
        end)

        -- I/O
        it("returns existing Service", function()
          local service = assert(db.services:select_by_name("service_1"))
          assert.equal("service1.com", service.host)
        end)

        it("returns nothing on non-existing Service", function()
          local service, err, err_t = db.services:select_by_name("non-existing")
          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.is_nil(service)
        end)
      end)

      describe(":update()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.services:update()
          end, "primary_key must be a table")

          assert.has_error(function()
            db.services:update({})
          end, "entity must be a table")
        end)

        it("errors on invalid values", function()
          local service = assert(db.services:insert({ host = "service.test" }))
          local pk = { id = service.id }
          local new_service, err, err_t = db.services:update(pk, { protocol = 123 })
          assert.is_nil(new_service)
          local message = "schema violation (protocol: expected a string)"
          assert.equal(fmt("[%s] %s", strategy, message), err)
          assert.same({
            code        = Errors.codes.SCHEMA_VIOLATION,
            name        = "schema violation",
            message     = message,
            strategy    = strategy,
            fields      = {
              protocol  = "expected a string",
            }
          }, err_t)
        end)

        -- I/O
        it("returns not found error", function()
          local pk = { id = utils.uuid() }
          local service, err, err_t = db.services:update(pk, { protocol = "http" })
          assert.is_nil(service)
          local message = fmt(
            [[[%s] could not find the entity with primary key '{id="%s"}']],
            strategy,
            pk.id)
          assert.equal(message, err)
          assert.equal(Errors.codes.NOT_FOUND, err_t.code)
        end)

        it("updates an existing Service", function()
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
        end)

        it("cannot update a Service to bear an already existing name", function()
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
        end)
      end)

      describe(":update_by_name()", function()
        local s1, s2
        before_each(function()
          if s1 then
            assert(db.services:delete({ id = s1.id }))
          end
          if s2 then
            assert(db.services:delete({ id = s2.id }))
          end

          s1 = assert(db.services:insert({
            name = "update-by-name-service",
            host = "update-by-name-service.com",
          }))
          s2 = assert(db.services:insert({
            name = "existing-service",
            host = "existing-service.com",
          }))
        end)

        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.services:update_by_name(123)
          end, "name must be a string")
        end)

        it("errors on invalid values", function()
          local new_service, err, err_t = db.services:update_by_name("update-by-name-service", {
            protocol = 123
          })
          assert.is_nil(new_service)
          local message = "schema violation (protocol: expected a string)"
          assert.equal(fmt("[%s] %s", strategy, message), err)
          assert.same({
            code        = Errors.codes.SCHEMA_VIOLATION,
            name        = "schema violation",
            message     = message,
            strategy    = strategy,
            fields      = {
              protocol  = "expected a string",
            }
          }, err_t)
        end)

        -- I/O
        it("returns not found error", function()
          local service, err, err_t = db.services:update_by_name("inexisting-service", { protocol = "http" })
          assert.is_nil(service)
          local message = fmt(
            [[[%s] could not find the entity with '{name="inexisting-service"}']],
            strategy)
          assert.equal(message, err)
          assert.equal(Errors.codes.NOT_FOUND, err_t.code)
        end)

        it("updates an existing Service", function()
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
        end)

        it("updates an existing Service", function()
          local updated_service, err, err_t = db.services:update_by_name("update-by-name-service", {
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
        end)

        it("cannot update a Service to bear an already existing name", function()
          local updated_service, _, err_t = db.services:update_by_name("update-by-name-service", {
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
        end)
      end)

      describe(":delete()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.services:delete()
          end, "primary_key must be a table")
        end)

        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.services:delete_by_name(123)
          end, "name must be a string")
        end)

        -- I/O
        it("returns nothing if the Service does not exist", function()
          local u = utils.uuid()
          local ok, err, err_t = db.services:delete({
            id = u
          })
          assert.is_true(ok)
          assert.is_nil(err_t)
          assert.is_nil(err)
        end)

        it("deletes an existing Service", function()
          local service = assert(db.services:insert({
            host = "example.com"
          }))

          local ok, err, err_t = db.services:delete({
            id = service.id
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.is_true(ok)

          local service_in_db, err, err_t = db.services:select({
            id = service.id
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.is_nil(service_in_db)
        end)
      end)

      describe(":delete_by_name()", function()
        local service

        lazy_setup(function()
          service = assert(db.services:insert({
            name = "delete-by-name-service",
            host = "service1.com",
          }))
        end)

        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.services:delete_by_name(123)
          end, "name must be a string")
        end)

        -- I/O
        it("returns nothing if the Service does not exist", function()
          local ok, err, err_t = db.services:delete_by_name("delete-by-name-service0")
          assert.is_true(ok)
          assert.is_nil(err_t)
          assert.is_nil(err)
        end)

        it("deletes an existing Service", function()
          local ok, err, err_t = db.services:delete_by_name("delete-by-name-service")
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.is_true(ok)

          local service_in_db, err, err_t = db.services:select({
            id = service.id
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.is_nil(service_in_db)
        end)
      end)
    end)

    --[[
    -- Services and Routes relationships
    --
    --]]

    describe("Services and Routes association", function()
      it(":insert() a Route with a relation to a Service", function()
        local service = assert(db.services:insert({
          protocol = "http",
          host     = "service.com"
        }))

        local route, err, err_t = db.routes:insert({
          protocols = { "http" },
          hosts     = { "example.com" },
          service   = service,
        }, { nulls = true })
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.same({
          id               = route.id,
          created_at       = route.created_at,
          updated_at       = route.updated_at,
          protocols        = { "http" },
          name             = ngx.null,
          methods          = ngx.null,
          hosts            = { "example.com" },
          paths            = ngx.null,
          snis             = ngx.null,
          sources          = ngx.null,
          destinations     = ngx.null,
          regex_priority   = 0,
          strip_path       = true,
          preserve_host    = false,
          tags             = ngx.null,
          service          = {
            id = service.id
          },
        }, route)

        local route_in_db, err, err_t = db.routes:select({ id = route.id }, { nulls = true })
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.same(route, route_in_db)
      end)

      it(":update() attaches a Route to an existing Service", function()
        local service1 = bp.services:insert({ host = "service1.com" })
        local service2 = bp.services:insert({ host = "service2.com" })

        local route = bp.routes:insert({ service = service1, methods = { "GET" } })

        local new_route, err, err_t = db.routes:update({ id = route.id }, {
          service = service2
        })
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.same(new_route.service, { id = service2.id })
      end)

      it(":update() cannot attach a Route to a non-existing Service", function()
        local service = {
          id = utils.uuid()
        }

        local route = bp.routes:insert({
          hosts = { "example.com" },
        })

        local new_route, err, err_t = db.routes:update({ id = route.id }, {
          service = service
        })
        assert.is_nil(new_route)
        local message = fmt(unindent([[
          the foreign key '{id="%s"}' does not reference an existing
          'services' entity.
        ]], true, true), service.id)

        assert.equal(fmt("[%s] %s", strategy, message), err)
        assert.same({
          code     = Errors.codes.FOREIGN_KEY_VIOLATION,
          name     = "foreign key violation",
          strategy = strategy,
          message  = message,
          fields   = {
            service = {
              id = service.id,
            }
          }
        }, err_t)
      end)

      it(":delete() a Service is not allowed if a Route is associated to it", function()
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
      end)

      it(":delete() a Route without deleting the associated Service", function()
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
      end)

      describe("routes:page_for_service()", function()
        -- no I/O
        it("errors out if invalid arguments", function()
          assert.has_error(function()
            db.routes:page_for_service(nil)
          end, "foreign_key must be a table")

          assert.has_error(function()
            db.routes:page_for_service({ id = 123 }, "100")
          end, "size must be a number")

          assert.has_error(function()
            db.routes:page_for_service({ id = 123 }, 100, 12345)
          end, "offset must be a string")
        end)

        -- I/O
        it("lists no Routes associated to an inexsistent Service", function()
          local rows, err, err_t = db.routes:page_for_service {
            id = a_blank_uuid,
          }
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.same({}, rows)
        end)

        it("returns a table encoding to a JSON Array when empty", function()
          local rows, err, err_t = db.routes:page_for_service {
            id = a_blank_uuid,
          }
          assert.is_nil(err_t)
          assert.is_nil(err)

          if #rows > 0 then
            error("should have returned exactly 0 rows")
          end

          assert.equals("[]", cjson.encode(rows))
        end)

        it("lists Routes associated to a Service", function()
          local service = bp.services:insert()

          local route1 = bp.routes:insert {
            methods = { "GET" },
            service = service,
          }

          bp.routes:insert {
            hosts = { "example.com" },
            -- different service
          }

          local rows, err, err_t = db.routes:page_for_service {
            id = service.id,
          }
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.same({ route1 }, rows)
        end)

        it("invokes schema post-processing", function()
          local service = bp.services:insert {
            host = "example.com",
          }

          bp.routes:insert {
            service = service,
            methods = { "GET" },
          }

          local rows, err, err_t = db.routes:page_for_service {
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
        end)

        describe("paginates", function()
          local service

          describe("page size", function()
            lazy_setup(function()
              service = bp.services:insert()

              for i = 1, 102 do
                bp.routes:insert {
                  hosts   = { "paginate-" .. i .. ".com" },
                  service = service,
                }
              end
            end)

            it("defaults page_size = 100", function()
              local rows, err, err_t = db.routes:page_for_service {
                id = service.id,
              }
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.equal(100, #rows)
            end)

            it("max page_size = 1000", function()
              local _, _, err_t = db.routes:page_for_service({
                id = service.id,
              }, 1002)
              assert.same({
                code = Errors.codes.INVALID_SIZE,
                message = "size must be an integer between 1 and 1000",
                name = "invalid size",
                strategy = strategy,
              }, err_t)
            end)
          end)

          describe("page offset", function()
            lazy_setup(function()

              service = bp.services:insert()

              for i = 1, 10 do
                bp.routes:insert {
                  hosts   = { "paginate-" .. i .. ".com" },
                  service = service,
                }
              end
            end)

            it("fetches all rows in one page", function()
              local rows, err, err_t, offset = db.routes:page_for_service {
                id = service.id,
              }
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_nil(offset)
              assert.equal(10, #rows)
            end)

            it("fetched rows are returned in a table without hash part", function()
              local rows, err, err_t = db.routes:page_for_service {
                id = service.id,
              }
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)

              local keys = {}

              for k in pairs(rows) do
                table.insert(keys, k)
              end

              assert.equal(#rows, #keys) -- no hash part in rows
            end)

            it("fetches rows always in same order", function()
              local rows1 = db.routes:page_for_service { id = service.id }
              local rows2 = db.routes:page_for_service { id = service.id }
              assert.is_table(rows1)
              assert.is_table(rows2)
              assert.same(rows1, rows2)
            end)

            it("returns offset when page_size < total", function()
              local rows, err, err_t, offset = db.routes:page_for_service({
                id = service.id,
              }, 5)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows)
              assert.equal(5, #rows)
              assert.is_string(offset)
            end)

            it("fetches subsequent pages with offset", function()
              local rows_1, err, err_t, offset = db.routes:page_for_service({
                id = service.id,
              }, 5)
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

              local rows_2, err, err_t, offset = db.routes:page_for_service({
                id = service.id,
              }, page_size, offset)

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
            end)

            it("fetches same page with same offset", function()
              local _, err, err_t, offset = db.routes:page_for_service({
                id = service.id,
              }, 3)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_string(offset)

              local rows_a, err, err_t = db.routes:page_for_service({
                id = service.id,
              }, 3, offset)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows_a)
              assert.equal(3, #rows_a)

              local rows_b, err, err_t = db.routes:page_for_service({
                id = service.id,
              }, 3, offset)
              assert.is_nil(err_t)
              assert.is_nil(err)
              assert.is_table(rows_b)
              assert.equal(3, #rows_b)

              for i = 1, #rows_a do
                assert.same(rows_a[i], rows_b[i])
              end
            end)

            it("fetches pages with last page having a single row", function()
              local rows, offset

              repeat
                local err, err_t

                rows, err, err_t, offset = db.routes:page_for_service({
                  id = service.id,
                }, 3, offset)
                assert.is_nil(err_t)
                assert.is_nil(err)

                if offset then
                  assert.equal(3, #rows)
                end
              until offset == nil

              assert.equal(1, #rows) -- last page
            end)

            it("fetches first page with invalid offset", function()
              local rows, err, err_t = db.routes:page_for_service({
                id = service.id,
              }, 3, "hello")
              assert.is_nil(rows)
              local message  = "'hello' is not a valid offset: " ..
                               "bad base64 encoding"
              assert.equal(fmt("[%s] %s", strategy, message), err)
              assert.same({
                code     = Errors.codes.INVALID_OFFSET,
                name     = "invalid offset",
                message  = message,
                strategy = strategy,
              }, err_t)
            end)
          end)
        end) -- paginates
      end) -- routes:page_for_service()
    end) -- Services and Routes association

    --[[
    -- Targets entity

    db.targets:page_for_upstream(primary_key)
    --]]

    describe("Targets", function()
      local upstream

      lazy_setup(function()
        upstream = bp.upstreams:insert()

        for i = 1, 2 do
          bp.targets:insert({
            upstream = upstream,
            target = "target" .. i,
          })
        end
      end)

      describe(":page_for_upstream()", function()
        it("return value 'offset' is a string", function()
          local page, _, _, offset = db.targets:page_for_upstream({
            id = upstream.id,
          }, 1)
          assert.not_nil(page)
          assert.is_string(offset)
        end)
      end)
    end)
  end) -- kong.db [strategy]
end
