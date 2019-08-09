-- local singletons  = require "kong.singletons"
-- local workspaces   = require "kong.workspaces"
local UrlHelpers   = require "kong.portal.render_toolset.shared.url"

local PortalUrls = {}


-- local function get_portal_urls()
--   local conf = singletons.configuration
--   local render_ctx = singletons.render_ctx
--   local workspace = workspaces.get_workspace()
--   local portal_gui_url = workspaces.build_ws_portal_gui_url(conf, workspace)
--   local portal_api_url = workspaces.build_ws_portal_api_url(conf, workspace)
--   local current_url = portal_gui_url .. render_ctx.route

--   return {
--     current = current_url,
--     api = portal_api_url,
--     gui = portal_gui_url,
--   }
-- end


-- function PortalUrls:new()
--   local o = {
--     ctx = get_portal_urls()
--   }
--   setmetatable(o, self)
--   self.__index = self
--   self.__call = function(t)
--     return t.ctx
--   end

--   return o
-- end


function PortalUrls:gui()
  local ctx = self.ctx.gui

  return self
          :set_ctx(ctx)
          :next({ UrlHelpers })
end


function PortalUrls:api()
  local ctx = self.ctx.api

  return self
          :set_ctx(ctx)
          :next({ UrlHelpers })
end


function PortalUrls:current()
  local ctx = self.ctx.current

  return self
          :set_ctx(ctx)
          :next({ UrlHelpers })
end


return PortalUrls
