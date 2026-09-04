local http_mock = require "spec.helpers.http_mock"
local tapping = require "spec.helpers.http_mock.tapping"
local helpers = require "spec.helpers"

for _, tls in ipairs {true, false} do
  describe("http_mock with " .. (tls and "https" or "http") , function()
    local mock, client
    lazy_setup(function()
      mock = assert(http_mock.new(nil, {
        ["/"] = {
          access = [[
            ngx.print("hello world")
            ngx.exit(200)
          ]]
        },
        ["/404"] = {
          access = [[
            ngx.exit(404)
          ]]
        }
      }, {
        eventually_timeout = 0.5,
        tls = tls,
        gen_client = true,
        log_opts = {
          resp = true,
          resp_body = true
        }
      }))

      assert(mock:start())
    end)

    lazy_teardown(function()
      assert(mock:stop())
    end)

    before_each(function()
      client = mock:get_client()
    end)

    after_each(function()
      mock:clean()
      -- it's an known issue of http_client that if we do not close the client, the next request will error out
      client:close()
      mock.client = nil
    end)

    it("get #response", function()
      local res = assert(client:send({}))
      assert.response(res).has.status(200)
      assert.same(res:read_body(), "hello world")

      mock.eventually:has_response_satisfy(function(resp)
        assert.same(resp.body, "hello world")
      end)
    end)

    it("clean works", function()
      client:send({})
      client:send({})
      mock:clean()

      assert.error(function()
        mock.eventually:has_response_satisfy(function(resp)
          assert.same(resp.body, "hello world")
        end)
      end)
    end)

    it("clean works 2", function()
      mock.eventually:has_no_response_satisfy(function(resp)
        assert.same(resp.body, "hello world")
      end)
    end)

    it("mutiple request", function()
      assert.response(assert(client:send({}))).has.status(200)
      assert.response(assert(client:send({}))).has.status(200)
      assert.response(assert(client:send({}))).has.status(200)

      local records = mock:retrieve_mocking_logs()

      assert.equal(3, #records)
    end)

    it("request field", function()
      assert.response(assert(client:send({}))).has.status(200)

      mock.eventually:has_request_satisfy(function(req)
        assert.match("localhost:%d+", req.headers.Host)
        assert(req.headers["User-Agent"])
        req.headers["Host"] = nil
        req.headers["User-Agent"] = nil
        assert.same(req, {
          headers = {},
          method = "GET",
          uri = "/"
        })
      end)
    end)

    it("http_mock assertion", function()
      local function new_check(record, status)
        assert.same(record.resp.status, status)
        return "has a response with status " .. status
      end

      http_mock.register_assert("status", new_check)

      assert.response(assert(client:send({}))).has.status(200)
      assert.no_error(function()
        mock.eventually:has_status(200)
      end)

      assert.response(assert(client:send({}))).has.status(200)
      assert.error(function()
        mock.eventually:has_status(404)
      end)

      assert.response(assert(client:send({}))).has.status(200)
      assert.no_error(function()
        mock.eventually:has_no_status(404)
      end)

      assert.response(assert(client:send({}))).has.status(200)
      assert.error(function()
        mock.eventually:has_no_status(200)
      end)

      assert.response(assert(client:send({}))).has.status(200)
      assert.response(assert(client:send({}))).has.status(200)
      assert.no_error(function()
        mock.eventually:all_status(200)
      end)

      assert.response(assert(client:send({}))).has.status(200)
      assert.response(assert(client:send({
        path = "/404"
      }))).has.status(404)
      assert.error(function()
        mock.eventually:all_status(200)
      end)

      assert.response(assert(client:send({}))).has.status(200)
      assert.response(assert(client:send({
        path = "/404"
      }))).has.status(404)
      assert.no_error(function()
        mock.eventually:not_all_status(200)
      end)

      assert.response(assert(client:send({}))).has.status(200)
      assert.response(assert(client:send({}))).has.status(200)
      assert.error(function()
        mock.eventually:not_all_status(200)
      end)
    end)
  end)
end

describe("http_mock error catch", function()
  it("error catch", function()
    local mock = assert(http_mock.new(nil, [[
      error("hello world")
      ngx.exit(200)
    ]], {
      eventually_timeout = 0.5,
      tls = true,
      gen_client = true,
      log_opts = {
        resp = true,
        resp_body = true
      }
    }))

    finally(function()
      assert(mock:stop())
    end)

    assert(mock:start())
    local client = mock:get_client()
    local res = assert(client:send({}))
    assert.response(res).has.status(500)

    mock.eventually:has_error_satisfy(function(err)
      return assert.same("hello world", err[1][1])
    end)

    mock:clean()
    -- then we have no Error
    mock.eventually:has_no_error()
  end)
end)

describe("http_mock config", function()
  it("default mocking", function()
    local mock = assert(http_mock.new())
    assert(mock:start())
    finally(function()
      assert(mock:stop())
    end)
    local client = mock:get_client()
    local res = assert(client:send({}))
    assert.response(res).has.status(200)
    assert.same(res:read_body(), "ok")
  end)

  it("prefix", function()
    local mock_prefix = "servroot_mock1"
    local mock = assert(http_mock.new(nil, nil, {
      prefix = mock_prefix
    }))
    mock:start()
    finally(function()
      assert(mock:stop())
    end)


    helpers.wait_for_file_contents(mock_prefix .. "/logs/nginx.pid")
  end)

  it("init_by_lua_block inject", function ()
    local mock = assert(http_mock.new(nil, {
      ["/test"] = {
        access = [[
          ngx.print(test_value)
        ]],
      },
    }, {
      init = [[
        -- Test that the mock is injected
        test_value = "hello world"
      ]]
    }))
    mock:start()
    finally(function()
      assert(mock:stop())
    end)

    local client = mock:get_client()
    local res = assert(client:send({
      path = "/test"
    }))
    assert.response(res).has.status(200)
    assert.same(res:read_body(), "hello world")
  end)
end)

local function remove_volatile_headers(req_t)
  req_t.headers["Connection"] = nil
  req_t.headers["Host"] = nil
  req_t.headers["User-Agent"] = nil
  req_t.headers["Content-Length"] = nil
end

describe("http_mock.tapping", function()
  local tapped, tapped_port
  lazy_setup(function()
    tapped, tapped_port = http_mock.new(nil, nil, {
      log_opts = {
        req = true,
        req_body = true,
        req_body_large = true,
      }
    })
    tapped:start()
  end)
  lazy_teardown(function()
    tapped:stop(true)
  end)

  it("works", function()
    local tapping_mock = tapping.new(tapped_port)
    tapping_mock:start()
    finally(function()
      tapping_mock:stop(true)
    end)
    local client = tapping_mock:get_client()
    local request = {
      headers = {
        ["test"] = "mock_debug"
      },
      method = "POST",
      path = "/test!",
      body = "hello world",
    }
    local res = assert(client:send(request))
    assert.response(res).has.status(200)
    assert.same(res:read_body(), "ok")

    request.uri = request.path
    request.path = nil

    local record = tapping_mock:retrieve_mocking_logs()
    local req_t = assert(record[1].req)
    remove_volatile_headers(req_t)
    assert.same(request, req_t)

    local upstream_record = tapped:retrieve_mocking_logs()
    local upstream_req_t = assert(upstream_record[1].req)
    remove_volatile_headers(upstream_req_t)
    assert.same(request, upstream_req_t)
  end)
end)
