local http = require "resty.luasocket.http"
local print = print
local fmt = string.format

local conf_loader = require "kong.conf_loader"
local pl_path = require "pl.path"
local log = require "kong.cmd.utils.log"

local function execute(args)
  log.disable()

  -- only to retrieve the default prefix or use given one
  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))

  if pl_path.exists(conf.kong_env) then
    -- load <PREFIX>/kong.conf containing running node's config
    conf = assert(conf_loader(conf.kong_env))
  end

  log.enable()

  if #conf.status_listeners == 0 then
    print("No status listeners found in configuration.")
    return
  end

  local status_listener = conf.status_listeners[1]

  local scheme = "http"
  if status_listener.ssl then
    scheme = "https"
  end

  local url = scheme .. "://" .. status_listener.ip .. ":" .. status_listener.port .. "/status/unready"

  local httpc = http.new()
  httpc:set_timeout(1000)

  local res, err = httpc:request_uri(url, {
    method = "POST",
    headers = {
        ["Content-Type"] = "application/json"
    },
    body = "{}",
    -- we don't need to verify the SSL certificate for this request
    ssl_verify = false,
  })

  httpc:close()

  if not res then
    print(fmt("Failed to send request to %s: %s", url, err))
    return
  end

  if res.status ~= 204 then
    print(fmt("Unexpected response status from %s: %d", url, res.status))
    return
  end

  print("Kong's status successfully changed to 'unready'")
end


local lapp = [[
Usage: kong unready [OPTIONS]

Make status listeners(`/status/ready`) return 503 Service Unavailable.

Example usage:
 kong unready

Options:
 -c,--conf    (optional string)  configuration file
 -p,--prefix  (optional string)  override prefix directory
]]


return {
  lapp = lapp,
  execute = execute,
}
