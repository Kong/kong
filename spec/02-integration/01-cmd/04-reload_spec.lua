local helpers = require "spec.helpers"

describe("kong reload", function()
  setup(function()
    helpers.prepare_prefix()
  end)
  after_each(function()
    helpers.kill_all()
  end)

  it("sends a 'reload' signal to a running Nginx master process", function()
    assert(helpers.start_kong())
    helpers.wait_until_running(helpers.test_conf.nginx_pid)
    local original_nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid),
                                      "no nginx master PID")

    assert(helpers.kong_exec("reload --prefix "..helpers.test_conf.prefix))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)
    local reloaded_nginx_pid = helpers.file.read(helpers.test_conf.nginx_pid)

    -- same master PID
    assert.equal(original_nginx_pid, reloaded_nginx_pid)
  end)
  it("reloads from a --conf argument", function()
    assert(helpers.start_kong {
      proxy_listen = "0.0.0.0:9002"
    })
    helpers.wait_until_running(helpers.test_conf.nginx_pid)
    local original_nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid),
                                      "no nginx master PID")

    -- http_client throws an error if it cannot connect
    local client = helpers.http_client("0.0.0.0", 9002)
    client:close()

    assert(helpers.kong_exec("reload --conf "..helpers.test_conf_path, {
      proxy_listen = "0.0.0.0:9000"
    }))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)
    local reloaded_nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid),
                                      "no nginx master PID")

    -- same master PID
    assert.equal(original_nginx_pid, reloaded_nginx_pid)

    -- new proxy port
    client = helpers.http_client("0.0.0.0", 9000)
    client:close()
  end)
  it("accepts a custom nginx template and reloads Kong with it", function()
    assert(helpers.start_kong {
      proxy_listen = "0.0.0.0:9002"
    })
    helpers.wait_until_running(helpers.test_conf.nginx_pid)

    -- http_client throws an error if it cannot connect
    local client = helpers.http_client("0.0.0.0", 9002)
    client:close()

    assert(helpers.kong_exec(
      "reload --conf " .. helpers.test_conf_path .. " " ..
      "--nginx-conf spec/fixtures/custom_nginx.template"
    ))
    helpers.wait_until_running(helpers.test_conf.nginx_pid)

    -- new server in this nginx config
    client = helpers.http_client("0.0.0.0", 9999)
    local res = assert(client:send {
      path = "/custom_server_path"
    })
    assert.res_status(200, res)
    client:close()
  end)

  describe("errors", function()
    it("complains about missing PID if not already running", function()
      local ok, err = helpers.kong_exec("reload --prefix "..helpers.test_conf.prefix)
      assert.False(ok)
      assert.matches("Error: nginx not running in prefix: "..helpers.test_conf.prefix, err, nil, true)
    end)
  end)
end)
