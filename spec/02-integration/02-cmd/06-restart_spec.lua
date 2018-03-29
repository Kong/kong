local helpers = require "spec.helpers"

describe("kong restart", function()
  setup(function()
    assert(helpers.dao:run_migrations())
    helpers.prepare_prefix()
  end)
  teardown(function()
    helpers.clean_prefix()
  end)
  after_each(function()
    helpers.kill_all()
  end)

  it("restart help", function()
    local _, stderr = helpers.kong_exec "restart --help"
    assert.not_equal("", stderr)
  end)
  it("restarts if not running", function()
    assert(helpers.kong_exec("restart --conf " .. helpers.test_conf_path))
  end)
  it("restarts if already running from --conf", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path, {}))
    ngx.sleep(2)
    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid))

    assert(helpers.kong_exec("restart --conf " .. helpers.test_conf_path, {}))
    ngx.sleep(2)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.nginx_pid)), nginx_pid)
  end)
  it("restarts if already running from --prefix", function()
    local env = {
      pg_database = helpers.test_conf.pg_database
    }

    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path, env))
    ngx.sleep(2)
    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid))

    assert(helpers.kong_exec("restart --prefix " .. helpers.test_conf.prefix, env))
    ngx.sleep(2)
    assert.is_not.equal(assert(helpers.file.read(helpers.test_conf.nginx_pid)), nginx_pid)
  end)
  it("accepts a custom nginx template", function()
    local env = {
      pg_database = helpers.test_conf.pg_database
    }

    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path, env))
    ngx.sleep(2)

    assert(helpers.kong_exec("restart --prefix " .. helpers.test_conf.prefix
           .. " --nginx-conf spec/fixtures/custom_nginx.template", env))
    ngx.sleep(2)

    -- new server
    local client = helpers.http_client(helpers.mock_upstream_host,
                                       helpers.mock_upstream_port,
                                       5000)
    local res = assert(client:send {
      path = "/get",
    })
    assert.res_status(200, res)
    client:close()
  end)
  it("restarts with default configuration and prefix", function()
    -- don't want to force migrations to be run on default
    -- keyspace/database
    local env = {
      prefix = helpers.test_conf.prefix,
      database = helpers.test_conf.database,
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
      dns_resolver = ""
    }

    assert(helpers.kong_exec("start", env))
    assert(helpers.kong_exec("restart", env))
  end)
end)
