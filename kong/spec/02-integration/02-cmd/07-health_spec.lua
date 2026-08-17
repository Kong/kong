local helpers = require "spec.helpers"

local function run_health(script, params)
  local cmd = script .. " " .. params
  if script == "health" then
    return helpers.kong_exec(cmd)
  end
  return helpers.execute(cmd)
end


for _, health_cmd in ipairs({"health", "bin/kong-health"}) do
  describe("kong health-check: " .. health_cmd, function()
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

    it("health help", function()
      local _, stderr = run_health(health_cmd, "--help")
      assert.not_equal("", stderr)
    end)
    it("succeeds when Kong is running with custom --prefix", function()
      assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path))

      local _, _, stdout = assert(run_health(health_cmd,  "--prefix " .. helpers.test_conf.prefix))

      if health_cmd == "health" then
        assert.matches("nginx%.-running", stdout)
      end
      assert.matches("Kong is healthy at " .. helpers.test_conf.prefix, stdout, nil, true)
    end)
    it("fails when Kong is not running", function()
      local ok, stderr = run_health(health_cmd, "--prefix " .. helpers.test_conf.prefix)
      assert.False(ok)
      assert.matches("Kong is not running at " .. helpers.test_conf.prefix, stderr, nil, true)
    end)

    describe("errors", function()
      it("errors on inexisting prefix", function()
        local ok, stderr = run_health(health_cmd, "--prefix inexistant")
        assert.False(ok)
        assert.matches("no such prefix: ", stderr, nil, true)
      end)
    end)
  end)
end
