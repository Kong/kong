local kong_meta = require("kong.meta")
local deep_copy = require "kong.tools.table".deep_copy


local _M = deep_copy(require("kong.llm.proxy.handler"))


_M.PRIORITY = 770
_M.VERSION = kong_meta.version


return _M
