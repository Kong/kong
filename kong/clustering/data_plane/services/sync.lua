-- CP => DP

local cjson = require("cjson.safe")
local config_helper = require("kong.clustering.config_helper")
local constants = require("kong.clustering.rpc.constants")
local callbacks = require("kong.clustering.rpc.callbacks")
--local utils = require("kong.tools.utils")


--local inflate_gzip = utils.inflate_gzip
--local yield = utils.yield


local _M = {}
local _MT = { __index = _M, }


function _M.new()
  local self = {}

  return setmetatable(self, _MT)
end


function _M:init()
  callbacks.register("kong.sync.v1.push_all", function(params)
    ngx.log(ngx.ERR, "xxx sync push all, data type=", type(params.data))

    local msg = assert(params.data)

    --local msg = assert(inflate_gzip(data))
    --yield()
    --msg = assert(cjson.decode(msg))
    --yield()

    ngx.log(ngx.ERR, "received reconfigure frame from control plane",
                     msg.timestamp and " with timestamp: " .. msg.timestamp or "")

    local config_table = assert(msg.config_table)
    local declarative_config = kong.db.declarative_config

    local pok, res, err = pcall(config_helper.update, declarative_config,
                                config_table, msg.config_hash, msg.hashes)
    if not pok or not res then
      ngx_log(ngx_ERR, "unable to update running config: ",
                       (not pok and res) or err)
      return nil, {code = constants.INTERNAL_ERROR, message = "error"}
    end

    return { msg = "sync ok" }
  end)

end


return _M
