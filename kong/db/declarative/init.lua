local declarative_config = require "kong.db.schema.others.declarative_config"
local lyaml = require "lyaml"
local cjson = require "cjson.safe"


local declarative = {}


function declarative.init(conf)
  local schema, err = declarative_config.load(conf.loaded_plugins)
  if not schema then
    return nil, err
  end

  local self = {
    schema = schema
  }
  setmetatable(self, { __index = declarative })
  return self
end


function declarative.parse_file(self, filename, accept)
  assert(type(filename) == "string")

  local fd, err = io.open(filename)
  if not fd then
    return nil, "could not open declarative configuration file: " ..
                filename .. ": " .. err
  end

  local contents, err = fd:read("*a")
  if not contents then
    return nil, "could not read declarative configuration file: " ..
                filename .. ": " .. err
  end

  assert(fd:close())

  return declarative.parse_string(self, contents, filename, accept)
end


function declarative.parse_string(self, contents, filename, accept)

  -- do not accept Lua by default
  accept = accept or { yaml = true, json = true }

  local dc_table, err
  if accept.yaml and filename:match("ya?ml$") then
    local pok
    pok, dc_table, err = pcall(lyaml.load, contents)
    if not pok then
      err = dc_table
      dc_table = nil
    end

  elseif accept.json and filename:match("json$") then
    dc_table, err = cjson.decode(contents)

  elseif accept.lua and filename:match("lua$") then
    local chunk = loadstring(contents)
    setfenv(chunk, {})
    if chunk then
      local pok, dc_table = pcall(chunk)
      if not pok then
        err = dc_table
      end
    end

  else
    local accepted = {}
    for k, _ in pairs(accept) do
      table.insert(accepted, k)
    end
    table.sort(accepted)
    return nil, "unknown file extension (" ..
                table.concat(accepted, ", ") ..
                " " .. (#accepted == 1 and "is" or "are") ..
                " supported): " .. filename
  end

  if not dc_table then
    return nil, "failed parsing declarative configuration file " ..
        filename .. (err and ": " .. err or "")
  end

  local ok, err = self.schema:validate(dc_table)
  if not ok then
    return nil, err
  end

  local entries, err = self.schema:flatten(dc_table)
  if err then
    return nil, err
  end

  return entries
end


return declarative
