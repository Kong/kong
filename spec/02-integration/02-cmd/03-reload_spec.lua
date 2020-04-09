local helpers = require "spec.helpers"
local cjson = require "cjson"


local function get_kong_workers()
  local workers
  helpers.wait_until(function()
    local pok, admin_client = pcall(helpers.admin_client)
    if not pok then
      return false
    end
    local res = admin_client:send {
      method = "GET",
      path = "/",
    }
    if not res or res.status ~= 200 then
      return false
    end
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    admin_client:close()
    workers = json.prng_seeds
    return true
  end, 10)
  return workers
end


local function assert_wait_call(fn, ...)
  local res
  local args = { ... }
  helpers.wait_until(function()
    res = fn(unpack(args))
    return res ~= nil
  end, 10)
  return res
end


local function wait_until_no_common_workers(workers, expected_total, strategy)
  if strategy == "cassandra" then
    ngx.sleep(0.5)
  end
  helpers.wait_until(function()
    local pok, admin_client = pcall(helpers.admin_client)
    if not pok then
      return false
    end
    local res = assert(admin_client:send {
      method = "GET",
      path = "/",
    })
    assert.res_status(200, res)
    local json = cjson.decode(assert.res_status(200, res))
    admin_client:close()

    local new_workers = json.prng_seeds
    local total = 0
    local common = 0
    for k, v in pairs(new_workers) do
      total = total + 1
      if workers[k] == v then
        common = common + 1
      end
    end
    return common == 0 and total == (expected_total or total)
  end)
end


local function kong_reload(strategy, ...)
  local workers = get_kong_workers()
  local ok, err = helpers.kong_exec(...)
  if ok then
    wait_until_no_common_workers(workers, nil, strategy)
  end
  return ok, err
end


for _, strategy in helpers.each_strategy() do

