local luarocks = require "kong.cli.utils.luarocks"

describe("Luarocks", function()

  it("should get luarocks dir", function()
    local res = luarocks.get_dir()
    assert.truthy(res.name)
    assert.truthy(res.root)
  end)

  it("should get luarocks config dir", function()
    local res = luarocks.get_config_dir()
    assert.truthy(res)
  end)

  it("should get luarocks install dir", function()
    local res = luarocks.get_install_dir()
    assert.truthy(res)
  end)

end)
