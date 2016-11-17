local conf_loader = require "kong.conf_loader"
local pl_app = require "pl.lapp"
local log = require "kong.cmd.utils.log"

local function execute(args)
  local conf, err, errors = conf_loader(args.conf)
  if not conf then
    if errors then
      for i = 1, #errors do
        log.error(errors[i])
      end
    elseif err then
      log.error(err)
    end

    pl_app.quit(nil, true)
  end

  log("configuration at %s is valid", args.conf)
end

local lapp = [[
Usage: kong check <conf>

Check the validity of a given Kong configuration file.

<conf> (default /etc/kong/kong.conf) configuration file
]]

return {
  lapp = lapp,
  execute = execute
}
