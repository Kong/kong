local http_mock = require "spec.helpers.http_mock"

--- tapping implemented with http_mock
---@class http_mock.tapping: http_mock
local tapping = {}

-- create a new tapping route
-- @param target string|number: the target host/port of the tapping route
-- @return table: the tapping route
function tapping.new_tapping_route(target)
  if tonumber(target) then
    -- TODO: handle the resovler!
    target = "http://127.0.0.1:" .. target
  end

  if not target:find("://") then
    target = "http://" .. target
  end

  return {
    ["/"] = {
      directives = [[proxy_pass ]] .. target .. [[;]],
    }
  }
end

-- create a new http_mock.tapping instance with a tapping route
-- @param target string|number: the target host/port of the tapping route
-- @param listens table|string|number|nil: the listen directive of the mock server, defaults to a random available port
-- @param prefix string|nil: the prefix of the mock server, defaults to "servroot_tapping"
-- @param log_opts table|nil: log_opts, left it empty to use the defaults, with req_large_body enabled
-- @return http_mock.tapping: a tapping instance
-- @return number: the port the mock server listens to
function tapping.new(target, listens, prefix, log_opts)
  ---@diagnostic disable-next-line: return-type-mismatch
  return http_mock.new(listens, tapping.new_tapping_route(target), {
    prefix = prefix or "servroot_tapping",
    log_opts = log_opts or {
      req = true,
      req_body = true,
      req_large_body = true,
    },
  })
end

return tapping
