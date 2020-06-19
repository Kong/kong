local SKey_Meta = {}


function SKey_Meta:select_existing_active()
  local rows, err = self.strategy:select_existing_active()
  if err then
    return nil, err
  end

  assert(#rows == 1 or #rows == 0)

  return rows[1]
end


function SKey_Meta:activate(id)
  return self.strategy:activate(id)
end


return SKey_Meta
