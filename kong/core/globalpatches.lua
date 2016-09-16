local meta = require "kong.meta"

_G._KONG = {
  _NAME = meta._NAME,
  _VERSION = meta._VERSION
}

local is_resty_cli = (arg ~= nil) -- only the cli has a global `arg` table, openresty doesn't have it

do -- randomseeding patch
  
  -- globally disable randomseed
  local randomseed = _G.math.randomseed
  local seed_index = {}
  _G.math.randomseed = function()

    -- Init is special because a forked worker has to reseed, so we use a string key.
    -- Not entirely sure this is necessary, but better safe than sorry.
    local whoami = ngx.get_phase() == "init" and "init" or ngx.worker.pid()

    if not seed_index[whoami] then
      local seed = ngx.time() + ngx.worker.pid()
      ngx.log(ngx.DEBUG, "random seed: ", seed, " for worker n", ngx.worker.id(),
                         " (pid: ", ngx.worker.pid(), ")")
      randomseed(seed)
      seed_index[whoami] = seed
    else
      ngx.log(ngx.DEBUG, debug.traceback("ignoring attempt to reseed the random generator @ "))
    end
  end

  --[[ The below code will enforce best practices, but fails when the culprit is in external code
  local randomseed = math.randomseed
  local seed

  --- Seeds the random generator, use with care.
  -- The uuid.seed() method will create a unique seed per worker
  -- process, using a combination of both time and the worker's pid.
  -- We only allow it to be called once to prevent third-party modules
  -- from overriding our correct seed (many modules make a wrong usage
  -- of `math.randomseed()` by calling it multiple times or do not use
  -- unique seed for Nginx workers).
  -- luacheck: globals math
  _G.math.randomseed = function()
    if not seed then
      if ngx.get_phase() ~= "init_worker" and not is_resty_cli then  
        error("math.randomseed() must be called in init_worker", 2)
      end

      seed = ngx.time() + ngx.worker.pid()
      ngx.log(ngx.DEBUG, "random seed: ", seed, " for worker n", ngx.worker.id(),
                         " (pid: ", ngx.worker.pid(), ")")
      randomseed(seed)
    else
      ngx.log(ngx.DEBUG, "attempt to seed random number generator, but ",
                         "already seeded with ", seed)
    end
  end
  --]]
end



do -- cosockets connect patch for dns resolution
  
  --- Patch the TCP connect method such that all connections will be resolved
  -- first by the internal DNS resolver. 
  -- STEP 1: load code that should not be using the patched versions
  require "resty.dns.resolver"  -- will cache TCP and UDP functions
  -- STEP 2: forward declaration of locals to hold stuff loaded AFTER patching
  local toip
  -- STEP 3: store original unpatched versions
  local old_tcp = ngx.socket.tcp
  -- STEP 4: patch globals
  _G.ngx.socket.tcp = function(...)
    local sock = old_tcp(...)
    local old_connect = sock.connect
    
    sock.connect = function(s, host, port, sock_opts)
      local target_ip, target_port = toip(host, port)
      if not target_ip then 
        return nil, "[toip() name lookup failed]:"..tostring(target_port)
      else
        -- need to do the extra check here: https://github.com/openresty/lua-nginx-module/issues/860
        if not sock_opts then
          return old_connect(s, target_ip, target_port)
        else
          return old_connect(s, target_ip, target_port, sock_opts)
        end
      end
    end
    return sock
  end
  -- STEP 5: load code that should be using the patched versions, if any (because of dependency chain)
  toip = require("dns.client").toip  -- this will load utils and penlight modules for example
end



do -- patch for LuaSocket tcp sockets, block usage in cli.

  if is_resty_cli then
    local socket = require "socket"
    socket.tcp = function(...)
      error("should not be using this")
    end
  end
end



do -- Cassandra cache-shm patch

  --- Patch cassandra driver.
  -- The cache module depends on an `shm` which isn't available on the `resty` cli.
  -- in non-nginx Lua it uses a stub. So for the cli make it think it's non-nginx.
  if is_resty_cli then
    local old_ngx = _G.ngx
    _G.ngx = nil
    require "cassandra.cache"
    _G.ngx = old_ngx
  end
end



do -- cassandra resty-lock patch
  
  --- stub for resty.lock module which isn't available in the `resty` cli because it
  -- requires an `shm`.
  if is_resty_cli then
    package.loaded["resty.lock"] = {
        new = function()
          return {
            lock = function(self, key)
              return 0   -- cli is single threaded, so a lock always succeeds
            end,
            unlock = function(self, key)
              return 1   -- same as above, always succeeds
            end
          }
        end,
      }
  end
end
