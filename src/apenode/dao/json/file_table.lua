-- Copyright (C) Mashape, Inc.

local utils = require "apenode.core.utils"
local cjson = require "cjson"
local file_path = configuration.dao.properties.file_path

local _M = {}

function _M.init(collection_name)

  local json = load_file()
  local collection = json[collection_name]
  if not collection then
    json[collection_name] = {}
    utils.write_to_file(file_path, cjson.encode(json))
  end

  local t = {}

  -- create metatable
  local mt = {
    __index = function (t,k)
      local json = load_file()
      local collection = json[collection_name]

      if k then
        return collection[k]
      else
        local result = {}
        for k,v in pairs(collection) do
          table.insert(result, v)
        end
        return result
      end
    end,

    __newindex = function (t,k,v)
      local json = load_file()
      local collection = json[collection_name]

      collection[k] = v

      json[collection_name] = collection
      utils.write_to_file(file_path, cjson.encode(json))
    end
  }
  setmetatable(t, mt)

  return t
end

function load_file()
  return cjson.decode(read_file())
end

function read_file()
  local contents = utils.read_file(file_path)
  if not contents or contents == "" then
    contents = "{}"
  end
  return contents
end

return _M
