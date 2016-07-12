local helpers = require "spec.helpers"

describe("kong reload", function()
  setup(function()
    helpers.kill_all()
  end)
  teardown(function()
    helpers.kill_all()
    helpers.clean_prefix()
  end)

  it("send a HUP signal to a running Nginx master process", function()
    finally(function()
      helpers.kill_all()
    end)

    assert(helpers.start_kong())
    local nginx_pid = helpers.file.read(helpers.test_conf.nginx_pid)

    -- kong_exec uses test conf too, so same prefix
    assert(helpers.kong_exec("reload --prefix "..helpers.test_conf.prefix))

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(helpers.test_conf.nginx_pid))
  end)
  it("reloads from a --conf argument", function()
    finally(function()
      helpers.kill_all()
    end)

    assert(helpers.start_kong {
      proxy_listen = "0.0.0.0:9002"
    })
    local client = helpers.http_client("0.0.0.0", 9002, 5000)
    client:close()

    local nginx_pid = helpers.file.read(helpers.test_conf.nginx_pid)

    assert(helpers.kong_exec("reload --conf "..helpers.test_conf_path, {
      proxy_listen = "0.0.0.0:9000"
    }))

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(helpers.test_conf.nginx_pid))

    ngx.sleep(1)

    -- new proxy port
    client = helpers.http_client("0.0.0.0", 9000, 5000)
    client:close()
  end)

  describe("errors", function()
    it("complains about missing PID if not already running", function()
      local ok, err = helpers.kong_exec("reload")
      assert.False(ok)
      assert.matches("Error: could not get Nginx pid (is Nginx running in this prefix?)", err, nil, true)
    end)
  end)
end)
