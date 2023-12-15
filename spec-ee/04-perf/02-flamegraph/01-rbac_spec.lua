-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local perf = require("spec.helpers.perf")
local split = require("pl.stringx").split
local utils = require("spec.helpers.perf.utils")
local shell = require "resty.shell"

perf.use_defaults()
perf.enable_charts(false)

local versions = {}

local env_versions = os.getenv("PERF_TEST_VERSIONS")
if env_versions then
  versions = split(env_versions, ",")
end

local LOAD_DURATION = 60

local wrk_script = [[
  function request()
    return wrk.format(nil, "/services", { ["Kong-admin-token"] = "kong_perf" })
  end
]]

shell.run("mkdir -p output", nil, 0)

for _, version in ipairs(versions) do
  describe("perf test for Kong " .. version .. " #admin_api #rbac", function()
    lazy_setup(function()
      local helpers = perf.setup_kong(version)

      local bp, db = helpers.get_db_utils()

      local user = assert(db.rbac_users:insert({
        name = "kong",
        user_token = "kong_perf",
      }))

      local role_id = assert(bp.rbac_roles:insert().id)

      assert(db.rbac_role_endpoints:insert({
        role = { id = role_id },
        workspace = "*",
        endpoint = "*",
        actions = 15,
        negative = false,
      }))

      assert(db.rbac_user_roles:insert({
        user = user,
        role = { id = role_id },
      }))
    end)

    before_each(function()
      perf.start_kong({
        nginx_worker_processes = 1,
        vitals = "off",
        enforce_rbac = "on",
        --kong configs
      })
    end)

    after_each(function()
      perf.stop_kong()
    end)

    lazy_teardown(function()
      perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)
    end)

    it("GET /services with super-admin", function()
      perf.start_stapxx("lj-lua-stacks.sxx", "-D MAXMAPENTRIES=1000000 --arg time=" .. LOAD_DURATION)

      perf.start_load({
        uri = perf.get_admin_uri(),
        connections = 10,
        threads = 5,
        duration = LOAD_DURATION,
        script = wrk_script,
      })

      ngx.sleep(LOAD_DURATION)

      local result = assert(perf.wait_result())

      print(("### Result for Kong %s:\n%s"):format(version, result))

      perf.generate_flamegraph(
        "output/" .. utils.get_test_output_filename() .. ".svg",
        "Flame graph for Kong " .. utils.get_test_descriptor()
      )

      perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")
    end)
  end)
end
