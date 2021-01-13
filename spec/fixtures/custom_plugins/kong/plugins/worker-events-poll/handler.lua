local kong = kong
local math = math


local WorkerEventsPoll = {
  PRIORITY = math.huge
}


function WorkerEventsPoll:preread()
  kong.worker_events.poll()
end


function WorkerEventsPoll:rewrite()
  kong.worker_events.poll()
end


return WorkerEventsPoll
