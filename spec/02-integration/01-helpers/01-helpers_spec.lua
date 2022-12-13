local helpers = require "spec.helpers"
local cjson   = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("helpers [#" .. strategy .. "]: assertions and modifiers", function()
    local proxy_client
    local env = {
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      })

      local service = bp.services:insert {
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      }

      bp.routes:insert {
        hosts     = { "mock_upstream" },
        protocols = { "http" },
        service   = service
      }

      assert(helpers.start_kong(env))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client(5000)
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    describe("http_client", function()
      it("encodes nested tables and arrays in Kong-compatible way when using form-urlencoded content-type", function()
        local tests = {
          { input = { names = { "alice", "bob", "casius" } },
            expected = { ["names[1]"] = "alice",
                         ["names[2]"] = "bob",
                         ["names[3]"] = "casius" } },

          { input = { headers = { location = { "here", "there", "everywhere" } } },
            expected = { ["headers.location[1]"] = "here",
                         ["headers.location[2]"] = "there",
                         ["headers.location[3]"] = "everywhere" } },

          { input = { ["hello world"] = "foo, bar" } ,
            expected = { ["hello world"] = "foo, bar" } },

          { input = { hash = { answer = 42 } },
            expected = { ["hash.answer"] = "42" } },

          { input = { hash_array = { arr = { "one", "two" } } },
            expected = { ["hash_array.arr[1]"] = "one",
                         ["hash_array.arr[2]"] = "two" } },

          { input = { array_hash = { { name = "peter" } } },
            expected = { ["array_hash[1].name"] = "peter" } },

          { input = { array_array = { { "x", "y" } } },
            expected = { ["array_array[1][1]"] = "x",
                         ["array_array[1][2]"] = "y" } },

          { input = { hybrid = { 1, 2, n = 3 } },
            expected = { ["hybrid[1]"] = "1",
                         ["hybrid[2]"] = "2",
                         ["hybrid.n"] = "3" } },
        }

        for i = 1, #tests do
          local r = proxy_client:get("/", {
            headers = {
              ["Content-type"] = "application/x-www-form-urlencoded",
              host             = "mock_upstream",
            },
            body = tests[i].input
          })
          local json = assert.response(r).has.jsonbody()
          assert.same(tests[i].expected, json.post_data.params)
        end
      end)

      describe("reopen", function()
        local client

        local function restart_kong()
          assert(helpers.restart_kong(env))

          -- ensure we can make at least one successful request after restarting
          helpers.wait_until(function()
            -- helpers.proxy_client() will throw an error if connect() fails,
            -- so we need to wrap the whole thing in pcall
            return pcall(function()
              local httpc = helpers.proxy_client(1000, 15555)
              local res = httpc:get("/")
              assert(res.status == 200)
              httpc:close()
            end)
          end)
        end

        before_each(function()
          client = helpers.proxy_client(1000, 15555)
        end)

        after_each(function()
          if client then
            client:close()
          end
        end)

        describe("(disabled)", function()
          it("is the default behavior", function()
            assert.falsy(client.reopen)
          end)

          it("does not retry requests when the connection is closed by the server", function()
            -- sanity
            local res, err = client:get("/")
            assert.res_status(200, res, err)

            restart_kong()

            res, err = client:send({ method = "GET", path = "/" })
            assert.is_nil(res, "expected request to fail")
            assert.equals("closed", err)
          end)

          it("does not retry requests when the connection is closed by the client", function()
            -- sanity
            local res, err = client:get("/")
            assert.res_status(200, res, err)

            client:close()

            res, err = client:send({ method = "GET", path = "/" })
            assert.is_nil(res, "expected request to fail")
            assert.equals("closed", err)
          end)
        end)

        describe("(enabled)", function()
          it("retries requests when a connection is closed by the server", function()
            client.reopen = true

            -- sanity
            local res, err = client:get("/")
            assert.res_status(200, res, err)

            restart_kong()

            res, err = client:get("/")
            assert.res_status(200, res, err)

            restart_kong()

            res, err = client:head("/")
            assert.res_status(200, res, err)
          end)

          it("retries requests when a connection is closed by the client", function()
            client.reopen = true

            -- sanity
            local res, err = client:get("/")
            assert.res_status(200, res, err)

            client:close()

            res, err = client:head("/")
            assert.res_status(200, res, err)
          end)

          it("does not retry unsafe requests", function()
            client.reopen = true

            -- sanity
            local res, err = client:get("/")
            assert.res_status(200, res, err)

            restart_kong()

            res, err = client:send({ method = "POST", path = "/" })
            assert.is_nil(res, "expected request to fail")
            assert.equals("closed", err)
          end)

          it("raises an exception when reconnection fails", function()
            client.reopen = true

            -- sanity
            local res, err = client:get("/")
            assert.res_status(200, res, err)

            helpers.stop_kong(nil, true, true)
            finally(function()
              helpers.start_kong(env, nil, true)
            end)

            assert.error_matches(function()
              -- using send() instead of get() because get() has an extra
              -- assert() call that might muddy the waters a little bit
              client:send({ method = "GET", path = "/" })
            end, "connection refused")
          end)
        end)
      end)
    end)

    describe("response modifier", function()
      it("fails with bad input", function()
        assert.error(function() assert.response().True(true) end)
        assert.error(function() assert.response(true).True(true) end)
        assert.error(function() assert.response("bad...").True(true) end)
      end)
      it("succeeds with a mock_upstream response", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.response(r).True(true)
      end)
      it("succeeds with a mock upstream response", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/anything",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.response(r).True(true)
      end)
    end)

    describe("request modifier", function()
      it("fails with bad input", function()
        assert.error(function() assert.request().True(true) end)
        assert.error(function() assert.request(true).True(true) end)
        assert.error(function() assert.request("bad... ").True(true) end)
      end)
      it("succeeds with a mock_upstream response", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.request(r).True(true)
      end)
      it("succeeds with a mock_upstream response", function()
        -- GET request
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.request(r).True(true)

        -- POST request
        local r = assert(proxy_client:send {
          method = "POST",
          path   = "/post",
          body   = {
            v1 = "v2",
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "www-form-urlencoded",
          },
        })
        assert.request(r).True(true)
      end)
      it("fails with a non mock_upstream response", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/headers",   -- this path is not supported, but should yield valid json for the test
          headers = {
            host = "127.0.0.1:15555",
          },
        })
        assert.error(function() assert.request(r).True(true) end)
      end)
    end)

    describe("contains assertion", function()
      it("verifies content properly", function()
        local arr = { "one", "three" }
        assert.equals(1, assert.contains("one", arr))
        assert.not_contains("two", arr)
        assert.equals(2, assert.contains("ee$", arr, true))
      end)
    end)

    describe("status assertion", function()
      it("succeeds with a response", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.status(200, r)
        local body = assert.response(r).has.status(200)
        assert(cjson.decode(body))

        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/404",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.response(r).has.status(404)
      end)
      it("fails with bad input", function()
        assert.error(function() assert.status(200, nil) end)
        assert.error(function() assert.status(200, {}) end)
      end)
    end)

    describe("jsonbody assertion", function()
      it("fails with explicit or no parameters", function()
        assert.error(function() assert.jsonbody({}) end)
        assert.error(function() assert.jsonbody() end)
      end)
      it("succeeds on a response object on /request", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host = "mock_upstream",
          },
        })
        local json = assert.response(r).has.jsonbody()
        assert(json.url:find(helpers.mock_upstream_host), "expected a mock_upstream response")
      end)
      it("succeeds on a mock_upstream request object on /request", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = { hello = "world" },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        local json = assert.request(r).has.jsonbody()
        assert.equals("world", json.params.hello)
      end)
      it("succeeds on a mock_upstream request object on /post", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          body    = { hello = "world" },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        local json = assert.request(r).has.jsonbody()
        assert.equals("world", json.params.hello)
      end)
    end)

    describe("header assertion", function()
      it("checks appropriate response headers", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = { hello = "world" },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        local v1 = assert.response(r).has.header("x-powered-by")
        local v2 = assert.response(r).has.header("X-POWERED-BY")
        assert.equals(v1, v2)
        assert.error(function() assert.response(r).has.header("does not exists") end)
      end)
      it("checks appropriate mock_upstream request headers", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host                   = "mock_upstream",
            ["just-a-test-header"] = "just-a-test-value"
          }
        })
        local v1 = assert.request(r).has.header("just-a-test-header")
        local v2 = assert.request(r).has.header("just-a-test-HEADER")
        assert.equals("just-a-test-value", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.response(r).has.header("does not exists") end)
      end)
      it("checks appropriate mock_upstream request headers", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host                   = "mock_upstream",
            ["just-a-test-header"] = "just-a-test-value"
          }
        })
        local v1 = assert.request(r).has.header("just-a-test-header")
        local v2 = assert.request(r).has.header("just-a-test-HEADER")
        assert.equals("just-a-test-value", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.response(r).has.header("does not exists") end)
      end)
    end)

    describe("queryParam assertion", function()
      it("checks appropriate mock_upstream query parameters", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            hello = "world",
          },
          headers = {
            host = "mock_upstream",
          },
        })
        local v1 = assert.request(r).has.queryparam("hello")
        local v2 = assert.request(r).has.queryparam("HELLO")
        assert.equals("world", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.response(r).has.queryparam("notHere") end)
      end)
      it("checks appropriate mock_upstream query parameters", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          query   = {
            hello = "world",
          },
          body    = {
            hello2 = "world2",
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        local v1 = assert.request(r).has.queryparam("hello")
        local v2 = assert.request(r).has.queryparam("HELLO")
        assert.equals("world", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.response(r).has.queryparam("notHere") end)
      end)
    end)

    describe("formparam assertion", function()
      it("checks appropriate mock_upstream url-encoded form parameters", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          },
        })
        local v1 = assert.request(r).has.formparam("hello")
        local v2 = assert.request(r).has.formparam("HELLO")
        assert.equals("world", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.request(r).has.queryparam("notHere") end)
      end)
      it("fails with mock_upstream non-url-encoded form data", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        assert.error(function() assert.request(r).has.formparam("hello") end)
      end)
      it("checks appropriate mock_upstream url-encoded form parameters", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          body    = {
            hello = "world",
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          },
        })
        local v1 = assert.request(r).has.formparam("hello")
        local v2 = assert.request(r).has.formparam("HELLO")
        assert.equals("world", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.request(r).has.queryparam("notHere") end)
      end)
      it("fails with mock_upstream non-url-encoded form parameters", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          body    = {
            hello = "world"
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        assert.error(function() assert.request(r).has.formparam("hello") end)
      end)
    end)


    describe("certificates,", function()

      local function get_cert(server_name)
        local _, _, stdout = assert(helpers.execute(
          string.format("echo 'GET /' | openssl s_client -connect 0.0.0.0:%d -servername %s",
                        helpers.get_proxy_port(true), server_name)
        ))
        return stdout
      end


      it("cn assertion with 2 parameters, positive success", function()
        local cert = get_cert("ssl1.com")
        assert.has.cn("localhost", cert)
      end)

      it("cn assertion with 2 parameters, positive failure", function()
        local cert = get_cert("ssl1.com")
        assert.has.error(function()
          assert.has.cn("some.other.host.org", cert)
        end)
      end)

      it("cn assertion with 2 parameters, negative success", function()
        local cert = get_cert("ssl1.com")
        assert.Not.cn("some.other.host.org", cert)
      end)

      it("cn assertion with 2 parameters, negative failure", function()
        local cert = get_cert("ssl1.com")
        assert.has.error(function()
          assert.Not.cn("localhost", cert)
        end)
      end)

      it("cn assertion with modifier and 1 parameter", function()
        local cert = get_cert("ssl1.com")
        assert.certificate(cert).has.cn("localhost")
      end)

      it("cn assertion with modifier and 2 parameters fails", function()
        local cert = get_cert("ssl1.com")
        assert.has.error(function()
          assert.certificate(cert).has.cn("localhost", cert)
        end)
      end)

    end)

  end)
