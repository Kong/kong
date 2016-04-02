local helpers = require "spec.helpers"

local function exec(args)
  args = args or ""
  return helpers.execute(helpers.bin_path.." "..args)
end

describe("Compile", function()
  it("compiles a Kong NGINX config", function()
    local ok, _, stdout, stderr = exec "compile"
    assert.True(ok)
    assert.equal("", stderr)
    assert.matches("init_by_lua_block", stdout)
    assert.matches("init_worker_by_lua_block", stdout)
    assert.matches("lua_code_cache", stdout)
    assert.matches("server_name kong", stdout)
    assert.matches("server_name kong_admin", stdout)
    assert.matches('config["pg_database"] = "kong"', stdout, nil, true)
  end)
  it("accepts a custom Kong conf", function()
    local ok, _, stdout, stderr = exec("compile --conf "..helpers.test_conf_path)
    assert.True(ok)
    assert.equal("", stderr)
    assert.matches('config["pg_database"] = "kong_tests"', stdout, nil, true)
  end)
end)
