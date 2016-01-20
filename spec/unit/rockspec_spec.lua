local stringy = require "stringy"
local IO = require "kong.tools.io"
local fs = require "luarocks.fs"

-- Function that checks if the path has been imported as a module
local is_in_rockspec = function(path)
  if stringy.startswith(path, "./") then
    path = string.sub(path, 3)
  end
  local found = false
  for _, v in pairs(build.modules) do
    if v == path then
      found = true
      break
    end
  end
  return found
end

describe("Rockspec", function()
  local rockspec_path, files

  setup(function()
    for _, filename in ipairs(fs.list_dir(".")) do
      if stringy.endswith(filename, "rockspec") then
        rockspec_path = filename
        break
      end
    end
    if not rockspec_path then
      error("Can't find the rockspec file")
    end

    loadfile(rockspec_path)()

    local res = IO.os_execute("find . -type f -name *.lua", true)
    if not res or stringy.strip(res) == "" then
      error("Error executing the command")
    end

    files = stringy.split(res, "\n")
  end)

  describe("modules", function()
    for _, v in ipairs(files) do
      it("should include "..v, function()
        local path = stringy.strip(v)
        if path ~= "" and stringy.startswith(path, "./kong") then
          assert.True(is_in_rockspec(path))
        end
      end)
    end
  end)
end)
