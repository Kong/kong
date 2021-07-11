local pl_utils = require "pl.utils"


local concat = table.concat
local select = select
local type = type


local function init_cli()
  local log = require "kong.cmd.utils.log"
  pl_utils.set_deprecation_func(function(msg, trace)
    if trace then
      log.warn(msg, " ", trace)
    else
      log.warn(msg)
    end
  end)
end


local function init()
  local log = ngx.log
  local warn = ngx.WARN
  pl_utils.set_deprecation_func(function(msg, trace)
    if kong and kong.log then
      if trace then
        kong.log.deprecation.write(msg, " ", trace)
      else
        kong.log.deprecation.write(msg)
      end

    else
      if trace then
        log(warn, msg, " ", trace)
      else
        log(warn, msg)
      end
    end
  end)
end


local deprecation = {}


function deprecation.init(is_cli)
  if is_cli then
    init_cli()
  else
    init()
  end
end


function deprecation.raise(...)
  local argc = select("#", ...)
  local last_arg = select(argc, ...)
  if type(last_arg) == "table" then
    pl_utils.raise_deprecation({
      message = concat({ ... }, nil, 1, argc - 1),
      deprecated_after = last_arg.after,
      version_removed = last_arg.removal,
      no_trace = not last_arg.trace,
    })

  else
    pl_utils.raise_deprecation({
      message = concat({ ... }, nil, 1, argc),
      no_trace = true,
    })
  end
end


return setmetatable(deprecation, {
  __call = function(_, ...)
    return deprecation.raise(...)
  end
})
