local helpers = require "spec.helpers"
local cjson = require "cjson"
local random_string = require("kong.tools.rand").random_string


local fmt = string.format

local function wait_for_spans(zipkin_client, expected_spans, service_name)
  helpers.wait_until(function()
    local received_spans = 0
    local res = zipkin_client:get("/api/v2/traces", {
      query = {
        limit = 1000,
        remoteServiceName = service_name,
      }
    })
    local data = assert.response(res).has.status(200)
    local all_spans = cjson.decode(data)
    for i = 1, #all_spans do
      received_spans = received_spans + #all_spans[i]
    end
    return received_spans == expected_spans
  end)
end


describe("queueing behavior", function()
  local max_batch_size = 10
  local service
  local zipkin_client
  local proxy_client

  lazy_setup(function()
    local bp = helpers.get_db_utils(nil, { "services", "routes", "plugins" })

    -- enable zipkin plugin globally pointing to mock server
    bp.plugins:insert({
      name = "zipkin",
      protocols = { "http" },
      config = {
        sample_ratio = 1,
        http_endpoint = fmt("http://%s:%d/api/v2/spans", helpers.zipkin_host, helpers.zipkin_port),
        static_tags = {
          { name = "static", value = "ok" },
        },
        default_header_type = "b3-single",
        phase_duration_flavor = "tags",
        queue = {
          max_batch_size = max_batch_size,
          max_coalescing_delay = 10,
        }
      }
    })

    service = bp.services:insert {
      name = string.lower("http-" .. random_string()),
    }

    -- kong (http) mock upstream
    bp.routes:insert({
      name = string.lower("route-" .. random_string()),
      service = service,
      hosts = { "http-route" },
      preserve_host = true,
      paths = { "/" },
    })

    helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      stream_listen = helpers.get_proxy_ip(false) .. ":19000",
    })

    proxy_client = helpers.proxy_client()
    zipkin_client = helpers.http_client(helpers.zipkin_host, helpers.zipkin_port)
  end)


  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    helpers.clean_logfile() -- prevent log assertions from poisoning each other.
  end)

  it("batches spans from multiple requests", function()
    local count = 10

    for _ = 1, count do
      local r = proxy_client:get("/", {
        headers = {
          ["x-b3-sampled"] = "1",
          host = "http-route",
          ["zipkin-tags"] = "foo=bar; baz=qux"
        },
      })
      assert.response(r).has.status(200)
    end
    wait_for_spans(zipkin_client, 3 * count, service.name)
    assert.logfile().has.line("zipkin batch size: " .. tostring(max_batch_size), true)
  end)
end)
