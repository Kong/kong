local helpers = require "spec.helpers"
local cjson = require "cjson"


local wait_for_file_contents = helpers.wait_for_file_contents

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

    local nginx_pid = wait_for_file_contents(helpers.test_conf.nginx_pid, 10)

    -- kong_exec uses test conf too, so same prefix
    assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix))

    local nginx_pid_after = wait_for_file_contents(helpers.test_conf.nginx_pid, 10)

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

    local workers = helpers.get_kong_workers()

    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid),
                             "no nginx master PID")

    assert(helpers.kong_exec("reload --conf spec/fixtures/reload.conf"))

    helpers.wait_until_no_common_workers(workers, 1)

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(helpers.test_conf.nginx_pid))

    -- new proxy port
    client = helpers.http_client("0.0.0.0", 9000, 5000)
    client:close()
  end)

  it("reloads from environment variables", function()
    assert(helpers.start_kong({
      proxy_listen = "0.0.0.0:9002"
    }, nil, true))

    -- http_client errors out if cannot connect
    local client = helpers.http_client("0.0.0.0", 9002, 5000)
    client:close()

    local workers = helpers.get_kong_workers()

    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid),
                             "no nginx master PID")

    assert(helpers.kong_exec("reload --conf " .. helpers.test_conf_path, {
      proxy_listen = "0.0.0.0:9000"
    }))

    helpers.wait_until_no_common_workers(workers, 1)

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

    local workers = helpers.get_kong_workers()

    -- http_client errors out if cannot connect
    local client = helpers.http_client("0.0.0.0", 9002, 5000)
    client:close()

    assert(helpers.kong_exec("reload --conf " .. helpers.test_conf_path
           .. " --nginx-conf spec/fixtures/custom_nginx.template"))


    helpers.wait_until_no_common_workers(workers, 1)

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
    local pids_1 = json.pids
    client:close()

    assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix))

    client = helpers.admin_client()
    local res = assert(client:get("/"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local pids_2 = json.pids
    client:close()

    assert.equal(pids_2.master, pids_1.master)

    for _, v in ipairs(pids_2.workers) do
      for _, v_old in ipairs(pids_1.workers) do
        assert.not_equal(v, v_old)
      end
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

    assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix))

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

      assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix, {
        declarative_config = yaml_file,
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

      assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix))

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

    it("preserves declarative config from memory even when kong was started with a declarative_config", function()
      local yaml_file = helpers.make_yaml_file [[
        _format_version: "1.1"
        services:
        - name: my-service-on-start
          url: http://127.0.0.1:15555
          routes:
          - name: example-route
            hosts:
            - example.test
      ]]

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
        declarative_config = yaml_file,
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

        return "my-service-on-start" == json.data[1].name
      end, 10)

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

      assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix))

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

      assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix, {
        declarative_config = yaml_file,
      }))

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

    if strategy ~= "off" then
      it("complains when database connection is invalid", function()
        assert(helpers.start_kong({
          proxy_listen = "0.0.0.0:9002"
        }, nil, true))

        local ok = helpers.kong_exec("reload --conf " .. helpers.test_conf_path, {
          database = strategy,
          pg_port = 1234,
        })

        assert.False(ok)
      end)
    end
  end)
end)

end


describe("key-auth plugin invalidation on dbless reload #off", function()
  it("(regression - issue 5705)", function()
    local admin_client
    local proxy_client
    local yaml_file = helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: my-service
        url: https://127.0.0.1:15556
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
        url: https://127.0.0.1:15556
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
    assert(helpers.reload_kong("off", "reload --prefix " .. helpers.test_conf.prefix, {
      declarative_config = yaml_file,
    }))

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

describe("Admin GUI config", function ()
  it("should be reloaded and invalidate kconfig.js cache", function()

    assert(helpers.start_kong({
      database = "off",
      admin_gui_listen = "127.0.0.1:9012",
      admin_gui_url = "http://test1.example.com"
    }))

    finally(function()
      helpers.stop_kong()
    end)

    local client = assert(helpers.admin_gui_client(nil, 9012))

    local res = assert(client:send {
      method = "GET",
      path = "/kconfig.js",
    })
    res = assert.res_status(200, res)
    assert.matches("'ADMIN_GUI_URL': 'http://test1.example.com'", res, nil, true)

    client:close()

    assert(helpers.reload_kong("off", "reload --conf " .. helpers.test_conf_path .. " --nginx-conf spec/fixtures/default_nginx.template", {
      database = "off",
      admin_gui_listen = "127.0.0.1:9012",
      admin_gui_url = "http://test2.example.com",
      admin_gui_path = "/manager",
    }))

    ngx.sleep(1)    -- to make sure older workers are gone

    client = assert(helpers.admin_gui_client(nil, 9012))
    res = assert(client:send {
      method = "GET",
      path = "/kconfig.js",
    })
    assert.res_status(404, res)

    res = assert(client:send {
      method = "GET",
      path = "/manager/kconfig.js",
    })
    res = assert.res_status(200, res)
    assert.matches("'ADMIN_GUI_URL': 'http://test2.example.com'", res, nil, true)
    client:close()
  end)
end)
