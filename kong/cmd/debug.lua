-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local log         = require "kong.cmd.utils.log"
local cjson       = require "cjson"
local resty_http  = require "resty.http"
local conf_loader = require "kong.conf_loader"

-- EXIT CODES
local EC_SUCCESS    = 0
local EC_FAILURE    = 1
local EC_INPROGRESS = 2

local DEFAULT_TIMEOUT = 5000  -- 5s, enough for debugging endpoint APIs

local log_levels = {
  debug = true, info = true, notice = true, warn = true, error = true,
  crit = true, alert = true, emerg = true,
}

local NEEDS_DEBUG_LISTEN_MSG =
  "To use `kong debug`, you need to enable domain socket based debug server\n" ..
  "by setting \"debug_listen_local\" to \"on\" in the kong.conf.\n\n"


-- We implement a wrapper for making a request to the unix domain socket
-- as the API httpc:request_uri() doesn't support it.
local function request_unix_domain_socket(params)
  -- connect to the unix domain socket
  local httpc = resty_http.new()
  httpc:set_timeout(DEFAULT_TIMEOUT)

  local ok, err = httpc:connect({
    host = params.socket_path,
  })

  if not ok then
    error("Failed to connect to the debug endpoint: " .. err .. "\n\n" ..
          NEEDS_DEBUG_LISTEN_MSG)
  end

  if params.verbose then
    log.verbose("")
    log.verbose("request: %s %s", params.method, params.path)
    log.verbose("body:    %s", cjson.encode(params.body))
  end

  -- send the http request
  local res, err = httpc:request({
    path = params.path,
    method = params.method,
    headers = {
      ["Host"] = "127.0.0.1",
      ["Content-Type"] = "application/json",
    },
    body = params.body,
  })

  if not res then
    error("Failed to access the debug endpoint: " .. err)
  end

  -- read the response body
  local body, err = res:read_body()
  if not body then
    error("Failed to get response: " .. err)
  end
  res.body = body

  --  the result
  if params.verbose then
    log.verbose("")
    log.verbose(res.status .. " " .. res.reason)

    for k,v in pairs(res.headers) do
      log.verbose(k .. ": " .. v)
    end

    log.verbose("")
    log.verbose(res.body)
  end

  if res.status == 204 then
    res.body = cjson.decode(res.headers["X-Kong-Profiling-State"])

  else
    res.body = cjson.decode(res.body)
  end

  if res.status == 500 then
    error("Kong returned an error: " .. tostring(res.body))
  end

  return res
end


local function log_state(msg, state)
  if state.pid then
    log(msg .. " on pid: " .. state.pid)

  else
    log(msg)
  end

  if state.path then
    log("Profiling file: %s", state.path)
  end
end


local function profiling_handler(socket_path, args, options)
  local profiler = args[1]
  local action = args[2]

  if not ((profiler == "cpu" or profiler == "memory") and
          (action == "start" or action == "stop" or action == "status")) and
     not (profiler == "gc-snapshot" and not action)
  then
    error("Invalid profiling commands\n" ..
          "Usage: kong debug profiling cpu|memory start|stop|status\n" ..
          "       kong debug profiling gc-snapshot")
  end

  if profiler == "cpu" then
    if not options.mode or options.mode == "time" and options.step then
      error("--step option cannot be used for `time` mode")

    elseif options.mode == "instructions" and options.interval then
      error("--interval option cannot be used for `instructions` mode")
    end
  end

  -- construct the request

  local method = action == "stop"          and "DELETE" or
                 action == "start"         and "POST" or
                 profiler == "gc-snapshot" and "POST" or
                                               "GET"
  local path = "/debug/profiling/" .. profiler

  local params = {
    socket_path = socket_path,
    path = path,
    method = method,
    body = cjson.encode(options),
    verbose = args.v,
  }

  -- request to the gateway
  local res = request_unix_domain_socket(params)
  local state = res.body

  -- handle the result

  if res.status == 409 then
    log.error(res.body.message)
    return EC_INPROGRESS
  end

  -- profiling cpu|memory start
  if action == "start" then
    if res.status == 201 then
      log(res.body.message .. " (randomly chosen worker process PID)")
      return EC_SUCCESS
    end

    log.error(res.body.message)
    return EC_FAILURE
  end

  -- profiling cpu|memory stop
  if action == "stop" then
    if res.status == 204 then
      log_state("Profiling stopped", state)
      return EC_SUCCESS
    end

    log.error(res.body.message)
    return EC_FAILURE
  end

  -- profiling cpu|memory status (without `-f` option)
  if action == "status" and not options.f then
    log_state(state.status == "started" and "Profiling is active"
                                        or  "Profiling stopped", state)
    return EC_SUCCESS
  end

  -- profiling gc-snapshot
  -- profiling cpu|memory status -f
  --
  -- wait for results

  log("Waiting for %s profiling to complete...\n", profiler)
  log("To stop profiling, type \"kong debug profiling %s stop\" from another window.\n", profiler)

  params.method = "GET"

  while true do
    ngx.sleep(1)

    local res = request_unix_domain_socket(params)
    local state = res.body

    if state.status == "stopped" or state.remain == 0 then
      log_state("Profiling stopped", state)
      return EC_SUCCESS
    end

    if state.status ~= "started" then
      error("Invalid status " .. tostring(state.status))
    end

    log("Profiling is active on pid: %s, remaining time: %s s",
        state.pid, state.remain)
  end
