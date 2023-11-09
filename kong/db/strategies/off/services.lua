local null = ngx.null
local tb_insert = table.insert

local Services = {}

function Services:select_by_ca_certificate(ca_id, limit)
  local PAGE_SIZE = 100
  local next_offset = nil
  local rows, err
  local matches = {}
  local count = 0
  local options = { workspace = null }

  repeat
    rows, err, next_offset = self:page(PAGE_SIZE, next_offset, options)
    if err then
      return nil, err
    end
    for _, row in ipairs(rows) do
      if limit and count >= limit then
        return matches, nil
      end

      if type(row.ca_certificates) == 'table' then
        for _, id in ipairs(row.ca_certificates) do
          if id == ca_id then
            tb_insert(matches, row)
            count = count + 1
            goto continue
          end
        end
      end

      ::continue::
    end

  until next_offset == nil

  return matches, nil
end

return Services
