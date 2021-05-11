local InitWorkerLuaError = {}


InitWorkerLuaError.PRIORITY = 1000


function InitWorkerLuaError:init_worker(conf)
  error("this fails intentionally")
end


return InitWorkerLuaError
