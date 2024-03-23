-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

describe("kong quit", function()
  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    helpers.clean_prefix()
    helpers.prepare_prefix()
  end)
  after_each(function()
    helpers.kill_all()
  end)
  lazy_teardown(function()
    helpers.clean_prefix()
  end)

  it("quit help", function()
    local _, stderr = helpers.kong_exec "quit --help"
    assert.not_equal("", stderr)
  end)
  it("quits gracefully", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path))
    assert(helpers.kong_exec("quit --prefix " .. helpers.test_conf.prefix))
  end)
  it("quit gracefully with --timeout option", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path))
    assert(helpers.kong_exec("quit --timeout 2 --prefix " .. helpers.test_conf.prefix))
  end)
  it("quit gracefully with --wait option", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path))
    ngx.update_time()
    local start = ngx.now()
    assert(helpers.kong_exec("quit --wait 2 --prefix " .. helpers.test_conf.prefix))
    ngx.update_time()
    local duration = ngx.now() - start
    assert.is.near(2, duration, 2.5)
  end)
end)
