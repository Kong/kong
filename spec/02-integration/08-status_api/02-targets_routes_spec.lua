local helpers = require "spec.helpers"
local cjson = require "cjson"

local function client_send(req)
  local client = helpers.http_client("127.0.0.1", 9500, 20000)
  local res = assert(client:send(req))
  local status, body = res.status, res:read_body()
  client:close()
  return status, body
end

local strategy = "off"

describe("Status API #" .. strategy, function()
  local bp
  local client

  local apis, healthcheck_apis = {}, {}

  local upstream, empty_upstream, healthcheck_upstream

  lazy_setup(function()
    local fixtures = {
      dns_mock = helpers.dns_mock.new()
    }
    fixtures.dns_mock:A {
      name = "custom_localhost",
      address = "127.0.0.1",
    }

    bp = helpers.get_db_utils(strategy, {
      "upstreams",
      "targets",
    })

    upstream = bp.upstreams:insert {}

    for i=1, 4 do
      apis[i] = bp.targets:insert {
        target = string.format("api-%d:80", i),
        weight = 10 * i,
        upstream = { id = upstream.id },
      }
    end

    healthcheck_upstream = bp.upstreams:insert {
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

    for i=1, 4 do
      healthcheck_apis[i] = bp.targets:insert {
        target = string.format("hc-api-%d:80", i),
        weight = 10 * i,
        upstream = { id = healthcheck_upstream.id },
      }
    end

    empty_upstream = bp.upstreams:insert {}

    assert(helpers.start_kong({
      status_listen = "127.0.0.1:9500",
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }, nil, nil, fixtures))
  end)

  lazy_teardown(function()
    assert(helpers.stop_kong())
  end)

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", 9500, 20000))
  end)

  after_each(function()
    if client then client:close() end
  end)

  describe("/upstreams/{upstream}/targets/", function()

    describe("POST", function()
      it("is not exposed", function()
        local res = assert(client:post(
          "/upstreams/" .. upstream.name .. "/targets/", {
          body = {
            target = "mashape.com",
          },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.response(res).has.status(405)
      end)
    end)

    describe("GET", function()
      it("shows all targets", function()
        for _, append in ipairs({ "", "/" }) do
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/" .. upstream.name .. "/targets" .. append,
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()

          -- we got three active targets for this upstream
          assert.equal(4, #json.data)

          local apis_targets = {}
          for _, t in ipairs(apis) do
            apis_targets[t.id] = t.target
          end

          local data_targets = {}
          for _, t in ipairs(json.data) do
            data_targets[t.id] = t.target
          end
          
          assert.same(apis_targets, data_targets)
        end
      end)

      describe("empty results", function()
        it("data property is an empty array", function()
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

      -- Performs tests similar to /upstreams/:upstream_id/targets,
      -- and checks for the "health" field of each target.
      -- @param targets the array of target data produced by add_targets
      -- @param n the expected number of targets in the response
      -- It is different from #targets because add_targets adds
      -- zero-weight targets as well.
      -- @param health the expected "health" response for all targets
      local function check_health_endpoint(targets, upstream, n, health)
        for _, append in ipairs({ "", "/" }) do
          local status, body = client_send({
            method = "GET",
            path = "/upstreams/" .. upstream.name .. "/health" .. append,
          })
          assert.same(200, status)
          local res = assert(cjson.decode(body))

          assert.equal(n, #res.data)

            
          local apis_targets = {}
          for _, t in ipairs(targets) do
            apis_targets[t.id] = t.target
          end

          local data_targets = {}
          for _, t in ipairs(res.data) do
            data_targets[t.id] = t.target
          end
          
          assert.same(apis_targets, data_targets)

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

      describe("with healthchecks off", function()
        it("returns HEALTHCHECKS_OFF for targets that resolve", function()
          check_health_endpoint(apis, upstream, 4, "HEALTHCHECKS_OFF")
        end)

      end)

      describe("with healthchecks on", function()

        it("returns DNS_ERROR if DNS cannot be resolved", function()

          check_health_endpoint(healthcheck_apis, healthcheck_upstream, 4, "DNS_ERROR")

        end)

        pending("returns HEALTHY if failure not detected", function()

          check_health_endpoint(healthcheck_apis, healthcheck_upstream, 4, "HEALTHY")

        end)

      end)
    end)
  end)

  describe("/upstreams/{upstream}/targets/all/", function()

    describe("GET", function()
      it("retrieves the first page", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream.name .. "/targets/all",
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal(4, #json.data)
      end)
      it("offset is a string", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream.name .. "/targets",
          query = {size = 2},
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_string(json.offset)
      end)
      it("paginates a set", function()
        local pages = {}
        local offset

        for i = 1, 3 do
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/" .. upstream.name .. "/targets/all",
            query = {size = 2, offset = offset}
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()

          if i < 3 then
            assert.equal(2, #json.data)
          else
            assert.equal(0, #json.data)
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
  
    describe("POST", function()

      it("is not exposed", function()
        local status, body
        status, body = assert(client_send {
          method = "POST",
          path = "/upstreams/" .. upstream.name .. "/targets/" .. apis[1].target .. "/unhealthy"
        })
        assert.same(404, status, body)
      end)
    end)
  end)

  describe("/upstreams/{upstream}/targets/{target}", function()
    local target = apis[1]

    describe("GET", function()

      it("returns target entity", function()
        local res = client:get("/upstreams/" .. upstream.name .. "/targets/" .. target.target)
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        json.tags = nil
        if json.upstream.id then
          json.upstream = json.upstream.id
        end
        assert.same(target, json)
      end)
    end)

    describe("PATCH", function()

      it("is not exposed", function()
        local res = client:patch("/upstreams/" .. upstream.name .. "/targets/" .. target.target, {
          body = {
            weight = 659,
          },
          headers = { ["Content-Type"] = "application/json" }
        })
        assert.response(res).has.status(405)
      end)
    end)

    describe("PUT", function()

      it("is not exposed", function()
        local res = client:put("/upstreams/" .. upstream.name .. "/targets/" .. target.target, {
          body = {
            target = target.target
          },
          headers = { ["Content-Type"] = "application/json" }
        })

        assert.response(res).has.status(405)
      end)

    end)

    describe("DELETE", function()

      it("is not exposed", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/upstreams/" .. upstream.name .. "/targets/" .. target.target
        })
        assert.response(res).has.status(405)
      end)
    end)
  end)
end)