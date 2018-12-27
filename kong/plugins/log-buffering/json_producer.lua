-- JSON array producer object for using the Generic Logging Buffer.
local cjson = require("cjson")


local json_producer = {}


local cjson_encode = cjson.encode


local function add_entry(self, data)
  if not self.encoded then
    data = cjson_encode(data)
  end
  local n = #self.output
  if n == 0 then
    self.output[1] = "["
  else
    self.output[n+1] = ","
  end
  self.output[n+2] = data
  self.bytes = self.bytes + #data + 1
  return true, (n + 2) / 2
end


local function produce(self)
  local count = #self.output / 2
  self.output[#self.output + 1] = "]"
  local data = table.concat(self.output)
  return data, count, #data
end


local function reset(self)
  self.output = {}
  self.bytes = 1
end


-- Produces the given entries into a JSON array.
-- @param raw_tree (boolean)
-- If `encoded` is `true`, entries are assumed to be strings
-- that already represent JSON-encoded data.
-- If `encoded` is `false`, entries are assumed to be Lua objects
-- that need to be encoded during serialization.
function json_producer.new(encoded)
  if encoded ~= nil and type(encoded) ~= "boolean" then
    error("arg 2 (encoded) must be boolean")
  end

  local self = {
    output = {},
    bytes = 1,
    encoded = encoded,

    add_entry = add_entry,
    produce = produce,
    reset = reset,
  }

  return self
end


return json_producer
