-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

describe("kong check", function()
  it("validates a conf", function()
    local _, _, stdout = assert(helpers.kong_exec("check " .. helpers.test_conf_path))
    assert.matches("configuration at .- is valid", stdout)
  end)
  it("reports invalid conf", function()
    local _, stderr = helpers.kong_exec("check spec/fixtures/invalid.conf")
    assert.matches("[error] cassandra_repl_strategy has", stderr, nil, true)
  end)
  it("doesn't like invalid files", function()
    local _, stderr = helpers.kong_exec("check inexistent.conf")
    assert.matches("[error] no file at: inexistent.conf", stderr, nil, true)
  end)
end)
