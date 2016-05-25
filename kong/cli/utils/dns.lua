local stringy = require "stringy"
local IO = require "kong.tools.io"
local utils = require "kong.tools.utils"

local _M = {}

function _M.parse_dns_address(address)
  local with_port = string.match(address, "%[")
  local parts = stringy.split(address, ":")
  return {
    address = address,
    host = address:match("%[?([%w%.:]+)%]?"),
    port = with_port and tonumber(parts[#parts]) or 53
  }
end

function _M.parse_resolv_entry(v)
  local address = v:match("%s*nameserver%s+([%[%]%w%.:]+)")
  if address then
    return _M.parse_dns_address(address)
  end
end

function _M.parse_options_entry(v)
  local options = v:match("%s*options%s+[%s%w:]+")
  if options then
    local timeout, attempts
    for option in options:gmatch("%S+") do
      timeout = timeout or tonumber(option:match("%s*timeout:(%d+)%s*"))
      attempts = attempts or tonumber(option:match("%s*attempts:(%d+)%s*"))
    end

    if timeout or attempts then
      return {timeout = timeout and timeout * 1000 or timeout, attempts = attempts}  -- In milliseconds
    end
  end
end

function _M.parse_etc_hosts()
  local contents = IO.read_file("/etc/hosts")
  if contents then
    local results = {}
    local lines = stringy.split(contents, "\n")
    for _, line in ipairs(lines) do
      if not stringy.startswith(stringy.strip(line), "#") then
        local ip_address
        for entry in line:gmatch("%S+") do
          if not ip_address then 
            ip_address = entry
          else
            if not results[entry] then
              results[entry] = ip_address
            end
          end
        end
      end
    end
    return results
  end
end

function _M.find_first_namespace()
  local contents = IO.read_file("/etc/resolv.conf")
  if contents then
    -- Find first nameserver
    local lines = stringy.split(contents, "\n")
    local options, nameserver

    for _, line in ipairs(lines) do
      nameserver = nameserver or _M.parse_resolv_entry(line)
      options = options or _M.parse_options_entry(line)
    end

    if nameserver then
      return utils.table_merge(nameserver, options and options or {})
    end
  end
end

return _M