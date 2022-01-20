-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong

local _DocumentObjects = {}


function _DocumentObjects:insert(entity, options)
  -- ensure the file exists
  if entity.path then
    local document = kong.db.files:select_by_path(entity.path)
    if not document then
      return kong.response.exit(404, { message = "File at path "..entity.path.." not found" })
    end
  end

  local created, err, err_t = self.super.insert(self, entity, options)

  -- Currently not supporting multiple documents per service
  -- Deleting previously created ones to replace it with the new one (TDX-1620)
  if not err and not err_t and entity.service and entity.service.id then
    for row, err in kong.db.document_objects:each_for_service({ id = entity.service.id }) do
      if row and row.id ~= created.id then
        kong.db.document_objects:delete({ id = row.id })
      end
    end
  end

  return created, err, err_t
end

return _DocumentObjects