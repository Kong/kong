local rbac       = require "kong.rbac"
local Consumers = {}


function Consumers:page_by_type(db, size, offset, options)
  local rows, err_t, offset = self.strategy:page_by_type(options.type,
                                                         size or 100, offset,
                                                         options)
  if err_t then
    return rows, tostring(err_t), err_t
  end

  local entities, err
  entities, err, err_t = self:rows_to_entities(rows, options)
  if not entities then
    return nil, err, err_t
  end

  if not options or not options.skip_rbac then
    entities = rbac.narrow_readable_entities(self.schema.name, entities)
  end

  return entities, nil, nil, offset
end


return Consumers
