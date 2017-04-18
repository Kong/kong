local helpers = require "spec.helpers"
local dao_helpers = require "spec.02-integration.02-dao.helpers"
local cjson = require "cjson"
local DAOFactory = require "kong.dao.factory"

local slots_default, slots_max = 100, 2^16

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title.." with application/www-form-urlencoded", test_form_encoded)
  it(title.." with application/json", test_json)
end

local function validate_order(list, size)
  assert(type(list) == "table", "expected list table, got "..type(list))
  assert(next(list), "table is empty")
  assert(type(size) == "number", "expected size number, got "..type(size))
  assert(size > 0, "expected size to be > 0")
  local c = {}
  local max = 0
  for i,v in pairs(list) do  --> note: pairs, not ipairs!!
    if i > max then max = i end
    c[i] = v
  end
  assert(max == size, "highest key is not equal to the size")
  table.sort(c)
  max = 0
  for i, v in ipairs(c) do
    assert(i == v, "expected sorted table to have equal keys and values")
    if i>max then max = i end
  end
  assert(max == size, "expected array, but got list with holes")
end

dao_helpers.for_each_dao(function(kong_config)

describe("Admin API", function()
  local client
  local dao

  setup(function()
    dao = assert(DAOFactory.new(kong_config))

    assert(helpers.start_kong{
      database = kong_config.database
    })
    client = assert(helpers.admin_client())
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("/upstreams " .. kong_config.database, function()
    describe("POST", function()
      before_each(function()
        dao:truncate_tables()
      end)
      it_content_types("creates an upstream with defaults", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my.upstream",
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(slots_default, json.slots)
          validate_order(json.orderlist, json.slots)
        end
      end)
      it("creates an upstream without defaults with application/json", function()
        local res = assert(client:send {
          method = "POST",
          path = "/upstreams",
          body = {
            name = "my.upstream",
            slots = 10,
            orderlist = { 10,9,8,7,6,5,4,3,2,1 },
          },
          headers = {["Content-Type"] = "application/json"}
        })
        assert.response(res).has.status(201)
        local json = assert.response(res).has.jsonbody()
        assert.equal("my.upstream", json.name)
        assert.is_number(json.created_at)
        assert.is_string(json.id)
        assert.are.equal(10, json.slots)
        validate_order(json.orderlist, json.slots)
        assert.are.same({ 10,9,8,7,6,5,4,3,2,1 }, json.orderlist)
      end)
      pending("creates an upstream without defaults with application/www-form-urlencoded", function()
-- pending due to inability to pass array
-- see also the todo's below
        local res = assert(client:send {
          method = "POST",
          path = "/upstreams",
          body = "name=my.upstream&slots=10&"..
                 "orderlist[]=10&orderlist[]=9&orderlist[]=8&orderlist[]=7&"..
                 "orderlist[]=6&orderlist[]=5&orderlist[]=4&orderlist[]=3&"..
                 "orderlist[]=2&orderlist[]=1",
          headers = {["Content-Type"] = "application/www-form-urlencoded"}
        })
        assert.response(res).has.status(201)
        local json = assert.response(res).has.jsonbody()
        assert.equal("my.upstream", json.name)
        assert.is_number(json.created_at)
        assert.is_string(json.id)
        assert.are.equal(10, json.slots)
        validate_order(json.orderlist, json.slots)
        assert.are.same({ 10,9,8,7,6,5,4,3,2,1 }, json.orderlist)
      end)
      it("creates an upstream with "..slots_max.." slots", function(content_type)
        local res = assert(client:send {
          method = "POST",
          path = "/upstreams",
          body = {
            name = "my.upstream",
            slots = slots_max,
          },
          headers = {["Content-Type"] = "application/json"}
        })
        assert.response(res).has.status(201)
        local json = assert.response(res).has.jsonbody()
        assert.equal("my.upstream", json.name)
        assert.is_number(json.created_at)
        assert.is_string(json.id)
        assert.are.equal(slots_max, json.slots)
        validate_order(json.orderlist, json.slots)
      end)
      describe("errors", function()
        it("handles malformed JSON body", function()
          local res = assert(client:request {
            method = "POST",
            path = "/upstreams",
            body = '{"hello": "world"',
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.res_status(400, res)
          assert.equal('{"message":"Cannot parse JSON body"}', body)
        end)
        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing parameter
            local res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                slots = 50,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ name = "name is required" }, json)

            -- Invalid name parameter
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "some invalid host name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Invalid name; must be a valid hostname" }, json)
            -- Invalid slots parameter
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                slots = 2^16+1
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "number of slots must be between 10 and 65536" }, json)
          end
        end)
        it_content_types("handles invalid input - orderlist", function(content_type)
          return function()
--TODO: line below disables the test for urlencoded, because the orderlist array isn't passed/received properly
if content_type == "application/x-www-form-urlencoded" then return end
            -- non-integers
            local res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                slots = 10,
                orderlist = { "one","two","three","four","five","six","seven","eight","nine","ten" },
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "invalid orderlist" }, json)
            -- non-consecutive
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                slots = 10,
                orderlist = { 1,2,3,4,5,6,7,8,9,11 }, -- 10 is missing
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "invalid orderlist" }, json)
            -- doubles
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                slots = 10,
                orderlist = { 1,2,3,4,5,1,2,3,4,5 }, 
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "invalid orderlist" }, json)
          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.res_status(201, res)

            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.same({ name = "already exists with value 'my.upstream'" }, json)
          end
        end)
      end)
    end)

    describe("PUT", function()
      before_each(function()
        dao:truncate_tables()
      end)

      it_content_types("creates if not exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my-upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.is_number(json.slots)
          assert.is_table(json.orderlist)
        end
      end)
      --it_content_types("replaces if exists", function(content_type)
      pending("replaces if exists", function(content_type)
--TODO: no idea why this fails in an odd manner...
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              slots = 100,
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()

          res = assert(client:send {
            method = "PUT",
            path = "/upstreams",
            body = {
              id = json.id,
              name = "my-new-upstream",
              slots = 123,
              created_at = json.created_at
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(200)
          local updated_json = assert.response(res).has.jsonbody()
          assert.equal("my-new-upstream", updated_json.name)
          assert.equal(123, updated_json.slots)
          assert.equal(json.id, updated_json.id)
          assert.equal(json.created_at, updated_json.created_at)
        end
      end)
      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing parameter
            local res = assert(client:send {
              method = "PUT",
              path = "/upstreams",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.response(res).has.status(400)
            local json = cjson.decode(body)
            assert.same({ name = "name is required" }, json)

            -- Invalid parameter
            res = assert(client:send {
              method = "PUT",
              path = "/upstreams",
              body = {
                name = "1.2.3.4", -- ip is not allowed
                created_at = 1461276890000
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.response(res).has.status(400)
            local json = cjson.decode(body)
            assert.same({ message = "Invalid name; no ip addresses allowed" }, json)
          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          return function()
            -- @TODO this particular test actually defeats the purpose of PUT.
            -- It should probably replace the entity
            local res = assert(client:send {
                method = "PUT",
                path = "/upstreams",
                body = {
                  name = "my-upstream",
                  created_at = 1461276890000
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.response(res).has.status(201)
              local json = assert.response(res).has.jsonbody()

              res = assert(client:send {
                method = "PUT",
                path = "/upstreams",
                body = {
                  name = "my-upstream",
                  created_at = json.created_at
                },
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.response(res).has.status(409)
              local json = cjson.decode(body)
              assert.same({ name = "already exists with value 'my-upstream'" }, json)
            end
        end)
      end)
    end)

    describe("GET", function()
      setup(function()
        dao:truncate_tables()

        for i = 1, 10 do
          assert(dao.upstreams:insert {
            name = "upstream-"..i,
          })
        end
      end)
      teardown(function()
        dao:truncate_tables()
      end)

      it("retrieves the first page", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/upstreams"
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal(10, #json.data)
        assert.equal(10, json.total)
      end)
      it("paginates a set", function()
        local pages = {}
        local offset

        for i = 1, 4 do
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams",
            query = {size = 3, offset = offset}
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          assert.equal(10, json.total)

          if i < 4 then
            assert.equal(3, #json.data)
          else
            assert.equal(1, #json.data)
          end

          if i > 1 then
            -- check all pages are different
            assert.not_same(pages[i-1], json)
          end

          offset = json.offset
          pages[i] = json
        end
      end)
      it("handles invalid filters", function()
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams",
            query = {foo = "bar"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ foo = "unknown field" }, json)
      end)
      it("ignores an invalid body", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/upstreams",
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)
      end)

      describe("empty results", function()
        setup(function()
          dao:truncate_tables()
        end)

        it("data property is an empty array", function()
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same({ data = {}, total = 0 }, json)
        end)
      end)
    end)

    describe("DELETE", function()
      it("by id", function(content_type)
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              slots = 100,
            },
            headers = { ["Content-Type"] = "application/json" }
          })

          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()

          res = assert(client:send {
            method = "DELETE",
            path = "/upstreams/" .. json.id,
          })

          assert.response(res).has.status(204)
      end)

      it("by name", function(content_type)
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              slots = 100,
            },
            headers = { ["Content-Type"] = "application/json" }
          })

          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()

          res = assert(client:send {
            method = "DELETE",
            path = "/upstreams/" .. json.name,
          })

          assert.response(res).has.status(204)
      end)
    end)

    it("returns 405 on invalid method", function()
      local methods = { "DELETE" }

      for i = 1, #methods do
        local res = assert(client:send {
          method = methods[i],
          path = "/upstreams",
          body = {}, -- tmp: body to allow POST/PUT to work
          headers = { ["Content-Type"] = "application/json" }
        })

        local body = assert.response(res).has.status(405)
        local json = cjson.decode(body)
        assert.same({ message = "Method not allowed" }, json)
      end
    end)

  end)
end)

end)
