local jq = require "resty.jq"
local lrucache = require "resty.lrucache"


local assert = assert


local LRU = lrucache.new(1000)


return function(program, body, opts)
  local jqp = LRU:get(program)
  if not jqp then
    jqp = assert(jq.new())
    assert(jqp:compile(program))
    LRU:set(program, jqp)
  end

  return assert(jqp:filter(body, opts))
end
