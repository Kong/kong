local fmt = string.format

local session_metadatas = {}

function session_metadatas:select_by_audience_and_subject(audience, subject)
  if type(audience) ~= "string" then
    error("audience must be string")
  end

  if type(subject) ~= "string" then
    error("subject must be string")
  end

  local qs = fmt(
    "SELECT * FROM session_metadatas WHERE audience = %s AND subject = %s;",
    kong.db.connector:escape_literal(audience),
    kong.db.connector:escape_literal(subject))

  return kong.db.connector:query(qs, "read")
end

return session_metadatas
