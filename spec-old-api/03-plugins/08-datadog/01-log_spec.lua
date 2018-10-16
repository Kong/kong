local helpers = require "spec.helpers"
local pl_file = require "pl.file"

describe("Plugin: datadog (log)", function()
  local client
  setup(function()
    local bp, db, dao = helpers.get_db_utils()

    local consumer1 = bp.consumers:insert {
      username = "foo",
      custom_id = "bar"
    }
    bp.keyauth_credentials:insert {
      key = "kong",
      consumer = { id = consumer1.id },
    }

    local api1 = assert(dao.apis:insert {
      name         = "dd1",
      hosts        = { "datadog1.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "key-auth",
      api = { id = api1.id }
    })
    local api2     = assert(dao.apis:insert {
      name         = "dd2",
      hosts        = { "datadog2.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    local api3     = assert(dao.apis:insert {
      name         = "dd3",
      hosts        = { "datadog3.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    local api4     = assert(dao.apis:insert {
      name         = "dd4",
      hosts        = { "datadog4.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "key-auth",
      api = { id = api4.id }
    })
    assert(db.plugins:insert {
      name   = "datadog",
      api = { id = api1.id },
      config = {
        host = "127.0.0.1",
        port = 9999,
      },
    })
    assert(db.plugins:insert {
      name   = "datadog",
      api = { id = api2.id },
      config = {
        host    = "127.0.0.1",
        port    = 9999,
        metrics = {
          {
            name        = "status_count",
            stat_type   = "counter",
            sample_rate = 1,
          },
          {
            name        = "request_count",
            stat_type   = "counter",
            sample_rate = 1,
          },
        },
      },
    })
    assert(db.plugins:insert {
      name   = "datadog",
      api = { id = api3.id },
      config = {
        host    = "127.0.0.1",
        port    = 9999,
        metrics = {
          {
            name        = "status_count",
            stat_type   = "counter",
            sample_rate = 1,
            tags        = {"T1:V1"},
          },
          {
            name        = "request_count",
            stat_type   = "counter",
            sample_rate = 1,
            tags        = {"T2:V2,T3:V3,T4"},
          },
          {
            name        = "latency",
            stat_type   = "gauge",
            sample_rate = 1,
            tags        = {"T2:V2:V3,T4"},
          },
        },
      },
    })
    assert(db.plugins:insert {
      name   = "datadog",
      api = { id = api4.id },
      config = {
        host   = "127.0.0.1",
        port   = 9999,
        prefix = "prefix",
      },
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    client = helpers.proxy_client()
  end)
  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("logs metrics over UDP", function()
    local thread = helpers.udp_server(9999, 12)

    local res = assert(client:send {
      method = "GET",
      path = "/status/200?apikey=kong",
      headers = {
        ["Host"] = "datadog1.com"
      }
    })
    assert.res_status(200, res)

    local ok, gauges = thread:join()
    assert.True(ok)
    assert.equal(12, #gauges)
    assert.contains("kong.dd1.request.count:1|c|#app:kong", gauges)
    assert.contains("kong.dd1.latency:%d+|ms|#app:kong", gauges, true)
    assert.contains("kong.dd1.request.size:%d+|ms|#app:kong", gauges, true)
    assert.contains("kong.dd1.request.status.200:1|c|#app:kong", gauges)
    assert.contains("kong.dd1.request.status.total:1|c|#app:kong", gauges)
    assert.contains("kong.dd1.response.size:%d+|ms|#app:kong", gauges, true)
    assert.contains("kong.dd1.upstream_latency:%d+|ms|#app:kong", gauges, true)
    assert.contains("kong.dd1.kong_latency:%d*|ms|#app:kong", gauges, true)
    assert.contains("kong.dd1.user.uniques:.*|s|#app:kong", gauges, true)
    assert.contains("kong.dd1.user.*.request.count:1|c|#app:kong", gauges, true)
    assert.contains("kong.dd1.user.*.request.status.total:1|c|#app:kong",
                    gauges, true)
    assert.contains("kong.dd1.user.*.request.status.200:1|c|#app:kong",
                    gauges, true)
  end)

  it("logs metrics over UDP with custome prefix", function()
    local thread = helpers.udp_server(9999, 12)

    local res = assert(client:send {
      method = "GET",
      path = "/status/200?apikey=kong",
      headers = {
        ["Host"] = "datadog4.com"
      }
    })
    assert.res_status(200, res)

    local ok, gauges = thread:join()
    assert.True(ok)
    assert.equal(12, #gauges)
    assert.contains("prefix.dd4.request.count:1|c|#app:kong",gauges)
    assert.contains("prefix.dd4.latency:%d+|ms|#app:kong", gauges, true)
    assert.contains("prefix.dd4.request.size:%d+|ms|#app:kong", gauges, true)
    assert.contains("prefix.dd4.request.status.200:1|c|#app:kong", gauges)
    assert.contains("prefix.dd4.request.status.total:1|c|#app:kong", gauges)
    assert.contains("prefix.dd4.response.size:%d+|ms|#app:kong", gauges, true)
    assert.contains("prefix.dd4.upstream_latency:%d+|ms|#app:kong", gauges, true)
    assert.contains("prefix.dd4.kong_latency:%d*|ms|#app:kong", gauges, true)
    assert.contains("prefix.dd4.user.uniques:.*|s|#app:kong", gauges, true)
    assert.contains("prefix.dd4.user.*.request.count:1|c|#app:kong",
                    gauges, true)
    assert.contains("prefix.dd4.user.*.request.status.total:1|c|#app:kong",
                    gauges, true)
    assert.contains("prefix.dd4.user.*.request.status.200:1|c|#app:kong",
                    gauges, true)
  end)

  it("logs only given metrics", function()
    local thread = helpers.udp_server(9999, 3)

    local res = assert(client:send {
      method = "GET",
      path = "/status/200",
      headers = {
        ["Host"] = "datadog2.com"
      }
    })
    assert.res_status(200, res)

    local ok, gauges = thread:join()
    assert.True(ok)
    assert.equal(3, #gauges)
    assert.contains("kong.dd2.request.count:1|c", gauges)
    assert.contains("kong.dd2.request.status.200:1|c", gauges)
    assert.contains("kong.dd2.request.status.total:1|c", gauges)
  end)

  it("logs metrics with tags", function()
    local thread = helpers.udp_server(9999, 4)

    local res = assert(client:send {
      method = "GET",
      path = "/status/200",
      headers = {
        ["Host"] = "datadog3.com"
      }
    })
    assert.res_status(200, res)

    local ok, gauges = thread:join()
    assert.True(ok)
    assert.contains("kong.dd3.request.count:1|c|#T2:V2,T3:V3,T4", gauges)
    assert.contains("kong.dd3.request.status.200:1|c|#T1:V1", gauges)
    assert.contains("kong.dd3.request.status.total:1|c|#T1:V1", gauges)
    assert.contains("kong.dd3.latency:%d+|g|#T2:V2:V3,T4", gauges, true)
  end)

  it("should not return a runtime error (regression)", function()
    local thread = helpers.udp_server(9999, 1, 1)

    local res = assert(client:send {
      method = "GET",
      path = "/NonMatch",
      headers = {
        ["Host"] = "fakedns.com"
      }
    })

    assert.res_status(404, res)

    local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
    assert.not_matches("attempt to index field 'api' (a nil value)", err_log, nil, true)
    thread:join()
  end)
end)
