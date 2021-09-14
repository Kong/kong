local pl_utils = require "pl.utils"


if ngx.IS_CLI then
  local log = require "kong.cmd.utils.log"
  pl_utils.set_deprecation_func(function(msg, trace)
    if trace then
      log.warn(msg, " ", trace)
    else
      log.warn(msg)
    end
  end)

else
  pl_utils.set_deprecation_func(function(msg, trace)
    if kong and kong.log then
      if trace then
        kong.log.warn(msg, " ", trace)
      else
        kong.log.warn(msg)
      end

    else
      if trace then
        ngx.log(ngx.WARN, msg, " ", trace)
      else
        ngx.log(ngx.WARN, msg)
      end
    end
  end)
end


return function(message, version_removed, deprecated_after, trace)
  pl_utils.raise_deprecation({
   message = message,
   version_removed = version_removed,
   deprecated_after = deprecated_after,
   no_trace = not trace,
  })
end
