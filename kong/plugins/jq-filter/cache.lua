local jq = require "resty.jq"
local lrucache = require "resty.lrucache"


local LRU = lrucache.new(1000)


return function(program)
  local jqp = LRU:get(program)
  if not jqp then
    jqp = jq.new()
    local ok, err = jqp:compile(program)
    if not ok or err then
      return nil, err
    end
    LRU:set(program, jqp)
  end

  return jqp, nil
end
