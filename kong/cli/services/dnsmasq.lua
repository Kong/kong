local BaseService = require "kong.cli.services.base_service"
local logger = require "kong.cli.utils.logger"
local IO = require "kong.tools.io"
local version = require "version"

local Dnsmasq = BaseService:extend()

local SERVICE_NAME = "dnsmasq"

-- compatible Dnsmasq version
local version_command = " -v"                    -- commandline param to get version
local version_pattern = "^Dnsmasq.-([%d%.]+)"    -- pattern to grab version from output
local compatible = version.set("2.72", "2.75")   -- compatible from-to versions


function Dnsmasq:new(configuration)
  self._configuration = configuration
  Dnsmasq.super.new(self, SERVICE_NAME, self._configuration.nginx_working_dir)
end

function Dnsmasq:_get_cmd()
  local cmd, err = Dnsmasq.super._get_cmd(self, {}, function(path)
    local res, code = IO.os_execute(path..version_command)
    if code == 0 then
      local version_match = res:match(version_pattern)
      if (not version_match) or (not compatible:matches(version_match)) then
        logger:error("Incompatible Dnsmasq version. Kong requires version "..tostring(compatible)..
          (version_match and ", got "..tostring(version_match) or ""))
        os.exit(1)
      end
      return version_match
    end

    return false
  end)

  return cmd, err
end

function Dnsmasq:prepare()
  return Dnsmasq.super.prepare(self, self._configuration.nginx_working_dir)
end

function Dnsmasq:start()
  if self._configuration.dns_resolver.dnsmasq then
    if self:is_running() then
      return nil, SERVICE_NAME.." is already running"
    end

    local cmd, err = self:_get_cmd()
    if err then
      return nil, err
    end

    -- dnsmasq always listens on the local 127.0.0.1 address
    local res, code = IO.os_execute(cmd.." -p "..self._configuration.dns_resolver.port.." --pid-file="..self._pid_file_path.." -N -o --listen-address=127.0.0.1")    
    if code == 0 then
      while not self:is_running() do
        -- Wait for PID file to be created
      end

      setmetatable(self._configuration.dns_resolver, require "kong.tools.printable")
      logger:info(string.format([[dnsmasq............%s]], tostring(self._configuration.dns_resolver)))
      return true
    else
      return nil, res
    end
  end
  return true
end

function Dnsmasq:stop()
  if self._configuration.dns_resolver.dnsmasq then
    Dnsmasq.super.stop(self, true) -- Killing dnsmasq just with "kill PID" apparently doesn't terminate it
  end
end

return Dnsmasq