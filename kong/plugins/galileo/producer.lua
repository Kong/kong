-- Producer object for using the Generic Logging Buffer.


local alf = require "kong.plugins.galileo.alf"


local producer = {}


local function add_entry(self, ...)
  return self.cur_alf:add_entry(...)
end


local function produce(self)
  local produced, count_or_err = self.cur_alf:serialize(self.service_token, self.environment)
  if produced then
    return produced, count_or_err, #produced
  end
  return nil, count_or_err
end


local function reset(self)
  return self.cur_alf:reset()
end


function producer.new(conf)
  assert(type(conf) == "table",
         "arg #1 (conf) must be a table")
  assert(type(conf.service_token) == "string",
         "service_token must be a string")
  assert(type(conf.server_addr) == "string",
         "server_addr must be a string")
  assert(conf.log_bodies == nil or type (conf.log_bodies) == "boolean",
         "log_bodies must be a boolean")
  assert(conf.environment == nil or type(conf.environment) == "string",
         "environment must be a string")

  local self = {
    service_token = conf.service_token,
    environment = conf.environment,

    cur_alf = alf.new(conf.log_bodies or false, conf.server_addr),

    add_entry = add_entry,
    produce = produce,
    reset = reset,
  }

  return self
end


return producer
