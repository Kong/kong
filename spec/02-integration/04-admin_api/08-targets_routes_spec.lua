local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils   = require "kong.tools.utils"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_multipart = fn("multipart/form-data")
  local test_json = fn("application/json")

  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
  it(title .. " with application/json", test_json)
end

local function client_send(req)
  local client = helpers.admin_client()
  local res = assert(client:send(req))
  local status, body = res.status, res:read_body()
  client:close()
  return status, body
end

for _, strategy in helpers.each_strategy() do

describe("Admin API #" .. strategy, function()
  local bp
  local db
  local client
  local weight_default, weight_min, weight_max = 100, 0, 1000
  local default_port = 8000

  lazy_setup(function()
    bp, db = helpers.get_db_utils(strategy, {
      "upstreams",
      "targets",
    })
    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  lazy_teardown(function()
    assert(helpers.stop_kong())
  end)

  before_each(function()
    client = assert(helpers.admin_client())
  end)

  after_each(function()
    if client then client:close() end
  end)

  describe("/targets", function()
    it("returns a 404", function()
      local res = assert(client:send {
        method = "GET",
        path = "/targets"
      })
      assert.response(res).has.status(404)
      local json = assert.response(res).has.jsonbody()
      assert.equal("Not found", json.message)
    end)
  end)

  describe("/upstreams/{upstream}/targets/", function()
    describe("POST", function()
      it_content_types("creates a target with defaults", function(content_type)
        return function()
          local upstream = bp.upstreams:insert { slots = 10 }
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/" .. upstream.name .. "/targets/",
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
          local upstream = bp.upstreams:insert { slots = 10 }
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/" .. upstream.name .. "/targets/",
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
        local upstream = bp.upstreams:insert { slots = 10 }
        -- insert elements in two targets alternately to build up a history
        for i = 1, 11 do
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/" .. upstream.name .. "/targets/",
            body = {
              target = "mashape.com:1111",
              weight = i,
            },
            headers = {
              ["Content-Type"] = "application/json"
            },
          })
          assert.response(res).has.status(201)

          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/" .. upstream.name .. "/targets/",
            body = {
              target = "mashape.com:2222",
              weight = i,
            },
            headers = {
              ["Content-Type"] = "application/json"
            },
          })
          assert.response(res).has.status(201)
        end

        -- now insert a few more elements only in the second target, to trigger a cleanup
        for i = 12, 13 do
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/" .. upstream.name .. "/targets/",
            body = {
              target = "mashape.com:2222",
              weight = i,
            },
            headers = {
              ["Content-Type"] = "application/json"
            },
          })
          assert.response(res).has.status(201)
        end

        local history = assert(db.targets:select_by_upstream_raw({ id = upstream.id }))
        -- cleanup took place
        assert(#history <= 5)

        -- the remaining entries should be the correct ones
        -- (i.e. the target not involved in the operation that triggered the cleanup
        -- should not be corrupted)
        local targets = assert(db.targets:page_for_upstream({ id = upstream.id }))
        table.sort(targets, function(a,b) return a.target < b.target end)
        assert.same("mashape.com:1111", targets[1].target)
        assert.same(11, targets[1].weight)
        assert.same("mashape.com:2222", targets[2].target)
        assert.same(13, targets[2].weight)
      end)

      describe("errors", function()
        it("handles malformed JSON body", function()
          local upstream = bp.upstreams:insert { slots = 10 }
          local res = assert(client:request {
            method = "POST",
            path = "/upstreams/" .. upstream.name .. "/targets/",
            body = '{"hello": "world"',
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.response(res).has.status(400)
          local json = cjson.decode(body)
          assert.same({ message = "Cannot parse JSON body" }, json)
        end)
        it_content_types("handles invalid input", function(content_type)
          return function()
            local upstream = bp.upstreams:insert { slots = 10 }
            -- Missing parameter
            local res = assert(client:send {
              method = "POST",
              path = "/upstreams/" .. upstream.name .. "/targets/",
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
              path = "/upstreams/" .. upstream.name .. "/targets/",
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
              path = "/upstreams/" .. upstream.name .. "/targets/",
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
              local upstream = bp.upstreams:insert { slots = 10 }
              local res = assert(client:send {
                method = method,
                path = "/upstreams/" .. upstream.name .. "/targets/",
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
      local apis = {}

      local upstream

      before_each(function()
        upstream = bp.upstreams:insert {}

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
              upstream = { id = upstream.id },
            }
          end
        end
      end)

      it("only shows active targets", function()
        for _, append in ipairs({ "", "/" }) do
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/" .. upstream.name .. "/targets" .. append,
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

      describe("empty results", function()
        it("data property is an empty array", function()
          local empty_upstream = bp.upstreams:insert {}
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/" .. empty_upstream.name .. "/targets",
          })
          local body = assert.response(res).has.status(200)
          assert.match('"data":%[%]', body)
        end)
      end)
    end)
  end)

  describe("/upstreams/{upstream}/health/", function()

    describe("GET", function()
      local upstream
      local node_id

      local function add_targets(target_fmt)
        local targets = {}
        local weights = {
          { 10, 0 },
          { 10 },
          { 10 },
          { 10, 10 },
        }

        for i = 1, #weights do
          for j = 1, #weights[i] do
            local status, body = client_send({
              method = "POST",
              path = "/upstreams/" .. upstream.name .. "/targets",
              headers = {
                ["Content-Type"] = "application/json",
              },
              body = {
                target = string.format(target_fmt, i),
                weight = weights[i][j],
              }
            })
            assert.same(201, status)
            targets[i] = assert(cjson.decode(body))
          end
        end
        return targets
      end

      -- Performs tests similar to /upstreams/:upstream_id/targets,
      -- and checks for the "health" field of each target.
      -- @param targets the array of target data produced by add_targets
      -- @param n the expected number of targets in the response
      -- It is different from #targets because add_targets adds
      -- zero-weight targets as well.
      -- @param health the expected "health" response for all targets
      local function check_health_endpoint(targets, n, health)
        for _, append in ipairs({ "", "/" }) do
          local status, body = client_send({
            method = "GET",
            path = "/upstreams/" .. upstream.name .. "/health" .. append,
          })
          assert.same(200, status)
          local res = assert(cjson.decode(body))

          assert.same(node_id, res.node_id)
          assert.equal(n, #res.data)

          -- when multiple active targets are present, we only see the last one
          assert.equal(targets[4].id, res.data[1].id)

          -- validate the remaining returned targets
          -- note the backwards order, because we walked the targets backwards
          assert.equal(targets[3].target, res.data[2].target)
          assert.equal(targets[2].target, res.data[3].target)
          for i = 1, n do
            if res.data[i].data ~= nil and res.data[i].data.addresses ~= nil then
              for j = 1, #res.data[i].data.addresses do
                assert.equal(health, res.data[i].data.addresses[j].health)
              end
              assert.equal(health, res.data[i].health)
            end
          end
        end
      end

      lazy_setup(function()
        local status, body = client_send({
          method = "GET",
          path = "/",
        })
        assert.same(200, status)
        local res = assert(cjson.decode(body))
        assert.string(res.node_id)
        node_id = res.node_id
      end)

      before_each(function()
        local any_upstream = bp.upstreams:insert {}
        local status, body = client_send({
          method = "POST",
          path = "/upstreams",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            name = any_upstream.name .. "-health",
          }
        })
        assert.same(201, status)
        upstream = assert(cjson.decode(body))
      end)

      describe("with healthchecks off", function()
        it("returns HEALTHCHECKS_OFF for targets that resolve", function()
          add_targets("127.0.0.1:8%d")
          local targets = add_targets("custom_localhost:8%d")
          check_health_endpoint(targets, 6, "HEALTHCHECKS_OFF")
        end)

        it("returns DNS_ERROR if DNS cannot be resolved", function()
          local targets = add_targets("bad-health-target-%d:80")

          check_health_endpoint(targets, 3, "DNS_ERROR")
        end)
      end)

      describe("with healthchecks on", function()
        before_each(function()
          local status = client_send({
            method = "PATCH",
            path = "/upstreams/" .. upstream.name,
            headers = {
              ["Content-Type"] = "application/json",
            },
            body = {
              healthchecks = {
                passive = {
                  healthy = {
                    successes = 1,
                  },
                  unhealthy = {
                    tcp_failures = 1,
                    http_failures = 1,
                    timeouts = 1,
                  },
                }
              }
            }
          })
          assert.same(200, status)
        end)

        it("returns DNS_ERROR if DNS cannot be resolved", function()

          local targets = add_targets("bad-target-%d:80")

          check_health_endpoint(targets, 3, "DNS_ERROR")

        end)

        it("returns HEALTHY if failure not detected", function()

          local targets = add_targets("custom_localhost:222%d")

          check_health_endpoint(targets, 3, "HEALTHY")

        end)

        it("returns UNHEALTHY if failure detected", function()

          local targets = add_targets("custom_localhost:222%d")

          local status = client_send({
            method = "PATCH",
            path = "/upstreams/" .. upstream.name,
            headers = {
              ["Content-Type"] = "application/json",
            },
            body = {
              healthchecks = {
                active = {
                  healthy = {
                    interval = 0.1,
                  },
                  unhealthy = {
                    interval = 0.1,
                    tcp_failures = 1,
                  },
                }
              }
            }
          })
          assert.same(200, status)

          -- Give time for active healthchecks to kick in
          ngx.sleep(0.3)

          check_health_endpoint(targets, 3, "UNHEALTHY")

        end)
      end)
    end)
  end)

  describe("/upstreams/{upstream}/targets/all/", function()
    describe("GET", function()
      local upstream
      before_each(function()
        upstream = bp.upstreams:insert {}
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
          path = "/upstreams/" .. upstream.name .. "/targets/all",
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal(10, #json.data)
      end)
      it("offset is a string", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream.name .. "/targets",
          query = {size = 3},
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_string(json.offset)
      end)
      it("paginates a set", function()
        local pages = {}
        local offset

        for i = 1, 4 do
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/" .. upstream.name .. "/targets/all",
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
      it("ingores filters", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream.name .. "/targets/all",
          query = {foo = "bar"},
        })
        assert.response(res).has.status(200)
      end)
      it("ignores an invalid body", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream.name .. "/targets/all",
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.response(res).has.status(200)
      end)

      describe("empty results", function()
        it("data property is an empty array", function()
          local empty_upstream = bp.upstreams:insert {}
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/" .. empty_upstream.name .. "/targets/all",
          })
          local body = assert.response(res).has.status(200)
          local json = cjson.decode(body)
          assert.same({
            data = {},
            next = ngx.null,
          }, json)
          -- ensure JSON representation is correct
          assert.match('"data":%[%]', body)
        end)
      end)
    end)
  end)

  describe("/upstreams/{upstream}/targets/{target}/(un)healthy", function()

    local localhosts = {
      ipv4 = "127.0.0.1",
      ipv6 = "[0000:0000:0000:0000:0000:0000:0000:0001]",
      hostname = "localhost",
    }
    for mode, localhost in pairs(localhosts) do

      describe("POST #" .. mode, function()
        local upstream
        local target_path
        local target
        local wrong_target

        lazy_setup(function()
          local my_target_name = localhost .. ":8192"

          wrong_target = bp.targets:insert {
            target = my_target_name,
            weight = 10
          }

          upstream = bp.upstreams:insert {}
          local status, body = assert(client_send({
            method = "PATCH",
            path = "/upstreams/" .. upstream.id,
            headers = {["Content-Type"] = "application/json"},
            body = {
              healthchecks = {
                passive = {
                  healthy = {
                    successes = 1,
                  },
                  unhealthy = {
                    tcp_failures = 1,
                    http_failures = 1,
                    timeouts = 1,
                  },
                }
              }
            }
          }))
          assert.same(200, status, body)
          local json = assert(cjson.decode(body))

          status, body = assert(client_send({
            method = "POST",
            path = "/upstreams/" .. upstream.id .. "/targets",
            headers = {["Content-Type"] = "application/json"},
            body = {
              target = my_target_name,
              weight = 10,
              upstream = { id = json.id },
            }
          }))
          assert.same(201, status)
          target = assert(cjson.decode(body))
          assert.same(my_target_name, target.target)

          target_path = "/upstreams/" .. upstream.id .. "/targets/" .. target.target
        end)

        it("checks every combination of valid and invalid upstream and target", function()
          for i, u in ipairs({ utils.uuid(), "invalid", upstream.name, upstream.id }) do
            for j, t in ipairs({ utils.uuid(), "invalid:1234", wrong_target.id, target.target, target.id }) do
              for _, e in ipairs({ "healthy", "unhealthy" }) do
                local expected = (i >= 3 and j >= 4) and 204 or 404
                local path = "/upstreams/" .. u .. "/targets/" .. t .. "/" .. e
                local status = assert(client_send {
                  method = "POST",
                  path = "/upstreams/" .. u .. "/targets/" .. t .. "/" .. e
                })
                assert.same(expected, status, "bad status for path " .. path)
              end
            end
          end
        end)

        it("flips the target status from UNHEALTHY to HEALTHY", function()
          local status, body, json
          status, body = assert(client_send {
            method = "POST",
            path = target_path .. "/unhealthy"
          })
          assert.same(204, status, body)
          status, body = assert(client_send {
            method = "GET",
            path = "/upstreams/" .. upstream.id .. "/health"
          })
          assert.same(200, status)
          json = assert(cjson.decode(body))
          assert.same(target.target, json.data[1].target)
          assert.same("UNHEALTHY", json.data[1].health)
          status = assert(client_send {
            method = "POST",
            path = target_path .. "/healthy"
          })
          assert.same(204, status)
          status, body = assert(client_send {
            method = "GET",
            path = "/upstreams/" .. upstream.id .. "/health"
          })
          assert.same(200, status)
          json = assert(cjson.decode(body))
          assert.same(target.target, json.data[1].target)
          assert.same("HEALTHY", json.data[1].health)
        end)

        it("flips the target status from HEALTHY to UNHEALTHY", function()
          local status, body, json
          status = assert(client_send {
            method = "POST",
            path = target_path .. "/healthy"
          })
          assert.same(204, status)
          status, body = assert(client_send {
            method = "GET",
            path = "/upstreams/" .. upstream.id .. "/health"
          })
          assert.same(200, status)
          json = assert(cjson.decode(body))
          assert.same(target.target, json.data[1].target)
          assert.same("HEALTHY", json.data[1].health)
          status = assert(client_send {
            method = "POST",
            path = target_path .. "/unhealthy"
          })
          assert.same(204, status)
          status, body = assert(client_send {
            method = "GET",
            path = "/upstreams/" .. upstream.id .. "/health"
          })
          assert.same(200, status)
          json = assert(cjson.decode(body))
          assert.same(target.target, json.data[1].target)
          assert.same("UNHEALTHY", json.data[1].health)
        end)
      end)
    end
  end)

  describe("/upstreams/{upstream}/targets/{target}", function()
    describe("DELETE", function()
      local target

      local upstream
      before_each(function()
        upstream = bp.upstreams:insert {}

        bp.targets:insert {
          target = "api-1:80",
          weight = 10,
          upstream = { id = upstream.id },
        }

        -- predefine the target to mock delete
        target = bp.targets:insert {
          target = "api-2:80",
          weight = 10,
          upstream = { id = upstream.id },
        }
      end)

      it("acts as a sugar method to POST a target with 0 weight (by target)", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/upstreams/" .. upstream.name .. "/targets/" .. target.target
        })
        assert.response(res).has.status(204)

        local targets = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream.name .. "/targets/all",
        })
        assert.response(targets).has.status(200)
        local json = assert.response(targets).has.jsonbody()
        assert.equal(3, #json.data)

        local active = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream.name .. "/targets",
        })
        assert.response(active).has.status(200)
        json = assert.response(active).has.jsonbody()
        assert.equal(1, #json.data)
        assert.equal("api-1:80", json.data[1].target)
      end)

      it("acts as a sugar method to POST a target with 0 weight (by id)", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/upstreams/" .. upstream.name .. "/targets/" .. target.id
        })
        assert.response(res).has.status(204)

        local targets = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream.name .. "/targets/all",
        })
        assert.response(targets).has.status(200)
        local json = assert.response(targets).has.jsonbody()
        assert.equal(3, #json.data)

        local active = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream.name .. "/targets",
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
