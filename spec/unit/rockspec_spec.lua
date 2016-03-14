local stringy = require "stringy"
local IO = require "kong.tools.io"
local fs = require "luarocks.fs"

describe("Rockspec file", function()

  it("should include all the Lua modules", function()
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

    loadfile(rockspec_path)()

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

    local res = IO.os_execute("find . -type f -name *.lua", true)
    if not res or stringy.strip(res) == "" then
      error("Error executing the command")
    end

    local files = stringy.split(res, "\n")
    for _, v in ipairs(files) do
      local path = stringy.strip(v)
      if path ~= "" and stringy.startswith(path, "./kong") then
        if not is_in_rockspec(path) then
          error("Module "..path.." is not declared in rockspec")
        end
      end
    end
  end)

end)