local helpers = require "spec.helpers"

describe("kong reload", function()
  setup(function()
    helpers.kill_all()
    helpers.prepare_prefix()
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
    local pid_path = helpers.path.join(helpers.test_conf.prefix, "pids", "nginx.pid")
    local nginx_pid = helpers.file.read(pid_path)

    local ok, err = helpers.kong_exec("reload --prefix "..helpers.test_conf.prefix) -- kong_exec uses test conf too, so same prefix
    assert(ok, err)

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(pid_path))
  end)

  describe("errors", function()
    it("complains about missing PID if not already running", function()
      local ok, err = helpers.kong_exec("reload")
      assert.False(ok)
      assert.matches("Error: could not get Nginx pid (is Nginx running in this prefix?)", err, nil, true)
    end)
  end)
end)