end


local function log_level_handler(socket_path, args, options)
  local method, path

  -- handle arguments
  if not args[1] then
    error("Need one argument: get|set")
  end

  if args[1] == "set" then
    local log_level = options.level
    if not log_level then
      error("No log_level found, need option --level <log_level>\n\n" ..
            "  log_level: debug info notice warn error crit alert emerg")
    end

    if not log_levels[log_level] then
      error("Invalid log_level " .. log_level .. "\n\n" ..
            "  log_level: debug info notice warn error crit alert emerg")
    end

    method = "PUT"
    path = "/debug/node/log-level/" .. log_level

  elseif args[1] == "get" then
    method = "GET"
    path = "/debug/node/log-level"

  else
    error("Invalid argument " .. args[1])
  end

  -- request to the gateway
  local res = request_unix_domain_socket({
    socket_path = socket_path,
    path = path,
    method = method,
    body = cjson.encode(options),
    verbose = args.v,
  })

  log(res.body.message)
  return EC_SUCCESS
end


local command_handlers = {
  profiling = profiling_handler,
  log_level = log_level_handler,
}


local function execute(args)
  -- retrieve prefix or use given one
  local conf = assert(conf_loader(args.conf, { prefix = args.prefix }))
  local socket_path = "unix:" .. (args.unix_socket  or
                                  conf.prefix .. "/kong_debug.sock")

  -- construct the data of POST/PUT
  local options = {}
  for k,v in pairs(args) do
    if type(k) ~= "number" and k ~= "v" and k ~= "vv" and k ~= "command" then
      options[k] = v
    end
  end

  -- execute the sub command handler
  local code = command_handlers[args.command](socket_path, args, options)

  -- let the upper resty command get the exit code
  os.exit(code)
end


local lapp = [[
Usage: kong debug COMMAND [OPTIONS]

Invoke various debugging features in Kong.

The available commands are:

  For the endpoint in kong/api/routes/debug.lua,

  profiling cpu <start|stop|status>     Generate the raw data of Lua-land CPU
                                        flamegraph.

    --mode      (optional string default "time")
                                        The mode of CPU profiling, `time` means
                                        time-based profiling, `instruction`
                                        means instruction-counter-based
                                        profiling.

    --step      (optional number)       The initial value of the instruction
                                        counter. A sample will be taken when the
                                        counter goes to zero.
                                        (only for mode=instruction)

    --interval  (optional number)       Sampling interval in microseconds.
                                        (only for mode=time)

    --timeout (optional number)         Profiling will be stopped automatically
                                        after the timeout (in seconds).
                                        default: 10

  profiling memory <start|stop|status>  Generating the Lua GC heap memory
                                        tracing data (on-the-fly tracing).

    --stack_depth (optional number)     The maximum depth of the Lua stack.

    --timeout (optional number)         Profiling will be stopped automatically
                                        after the timeout (in seconds).
                                        default: 10

  profiling gc-snapshot                 Generate a Lua GC heap snapshot.

    --timeout (optional number)         Profiling will be stopped automatically
                                        after the timeout (in seconds).
                                        default: 120

  log_level set --level <log_level>     Set the logging level.
                                        It cannot work while not using a
                                        database because it needs to be
                                        protected by RBAC and RBAC is not
                                        available in DB-less.

    --level (optional string)           It can be one of the following: debug,
                                        info, notice, warn, error, crit, alert,
                                        or emerg.

    --timeout (optional number)         The log level will be restored to the
                                        original level after the timeout (in
                                        seconds).
                                        default: 60

  log_level get                         Get the logging level.


Options:
 --pid            (optional number)     The worker’s PID for profiling.

 -f                                     Follow mode for certain commands, such
                                        as 'profiling {cpu|memory} status'.
                                        It continuously checks the status until
                                        it completes.

 -c,--conf        (optional string)     Configuration file.
 -p,--prefix      (optional string)     Override prefix directory.


EXIT CODES
  Various error codes and their associated messages may be returned by this
  command during error situations.

 `0` - Success. The requested operation completed successfully.

 `1` - Error. The requested operation failed. An error message is available in
       the command output.

 `2` - In progress. The profiling is still in progress.
       The following commands make use of this return value:
       - kong debug profiling cpu start
       - kong debug profiling memory start
       - kong debug profiling gc-snapshot

]]


return {
  lapp = lapp,
  execute = execute,
  sub_commands = {
    log_level = true,
    profiling = true,
  },
}
