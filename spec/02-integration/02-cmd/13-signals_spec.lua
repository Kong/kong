local helpers = require "spec.helpers"


describe("signals", function()
  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    helpers.prepare_prefix()
  end)

  after_each(function()
    helpers.stop_kong()
  end)

  it("can receive USR1", function()
    assert(helpers.start_kong())
    helpers.signal(nil, "-USR1")

    local conf = helpers.get_running_conf()
    local _, code = helpers.execute("grep -F '(SIGUSR1) received from' " ..
                                     conf.nginx_err_logs, true)
    assert.equal(0, code)
  end)

  it("can receive USR2 #flaky", function()
    assert(helpers.start_kong())

    local conf = helpers.get_running_conf()
    local oldpid_f = conf.nginx_pid .. ".oldbin"

    finally(function()
      ngx.sleep(0.5)
      helpers.signal(nil, "-TERM")
      helpers.signal(nil, "-TERM", oldpid_f)
    end)

    helpers.signal(nil, "-USR2")

    helpers.pwait_until(function()
      -- USR2 received
      assert.logfile().has.line('(SIGUSR2) received from', true)

      -- USR2 succeeded
      assert.logfile().has.no.line('execve() failed', true)
      assert.logfile().has.line('start new binary process', true)

      -- new master started successfully
      assert.logfile().has.no.line('exited with code 1', true)

      -- 2 master processes
      assert.is_true(helpers.path.isfile(oldpid_f))
    end)

    -- quit old master
    helpers.signal(nil, "-QUIT", oldpid_f)
    helpers.wait_pid(oldpid_f)
    assert.is_false(helpers.path.isfile(oldpid_f))

    helpers.pwait_until(function ()
      assert.is_true(helpers.path.isfile(conf.nginx_pid))
      -- new master running
      assert.equal(0, helpers.signal(nil, "-0"))
    end)
  end)
end)
