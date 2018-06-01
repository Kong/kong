local helpers = require "spec.helpers"
local cjson = require "cjson"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end

local function client_send(req)
  local client = helpers.admin_client()
  local res = client:send(req)
  local status, body = res.status, res:read_body()
  client:close()
  return status, body
end

local upstream_name = "my_upstream"

describe("Admin API", function()

  local client, upstream
  local weight_default, weight_min, weight_max = 100, 0, 1000
  local default_port = 8000

  local dns_hostsfile
  setup(function()
    -- Adding a name-based resolution that won't fail
    dns_hostsfile = os.tmpname()
    local fd = assert(io.open(dns_hostsfile, "w"))
    assert(fd:write("127.0.0.1 localhost custom_localhost\n"))
    fd:close()
  end)

  teardown(function()
    os.remove(dns_hostsfile)
  end)

  before_each(function()
    assert(helpers.dao:run_migrations())
    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      dns_hostsfile = dns_hostsfile,
    }))
    client = assert(helpers.admin_client())

    helpers.dao:truncate_tables()

    upstream = assert(helpers.dao.upstreams:insert {
      name = upstream_name,
      slots = 10,
    })
  end)

  after_each(function()
    if client then client:close() end
    helpers.stop_kong()
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
        local history = assert(helpers.dao.targets:find_all {
          upstream_id = upstream.id,
        })
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
            assert.same({ target = "target is required" }, json)

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
            assert.same({ message = "Invalid target; not a valid hostname or ip address" }, json)

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
            assert.same({ message = "weight must be from 0 to 1000" }, json)
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
        local upstream3 = assert(helpers.dao.upstreams:insert {
          name = upstream_name3,
        })

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
            apis[i] = assert(helpers.dao.targets:insert {
              target = "api-" .. tostring(i) .. ":80",
              weight = weights[i][j],
              upstream_id = upstream3.id
            })
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
          assert.equal(3, json.total)

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

  describe("/upstreams/{upstream}/health/", function()

    describe("GET", function()
      local name = "health.test"
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
              path = "/upstreams/" .. name .. "/targets",
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
            path = "/upstreams/" .. name .. "/health" .. append,
          })
          assert.same(200, status)
          local res = assert(cjson.decode(body))

          assert.same(node_id, res.node_id)
          assert.equal(n, #res.data)
          assert.equal(n, res.total)

          -- when multiple active targets are present, we only see the last one
          assert.equal(targets[4].id, res.data[1].id)

          -- validate the remaining returned targets
          -- note the backwards order, because we walked the targets backwards
          assert.equal(targets[3].target, res.data[2].target)
          assert.equal(targets[2].target, res.data[3].target)

          for i = 1, n do
            assert.equal(health, res.data[i].health)
          end
        end
      end

      before_each(function()
        local status = client_send({
          method = "POST",
          path = "/upstreams",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            name = name,
          }
        })
        assert.same(201, status)

        local status, body = client_send({
          method = "GET",
          path = "/",
        })
        assert.same(200, status)
        local res = assert(cjson.decode(body))
        assert.string(res.node_id)
        node_id = res.node_id
      end)

      describe("with healthchecks off", function()
        it("returns HEALTHCHECKS_OFF for targets that resolve", function()

          local targets = add_targets("custom_localhost:8%d")
          add_targets("127.0.0.1:8%d")

          check_health_endpoint(targets, 6, "HEALTHCHECKS_OFF")

        end)

        it("returns DNS_ERROR if DNS cannot be resolved", function()

          local targets = add_targets("bad-target-%d:80")

          check_health_endpoint(targets, 3, "DNS_ERROR")

        end)
      end)

      describe("with healthchecks on", function()
        before_each(function()
          local status = client_send({
            method = "PATCH",
            path = "/upstreams/" .. name,
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
            path = "/upstreams/" .. name,
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
      before_each(function()
        for i = 1, 10 do
          assert(helpers.dao.targets:insert {
            target = "api-" .. i .. ":80",
            weight = 100,
            upstream_id = upstream.id,
          })
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
        assert.equal(10, json.total)
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
          path = "/upstreams/" .. upstream_name .. "/targets/all",
          query = {foo = "bar"},
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same({ foo = "unknown field" }, json)
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
          assert(helpers.dao.upstreams:insert {
            name = upstream_name2,
            slots = 10,
          })
        end)

        it("data property is an empty array", function()
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/" .. upstream_name2 .. "/targets/all",
          })
          local body = assert.response(res).has.status(200)
          local json = cjson.decode(body)
          assert.same({ data = {}, total = 0 }, json)
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
        local my_upstream_name = "healthy.xyz"
        local my_target_name = localhost .. ":8192"
        local target_path = "/upstreams/" .. my_upstream_name
                            .. "/targets/" .. my_target_name

        before_each(function()
          local status, body = assert(client_send({
            method = "POST",
            path = "/upstreams/",
            headers = {["Content-Type"] = "application/json"},
            body = {
              name = my_upstream_name,
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
          assert.same(201, status)
          local json = assert(cjson.decode(body))

          status = assert(client_send({
            method = "POST",
            path = "/upstreams/" .. my_upstream_name .. "/targets",
            headers = {["Content-Type"] = "application/json"},
            body = {
              target = my_target_name,
              weight = 10,
              upstream_id = json.id,
            }
          }))
          assert.same(201, status)
        end)

        it("flips the target status from UNHEALTHY to HEALTHY", function()
          local status, body, json
          status = assert(client_send {
            method = "POST",
            path = target_path .. "/unhealthy"
          })
          assert.same(204, status)
          status, body = assert(client_send {
            method = "GET",
            path = "/upstreams/" .. my_upstream_name .. "/health"
          })
          assert.same(200, status)
          json = assert(cjson.decode(body))
          assert.same(my_target_name, json.data[1].target)
          assert.same("UNHEALTHY", json.data[1].health)
          status = assert(client_send {
            method = "POST",
            path = target_path .. "/healthy"
          })
          assert.same(204, status)
          status, body = assert(client_send {
            method = "GET",
            path = "/upstreams/" .. my_upstream_name .. "/health"
          })
          assert.same(200, status)
          json = assert(cjson.decode(body))
          assert.same(my_target_name, json.data[1].target)
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
            path = "/upstreams/" .. my_upstream_name .. "/health"
          })
          assert.same(200, status)
          json = assert(cjson.decode(body))
          assert.same(my_target_name, json.data[1].target)
          assert.same("HEALTHY", json.data[1].health)
          status = assert(client_send {
            method = "POST",
            path = target_path .. "/unhealthy"
          })
          assert.same(204, status)
          status, body = assert(client_send {
            method = "GET",
            path = "/upstreams/" .. my_upstream_name .. "/health"
          })
          assert.same(200, status)
          json = assert(cjson.decode(body))
          assert.same(my_target_name, json.data[1].target)
          assert.same("UNHEALTHY", json.data[1].health)
        end)
      end)
    end
  end)

  describe("/upstreams/{upstream}/targets/{target}", function()
    describe("DELETE", function()
      local target
      local upstream_name4 = "example4.com"

      before_each(function()
        local upstream4 = assert(helpers.dao.upstreams:insert {
          name = upstream_name4,
        })

        assert(helpers.dao.targets:insert {
          target = "api-1:80",
          weight = 10,
          upstream_id = upstream4.id,
        })

        -- predefine the target to mock delete
        target = assert(helpers.dao.targets:insert {
          target = "api-2:80",
          weight = 10,
          upstream_id = upstream4.id,
        })
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
        assert.equal(3, json.total)

        local active = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream_name4 .. "/targets",
        })
        assert.response(active).has.status(200)
        json = assert.response(active).has.jsonbody()
        assert.equal(1, #json.data)
        assert.equal(1, json.total)
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
        assert.equal(3, json.total)

        local active = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream_name4 .. "/targets",
        })
        assert.response(active).has.status(200)
        json = assert.response(active).has.jsonbody()
        assert.equal(1, #json.data)
        assert.equal(1, json.total)
        assert.equal("api-1:80", json.data[1].target)
      end)
    end)
  end)
end)
