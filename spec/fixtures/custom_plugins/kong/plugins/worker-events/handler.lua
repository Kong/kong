local semaphore = require "ngx.semaphore"
local cjson = require "cjson"


local ngx = ngx
local kong = kong
local table = table


local worker_events = {}
local sema


local function load_data()
  local ok, err = sema:wait(5)
  if ok then
    local data = table.remove(worker_events, 1)
    if data then
      return data
    end

    return {
      error = "worker event data not found"
    }
  end

  return {
    error = err
  }
end


local WorkerEventsHandler = {
  PRIORITY = 500,
}


function WorkerEventsHandler.init_worker()
  sema = semaphore.new()
  kong.worker_events.register(function(data)
    worker_events[#worker_events+1] = {
      operation  = data.operation,
      entity     = data.entity,
      old_entity = data.old_entity,
    }
    sema:post()
  end, "dao:crud")
end


function WorkerEventsHandler:preread()
  local data = load_data()
  local json = cjson.encode(data)
  ngx.print(json)
  return ngx.exit(200)
end


function WorkerEventsHandler:access()
  return kong.response.exit(200, load_data())
end


return WorkerEventsHandler
