local helpers = require "spec.helpers"
local UDP_PORT = 20000


describe("Statsd Plugin", function()

  local client

  setup(function()
    helpers.dao:truncate_tables()
    assert(helpers.prepare_prefix())

    local api1 = assert(helpers.dao.apis:insert {
        request_host = "logging1.com", 
        upstream_url = "http://mockbin.com"
      })
    local api2 = assert(helpers.dao.apis:insert {
        request_host = "logging2.com", 
        upstream_url = "http://mockbin.com"
      })
    local api3 = assert(helpers.dao.apis:insert {
        request_host = "logging3.com", 
        upstream_url = "http://mockbin.com"
      })
    local api4 = assert(helpers.dao.apis:insert {
        request_host = "logging4.com", 
        upstream_url = "http://mockbin.com"
      })
    local api5 = assert(helpers.dao.apis:insert {
        request_host = "logging5.com", 
        upstream_url = "http://mockbin.com"
      })
    local api6 = assert(helpers.dao.apis:insert {
        request_host = "logging6.com", 
        upstream_url = "http://mockbin.com"
      })

    -- plugin 1
    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "statsd", 
      config = { 
        host = "127.0.0.1", 
        port = UDP_PORT, 
        metrics = {"request_count"}
      }
    })

    -- plugin 2
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "statsd", 
      config = { 
        host = "127.0.0.1", 
        port = UDP_PORT, 
        metrics = {"latency"}
      }
    })

    -- plugin 3
    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name = "statsd", 
      config = { 
        host = "127.0.0.1", 
        port = UDP_PORT, 
        metrics = {"status_count"}
      }
    })

    -- plugin 4
    assert(helpers.dao.plugins:insert {
      api_id = api4.id,
      name = "statsd", 
      config = { 
        host = "127.0.0.1", 
        port = UDP_PORT, 
        metrics = {"request_size"}
      }
    })

    -- plugin 5
    assert(helpers.dao.plugins:insert {
      api_id = api5.id,
      name = "statsd", 
      config = { 
        host = "127.0.0.1", 
        port = UDP_PORT, 
      }
    })

    -- plugin 6
    assert(helpers.dao.plugins:insert {
      api_id = api6.id,
      name = "statsd", 
      config = { 
        host = "127.0.0.1", 
        port = UDP_PORT, 
        metrics = {"response_size"}
      }
    })

    assert(helpers.start_kong())
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
  end)
  
  after_each(function()
    if client then client:close() end
  end)


  it("should log to UDP when metrics is request_count", function()
    local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

    local response = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging1.com"
        }
      })

    assert.has.res_status(200, response)

    local ok, res = thread:join()
    assert.True(ok)
    assert.truthy(res)
    assert.equal("kong.logging1_com.request.count:1|c", res)
  end)

  it("should log to UDP when metrics is status_count", function()
    local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

    local response = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging3.com"
        }
      })

    assert.has.res_status(200, response)

    local ok, res = thread:join()
    assert.True(ok)
    assert.truthy(res)
    assert.equal("kong.logging3_com.request.status.200:1|c", res)
  end)

  it("should log to UDP when metrics is request_size", function()
    local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

    local response = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging4.com"
        }
      })

    assert.has.res_status(200, response)

    local ok, res = thread:join()
    assert.True(ok)
    assert.truthy(res)
    local message = {}
    for w in string.gmatch(res,"kong.logging4_com.request.size:%d*|g") do
      table.insert(message, w)
    end
    assert.equal(1, #message)
  end)

  it("should log to UDP when metrics is latency", function()
    local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

    local response = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging2.com"
        }
      })

    assert.has.res_status(200, response)

    local ok, res = thread:join()
    assert.True(ok)
    assert.truthy(res)
    local message = {}
    for w in string.gmatch(res,"kong.logging2_com.latency:.*|g") do
      table.insert(message, w)
    end

    assert.equal(1, #message)
  end)

  it("should log to UDP when metrics is request_count", function()
    local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

    local response = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging5.com"
        }
      })

    assert.has.res_status(200, response)

    local ok, res = thread:join()
    assert.True(ok)
    assert.truthy(res)
    assert.equal("kong.logging5_com.request.count:1|c", res)
  end)

  it("should log to UDP when metrics is response_size", function()
    local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

    local response = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging6.com"
        }
      })

    assert.has.res_status(200, response)

    local ok, res = thread:join()
    assert.True(ok)
    assert.truthy(res)
    local message = {}
    for w in string.gmatch(res,"kong.logging6_com.response.size:%d*|g") do
      table.insert(message, w)
    end
    assert.equal(1, #message)
  end)
end)
