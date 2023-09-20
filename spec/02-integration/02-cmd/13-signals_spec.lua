local helpers = require "spec.helpers"
local process = require "kong.cmd.utils.process"


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
    helpers.signal(nil, process.SIG_USR1)

    assert.logfile().has.line('(SIGUSR1) received from', true)
  end)

  it("can receive USR2", function()
    assert(helpers.start_kong())

    local conf = helpers.get_running_conf()
    local pid_f = conf.nginx_pid
    local oldpid_f = conf.nginx_pid .. ".oldbin"

    finally(function()
      process.term(pid_f)
      process.term(oldpid_f)
    end)

    process.signal(pid_f, process.SIG_USR2)

    helpers.pwait_until(function()
      -- USR2 received
      assert.logfile().has.line('(SIGUSR2) received from', true)

      -- USR2 succeeded
      assert.logfile().has.no.line('execve() failed', true, 0)
      assert.logfile().has.line('start new binary process', true)

      -- new master started successfully
      assert.logfile().has.no.line('exited with code 1', true, 0)

      -- 2 master processes
      assert.truthy(process.pid_from_file(oldpid_f))
    end)

    -- quit old master
    process.quit(oldpid_f)
    helpers.wait_pid(oldpid_f)
    assert.is_false(helpers.path.isfile(oldpid_f))

    helpers.pwait_until(function ()
      assert.truthy(process.pid_from_file(pid_f))
      -- new master running
      assert.is_true(process.exists(pid_f))
    end)
  end)
end)
