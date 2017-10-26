local escape_uri  = ngx.escape_uri
local tonumber    = tonumber
local concat      = table.concat
local null        = ngx.null


local Endpoints = {}


function Endpoints.new(schema)
  local name = schema.name
  local self = {
    ["/" .. name] = {
      GET = function(self, db, helpers)
        local data, _, err_t, offset = db[name]:page(
          tonumber(self.params.size) or self.params.size,
          self.params.offset)

        if err_t then
          return helpers.yield_error(err_t)
        end

        local next_page = offset and concat {
          "/" .. name .. "?offset=" .. escape_uri(offset)
        } or null

        return helpers.responses.send_HTTP_OK{
          data   = data,
          offset = offset,
          next   = next_page,
        }

      end,

      POST = function(self, db, helpers)
        local data, _, err_t = db[name]:insert(self.params)
        if err_t then
          return helpers.yield_error(err_t)
        end

        return helpers.responses.send_HTTP_CREATED(data)
      end
    },

    ["/" .. name .. "/:id"] = {
      GET = function(self, db, helpers)
        -- TODO: composite key support
        local pk = { id = self.params.id }
        local entity, _, err_t = db[name]:select(pk)
        if err_t then
          return helpers.yield_error(err_t)
        end

        if entity then
          return helpers.responses.send_HTTP_OK(entity)
        end

        return helpers.responses.send_HTTP_NOT_FOUND()
      end,

      PATCH = function(self, db, helpers)
        -- TODO: composite key support
        local pk = { id = self.params.id }
        local updated_entity, _, err_t = db[name]:update(pk, self.params)
        if err_t then
          return helpers.yield_error(err_t)
        end

        return helpers.responses.send_HTTP_OK(updated_entity)
      end,

      DELETE = function(self, db, helpers)
        -- TODO: composite key support
        local pk = { id = self.params.id }
        local _, _, err_t = db[name]:delete(pk)
        if err_t then
          return helpers.yield_error(err_t)
        end

        return helpers.responses.send_HTTP_NO_CONTENT()
      end
    },
  }

  for field_name, field in schema:each_field() do
    if field.type == "foreign" then
      local schema_name = field.schema.name
      self["/" .. schema_name .. "/:id/" .. name] = {
        GET = function(self, db, helpers)
          -- TODO: composite key support
          local fk = { id = self.params.id }
          local entity = db[name]

          local rows, _, err_t, offset = entity["for_" .. field_name](
            entity,
            fk,
            tonumber(self.params.size) or self.params.size,
            self.params.offset)

          if err_t then
            return helpers.yield_error(err_t)
          end

          local next_page = offset and concat {
            "/", schema_name, "/", escape_uri(self.params.id), "/", name,
            "?offset=", escape_uri(offset)
          } or null

          return helpers.responses.send_HTTP_OK{
            data   = rows,
            offset = offset,
            next   = next_page,
          }
        end,
      }
    end
  end

  return self
end


return Endpoints