end

describe("helpers: utilities", function()
  describe("get_version()", function()
    it("gets the version of Kong running", function()
      local meta = require 'kong.meta'
      local version = require 'version'
      assert.equal(version(meta._VERSION), helpers.get_version())
    end)
  end)

  describe("wait_until()", function()
    it("does not errors out if thing happens", function()
      assert.has_no_error(function()
        local i = 0
        helpers.wait_until(function()
          i = i + 1
          return i > 1
        end, 3)
      end)
    end)
    it("errors out after delay", function()
      assert.error_matches(function()
        helpers.wait_until(function()
          return false, "thing still not done"
        end, 1)
      end, "timeout: thing still not done")
    end)
    it("reports errors in test function", function()
      assert.error_matches(function()
        helpers.wait_until(function()
          assert.equal("foo", "bar")
        end, 1)
      end, "Expected objects to be equal.", nil, true)
    end)
  end)

  describe("wait_for_file_contents()", function()
    local function time()
      ngx.update_time()
      return ngx.now()
    end

    it("returns the file contents when the file is readable and non-empty", function()
      local fname = assert(helpers.path.tmpname())
      assert(helpers.file.write(fname, "test"))

      assert.equals("test", helpers.wait_for_file_contents(fname))
    end)

    it("waits for the file if need be", function()
      local fname = assert(helpers.path.tmpname())
      assert(os.remove(fname))

      local timeout = 1
      local delay = 0.25
      local start, duration

      local sema = require("ngx.semaphore").new()

      local ok, res
      ngx.timer.at(0, function()
        start = time()

        ok, res = pcall(helpers.wait_for_file_contents, fname, timeout)

        duration = time() - start
        sema:post(1)
      end)

      ngx.sleep(delay)
      assert(helpers.file.write(fname, "test"))

      assert.truthy(sema:wait(timeout),
                    "timed out waiting for timer to finish")

      assert.truthy(ok, "timer raised an error: " .. tostring(res))
      assert.equals("test", res)

      assert.truthy(duration <= timeout,
                    "expected to finish in <" .. tostring(timeout) .. "s" ..
                    " but took " .. tostring(duration) ..  "s")

      assert.truthy(duration > delay,
                    "expected to finish in >=" .. tostring(delay) .. "s" ..
                    " but took " .. tostring(duration) ..  "s")
    end)

    it("doesn't wait longer than the timeout in the failure case", function()
      local fname = assert(helpers.path.tmpname())

      local timeout = 1
      local start, duration

      local sema = require("ngx.semaphore").new()

      local ok, err
      ngx.timer.at(0, function()
        start = time()

        ok, err = pcall(helpers.wait_for_file_contents, fname, timeout)

        duration = time() - start
        sema:post(1)
      end)

      assert.truthy(sema:wait(timeout * 1.5),
                    "timed out waiting for timer to finish")

      assert.falsy(ok, "expected wait_for_file_contents to fail")
      assert.not_nil(err)

      local diff = math.abs(duration - timeout)
      assert.truthy(diff < 0.5,
                    "expected to finish in about " .. tostring(timeout) .. "s" ..
                    " but took " .. tostring(duration) ..  "s")
    end)


    it("raises an assertion error if the file does not exist", function()
      assert.error_matches(function()
        helpers.wait_for_file_contents("/i/do/not/exist", 0)
      end, "does not exist or is not readable")
    end)

    it("raises an assertion error if the file is empty", function()
      local fname = assert(helpers.path.tmpname())

      assert.error_matches(function()
        helpers.wait_for_file_contents(fname, 0)
      end, "exists but is empty")
    end)
  end)

  describe("clean_logfile()", function()
    it("truncates a file", function()
      local fname = assert(os.tmpname())
      assert(helpers.file.write(fname, "some data\nand some more data\n"))
      assert(helpers.path.getsize(fname) > 0)

      finally(function()
        os.remove(fname)
      end)

      helpers.clean_logfile(fname)
      assert(helpers.path.getsize(fname) == 0)
    end)

    it("truncates the test conf error.log file if no input is given", function()
      local log_dir = helpers.path.join(helpers.test_conf.prefix, "logs")
      if not helpers.path.exists(log_dir) then
        assert(helpers.dir.makepath(log_dir))
        finally(function()
          finally(function()
            helpers.dir.rmtree(log_dir)
          end)
        end)
      end

      local fname = helpers.path.join(log_dir, "error.log")
      assert(helpers.file.write(fname, "some data\nand some more data\n"))
      assert(helpers.path.getsize(fname) > 0)

      helpers.clean_logfile(fname)
      assert(helpers.path.getsize(fname) == 0)
    end)

    it("creates an empty file if one does not exist", function()
      local fname = assert(os.tmpname())
      assert(os.remove(fname))
      assert(not helpers.path.exists(fname))

      helpers.clean_logfile(fname)

      finally(function()
        os.remove(fname)
      end)

      assert(helpers.path.isfile(fname))
      assert(helpers.path.getsize(fname) == 0)
    end)


    it("doesn't raise an error if the parent directory does not exist", function()
      local fname = "/tmp/i-definitely/do-not-exist." .. ngx.worker.pid()
      assert(not helpers.path.exists(fname))

      assert.has_no_error(function()
        helpers.clean_logfile(fname)
      end)
    end)

    it("raises an error if the path is not a file", function()
      local path = os.tmpname()
      os.remove(path)
      assert(helpers.dir.makepath(path))
      assert(helpers.path.isdir(path))

      finally(function()
        helpers.dir.rmtree(path)
      end)

      assert.error_matches(function()
        helpers.clean_logfile(path)
      end, "Is a directory")
    end)
  end)
end)
