local ipairs   = ipairs

local Services = {}

function Services:select_by_ca_certificate(ca_id, limit)
  -- parameter pre-checking
  local typ = type(ca_id)
  if typ ~= "string" then
    error("the arg#1 `ca_id` is invalid")
  end

  typ = type(limit)
  if typ ~= "number" then
    error("the arg#2 `limit` is invalid")
  end

  local PAGE_SIZE = 100
  local next_offset = nil
  local rows, err
  local matches_n = 0
  local matches = {}

  -- this is an O(n) operations, which might be slow for huge service list.
  -- However, the postgres DAO is also an O(n) SQL, so we didn't make it
  -- worse than postgres DAO.
  repeat
    rows, err, next_offset = self:page(PAGE_SIZE, next_offset)
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      local ca_certs = row.ca_certificates
      if type(ca_certs) ~= "table" then
        -- skip `nil` and `ngx.null`
        goto continue
      end

      -- is there any service associated ca_certificate's id
      -- equals to `ca_id`?
      for _, ca_cert_id in ipairs(ca_certs) do
        if ca_cert_id == ca_id then
          matches_n = matches_n + 1
          matches[matches_n] = row
          break
        end
      end

      if matches_n >= limit then
        break
      end

      ::continue::
    end

  until next_offset == nil

  return matches, nil
end

return Services