describe("kong reload #" .. strategy, function()
  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    helpers.prepare_prefix()
  end)
  lazy_teardown(function()
    helpers.clean_prefix()
  end)
  after_each(function()
    helpers.stop_kong(nil, true)
  end)

  it("send a 'reload' signal to a running Nginx master process", function()
    assert(helpers.start_kong())

    local nginx_pid = assert_wait_call(helpers.file.read, helpers.test_conf.nginx_pid)

    -- kong_exec uses test conf too, so same prefix
    assert(kong_reload(strategy, "reload --prefix " .. helpers.test_conf.prefix))

    local nginx_pid_after = assert_wait_call(helpers.file.read, helpers.test_conf.nginx_pid)

    -- same master PID
    assert.equal(nginx_pid, nginx_pid_after)
  end)

  it("reloads from a --conf argument", function()
    assert(helpers.start_kong({
      proxy_listen = "0.0.0.0:9002"
    }, nil, true))

    -- http_client errors out if cannot connect
    local client = helpers.http_client("0.0.0.0", 9002, 5000)
    client:close()

    local workers = get_kong_workers()

    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid),
                             "no nginx master PID")

    assert(helpers.kong_exec("reload --conf " .. helpers.test_conf_path, {
      proxy_listen = "0.0.0.0:9000"
    }))

    wait_until_no_common_workers(workers, 2)

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(helpers.test_conf.nginx_pid))

    -- new proxy port
    client = helpers.http_client("0.0.0.0", 9000, 5000)
    client:close()
  end)

  it("accepts a custom nginx template", function()
    assert(helpers.start_kong({
      proxy_listen = "0.0.0.0:9002"
    }, nil, true))

    local workers = get_kong_workers()

    -- http_client errors out if cannot connect
    local client = helpers.http_client("0.0.0.0", 9002, 5000)
    client:close()

    assert(helpers.kong_exec("reload --conf " .. helpers.test_conf_path
           .. " --nginx-conf spec/fixtures/custom_nginx.template"))


    wait_until_no_common_workers(workers, 2)

    -- new server
    client = helpers.http_client(helpers.mock_upstream_host,
                                 helpers.mock_upstream_port,
                                 5000)
    local res = assert(client:send {
      path = "/get",
    })
    assert.res_status(200, res)
    client:close()
  end)

  it("clears the 'kong' shm", function()
    local client

    assert(helpers.start_kong(nil, nil, true))

    finally(function()
      helpers.stop_kong(nil, true)
      if client then
        client:close()
      end
    end)

    client = helpers.admin_client()
    local res = assert(client:get("/"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local prng_seeds_1 = json.prng_seeds
    client:close()

    assert(kong_reload(strategy, "reload --prefix " .. helpers.test_conf.prefix))

    client = helpers.admin_client()
    local res = assert(client:get("/"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local prng_seeds_2 = json.prng_seeds
    client:close()

    for k in pairs(prng_seeds_1) do
      assert.is_nil(prng_seeds_2[k])
    end
  end)

  it("clears the 'kong' shm but preserves 'node_id'", function()
    local client

    assert(helpers.start_kong(nil, nil, true))

    finally(function()
      helpers.stop_kong(nil, true)
      if client then
        client:close()
      end
    end)

    client = helpers.admin_client()
    local res = assert(client:get("/"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local node_id_1 = json.node_id
    client:close()

    assert(kong_reload(strategy, "reload --prefix " .. helpers.test_conf.prefix))

    client = helpers.admin_client()
    local res = assert(client:get("/"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local node_id_2 = json.node_id
    client:close()

    assert.equal(node_id_1, node_id_2)
  end)

  if strategy == "off" then
    it("reloads the declarative_config from kong.conf", function()
      local yaml_file = helpers.make_yaml_file [[
        _format_version: "1.1"
        services:
        - name: my-service
          url: http://127.0.0.1:15555
          routes:
          - name: example-route
            hosts:
            - example.test
      ]]

      local pok, admin_client

      finally(function()
        os.remove(yaml_file)
        helpers.stop_kong(helpers.test_conf.prefix, true)
        if admin_client then
          admin_client:close()
        end
      end)

      assert(helpers.start_kong({
        database = "off",
        declarative_config = yaml_file,
        nginx_worker_processes = 1,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end

        local res = assert(admin_client:send {
          method = "GET",
          path = "/services",
        })
        assert.res_status(200, res)

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(1, #json.data)
        assert.same(ngx.null, json.next)

        admin_client:close()

        return "my-service" == json.data[1].name
      end, 10)

      -- rewrite YAML file
      helpers.make_yaml_file([[
        _format_version: "1.1"
        services:
        - name: mi-servicio
          url: http://127.0.0.1:15555
          routes:
          - name: example-route
            hosts:
            - example.test
      ]], yaml_file)

      assert(kong_reload(strategy, "reload --prefix " .. helpers.test_conf.prefix))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end
        local res = assert(admin_client:send {
          method = "GET",
          path = "/services",
        })
        assert.res_status(200, res)

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(1, #json.data)
        assert.same(ngx.null, json.next)
        admin_client:close()

        return "mi-servicio" == json.data[1].name
      end)
    end)

    it("preserves declarative config from memory when not using declarative_config from kong.conf", function()
      local pok, admin_client

      finally(function()
        helpers.stop_kong(helpers.test_conf.prefix, true)
        if admin_client then
          admin_client:close()
        end
      end)

      assert(helpers.start_kong({
        database = "off",
        nginx_worker_processes = 1,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end

        local res = assert(admin_client:send {
          method = "POST",
          path = "/config",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            _format_version = "1.1",
            services = {
              {
                name = "my-service",
                url = "http://127.0.0.1:15555",
              }
            }
          },
        }, 10)
        assert.res_status(201, res)

        admin_client:close()

        return true
      end)

      admin_client = assert(helpers.admin_client())

      assert(kong_reload(strategy, "reload --prefix " .. helpers.test_conf.prefix))

      admin_client = assert(helpers.admin_client())
      local res = assert(admin_client:send {
        method = "GET",
        path = "/services",
      })
      assert.res_status(200, res)

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(1, #json.data)
      assert.same(ngx.null, json.next)
      admin_client:close()

      return "my-service" == json.data[1].name
    end)

    it("change target loaded from declarative_config", function()
      local yaml_file = helpers.make_yaml_file [[
        _format_version: "1.1"
        services:
        - name: my-service
          url: http://127.0.0.1:15555
          routes:
          - name: example-route
            hosts:
            - example.test
        upstreams:
        - name: my-upstream
          targets:
          - target: 127.0.0.1:15555
            weight: 100
      ]]

      local pok, admin_client

      finally(function()
        os.remove(yaml_file)
        helpers.stop_kong(helpers.test_conf.prefix, true)
        if admin_client then
          admin_client:close()
        end
      end)

      assert(helpers.start_kong({
        database = "off",
        declarative_config = yaml_file,
        nginx_worker_processes = 1,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end

        local res = assert(admin_client:send {
          method = "GET",
          path = "/services",
        })
        assert.res_status(200, res)

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(1, #json.data)
        assert.same(ngx.null, json.next)

        admin_client:close()

        return "my-service" == json.data[1].name
      end, 10)

      -- rewrite YAML file
      helpers.make_yaml_file([[
        _format_version: "1.1"
        services:
        - name: my-service
          url: http://127.0.0.1:15555
          routes:
          - name: example-route
            hosts:
            - example.test
        upstreams:
        - name: my-upstream
          targets:
          - target: 127.0.0.1:15556
            weight: 100
      ]], yaml_file)

      assert(kong_reload(strategy, "reload --prefix " .. helpers.test_conf.prefix))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end
        local res = assert(admin_client:send {
          method = "GET",
          path = "/upstreams/my-upstream/health",
        })
        -- A 404 status may indicate that my-upstream is being recreated, so we
        -- should wait until timeout before failing this test
        if res.status == 404 then
          return false
        end

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        admin_client:close()

        return "127.0.0.1:15556" == json.data[1].target and
               "HEALTHCHECKS_OFF" == json.data[1].health
      end, 10)
    end)
  end

  describe("errors", function()
    it("complains about missing PID if not already running", function()
      helpers.prepare_prefix()

      local ok, err = helpers.kong_exec("reload --prefix " .. helpers.test_conf.prefix)
      assert.False(ok)
      assert.matches("Error: nginx not running in prefix: " .. helpers.test_conf.prefix, err, nil, true)
    end)
  end)
end)

end


describe("key-auth plugin invalidation on dbless reload", function()
  it("(regression - issue 5705)", function()
    local admin_client
    local proxy_client
    local yaml_file = helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: my-service
        url: https://example.com
        plugins:
        - name: key-auth
        routes:
        - name: my-route
          paths:
          - /
      consumers:
      - username: my-user
        keyauth_credentials:
        - key: my-key
    ]])

    finally(function()
      os.remove(yaml_file)
      helpers.stop_kong(helpers.test_conf.prefix, true)
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
    end)

    assert(helpers.start_kong({
      database = "off",
      declarative_config = yaml_file,
      nginx_worker_processes = 1,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    proxy_client = helpers.proxy_client()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/",
      headers = {
        ["apikey"] = "my-key"
      }
    })
    assert.res_status(200, res)

    res = assert(proxy_client:send {
      method  = "GET",
      path    = "/",
      headers = {
        ["apikey"] = "my-new-key"
      }
    })
    assert.res_status(401, res)

    proxy_client:close()

    admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "GET",
      path = "/key-auths",
    })
    assert.res_status(200, res)

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.same(1, #json.data)
    assert.same("my-key", json.data[1].key)
    admin_client:close()

    helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: my-service
        url: https://example.com
        plugins:
        - name: key-auth
        routes:
        - name: my-route
          paths:
          - /
      consumers:
      - username: my-user
        keyauth_credentials:
        - key: my-new-key
    ]], yaml_file)
    assert(kong_reload("off", "reload --prefix " .. helpers.test_conf.prefix))


    local res

    helpers.wait_until(function()
      admin_client = assert(helpers.admin_client())

      res = assert(admin_client:send {
        method = "GET",
        path = "/key-auths",
      })
      assert.res_status(200, res)
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      admin_client:close()
      assert.same(1, #json.data)
      return "my-new-key" == json.data[1].key
    end, 5)

    helpers.wait_until(function()
      proxy_client = helpers.proxy_client()
      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["apikey"] = "my-key"
        }
      })
      proxy_client:close()
      return res.status == 401
    end, 5)

    helpers.wait_until(function()
      proxy_client = helpers.proxy_client()
      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["apikey"] = "my-new-key"
        }
      })
      local body = res:read_body()
      proxy_client:close()
      return body ~= [[{"message":"Invalid authentication credentials"}]]
    end, 5)

    admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "GET",
      path = "/key-auths",
    })
    assert.res_status(200, res)

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.same(1, #json.data)
    assert.same("my-new-key", json.data[1].key)
    admin_client:close()

  end)
end)

