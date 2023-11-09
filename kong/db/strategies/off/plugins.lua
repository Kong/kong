local null = ngx.null

local Plugins = {}

function Plugins:select_by_ca_certificate(ca_id, limit, plugin_names)
  local PAGE_SIZE = 100
  local next_offset = nil
  local rows, err
  local matches = {}
  local count = 0
  local options = { workspace = null }

  if type(plugin_names) == string then
    plugin_names = { [plugin_names] = true }
  end

  repeat
    rows, err, next_offset = self:page(PAGE_SIZE, next_offset, options)
    if err then
      return nil, err
    end
    for _, row in ipairs(rows) do
      if limit and count >= limit then
        return matches, nil
      end

      if (not plugin_names or plugin_names[row.name]) and
        type(row.config) == 'table' and type(row.config.ca_certificates) == "table" then
        for _, id in ipairs(row.config.ca_certificates) do
          if id == ca_id then
            table.insert(matches, row)
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

return Plugins
