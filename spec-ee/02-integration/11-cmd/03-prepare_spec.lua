-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local signals = require "kong.cmd.utils.nginx_signals"
local shell   = require "resty.shell"

local fmt = string.format

local TEST_PREFIX = "servroot_prepared_test"


describe("kong prepare", function()
  lazy_setup(function()
    pcall(helpers.dir.rmtree, TEST_PREFIX)
  end)

  after_each(function()
    pcall(helpers.dir.rmtree, TEST_PREFIX)
  end)

  it("prepare profiling directory with the right permission", function()
    local _, user  = shell.run("whoami", nil, 0)
    user = user:match([[([%w_\-]+)]])

    assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path, {
      prefix = TEST_PREFIX,
      nginx_user = user,
      }))
    assert.truthy(helpers.path.exists(TEST_PREFIX))

    local profiling_dir = helpers.path.join(TEST_PREFIX, "profiling")
    assert.truthy(helpers.path.exists(profiling_dir))

    local _, stdout = shell.run("stat -c '%U' " .. profiling_dir, nil, 0)
    assert.equal(user, stdout:sub(1, -2)) -- strip trailing \n
  end)
end)
