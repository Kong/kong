local ERROR_CODE = {
  PARSE_ERROR       = -32700,
  INVALID_REQUEST   = -32600,
  METHOD_NOT_FOUND  = -32601,
  INVALID_PARAMS    = -32602,
  INTERNAL_ERROR    = -32603,
}


local WS_OPTS = {
  timeout         = 5000, -- 5 seconds
  max_payload_len = 64 * 1024,
}


local PING_INTERVAL = 30 -- seconds
local PING_WAIT     = PING_INTERVAL * 1.5


return {
  ERROR_CODE = ERROR_CODE,

  WS_OPTS = WS_OPTS,

  JSONRPC_VERSION = "2.0",

  PING_INTERVAL = PING_INTERVAL,
  PING_WAIT     = PING_WAIT,

  -- kong.meta.v1.hello
  META_HELLO_MSG_ID = 1,
  META_HELLO_METHOD = "kong.meta.v1.hello",
}
