-- This file requires all .lua files from kong's kong/ folder in order to compute the real coverage
-- since not all files are currently unit tested and the coverage is erroneous.

local path = require("path").new("/")
require "kong.tools.ngx_stub"

-- Stub DAO for lapis controllers
_G.dao = {}

local function retrieve_files(dir, options)
  local fs = require "luarocks.fs"
  local pattern = options.file_pattern
  local exclude_dir_patterns = options.exclude_dir_patterns

  if not pattern then pattern = "" end
  if not exclude_dir_patterns then exclude_dir_patterns = {} end
  local files = {}

  local function tree(dir)
    for _, file in ipairs(fs.list_dir(dir)) do
      local f = path:join(dir, file)
      if fs.is_dir(f) then
        local is_ignored = false
        for _, pattern in ipairs(exclude_dir_patterns) do
          if string.match(f, pattern) then
            is_ignored = true
            break
          end
        end
        if not is_ignored then
          tree(f)
        end
      elseif fs.is_file(f) and string.match(file, pattern) ~= nil then
        table.insert(files, f)
      end
    end
  end

  tree(dir)

  return files
end


local lua_sources = retrieve_files("./kong", { exclude_dir_patterns = {"cli", "vendor", "filelog", "reports"}, file_pattern = ".lua$" })

for _, source_link in ipairs(lua_sources) do
  dofile(source_link)
end
