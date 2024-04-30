-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_path = require "pl.path"
local utils = require "kong.tools.utils"

local debugger = os.getenv("KONG_EMMY_DEBUGGER")
local emmy_debugger_host = os.getenv("KONG_EMMY_DEBUGGER_HOST") or "localhost"
local emmy_debugger_port = os.getenv("KONG_EMMY_DEBUGGER_PORT") or 9966
local emmy_debugger_wait = os.getenv("KONG_EMMY_DEBUGGER_WAIT")
local emmy_debugger_source_path = utils.split(os.getenv("KONG_EMMY_DEBUGGER_SOURCE_PATH") or "", ":")

local function find_source(path)
  if pl_path.exists(path) then
    return path
  end

  if path:match("^=") then
    -- code is executing from .conf file, don't attempt to map
    return path
  end

  for _, source_path in ipairs(emmy_debugger_source_path) do
    local full_path = pl_path.join(source_path, path)
    if pl_path.exists(full_path) then
      return full_path
    end
  end

  ngx.log(ngx.ERR, "source file " .. path .. " not found in KONG_EMMY_DEBUGGER_SOURCE_PATH")

  return path
end

local function init()
  if not debugger then
    return
  end

  if not pl_path.isabs(debugger) then
    ngx.log(ngx.ERR, "KONG_EMMY_DEBUGGER (" .. debugger .. ") must be an absolute path")
    return
  end
  if not pl_path.exists(debugger) then
    ngx.log(ngx.ERR, "KONG_EMMY_DEBUGGER (" .. debugger .. ") file not found")
    return
  end
  local ext = pl_path.extension(debugger)
  if ext ~= ".so" and ext ~= ".dylib" then
    ngx.log(ngx.ERR, "KONG_EMMY_DEBUGGER (" .. debugger .. ") must be a .so (Linux) or .dylib (macOS) file")
    return
  end
  if ngx.worker.id() ~= 0 then
    ngx.log(ngx.ERR, "KONG_EMMY_DEBUGGER is only supported in the first worker process, suggest setting KONG_NGINX_WORKER_PROCESSES to 1")
    return
  end

  ngx.log(ngx.NOTICE, "loading EmmyLua debugger " .. debugger)
  ngx.log(ngx.WARN, "The EmmyLua integration for Kong is a feature solely for your convenience during development. Kong assumes no liability as a result of using the integration and does not endorse it’s usage. Issues related to usage of EmmyLua integration should be directed to the respective project instead.")

  _G.emmy = {
    fixPath = find_source
  }

  local name = pl_path.basename(debugger):sub(1, -#ext - 1)

  local save_cpath = package.cpath
  package.cpath = pl_path.dirname(debugger) .. '/?' .. ext
  local dbg = require(name)
  package.cpath = save_cpath

  dbg.tcpListen(emmy_debugger_host, emmy_debugger_port)

  ngx.log(ngx.NOTICE, "EmmyLua debugger loaded, listening on port ", emmy_debugger_port)

  if emmy_debugger_wait then
    -- Wait for IDE connection
    ngx.log(ngx.NOTICE, "waiting for IDE to connect")
    dbg.waitIDE()
    ngx.log(ngx.NOTICE, "IDE connected")
  end
end

return {
  init = init
}
