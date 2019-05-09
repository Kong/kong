local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("kong reload", function()
  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    helpers.prepare_prefix()
  end)
  lazy_teardown(function()
    helpers.clean_prefix()
  end)
  after_each(function()
    helpers.kill_all()
  end)

  it("send a 'reload' signal to a running Nginx master process", function()
    assert(helpers.start_kong())
    ngx.sleep(1)

    local nginx_pid = helpers.file.read(helpers.test_conf.nginx_pid)

    -- kong_exec uses test conf too, so same prefix
    assert(helpers.kong_exec("reload --prefix " .. helpers.test_conf.prefix))
    ngx.sleep(1)

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(helpers.test_conf.nginx_pid))
  end)
  it("reloads from a --conf argument", function()
    assert(helpers.start_kong({
      proxy_listen = "0.0.0.0:9002"
    }, nil, true))

    -- http_client errors out if cannot connect
    local client = helpers.http_client("0.0.0.0", 9002, 5000)
    client:close()

    ngx.sleep(1)

    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid),
                             "no nginx master PID")

    assert(helpers.kong_exec("reload --conf " .. helpers.test_conf_path, {
      proxy_listen = "0.0.0.0:9000"
    }))

    ngx.sleep(1)

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

    -- http_client errors out if cannot connect
    local client = helpers.http_client("0.0.0.0", 9002, 5000)
    client:close()

    ngx.sleep(1)

    assert(helpers.kong_exec("reload --conf " .. helpers.test_conf_path
           .. " --nginx-conf spec/fixtures/custom_nginx.template"))

    ngx.sleep(1)

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

    assert(helpers.kong_exec("reload --prefix " .. helpers.test_conf.prefix))
    ngx.sleep(1)

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

    assert(helpers.kong_exec("reload --prefix " .. helpers.test_conf.prefix))
    ngx.sleep(1)

    client = helpers.admin_client()
    local res = assert(client:get("/"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local node_id_2 = json.node_id
    client:close()

    assert.equal(node_id_1, node_id_2)
  end)

  describe("errors", function()
    it("complains about missing PID if not already running", function()
      helpers.prepare_prefix()

      local ok, err = helpers.kong_exec("reload --prefix " .. helpers.test_conf.prefix)
      assert.False(ok)
      assert.matches("Error: nginx not running in prefix: " .. helpers.test_conf.prefix, err, nil, true)
    end)
  end)
end)
