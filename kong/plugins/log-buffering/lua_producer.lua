-- Lua array producer object for using the Generic Logging Buffer.


local lua_producer = {}


local function add_entry(self, data)
  table.insert(self.output, data)
  self.size = self.size + #data
  return true, self.size
end


local function produce(self)
  return self.output, #self.output, self.size
end


local function reset(self)
  self.output = {}
  self.size = 0
end


function lua_producer.new(conf)
  local self = {
    output = {},
    size = 0,

    add_entry = add_entry,
    produce = produce,
    reset = reset,
  }

  return self
end


return lua_producer
