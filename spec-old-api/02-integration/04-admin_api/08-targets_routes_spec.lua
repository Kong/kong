local helpers = require "spec.helpers"
local cjson = require "cjson"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end

local upstream_name = "my_upstream"

for _, strategy in helpers.each_strategy() do

describe("Admin API #" .. strategy, function()

  local bp
  local db
  local client, upstream
  local weight_default, weight_min, weight_max = 100, 0, 1000
  local default_port = 8000

  before_each(function()
    bp, db = helpers.get_db_utils(strategy)
    assert(helpers.dao:run_migrations())
    assert(helpers.start_kong({
      database = strategy,
    }))

    client = assert(helpers.admin_client())

    assert(db:truncate("upstreams"))
    assert(db:truncate("targets"))

    upstream = bp.upstreams:insert {
      name = upstream_name,
      slots = 10,
    }
  end)

  after_each(function()
    if client then client:close() end
    assert(helpers.stop_kong())
  end)

  describe("/upstreams/{upstream}/targets/", function()
    describe("POST", function()
      it_content_types("creates a target with defaults", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/" .. upstream_name .. "/targets/",
            body = {
              target = "mashape.com",
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("mashape.com:" .. default_port, json.target)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(weight_default, json.weight)
        end
      end)
      it_content_types("creates a target without defaults", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/" .. upstream_name .. "/targets/",
            body = {
              target = "mashape.com:123",
              weight = 99,
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("mashape.com:123", json.target)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(99, json.weight)
        end
      end)
      it("cleans up old target entries", function()
        -- count to 12; 10 old ones, 1 active one, and then nr 12 to
        -- trigger the cleanup
        for i = 1, 12 do
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/" .. upstream_name .. "/targets/",
            body = {
              target = "mashape.com:123",
              weight = 99,
            },
            headers = {
              ["Content-Type"] = "application/json"
            },
          })
          assert.response(res).has.status(201)
        end
        local history = db.targets:for_upstream_raw({ id = upstream.id })
        -- there should be 2 left; 1 from the cleanup, and the final one
        -- inserted that triggered the cleanup
        assert.equal(2, #history)
      end)

      describe("errors", function()
        it("handles malformed JSON body", function()
          local res = assert(client:request {
            method = "POST",
            path = "/upstreams/" .. upstream_name .. "/targets/",
            body = '{"hello": "world"',
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.response(res).has.status(400)
          local json = cjson.decode(body)
          assert.same({ message = "Cannot parse JSON body" }, json)
        end)
        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing parameter
            local res = assert(client:send {
              method = "POST",
              path = "/upstreams/" .. upstream_name .. "/targets/",
              body = {
                weight = weight_min,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.response(res).has.status(400)
            local json = cjson.decode(body)
            assert.equal("schema violation", json.name)
            assert.same({ target = "required field missing" }, json.fields)

            -- Invalid target parameter
            res = assert(client:send {
              method = "POST",
              path = "/upstreams/" .. upstream_name .. "/targets/",
              body = {
                target = "some invalid host name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.response(res).has.status(400)
            local json = cjson.decode(body)
            assert.equal("schema violation", json.name)
            assert.same({ target = "Invalid target; not a valid hostname or ip address" }, json.fields)

            -- Invalid weight parameter
            res = assert(client:send {
              method = "POST",
              path = "/upstreams/" .. upstream_name .. "/targets/",
              body = {
                target = "mashape.com",
                weight = weight_max + 1,
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.response(res).has.status(400)
            local json = cjson.decode(body)
            assert.equal("schema violation", json.name)
            assert.same({ weight = "value should be between 0 and 1000" }, json.fields)
          end
        end)

        for _, method in ipairs({"PUT", "PATCH", "DELETE"}) do
          it_content_types("returns 405 on " .. method, function(content_type)
            return function()
              local res = assert(client:send {
                method = method,
                path = "/upstreams/" .. upstream_name .. "/targets/",
                body = {
                  target = "mashape.com",
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.response(res).has.status(405)
            end
          end)
        end
      end)
    end)

    describe("GET", function()
      local upstream_name3 = "example.com"
      local apis = {}

      before_each(function()
        local upstream3 = bp.upstreams:insert { name = upstream_name3 }

        -- testing various behaviors
        -- for each index in weights, create a number of targets,
        -- each with its weight as each element of the sub-array
        local weights = {
          { 10, 0 },        -- two targets, eventually resulting in down
          { 10, 0, 10 },    -- three targets, eventually resulting in up
          { 10 },           -- one target, up
          { 10, 10 },       -- two targets, up (we should only see one)
          { 10, 50, 0 },    -- three targets, two up in a row, eventually down
          { 10, 0, 20, 0 }, -- four targets, eventually down
        }

        for i = 1, #weights do
          for j = 1, #weights[i] do
            ngx.sleep(0.01)
            apis[i] = bp.targets:insert {
              target = "api-" .. tostring(i) .. ":80",
              weight = weights[i][j],
              upstream = { id = upstream3.id },
            }
          end
        end
      end)

      it("only shows active targets", function()
        for _, append in ipairs({ "", "/" }) do
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/" .. upstream_name3 .. "/targets" .. append,
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()

          -- we got three active targets for this upstream
          assert.equal(3, #json.data)

          -- when multiple active targets are present, we only see the last one
          assert.equal(apis[4].id, json.data[1].id)

          -- validate the remaining returned targets
          -- note the backwards order, because we walked the targets backwards
          assert.equal(apis[3].target, json.data[2].target)
          assert.equal(apis[2].target, json.data[3].target)
        end
      end)
    end)
  end)

  describe("/upstreams/{upstream}/targets/all/", function()
    describe("GET", function()
      before_each(function()
        for i = 1, 10 do
          bp.targets:insert {
            target = "api-" .. i .. ":80",
            weight = 100,
            upstream = { id = upstream.id },
          }
        end
      end)

      it("retrieves the first page", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream_name .. "/targets/all",
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal(10, #json.data)
      end)
      it("paginates a set", function()
        local pages = {}
        local offset

        for i = 1, 4 do
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/" .. upstream_name .. "/targets/all",
            query = {size = 3, offset = offset}
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()

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
      it("ignores an invalid body", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream_name .. "/targets/all",
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.response(res).has.status(200)
      end)

      describe("empty results", function()
        local upstream_name2 = "getkong.org"

        before_each(function()
          bp.upstreams:insert {
            name = upstream_name2,
            slots = 10,
          }
        end)

        it("data property is an empty array", function()
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/" .. upstream_name2 .. "/targets/all",
          })
          local body = assert.response(res).has.status(200)
          local json = cjson.decode(body)
          assert.same({ data = {} }, json)
        end)
      end)
    end)
  end)

  describe("/upstreams/{upstream}/targets/{target}", function()
    describe("DELETE", function()
      local target
      local upstream_name4 = "example4.com"

      before_each(function()
        local upstream4 = bp.upstreams:insert {
          name = upstream_name4,
        }

        bp.targets:insert {
          target = "api-1:80",
          weight = 10,
          upstream = { id = upstream4.id },
        }

        -- predefine the target to mock delete
        target = bp.targets:insert {
          target = "api-2:80",
          weight = 10,
          upstream = { id = upstream4.id },
        }
      end)

      it("acts as a sugar method to POST a target with 0 weight (by target)", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/upstreams/" .. upstream_name4 .. "/targets/" .. target.target
        })
        assert.response(res).has.status(204)

        local targets = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream_name4 .. "/targets/all",
        })
        assert.response(targets).has.status(200)
        local json = assert.response(targets).has.jsonbody()
        assert.equal(3, #json.data)

        local active = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream_name4 .. "/targets",
        })
        assert.response(active).has.status(200)
        json = assert.response(active).has.jsonbody()
        assert.equal(1, #json.data)
        assert.equal("api-1:80", json.data[1].target)
      end)

      it("acts as a sugar method to POST a target with 0 weight (by id)", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/upstreams/" .. upstream_name4 .. "/targets/" .. target.id
        })
        assert.response(res).has.status(204)

        local targets = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream_name4 .. "/targets/all",
        })
        assert.response(targets).has.status(200)
        local json = assert.response(targets).has.jsonbody()
        assert.equal(3, #json.data)

        local active = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream_name4 .. "/targets",
        })
        assert.response(active).has.status(200)
        json = assert.response(active).has.jsonbody()
        assert.equal(1, #json.data)
        assert.equal("api-1:80", json.data[1].target)
      end)
    end)
  end)
end)

end
