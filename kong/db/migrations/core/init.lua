local pl_path = require "pl.path"
local pl_dir = require "pl.dir"

local function get_files()
  -- find script path remember to strip off the starting @
  -- should be like: 'kong/db/migrations/core/init.lua' but
  -- detecting it dynamically for robustness
  local code_path = debug.getinfo(2, "S").source:sub(2)
  local path = pl_path.dirname(code_path)
  local this_filename = pl_path.basename(code_path)

  local files = pl_dir.getfiles(path)
  local orders = {}
  for i = #files, 1, -1 do -- traverse backwards as we're deleting entries
    local filename = pl_path.basename(files[i])
    if filename == this_filename or filename:sub(-4, -1) ~= ".lua" then
      -- this 'init.lua' file or any non-Lua files are not migration files
      table.remove(files, i)

    else
      -- grab the first sequence of digits as the order element
      local order = tonumber(select(3, filename:find("^(%d+)")) or "")
      if not order then
        error("migration file '" .. files[i] .. "' is lacking an order indicator")

      elseif orders[order] then
        error("migrations files '" .. orders[order] .. "' and '" ..
              files[i] .. "' have the same order indicator")

      else
        orders[order] = files[i]
        -- replace the entry with split name and order data
        files[i] = {
          filename = filename:sub(1, -5),  -- drop the '.lua' extension
          order = order
        }
      end
    end
  end

  table.sort(files, function(a, b) return a.order < b.order end)

  -- reduce table back to only filenames (but in proper order now)
  for i, entry in ipairs(files) do
    files[i] = entry.filename
  end

  return files
end

-- note: this cannot be a tail-call for debug.getinfo above to work
local files = get_files()

return files
