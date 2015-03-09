local constants = require "kong.constants"
local stringy = require "stringy"
local utils = require "kong.tools.utils"
local fs = require "luarocks.fs"

describe("Constants", function()

  it("the version set in constants should match the one in the rockspec", function()
    local rockspec_path
    for _, filename in ipairs(fs.list_dir(".")) do
      if stringy.endswith(filename, "rockspec") then
        rockspec_path = filename
        break
      end
    end

    if not rockspec_path then
      error("Can't find the rockspec file")
    end

    local file_content = utils.read_file(rockspec_path)
    local res = file_content:match("\"+[0-9.-]+[a-z]*[0-9-]*\"+")
    local extracted_version = res:sub(2, res:len() - 1)
    assert.are.same(constants.VERSION, extracted_version)
  end)

end)
