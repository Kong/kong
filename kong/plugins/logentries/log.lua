local cjson = require "cjson"
local logger = require "vendor.logger.socket"

local format = string.format

local _M = {}

function _M.execute(conf, message)
  if not logger.initted() then
    local ok, err = logger.init({
      host = conf.host,
      port = conf.port,
      flush_limit = conf.flush_limit,
      drop_limit = conf.drop_limit,
      pool_size  = conf.keepalive,
      timeout = conf.timeout,
    })

    if not ok then
      ngx.log(ngx.ERR, "[logentries] failed to initialize the logger: ", err)
      return
    end
  end

  local bytes, err = logger.log(format("%s\r\n", cjson.encode(message)))
  if not bytes then
    ngx.log(ngx.ERR, "[logentries] failed to log message: ", err)
    return
  end
end

return _M
