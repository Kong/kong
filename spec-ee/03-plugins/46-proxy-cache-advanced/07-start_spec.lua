-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

describe("kong starts with proxy-cache-advanced plugin", function()

  setup(function()
    helpers.get_db_utils(nil, nil, {"proxy-cache-advanced"})
  end)

  after_each(function()
    assert.True(helpers.stop_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("starts with default conf", function()
    assert(helpers.start_kong({
      plugins = "bundled,proxy-cache-advanced",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

end)

describe("kong starts with proxy-cache-advanced plugin for stream listening", function()

  setup(function()
    helpers.get_db_utils(nil, nil, {"proxy-cache-advanced"})
  end)

  after_each(function()
    assert.True(helpers.stop_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("starts with stream listen", function()
    assert(helpers.start_kong({
      plugins = "bundled,proxy-cache-advanced",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      stream_listen = "0.0.0.0:5555",
    }))
  end)

end)
