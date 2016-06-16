local helpers = require "spec.helpers"

local function exec(args)
  args = args or ""
  return helpers.execute(helpers.bin_path.." "..args)
end

describe("kong compile", function()
  it("compiles a Kong NGINX config", function()
    local ok, _, stdout, stderr = exec "compile"
    assert.equal("", stderr)
    assert.True(ok)
    assert.matches("init_by_lua_block", stdout)
    assert.matches("init_worker_by_lua_block", stdout)
    assert.matches("lua_code_cache on", stdout)
    assert.matches("server_name kong", stdout)
    assert.matches("server_name kong_admin", stdout)
    assert.matches("listen 0.0.0.0:8000", stdout, nil, true)
    assert.matches("listen 0.0.0.0:8001", stdout, nil, true)
    assert.matches("listen 0.0.0.0:8443 ssl", stdout, nil, true)
  end)
  it("accepts a custom Kong conf", function()
    local ok, _, stdout, stderr = exec("compile --conf "..helpers.test_conf_path)
    assert.equal("", stderr)
    assert.True(ok)
    assert.matches("listen 0.0.0.0:9000", stdout, nil, true)
    assert.matches("listen 0.0.0.0:9001", stdout, nil, true)
    assert.matches("listen 0.0.0.0:9443 ssl", stdout, nil, true)
  end)
end)
