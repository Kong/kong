-- Helper module for 210_to_211 migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.
local re_match = ngx.re.match


local core_entities_to_clean = {
  { name = "upstreams", unique_keys = { "name" } },
  { name = "consumers", unique_keys = { "username", "custom_id" } },
  { name = "services",  unique_keys = { "name" }, partitioned = true, },
  { name = "routes",    unique_keys = { "name" }, partitioned = true, },
}


local function render(template, keys)
  return (template:gsub("$%(([A-Z_]+)%)", keys))
end


-- check if a field has been migrated with spurious values
local function should_clean(value)
  local regex = [==[[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\:\$\(VALUE\)]==]
  local m, err = re_match(value, regex, "aijo")
  if err then
    return nil, err
  end

  return m ~= nil
end


-- clean Cassandra fields that should not have been migrated
local function clean_cassandra_fields(connector, entities)
  local coordinator = assert(connector:connect_migrations())

  for _, entity in ipairs(entities) do
    for rows, err in coordinator:iterate("SELECT * FROM " .. entity.name) do
      if err then
        return nil, err
      end

      for i = 1, #rows do
        local row = rows[i]
        local set_list = {}
        for _, key in ipairs(entity.unique_keys) do
          if row[key] and should_clean(row[key]) then
            table.insert(set_list, render([[$(KEY) = null]], {
              KEY = key,
            }))
          end
        end

        if #set_list > 0 then
          local cql = render("UPDATE $(TABLE) SET $(SET_LIST) WHERE $(PARTITION) id = $(ID)", {
            PARTITION = entity.partitioned
                        and "partition = '" .. entity.name .. "' AND"
                        or  "",
            TABLE = entity.name,
            SET_LIST = table.concat(set_list, ", "),
            ID = row.id,
          })

          local _, err = coordinator:execute(cql)
          if err then
            return nil, err
          end
        end

      end
    end
  end

  return true
end


--------------------------------------------------------------------------------


return {
  entities = core_entities_to_clean,
  clean_cassandra_fields = clean_cassandra_fields,
}
