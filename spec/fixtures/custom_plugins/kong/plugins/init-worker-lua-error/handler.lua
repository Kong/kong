local InitWorkerLuaError = {}


InitWorkerLuaError.PRIORITY = 1000
InitWorkerLuaError.VERSION = "1.0"


function InitWorkerLuaError:init_worker(conf)
  error("this fails intentionally")
end


return InitWorkerLuaError
