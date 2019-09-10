local helpers = require "spec.helpers"

local function wait_for_pid()
  local pid
  helpers.wait_until(function()
    pid = helpers.file.read(helpers.test_conf.nginx_pid)
    return pid
  end)
  return pid
end

describe("kong restart", function()
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

  it("restart help", function()
    local _, stderr = helpers.kong_exec "restart --help"
    assert.not_equal("", stderr)
  end)
  it("restarts if not running", function()
    local ok, stderr, stdout = helpers.kong_exec("restart --conf " ..
                                                 helpers.test_conf_path)
    assert(ok, stderr)
    assert.matches("Kong started", stdout)
  end)
  it("restarts if already running from --conf", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path, {}))
    local nginx_pid = wait_for_pid()

    assert(helpers.kong_exec("restart --conf " .. helpers.test_conf_path, {}))
    local new_pid = wait_for_pid()
    assert.is_not.equal(new_pid, nginx_pid)
  end)
  it("restarts if already running from --prefix", function()
    local env = {
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
    }

    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path, env))
    local nginx_pid = wait_for_pid()

    assert(helpers.kong_exec("restart --prefix " .. helpers.test_conf.prefix, env))
    local new_pid = wait_for_pid()
    assert.is_not.equal(new_pid, nginx_pid)
  end)
  it("accepts a custom nginx template", function()
    local env = {
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
    }

    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path, env))
    wait_for_pid()

    assert(helpers.kong_exec("restart --prefix " .. helpers.test_conf.prefix
           .. " --nginx-conf spec/fixtures/custom_nginx.template", env))
    wait_for_pid()

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
