local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local iputils = require "resty.iputils"

local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function() return {} end
  end
end


-- cache of parsed CIDR values
local cache = {}


local IpRestrictionHandler = BasePlugin:extend()

IpRestrictionHandler.PRIORITY = 1450

local function cidr_cache(cidr_tab)
  local cidr_tab_len = #cidr_tab

  local parsed_cidrs = new_tab(cidr_tab_len, 0) -- table of parsed cidrs to return

  -- build a table of parsed cidr blocks based on configured
  -- cidrs, either from cache or via iputils parse
  -- TODO dont build a new table every time, just cache the final result
  -- best way to do this will require a migration (see PR details)
  for i = 1, cidr_tab_len do
    local cidr        = cidr_tab[i]
    local parsed_cidr = cache[cidr]

    if parsed_cidr then
      parsed_cidrs[i] = parsed_cidr

    else
      -- if we dont have this cidr block cached,
      -- parse it and cache the results
      local lower, upper = iputils.parse_cidr(cidr)

      cache[cidr] = { lower, upper }
      parsed_cidrs[i] = cache[cidr]
    end
  end

  return parsed_cidrs
end

function IpRestrictionHandler:new()
  IpRestrictionHandler.super.new(self, "ip-restriction")
end

function IpRestrictionHandler:init_worker()
  IpRestrictionHandler.super.init_worker(self)
  local ok, err = iputils.enable_lrucache()
  if not ok then
    ngx.log(ngx.ERR, "[ip-restriction] Could not enable lrucache: ", err)
  end
end

function IpRestrictionHandler:access(conf)
  IpRestrictionHandler.super.access(self)
  local block = false
  local binary_remote_addr = ngx.var.binary_remote_addr

  if not binary_remote_addr then
    return responses.send_HTTP_FORBIDDEN("Cannot identify the client IP address, unix domain sockets are not supported.")
  end

  if conf.blacklist and #conf.blacklist > 0 then
    block = iputils.binip_in_cidrs(binary_remote_addr, cidr_cache(conf.blacklist))
  end

  if conf.whitelist and #conf.whitelist > 0 then
    block = not iputils.binip_in_cidrs(binary_remote_addr, cidr_cache(conf.whitelist))
  end

  if block then
    return responses.send_HTTP_FORBIDDEN("Your IP address is not allowed")
  end
end

return IpRestrictionHandler
