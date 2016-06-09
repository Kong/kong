local helpers = require "spec.helpers"

local KILL_ALL = "pkill nginx; pkill serf; pkill dnsmasq"

describe("kong reload", function()
  setup(function()
    helpers.execute(KILL_ALL)
    helpers.prepare_prefix()
  end)
  teardown(function()
    helpers.execute(KILL_ALL)
    helpers.clean_prefix()
  end)

  it("send a HUP signal to a running nginx master process", function()
    finally(function()
      helpers.execute(KILL_ALL)
    end)

    assert(helpers.start_kong())
    local pid_path = helpers.path.join(helpers.test_conf.prefix, "logs", "nginx.pid")
    local nginx_pid = helpers.file.read(pid_path)

    assert(helpers.kong_exec("reload")) -- kong_exec uses test conf too, so same prefix

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(pid_path))
  end)

  describe("errors", function()
    it("complains about missing PID if not already running", function()
      local ok, err = helpers.kong_exec("reload")
      assert.falsy(ok)
      assert.matches("Error: could not get Nginx pid (is Nginx running in this prefix?)", err, nil, true)
    end)
  end)
end)
