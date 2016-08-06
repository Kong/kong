local helpers = require "spec.helpers"

describe("kong reload", function()
  setup(function()
    helpers.prepare_prefix()
  end)
  teardown(function()
    helpers.clean_prefix()
  end)
  after_each(function()
    helpers.kill_all()
  end)

  it("send a HUP signal to a running Nginx master process", function()
    assert(helpers.start_kong())
    local nginx_pid = helpers.file.read(helpers.test_conf.nginx_pid)

    -- kong_exec uses test conf too, so same prefix
    assert(helpers.kong_exec("reload --prefix "..helpers.test_conf.prefix))

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(helpers.test_conf.nginx_pid))
  end)
  it("reloads from a --conf argument", function()
    assert(helpers.start_kong {
      proxy_listen = "0.0.0.0:9002"
    })

    -- http_client errors out if cannot connect
    local client = helpers.http_client("0.0.0.0", 9002, 5000)
    client:close()

    ngx.sleep(1)

    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid),
                             "no nginx master PID")

    assert(helpers.kong_exec("reload --conf "..helpers.test_conf_path, {
      proxy_listen = "0.0.0.0:9000"
    }))

    ngx.sleep(1)

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(helpers.test_conf.nginx_pid))

    -- new proxy port
    client = helpers.http_client("0.0.0.0", 9000, 5000)
    client:close()
  end)

  describe("errors", function()
    it("complains about missing PID if not already running", function()
      local ok, err = helpers.kong_exec("reload --prefix "..helpers.test_conf.prefix)
      assert.False(ok)
      assert.matches("Error: could not get Nginx pid (is Nginx running in this prefix?)", err, nil, true)
    end)
  end)
end)
