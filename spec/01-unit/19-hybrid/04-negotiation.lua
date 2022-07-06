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
    })

    assert.same({
      { {
        name = "test",
        message = "test service",
        version = "v1",
      }, },
      { {
        name = "test2",
        message = "No valid version",
      }, },
    }, { acc, rej, })
  end)
end)
