local constants = require "kong.constants"
local stringy = require "stringy"
local IO = require "kong.tools.io"
local fs = require "luarocks.fs"

describe("Static files", function()
  describe("Constants", function()
    it("version set in constants should match the one in the rockspec", function()
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

      local file_content = IO.read_file(rockspec_path)
      local res = file_content:match("\"+[0-9.-]+[a-z]*[0-9-]*\"+")
      local extracted_version = res:sub(2, res:len() - 1)
      assert.are.same(constants.ROCK_VERSION, extracted_version)

      local dash = string.find(extracted_version, "-")
      assert.are.same(constants.VERSION, dash and extracted_version:sub(1, dash - 1) or extracted_version)
    end)

    it("accessing non-existing error code should throw an error", function()
      assert.has_no_error(function() local _ = constants.DATABASE_ERROR_TYPES.DATABASE end)
      assert.has_error(function() local _ = constants.DATABASE_ERROR_TYPES.ThIs_TyPe_DoEs_NoT_ExIsT end)
    end)
  end)
end)
