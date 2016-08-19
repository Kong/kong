local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"
local schemas_validation = require "kong.dao.schemas_validation"
local validate = schemas_validation.validate_entity

return setmetatable({}, {
  __call = function(_, schema)
    local Model_mt = {}
    Model_mt.__meta = {
      __schema = schema,
      __name = schema.name,
      __table = schema.table
    }

    function Model_mt.__index(self, key)
      if key and string.find(key, "__") == 1 then
        local meta_field = Model_mt.__meta[key]
        if meta_field then
          return meta_field
        end
      end

      return Model_mt[key]
    end

    function Model_mt:validate(opts)
      local ok, errors, self_check_err = validate(self, self.__schema, opts)
      if errors ~= nil then
        return nil, Errors.schema(errors)
      elseif self_check_err ~= nil then
        -- TODO: merge errors and self_check_err now that our errors handle this
        return nil, Errors.schema(self_check_err)
      end
      return ok
    end

    function Model_mt:extract_keys()
      local schema = self.__schema
      local primary_keys_idx = {}
      local primary_keys, values, nils = {}, {}, {}
      for _, key in pairs(schema.primary_key) do
        -- check for uuid here. not all dbs might have ids of type uuid however
        if schema.fields[key].type == "id" and not utils.is_valid_uuid(self[key]) then
          return nil, nil, nil, self[key].." is not a valid uuid"
        end
        primary_keys[key] = self[key]
        primary_keys_idx[key] = true
      end
      for col in pairs(schema.fields) do
        if not primary_keys_idx[col] then
          if self[col] ~= nil then
            values[col] = self[col]
          else
            nils[col] = true
          end
        end
      end
      return primary_keys, values, nils
    end

    function Model_mt:has_primary_keys()
      local schema = self.__schema
      for _, key in pairs(schema.primary_key) do
        if self[key] == nil then
          return false
        end
      end
      return true
    end

    return setmetatable({}, {
      __call = function(_, tbl)
        local m = {}
        for k,v in pairs(tbl) do
          m[k] = v
        end
        return setmetatable(m, Model_mt)
      end
    })
  end
})
