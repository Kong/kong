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

    -- USR2 received
    local _, code = helpers.execute("grep -F '(SIGUSR2) received from' " ..
                                     conf.nginx_err_logs, true)
    assert.equal(0, code)

    -- USR2 succeeded
    _, code = helpers.execute("grep -F 'execve() failed' " ..
                               conf.nginx_err_logs, true)
    assert.equal(1, code)

    _, code = helpers.execute("grep -F 'start new binary process' " ..
                               conf.nginx_err_logs, true)
    assert.equal(0, code)

    -- new master started successfully
    _, code = helpers.execute("grep -F 'exited with code 1' " ..
                               conf.nginx_err_logs, true)
    assert.equal(1, code)

    -- 2 master processes
    assert.is_true(helpers.path.isfile(oldpid_f))

    -- quit old master
    helpers.signal(nil, "-QUIT", oldpid_f)
    helpers.wait_pid(oldpid_f)
    assert.is_false(helpers.path.isfile(oldpid_f))
    ngx.sleep(0.5)

    -- new master running
    assert.is_true(helpers.path.isfile(conf.nginx_pid))
    assert.equal(0, helpers.signal(nil, "-0"))
  end)
end)
