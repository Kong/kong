require("kong.cli.utils.logger"):set_silent(true) -- Set silent for test

local spec_helper = require "spec.spec_helpers"
local configuration = require("kong.tools.config_loader").load(spec_helper.get_env().conf_file)
local serf = require("kong.cli.services.serf")(configuration)

describe("Serf", function()

  setup(function()
    serf:prepare()
  end)

  it("should start and stop", function()
    local ok, err = serf:start()
    assert.truthy(ok)
    assert.falsy(err)

    assert.truthy(serf:is_running())

    -- Trying again will fail
    local ok, err = serf:start()
    assert.falsy(ok)
    assert.truthy(err)
    assert.equal("serf is already running", err)

    serf:stop()

    assert.falsy(serf:is_running())
  end)

  it("should stop even when not running", function()
    assert.falsy(serf:is_running())
    serf:stop()
    assert.falsy(serf:is_running())
  end)

end)
