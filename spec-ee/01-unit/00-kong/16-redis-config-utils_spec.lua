-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local redis_config_utils = require "kong.enterprise_edition.tools.redis.v2.config_utils"


describe("redis_config_utils", function()
  it("merge_ip_port", function()
    assert.same("127.0.0.5:1234", redis_config_utils.merge_ip_port({ip = "127.0.0.5", port = 1234 }))
  end)

  it("merge_host_port", function()
    assert.same("localhost.test:2345", redis_config_utils.merge_host_port({host = "localhost.test", port = 2345 }))
  end)

  it("split_ip_port", function()
    assert.same({ip = "127.0.0.5", port = 1234 }, redis_config_utils.split_ip_port("127.0.0.5:1234"))
  end)

  it("split_host_port", function()
    assert.same({host = "localhost.test", port = 2345 }, redis_config_utils.split_host_port("localhost.test:2345"))
  end)
end)
