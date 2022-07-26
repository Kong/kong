-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

_G.kong = {
  version = "3.0.0",
  configuration = {},
}

local negotiation = require("kong.clustering.services.negotiation")

local negotiate_services = negotiation.negotiate_services
local split_services = negotiation.split_services
local set_serivces = negotiation.__test_set_serivces

describe("kong.clustering.services.negotiation", function()
  it("exact match", function()
    set_serivces {
      extra_service = {
        { version = "v1", description = "test service" },
      },

      test = {
        { version = "v1", description = "test service" },
      },

      test2 = {
        { version = "v3", description = "test service2" },
      },
    }

    local result = negotiate_services {
      {
        name = "test",
        versions = {
          "v1",
        }
      },
      {
        name = "test2",
        versions = {
          "v3",
        }
      },
    }

    assert.same({
      {
        name = "test",
        negotiated_version = {
          description = "test service",
          version = "v1",
        },
      },
      {
        name = "test2",
        negotiated_version = {
          description = "test service2",
          version = "v3",
        },
      },
    }, result)
  end)


  it("list match (CP with preference)", function()
    set_serivces {
      extra_service = {
        { version = "v1", description = "test service" },
      },

      test = {
        { version = "v1", description = "test service" },
      },

      test2 = {
        { version = "v3", description = "test service2" },
        { version = "v4", description = "test service2" },
      },
    }

    local result = negotiate_services {
      {
        name = "test",
        versions = {
          "v1",
        }
      },
      {
        name = "test2",
        versions = {
          "v1", "v4", "v3",
        }
      },
    }

    assert.same({
      {
        name = "test",
        negotiated_version = {
          description = "test service",
          version = "v1",
        },
      },
      {
        name = "test2",
        negotiated_version = {
          description = "test service2",
          version = "v3",
        },
      },
    }, result)
  end)


  it("no match", function()
    set_serivces {
      extra_service = {
        { version = "v1", description = "test service" },
      },

      test = {
        { version = "v1", description = "test service" },
      },

      test2 = {
        { version = "v3", description = "test service2" },
        { version = "v4", description = "test service2" },
      },
    }

    local acc, rej = split_services(negotiate_services {
      {
        name = "test",
        versions = {
          "v1",
        }
      },
      {
        name = "test2",
        versions = {
          "v1", "v0",
        }
      },
      {
        name = "unknown",
        versions = {
          "v1", "v0", "v100"
        }
      },
    })

    assert.same({
      {
        {
          name = "test",
          message = "test service",
          version = "v1",
        },
      },
      {
        {
          name = "test2",
          message = "no valid version",
        },
        {
          name = "unknown",
          message = "unknown service",
        },
      },
    }, { acc, rej, })
  end)



  it("combined", function()
    set_serivces {
      extra_service = {
        { version = "v1", description = "test service" },
      },

      test = {
        { version = "v1", description = "test service" },
      },

      test2 = {
        { version = "v3", description = "test service2" },
        { version = "v4", description = "test service2" },
        { version = "v5", description = "test service2" },
      },
    }

    local acc, rej = split_services(negotiate_services {
      {
        name = "test",
        versions = {
          "v2",
        }
      },
      {
        name = "test2",
        versions = {
          "v1", "v0",
          "v3", "v4",
        }
      },
      {
        name = "unknown",
        versions = {
          "v1", "v0", "v100"
        }
      },
    })

    assert.same({
      {
        {
          message = "test service2",
          name = "test2",
          version = "v3"
        },
      }, {
        {
          message = "no valid version",
          name = "test"
        }, {
          message = "unknown service",
          name = "unknown"
        },
      }, },
      { acc, rej, })
  end)
end)
