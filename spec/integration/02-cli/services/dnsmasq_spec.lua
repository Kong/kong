require("kong.cli.utils.logger"):set_silent(true) -- Set silent for test

local spec_helper = require "spec.spec_helpers"
local configuration = require "kong.tools.config_loader".load(spec_helper.get_env().conf_file)
local dnsmasq = require("kong.cli.services.dnsmasq")(configuration)

describe("Dnsmasq", function()

  setup(function()
    dnsmasq:prepare()
  end)

  it("should start and stop", function()
    local ok, err = dnsmasq:start()
    assert.truthy(ok)
    assert.falsy(err)

    assert.truthy(dnsmasq:is_running())

    -- Trying again will fail
    local ok, err = dnsmasq:start()
    assert.falsy(ok)
    assert.truthy(err)
    assert.equal("dnsmasq is already running", err)

    dnsmasq:stop()

    assert.falsy(dnsmasq:is_running())
  end)

  it("should stop even when not running", function()
    assert.falsy(dnsmasq:is_running())
    dnsmasq:stop()
    assert.falsy(dnsmasq:is_running())
  end)

end)
