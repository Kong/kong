local pl_stringx    = require "pl.stringx"
local getters       = require "kong.portal.render_toolset.getters"
local ts_helpers    = require "kong.portal.render_toolset.helpers"
local files         = require "kong.portal.render_toolset.shared.files"
local portal_urls   = require "kong.portal.render_toolset.portal.urls"
local portal_config = require "kong.portal.render_toolset.portal.config"


local Portal = {}


function Portal:specs()
  local ctx = getters.select_all_files()

  local function compare_cb(_, item)
    local path_attrs = ts_helpers.get_file_attrs_by_path(item.path)
    local is_content = pl_stringx.split(path_attrs.base_path, '/')[1] == "content"
    local is_spec_extension =
      path_attrs.extension == "json" or
      path_attrs.extension == "yaml" or
      path_attrs.extension == "yml"

    if is_content and is_spec_extension then
      return true
    end

    return false
  end

  local function map_cb(v)
    v.parsed = ts_helpers.parse_oas(v.contents)
    v.route  = ts_helpers.get_route_from_path(v.path)
    return v
  end

  return self
          :set_ctx(ctx)
          :filter(compare_cb)
          :map(map_cb)
          :next({ files })
end


function Portal:config(arg)
  local ctx = getters.select_portal_config()

  return self
          :set_ctx(ctx)
          :next()
          :val(arg)
          :next({ portal_config })
end


function Portal:urls()
  local ctx = getters.get_portal_urls()

  return self
          :set_ctx(ctx)
          :next({ portal_urls })
end


function Portal:name()
  local ctx = getters.get_portal_name()

  return self
          :set_ctx(ctx)
          :next()
end


function Portal:redirect(arg)
  local ctx = getters.get_portal_redirect()

  return self
          :set_ctx(ctx)
          :next()
          :val(arg)
          :next()
end


return Portal
