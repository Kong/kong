local SKey_Meta = {}


function SKey_Meta:select_existing_active()
  local query = "SELECT id FROM keyring_meta_active"

  return self.connector:query(query)
end


function SKey_Meta:insert(entity)
  local query = [[
    INSERT INTO keyring_meta(id, created_at) VALUES('%s', %s) IF NOT EXISTS
  ]]

  return self.connector:query(
    string.format(query, entity.id, entity.created_at),
    nil,
    nil,
    "write"
  )
end


function SKey_Meta:activate(id)
  local query = [[
    INSERT INTO keyring_meta_active (active, id) VALUES ('active', '%s')
  ]]

  return self.connector:query(
    string.format(query, id),
    nil,
    nil,
    "write"
  )
end


return SKey_Meta
