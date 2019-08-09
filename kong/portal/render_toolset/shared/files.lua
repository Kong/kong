local ts_helpers = require "kong.portal.render_toolset.helpers"
-- local getters = require "kong.portal.render_toolset.getters"
local pl_stringx = require "pl.stringx"

local split = pl_stringx.split


local Files = {}


function Files:filter_by_path(arg)
  local function compare_cb(_, item)
    local is_valid = true
    local split_path = split(item.path, "/")
    local arg_path = split(arg, "/")

    for i, v in ipairs(arg_path) do
      if v ~= split_path[i] then
        is_valid = false
      end
    end

    return is_valid
  end

  return self
          :filter(compare_cb)
          :next()
end


function Files:filter_by_extension(arg)
  local function compare_cb(_, item)
    local route = ts_helpers.get_file_attrs_by_path(item.path)
    if route.extension == arg then
      return true
    end

    return false
  end

  return self
          :filter(compare_cb)
          :next()
end


function Files:filter_by_route(arg)
  local function compare_cb(_, item)
    local route = ts_helpers.get_route_from_path(item.path)
    local split_route = split(route, "/")
    local arg_path = split(arg, "/")
    local is_valid = true

    for i, v in ipairs(arg_path) do
      if v ~= split_route[i] then
        is_valid = false
      end
    end

    return is_valid
  end

  return self
          :filter(compare_cb)
          :next()
end


return Files
