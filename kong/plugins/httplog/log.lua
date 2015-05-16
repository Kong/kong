local cjson = require "cjson"
local http_client = require "kong.tools.http_client"

local APPLICATION_JSON_TYPE = "application/json"

local _M = {}

local function log(premature, conf, message)
  local response, status, headers = http_client.post(conf.logging_url, cjson.encode(message), { ["content-type"] = APPLICATION_JSON_TYPE })
end

function _M.execute(conf)
  local ok, err = ngx.timer.at(0, log, conf, ngx.ctx.log_message)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
  end
end

return _M
