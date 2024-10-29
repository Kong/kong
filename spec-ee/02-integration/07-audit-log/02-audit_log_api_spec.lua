-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local luatz = require "luatz"
local cjson = require "cjson"

local function insert_dummy_audit_request(bp, id, timestamp)
  return bp.audit_requests:insert({
    request_id = id,
    path = "/services",
    request_timestamp = timestamp,
  })
end

local function insert_dummy_audit_object(bp, id, timestamp)
  return bp.audit_objects:insert({
    id = id,
    request_timestamp = timestamp,
  })
end

for _, strategy in helpers.each_strategy() do
  describe("audit_log API with #" .. strategy, function()
    local admin_client
    local bp
    local db

    setup(function()
      bp, db = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_ignore_paths = [[/audit/(requests|objects)(\?.+)?]],
      }))
    end)

    teardown(function()
      db:truncate("audit_requests")
      db:truncate("audit_objects")
      helpers.stop_kong()
    end)

    before_each(function()
      db:truncate("audit_requests")
      db:truncate("audit_objects")
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      admin_client:close()
      db:truncate("audit_requests")
      db:truncate("audit_objects")
    end)

    describe("audit requests", function()
      describe("with empty audit log", function()
        it("registers calls to API", function()
          local res, json

          res = assert.res_status(200, admin_client:send({path = "/audit/requests"}))
          json = cjson.decode(res)
          assert.same(0, #json.data) -- no data in audit requests

          -- make additional calls
          assert.res_status(200, admin_client:get("/services"))
          assert.res_status(200, admin_client:get("/services"))
          assert.res_status(200, admin_client:get("/services"))

          -- expect to have 3 audit logs
          assert.eventually(function()
            res = assert.res_status(200, admin_client:send({path = "/audit/requests"}))
            json = cjson.decode(res)
            assert.same(3, #json.data)
          end).has_no_error()
        end)
      end)

      describe("with some data in audit log", function()
        local A_ID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        local B_ID = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        local C_ID = "cccccccccccccccccccccccccccccccc"
        local D_ID = "dddddddddddddddddddddddddddddddd"
        local E_ID = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        local F_ID = "ffffffffffffffffffffffffffffffff"

        before_each(function()
          insert_dummy_audit_request(bp, B_ID, luatz.timetable.new(2024, 3, 11, 14, 31, 8):timestamp())
          insert_dummy_audit_request(bp, D_ID, luatz.timetable.new(2024, 3, 11, 14, 31, 7):timestamp())
          insert_dummy_audit_request(bp, A_ID, luatz.timetable.new(2024, 3, 10, 0):timestamp())
          insert_dummy_audit_request(bp, F_ID, luatz.timetable.new(2024, 3, 10, 0):timestamp())
          insert_dummy_audit_request(bp, C_ID, luatz.timetable.new(2024, 3, 9, 0):timestamp())
          insert_dummy_audit_request(bp, E_ID, 3) -- timestamp of vaue "3"
        end)

        -- Assert paging behavior - given we have custom logic for paging in
        -- audit endpoints
        it("returns paged results sorted by request_timestamp descending", function()
          local res, json

          res = assert.res_status(200, admin_client:send({
            path = "/audit/requests",
            query = {size = 2}
          }))
          json = cjson.decode(res)
          assert.same(2, #json.data)

          assert.matches("^/audit/requests", json.next)
          assert.same(B_ID, json.data[1].request_id)
          assert.same(D_ID, json.data[2].request_id)

          local offset = json.offset
          res = assert.res_status(200, admin_client:send({
            path = "/audit/requests",
            query = {size = 2, offset = offset}
          }))
          json = cjson.decode(res)
          assert.same(2, #json.data)
          -- with the same timestamp - sorted by request_id (also descending)
          assert.same(F_ID, json.data[1].request_id)
          assert.same(A_ID, json.data[2].request_id)

          offset = json.offset
          res = assert.res_status(200, admin_client:send({
            path = "/audit/requests",
            query = {size = 2, offset = offset}
          }))
          json = cjson.decode(res)
          assert.same(2, #json.data)
          assert.same(C_ID, json.data[1].request_id)
          assert.same(E_ID, json.data[2].request_id)
        end)

        it("returns results sorted by other column if requested - only sort_by passed", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/requests",
            query = {sort_by = "request_id"}
          }))
          local json = cjson.decode(res)
          assert.same(6, #json.data)

          assert.same(A_ID, json.data[1].request_id)
          assert.same(B_ID, json.data[2].request_id)
          assert.same(C_ID, json.data[3].request_id)
          assert.same(D_ID, json.data[4].request_id)
          assert.same(E_ID, json.data[5].request_id)
          assert.same(F_ID, json.data[6].request_id)
        end)

        it("returns results sorted by other column if requested - both sort_by and sort_desc passed", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/requests",
            query = {sort_by = "request_id", sort_desc = false}
          }))
          local json = cjson.decode(res)
          assert.same(6, #json.data)

          assert.same(A_ID, json.data[1].request_id)
          assert.same(B_ID, json.data[2].request_id)
          assert.same(C_ID, json.data[3].request_id)
          assert.same(D_ID, json.data[4].request_id)
          assert.same(E_ID, json.data[5].request_id)
          assert.same(F_ID, json.data[6].request_id)
        end)

        it("returns results in custom order if requested", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/requests",
            query = {sort_by = "request_id", sort_desc = true}
          }))
          local json = cjson.decode(res)
          assert.same(6, #json.data)

          assert.same(F_ID, json.data[1].request_id)
          assert.same(E_ID, json.data[2].request_id)
          assert.same(D_ID, json.data[3].request_id)
          assert.same(C_ID, json.data[4].request_id)
          assert.same(B_ID, json.data[5].request_id)
          assert.same(A_ID, json.data[6].request_id)
        end)

        it("allows filtering by specific audit_request", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/requests",
            query = {request_timestamp = luatz.timetable.new(2024, 3, 11, 14, 31, 7):timestamp()}
          }))
          local json = cjson.decode(res)
          assert.same(1, #json.data)
          assert.same(D_ID, json.data[1].request_id)
        end)

        it("allows filtering by request_timestamp range - (exclusive range)", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/requests",
            query = {
              ["request_timestamp[lt]"] = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
              ["request_timestamp[gt]"] = luatz.timetable.new(2024, 3, 8, 0):timestamp(),
            }
          }))
          local json = cjson.decode(res)
          assert.same(1, #json.data)
          assert.same(C_ID, json.data[1].request_id)
        end)

        it("allows filtering by request_timestamp range - (inclusive range)", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/requests",
            query = {
              ["request_timestamp[lte]"] = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
              ["request_timestamp[gte]"] = luatz.timetable.new(2024, 3, 1, 0):timestamp(),
            }
          }))
          local json = cjson.decode(res)
          assert.same(3, #json.data)
          assert.same(F_ID, json.data[1].request_id)
          assert.same(A_ID, json.data[2].request_id)
          assert.same(C_ID, json.data[3].request_id)
        end)

        describe("when using before & after aliases", function()
          describe("when using timestamp", function()
            it("allows filtering by before  - (exclusive for provided time)", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/requests",
                query = {
                  before = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
                }
              }))
              local json = cjson.decode(res)
              assert.same(2, #json.data)
              assert.same(C_ID, json.data[1].request_id)
              assert.same(E_ID, json.data[2].request_id)
            end)

            it("allows filtering by before  - (exclusive for provided time) - even when timestamp resembles a year", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/requests",
                query = {
                  before = "2024",
                }
              }))
              local json = cjson.decode(res)
              assert.same(1, #json.data)
              assert.same(E_ID, json.data[1].request_id)
            end)

            it("allows filtering by before  - (exclusive for provided time)", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/requests",
                query = {
                  before = "0",
                }
              }))
              local json = cjson.decode(res)
              assert.same(0, #json.data)
            end)

            it("allows filtering by after  - (inclusive for provided time)", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/requests",
                query = {
                  after = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
                }
              }))
              local json = cjson.decode(res)
              assert.same(4, #json.data)
              assert.same(B_ID, json.data[1].request_id)
              assert.same(D_ID, json.data[2].request_id)
              assert.same(F_ID, json.data[3].request_id)
              assert.same(A_ID, json.data[4].request_id)
            end)

            it("allows filtering by before & after", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/requests",
                query = {
                  after =  luatz.timetable.new(2024, 3, 9, 0):timestamp(), -- inclusive
                  before = luatz.timetable.new(2024, 3, 10, 0):timestamp(), -- exclusive
                }
              }))
              local json = cjson.decode(res)
              assert.same(1, #json.data)
              assert.same(C_ID, json.data[1].request_id)
            end)

            it("filtering both by before & request_timestamp prioritizes before", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/requests",
                query = {
                  before = luatz.timetable.new(2024, 3, 9, 0):timestamp(),
                  ["request_timestamp[lt]"] = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
                }
              }))
              local json = cjson.decode(res)
              assert.same(1, #json.data)
              assert.same(E_ID, json.data[1].request_id)
            end)

            it("filtering both by after & request_timestamp prioritizes after", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/requests",
                query = {
                  after = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
                  ["request_timestamp[gte]"] = luatz.timetable.new(2024, 3, 8, 0):timestamp(),
                }
              }))
              local json = cjson.decode(res)
              assert.same(4, #json.data)
              assert.same(B_ID, json.data[1].request_id)
              assert.same(D_ID, json.data[2].request_id)
              assert.same(F_ID, json.data[3].request_id)
              assert.same(A_ID, json.data[4].request_id)
            end)

            it("filtering both by after & request_timestamp - allows non conflicting queries", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/requests",
                query = {
                  after = luatz.timetable.new(2024, 3, 11, 0):timestamp(),
                  ["request_timestamp[gte]"] = luatz.timetable.new(2024, 3, 11, 0):timestamp(),
                }
              }))
              local json = cjson.decode(res)

              -- after queries for gte and explicit gt are joined with
              -- AND clause making it more narrow
              assert.same(2, #json.data)
              assert.same(B_ID, json.data[1].request_id)
              assert.same(D_ID, json.data[2].request_id)
            end)

            describe("check pagination with filtering both by before & after", function()
              local res, json
              local count, size = 5, 2
              local before = luatz.timetable.new(2024, 3, 11, 14, 31, 9):timestamp()
              local after = luatz.timetable.new(2024, 3, 9, 0):timestamp()

              it("with sort_desc=true", function()
                local req_ids = {}
                local expected_order = { B_ID, D_ID, F_ID, A_ID, C_ID } -- sorted desc by ts
                local next_page = string.format("/audit/requests?beofore=%s&after=%s&size=%s&sort_desc=%s",
                  before, after, size, true)
                -- page 1
                res = assert(admin_client:send { path = next_page })
                json = cjson.decode(assert.res_status(200, res))
                for _, obj in ipairs(json.data) do
                  table.insert(req_ids, obj.request_id)
                end
                next_page = json.next
                assert(next_page ~= cjson.null)
                assert.same(size, #json.data)

                -- page 2
                res = assert(admin_client:send { path = next_page })
                json = cjson.decode(assert.res_status(200, res))
                for _, obj in ipairs(json.data) do
                  table.insert(req_ids, obj.request_id)
                end
                next_page = json.next
                assert(next_page ~= cjson.null)
                assert.same(size, #json.data)

                -- page 3
                res = assert(admin_client:send { path = next_page })
                json = cjson.decode(assert.res_status(200, res))
                for _, obj in ipairs(json.data) do
                  table.insert(req_ids, obj.request_id)
                end
                next_page = json.next
                assert(next_page == cjson.null)
                assert.same(1, #json.data)

                assert.same(count, #req_ids)
                for id = 1, count do
                  assert.equal(expected_order[id], req_ids[id])
                end
              end)

              it("with sort_desc=nil", function()
                local req_ids = {}
                local expected_order = { B_ID, D_ID, F_ID, A_ID, C_ID } -- sorted desc by ts
                local next_page = string.format("/audit/requests?beofore=%s&after=%s&size=%s",
                  before, after, size)
                -- page 1
                res = assert(admin_client:send { path = next_page })
                json = cjson.decode(assert.res_status(200, res))
                for _, obj in ipairs(json.data) do
                  table.insert(req_ids, obj.request_id)
                end
                next_page = json.next
                assert(next_page ~= cjson.null)
                assert.same(size, #json.data)

                -- page 2
                res = assert(admin_client:send { path = next_page })
                json = cjson.decode(assert.res_status(200, res))
                for _, obj in ipairs(json.data) do
                  table.insert(req_ids, obj.request_id)
                end
                next_page = json.next
                assert(next_page ~= cjson.null)
                assert.same(size, #json.data)

                -- page 3
                res = assert(admin_client:send { path = next_page })
                json = cjson.decode(assert.res_status(200, res))
                for _, obj in ipairs(json.data) do
                  table.insert(req_ids, obj.request_id)
                end
                next_page = json.next
                assert(next_page == cjson.null)
                assert.same(1, #json.data)

                assert.same(count, #req_ids)
                -- check order
                for id = 1, count do
                  assert.equal(expected_order[id], req_ids[id])
                end
              end)

              it("with sort_desc=false", function()
                local req_ids = {}
                local expected_order = { C_ID, A_ID, F_ID, D_ID, B_ID } -- sorted asc by ts
                local next_page = string.format("/audit/requests?beofore=%s&after=%s&size=%s&sort_desc=%s",
                  before, after, size, false)
                -- page 1
                res = assert(admin_client:send { path = next_page })
                json = cjson.decode(assert.res_status(200, res))
                for _, obj in ipairs(json.data) do
                  table.insert(req_ids, obj.request_id)
                end
                next_page = json.next
                assert(next_page ~= cjson.null)
                assert.same(size, #json.data)

                -- page 2
                res = assert(admin_client:send { path = next_page })
                json = cjson.decode(assert.res_status(200, res))
                for _, obj in ipairs(json.data) do
                  table.insert(req_ids, obj.request_id)
                end
                next_page = json.next
                assert(next_page ~= cjson.null)
                assert.same(size, #json.data)

                -- page 3
                res = assert(admin_client:send { path = next_page })
                json = cjson.decode(assert.res_status(200, res))
                for _, obj in ipairs(json.data) do
                  table.insert(req_ids, obj.request_id)
                end
                next_page = json.next
                assert(next_page == cjson.null)
                assert.same(1, #json.data)

                assert.same(count, #req_ids)
                -- check order
                for id = 1, count do
                  assert.equal(expected_order[id], req_ids[id])
                end
              end)
            end)
          end)

          describe("when using date", function()
            describe("when using correct date format (RFC3339)", function()
              it("allows filtering by before - (exclusive for provided time)", function()
                local res = assert.res_status(200, admin_client:send({
                  path = "/audit/requests",
                  query = {
                    before = "2024-03-11T14:31:07Z",
                  }
                }))
                local json = cjson.decode(res)
                assert.same(4, #json.data)
                assert.same(F_ID, json.data[1].request_id)
                assert.same(A_ID, json.data[2].request_id)
                assert.same(C_ID, json.data[3].request_id)
                assert.same(E_ID, json.data[4].request_id)
              end)

              it("allows filtering by after - inclusive for provided time)", function()
                local res = assert.res_status(200, admin_client:send({
                  path = "/audit/requests",
                  query = {
                    after = "2024-03-11T14:31:08Z",
                  }
                }))
                local json = cjson.decode(res)
                assert.same(1, #json.data)
                assert.same(B_ID, json.data[1].request_id)
              end)

              it("allows filtering by combination of before and after)", function()
                local res = assert.res_status(200, admin_client:send({
                  path = "/audit/requests",
                  query = {
                    before = "2024-03-11T14:31:07Z",
                    after =  "2024-03-10T00:00:00Z",
                  }
                }))
                local json = cjson.decode(res)
                assert.same(2, #json.data)
                assert.same(F_ID, json.data[1].request_id)
                assert.same(A_ID, json.data[2].request_id)
              end)
            end)

            describe("when date format is incorrect", function()
              it("before - returns 400 for partial dates", function()
                local res = assert.res_status(400, admin_client:send({
                  path = "/audit/requests",
                  query = {
                    before = "2013-07-02T09:00:00-07:00",
                  }
                }))
                local json = cjson.decode(res)
                assert.same({
                  code = 20,
                  message = "date param: '2013-07-02T09:00:00-07:00' does not match expected format: YYYY-MM-DDTHH:MI:SSZ",
                  name = "invalid search query"
                }, json)

                local res = assert.res_status(400, admin_client:send({
                  path = "/audit/requests",
                  query = {
                    before = "2024-03-11T14:31:07.533Z",
                  }
                }))
                local json = cjson.decode(res)
                assert.same({
                  code = 20,
                  message = "date param: '2024-03-11T14:31:07.533Z' does not match expected format: YYYY-MM-DDTHH:MI:SSZ",
                  name = "invalid search query"
                }, json)
              end)

              it("after - returns 400 for partial dates", function()
                local res = assert.res_status(400, admin_client:send({
                  path = "/audit/requests",
                  query = {
                    before = "2024-",
                  }
                }))
                local json = cjson.decode(res)
                assert.same({
                  code = 20,
                  message = "date param: '2024-' does not match expected format: YYYY-MM-DDTHH:MI:SSZ",
                  name = "invalid search query"
                }, json)
              end)

              it("before - returns 400 unmatching strings", function()
                local res = assert.res_status(400, admin_client:send({
                  path = "/audit/requests",
                  query = {
                    before = "before-something-else",
                  }
                }))
                local json = cjson.decode(res)
                assert.same({
                  code = 20,
                  message = "date param: 'before-something-else' does not match expected format: YYYY-MM-DDTHH:MI:SSZ",
                  name = "invalid search query"
                }, json)

                local res = assert.res_status(400, admin_client:send({
                  path = "/audit/requests",
                  query = {
                    after = "after-something-else",
                  }
                }))
                local json = cjson.decode(res)
                assert.same({
                  code = 20,
                  message = "date param: 'after-something-else' does not match expected format: YYYY-MM-DDTHH:MI:SSZ",
                  name = "invalid search query"
                }, json)
              end)
            end)
          end)
        end)
      end)
    end)

    describe("audit objects", function()
      before_each(function()
        db:truncate("consumers")
      end)

      after_each(function()
        db:truncate("consumers")
      end)

      describe("with empty audit_objects", function()
        it("registers calls to API", function()
          local res, json

          res = assert.res_status(200, admin_client:send({path = "/audit/objects"}))
          json = cjson.decode(res)
          assert.same(0, #json.data) -- no audit objects yet

          -- create a few entities
          assert.res_status(201, admin_client:post("/consumers", {
            body = { username = "c1" },
            headers = {["Content-Type"] = "application/json"}
          }))
          res = assert.res_status(201, admin_client:post("/consumers", {
            body = { username = "c2" },
            headers = {["Content-Type"] = "application/json"}
          }))
          json = cjson.decode(res)
          assert.res_status(200, admin_client:patch("/consumers/" .. json.id, {
            body = { username = "c2-updated" },
            headers = {["Content-Type"] = "application/json"}
          }))

          -- expect to have 3 additional audit logs
          assert.eventually(function()
            res = assert.res_status(200, admin_client:send({path = "/audit/objects"}))
            json = cjson.decode(res)
            assert.same(3, #json.data)
            -- request_timestamp is a new field - verify if it's not nill
          end).has_no_error()

          assert.not_nil(json.data[1].request_timestamp)
          assert.not_nil(json.data[2].request_timestamp)
          assert.not_nil(json.data[3].request_timestamp)
        end)
      end)

      describe("with some data in audit_objects", function()
        local A_UUID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        local B_UUID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        local C_UUID = "cccccccc-cccc-cccc-cccc-cccccccccccc"
        local D_UUID = "dddddddd-dddd-dddd-dddd-dddddddddddd"
        local E_UUID = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
        local F_UUID = "ffffffff-ffff-ffff-ffff-ffffffffffff"

        before_each(function()
          insert_dummy_audit_object(bp, B_UUID, luatz.timetable.new(2024, 3, 11, 14, 31, 8):timestamp())
          insert_dummy_audit_object(bp, D_UUID, luatz.timetable.new(2024, 3, 11, 14, 31, 7):timestamp())
          insert_dummy_audit_object(bp, A_UUID, luatz.timetable.new(2024, 3, 10, 0):timestamp())
          insert_dummy_audit_object(bp, F_UUID, luatz.timetable.new(2024, 3, 10, 0):timestamp())
          insert_dummy_audit_object(bp, C_UUID, luatz.timetable.new(2024, 3, 9, 0):timestamp())
          -- the column request_timestamp was added in migration and existing records will have 0 value in it
          -- (note: typedefs of type timestamp does not allow 0 - minimum is 1)
          insert_dummy_audit_object(bp, E_UUID, 1)
        end)

        -- Assert paging behavior - given we have custom logic for paging in
        -- audit endpoints
        it("returns paged results", function()
          local res, json

          res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {size = 2}
          }))
          json = cjson.decode(res)
          assert.same(2, #json.data)

          assert.matches("^/audit/objects", json.next)
          assert.same(B_UUID, json.data[1].id)
          assert.same(D_UUID, json.data[2].id)

          local offset = json.offset
          res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {size = 2, offset = offset}
          }))
          json = cjson.decode(res)
          assert.same(2, #json.data)
          -- with the same timestamp - sorted by request_id (also descending)
          assert.same(F_UUID, json.data[1].id)
          assert.same(A_UUID, json.data[2].id)

          offset = json.offset
          res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {size = 2, offset = offset}
          }))
          json = cjson.decode(res)
          assert.same(2, #json.data)
          assert.same(C_UUID, json.data[1].id)
          assert.same(E_UUID, json.data[2].id)
        end)

        it("returns results sorted by other column if requested - only sort_by passed", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {sort_by = "id"}
          }))
          local json = cjson.decode(res)
          assert.same(6, #json.data)

          assert.same(A_UUID, json.data[1].id)
          assert.same(B_UUID, json.data[2].id)
          assert.same(C_UUID, json.data[3].id)
          assert.same(D_UUID, json.data[4].id)
          assert.same(E_UUID, json.data[5].id)
          assert.same(F_UUID, json.data[6].id)
        end)

        it("returns results sorted by other column if requested - both sort_by and sort_desc passed", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {sort_by = "id", sort_desc = false}
          }))
          local json = cjson.decode(res)
          assert.same(6, #json.data)

          assert.same(A_UUID, json.data[1].id)
          assert.same(B_UUID, json.data[2].id)
          assert.same(C_UUID, json.data[3].id)
          assert.same(D_UUID, json.data[4].id)
          assert.same(E_UUID, json.data[5].id)
          assert.same(F_UUID, json.data[6].id)
        end)

        it("returns results in custom order if requested", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {sort_by = "id", sort_desc = true}
          }))
          local json = cjson.decode(res)
          assert.same(6, #json.data)

          assert.same(F_UUID, json.data[1].id)
          assert.same(E_UUID, json.data[2].id)
          assert.same(D_UUID, json.data[3].id)
          assert.same(C_UUID, json.data[4].id)
          assert.same(B_UUID, json.data[5].id)
          assert.same(A_UUID, json.data[6].id)
        end)

        it("allows filtering by specific audit_request", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {request_timestamp = luatz.timetable.new(2024, 3, 11, 14, 31, 7):timestamp() }
          }))
          local json = cjson.decode(res)
          assert.same(1, #json.data)
          assert.same(D_UUID, json.data[1].id)
        end)

        it("allows filtering by request_timestamp range - (exclusive range)", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {
              ["request_timestamp[lt]"] = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
              ["request_timestamp[gt]"] = luatz.timetable.new(2024, 3, 8, 0):timestamp(),
            }
          }))
          local json = cjson.decode(res)
          assert.same(1, #json.data)
          assert.same(C_UUID, json.data[1].id)
        end)

        it("allows filtering by request_timestamp range - (inclusive range)", function()
          local res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {
              ["request_timestamp[lte]"] = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
              ["request_timestamp[gte]"] = luatz.timetable.new(2024, 3, 8, 0):timestamp(),
            }
          }))
          local json = cjson.decode(res)
          assert.same(3, #json.data)
          assert.same(F_UUID, json.data[1].id)
          assert.same(A_UUID, json.data[2].id)
          assert.same(C_UUID, json.data[3].id)
        end)

        describe("when using before & after aliases", function()
          describe("when using timestamp", function()
            it("allows filtering by before  - (exclusive for provided time)", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/objects",
                query = {
                  before = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
                }
              }))
              local json = cjson.decode(res)
              assert.same(2, #json.data)
              assert.same(C_UUID, json.data[1].id)
              assert.same(E_UUID, json.data[2].id)
            end)

            it("allows filtering by after  - (inclusive for provided time)", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/objects",
                query = {
                  after = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
                }
              }))
              local json = cjson.decode(res)
              assert.same(4, #json.data)
              assert.same(B_UUID, json.data[1].id)
              assert.same(D_UUID, json.data[2].id)
              assert.same(F_UUID, json.data[3].id)
              assert.same(A_UUID, json.data[4].id)
            end)

            it("allows filtering by before & after", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/objects",
                query = {
                  after = luatz.timetable.new(2024, 3, 9, 0):timestamp(), -- inclusive
                  before = luatz.timetable.new(2024, 3, 10, 0):timestamp(), -- exclusive
                }
              }))
              local json = cjson.decode(res)
              assert.same(1, #json.data)
              assert.same(C_UUID, json.data[1].id)
            end)

            it("filtering both by before & request_timestamp prioritizes before", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/objects",
                query = {
                  before = luatz.timetable.new(2024, 3, 9, 0):timestamp(),
                  ["request_timestamp[lt]"] = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
                }
              }))
              local json = cjson.decode(res)
              assert.same(1, #json.data)
              assert.same(E_UUID, json.data[1].id)
            end)

            it("filtering both by after & request_timestamp prioritizes after", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/objects",
                query = {
                  after = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
                  ["request_timestamp[gte]"] = luatz.timetable.new(2024, 3, 8, 0):timestamp(),
                }
              }))
              local json = cjson.decode(res)
              assert.same(4, #json.data)
              assert.same(B_UUID, json.data[1].id)
              assert.same(D_UUID, json.data[2].id)
              assert.same(F_UUID, json.data[3].id)
              assert.same(A_UUID, json.data[4].id)
            end)

            it("filtering both by after & request_timestamp - allows non conflicting queries", function()
              local res = assert.res_status(200, admin_client:send({
                path = "/audit/objects",
                query = {
                  after = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
                  ["request_timestamp[gt]"] = luatz.timetable.new(2024, 3, 10, 0):timestamp(),
                }
              }))
              local json = cjson.decode(res)

              -- after queries for gte and explicit gt are joined with
              -- AND clause making it more narrow
              assert.same(2, #json.data)
              assert.same(B_UUID, json.data[1].id)
              assert.same(D_UUID, json.data[2].id)
            end)
          end)

          describe("when using date", function()
            describe("when using correct date format (RFC3339)", function()
              it("allows filtering by before - (exclusive for provided time)", function()
                local res = assert.res_status(200, admin_client:send({
                  path = "/audit/objects",
                  query = {
                    before = "2024-03-11T14:31:07Z",
                  }
                }))
                local json = cjson.decode(res)
                assert.same(4, #json.data)
                assert.same(F_UUID, json.data[1].id)
                assert.same(A_UUID, json.data[2].id)
                assert.same(C_UUID, json.data[3].id)
                assert.same(E_UUID, json.data[4].id)
              end)

              it("allows filtering by after - inclusive for provided time)", function()
                local res = assert.res_status(200, admin_client:send({
                  path = "/audit/objects",
                  query = {
                    after = "2024-03-11T14:31:08Z",
                  }
                }))
                local json = cjson.decode(res)
                assert.same(1, #json.data)
                assert.same(B_UUID, json.data[1].id)
              end)

              it("allows filtering by combination of before and after)", function()
                local res = assert.res_status(200, admin_client:send({
                  path = "/audit/objects",
                  query = {
                    before = "2024-03-11T14:31:07Z",
                    after =  "2024-03-10T00:00:00Z",
                  }
                }))
                local json = cjson.decode(res)
                assert.same(2, #json.data)
                assert.same(F_UUID, json.data[1].id)
                assert.same(A_UUID, json.data[2].id)
              end)
            end)

            describe("when date format is incorrect", function()
              it("before - returns 400 for partial dates", function()
                local res = assert.res_status(400, admin_client:send({
                  path = "/audit/objects",
                  query = {
                    before = "2013-07-02T09:00:00-07:00",
                  }
                }))
                local json = cjson.decode(res)
                assert.same({
                  code = 20,
                  message = "date param: '2013-07-02T09:00:00-07:00' does not match expected format: YYYY-MM-DDTHH:MI:SSZ",
                  name = "invalid search query"
                }, json)

                local res = assert.res_status(400, admin_client:send({
                  path = "/audit/objects",
                  query = {
                    before = "2024-03-11T14:31:07.533Z",
                  }
                }))
                local json = cjson.decode(res)
                assert.same({
                  code = 20,
                  message = "date param: '2024-03-11T14:31:07.533Z' does not match expected format: YYYY-MM-DDTHH:MI:SSZ",
                  name = "invalid search query"
                }, json)
              end)

              it("after - returns 400 for partial dates", function()
                local res = assert.res_status(400, admin_client:send({
                  path = "/audit/objects",
                  query = {
                    before = "2024-",
                  }
                }))
                local json = cjson.decode(res)
                assert.same({
                  code = 20,
                  message = "date param: '2024-' does not match expected format: YYYY-MM-DDTHH:MI:SSZ",
                  name = "invalid search query"
                }, json)
              end)

              it("before - returns 400 unmatching strings", function()
                local res = assert.res_status(400, admin_client:send({
                  path = "/audit/objects",
                  query = {
                    before = "before-something-else",
                  }
                }))
                local json = cjson.decode(res)
                assert.same({
                  code = 20,
                  message = "date param: 'before-something-else' does not match expected format: YYYY-MM-DDTHH:MI:SSZ",
                  name = "invalid search query"
                }, json)

                local res = assert.res_status(400, admin_client:send({
                  path = "/audit/objects",
                  query = {
                    after = "after-something-else",
                  }
                }))
                local json = cjson.decode(res)
                assert.same({
                  code = 20,
                  message = "date param: 'after-something-else' does not match expected format: YYYY-MM-DDTHH:MI:SSZ",
                  name = "invalid search query"
                }, json)
              end)
            end)
          end)
        end)
      end)
    end)
  end)

  describe("audit_log API with RBAC #" .. strategy, function()
    local admin_client
    local db

    before_each(function()
      _, db = helpers.get_db_utils(strategy)

      local conf = {
        database = strategy,
        admin_gui_url = "http://manager.konghq.com",
        admin_gui_auth = 'basic-auth',
        audit_log = "on",
        admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
        admin_gui_auth_password_complexity = "{\"kong-preset\": \"min_12\"}",
        enforce_rbac = "on",
        password = "foo",
        prefix = helpers.test_conf.prefix,
      }

      assert(helpers.kong_exec("migrations reset --yes", conf))
      assert(helpers.kong_exec("migrations bootstrap", conf))

      assert(helpers.start_kong(conf))

      ee_helpers.register_rbac_resources(db)
      admin_client = assert(helpers.admin_client())
    end)

    after_each(function()
      if admin_client then admin_client:close() end
      assert(helpers.stop_kong(nil, true))
    end)

    it("audit request should be have request-source and rbac_user_name", function()
      local options = {
        headers = {
          ["X-Request-Source"] = "Kong-Manager",
          ["Kong-Admin-User"]  = "kong_admin",
          ["Kong-Admin-Token"] = "foo"
        }
      }
      assert.res_status(200, admin_client:get("/services", options))
      assert.res_status(200, admin_client:get("/services", options))
      assert.res_status(200, admin_client:get("/services", options))

      local res, json

      res = assert.res_status(200, admin_client:send({
        path = "/audit/requests",
        query = { size = 2 },
        headers = options.headers
      }))
      json = cjson.decode(res)
      assert.same(2, #json.data)
      for key, value in pairs(json.data) do
        if key == "request-source" then
          assert.same("Kong-Manager", value)
        end
        if key == "rbac_user_name" then
          assert.same("kong_admin", value)
        end
      end

    end)
  end)
end
