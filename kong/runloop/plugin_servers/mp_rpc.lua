local msgpack = require "MessagePack"

local mp_pack = msgpack.pack
local mp_unpacker = msgpack.unpacker


local Rpc = {}
Rpc.__index = Rpc

Rpc.notifications_callbacks = {}

function Rpc.new(socket_path, notifications)
  kong.log.debug("mp_rpc.new: ", socket_path)
  return setmetatable({
    socket_path = socket_path,
    msg_id = 0,
    notifications_callbacks = notifications,
  }, Rpc)
end



-- add MessagePack empty array/map

msgpack.packers['function'] = function (buffer, f)
  f(buffer)
end

local function mp_empty_array(buffer)
  msgpack.packers['array'](buffer, {}, 0)
end

local function mp_empty_map(buffer)
  msgpack.packers['map'](buffer, {}, 0)
end

--- fix_mmap(t) : preprocess complex maps
function Rpc.fix_mmap(t)
  local o, empty = {}, true

  for k, v in pairs(t) do
    empty = false
    if v == true then
      o[k] = mp_empty_array

    elseif type(v) == "string" then
      o[k] = { v }

    else
      o[k] = v
    end
  end

  if empty then
    return mp_empty_map
  end

  return o
end


function Rpc:call(method, ...)
  self.msg_id = self.msg_id + 1
  local msg_id = self.msg_id

  local c, err = ngx.socket.connect("unix:" .. self.socket_path)
  if not c then
    kong.log.err("trying to connect: ", err)
    return nil, err
  end

  -- request: [ 0, msg_id, method, args ]
  local bytes, err = c:send(mp_pack({0, msg_id, method, {...}}))
  if not bytes then
    c:setkeepalive()
    return nil, err
  end

  local reader = mp_unpacker(function()
    return c:receiveany(4096)
  end)

  while true do
    -- read an MP object
    local ok, data = reader()
    if not ok then
      c:setkeepalive()
      return nil, "no data"
    end

    if data[1] == 2 then
      -- notification: [ 2, label, args ]
      self:notification(data[2], data[3])

    else
      -- response: [ 1, msg_id, error, result ]
      assert(data[1] == 1, "RPC response expected from Go plugin server")
      assert(data[2] == msg_id,
             "unexpected RPC response ID from Go plugin server")

      -- it's our answer
      c:setkeepalive()

      if data[3] ~= nil then
        return nil, data[3]
      end

      return data[4]
    end
  end
end


function Rpc:notification(label, args)
  local f = self.notifications_callbacks[label]
  if f then
    f(self, args)
  end
end


return Rpc
