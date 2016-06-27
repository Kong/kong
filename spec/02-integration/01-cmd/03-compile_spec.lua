local helpers = require "spec.helpers"

describe("kong compile", function()
  it("compiles a Kong NGINX config", function()
    local _, stderr, stdout = helpers.kong_exec "compile"
    assert.equal("", stderr)
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
    local _, stderr, stdout = helpers.kong_exec("compile --conf "..helpers.test_conf_path)
    assert.equal("", stderr)
    assert.matches("listen 0.0.0.0:9000", stdout, nil, true)
    assert.matches("listen 0.0.0.0:9001", stdout, nil, true)
    assert.matches("listen 0.0.0.0:9443 ssl", stdout, nil, true)
  end)
end)
