local type    = type
local ipairs  = ipairs
local assert  = assert

local Plugins = {}

function Plugins:select_by_ca_certificate(ca_id, limit, plugin_names)
  -- parameter pre-checking
  local typ = type(ca_id)
  if typ ~= "string" then
    error("the arg#1 `ca_id` is invalid")
  end

  if limit then
    typ = type(limit)
    if typ ~= "number" then
      error("the arg#2 `limit` is invalid")
    end
  end

  typ = type(plugin_names)
  if typ ~= "nil" and typ ~= "string" and typ ~= "table" then
    error("the arg#3 `plugin_names` is invalid")
  end

  --[[
    {
      ...
      [<plugin_name>] = true,
      [<plugin_name>] = true,
      ...
    }
  --]]
  local include_all_plugs = false
  local included_plugs = nil
  if plugin_names == nil then
    include_all_plugs = true

  elseif typ == "string" then
    included_plugs = {
      [plugin_names] = true
    }

  else
    assert(typ == "table")
    included_plugs = {}
    for _, name in ipairs(plugin_names) do
      included_plugs[name] = true
    end
  end

  local PAGE_SIZE = 100
  local next_offset = nil
  local rows, err
  local matches_n = 0
  local matches = {}

  -- this is an O(n) operations, which might be slow for huge plugin list.
  --
  -- For `plugin_names == nil` the postgres DAO is also O(n)
  -- so we didn't make it worse than postgres DAO.
  --
  -- Otherwise, the postgres DAO is O(lgn) as the `name` column was indexed by
  -- btree. However, this function will only be used by the
  -- `ca_certificates` CRUD events, which should be a
  -- low frequency operation, so the current impl should be ok.
  repeat
    rows, err, next_offset = self:page(PAGE_SIZE, next_offset)
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      -- the `config` field is not nullable in table constraints,
      -- so it should not be `nil` or `ngx.null`.
      assert(type(row.config) == "table")

      local ca_certs = row.config.ca_certificates
      if type(ca_certs) ~= "table" then
        -- skip `nil` and `ngx.null`
        goto continue
      end

      if not include_all_plugs then
        assert(type(included_plugs) == "table")

        if not included_plugs[row.name] then
          goto continue
        end

      else
        assert(included_plugs == nil)
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

      if limit and matches_n >= limit then
        break
      end

      ::continue::
    end

  until next_offset == nil

  return matches, nil
end

return Plugins
