local http = require "resty.http"

local EnableBuffering = {
  PRIORITY = 1000000,
  VERSION = "1.0",
}


function EnableBuffering:access(conf)
  local httpc = http.new()
  httpc:set_timeout(1)

  for suffix = 0, conf.calls - 1 do
    local uri = "http://really.really.really.really.really.really.not.exists." .. suffix
    pcall(function()
      httpc:request_uri(uri)
    end)
  end
end


return EnableBuffering
