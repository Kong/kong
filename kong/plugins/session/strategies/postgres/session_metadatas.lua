local fmt = string.format

local session_metadatas = {}

function session_metadatas:select_by_audience_and_subject(audience, subject)
  local qs = fmt(
    "SELECT * FROM session_metadatas WHERE audience = %s AND subject = %s;",
    kong.db.connector:escape_literal(audience),
    kong.db.connector:escape_literal(subject))

  return kong.db.connector:query(qs, "read")
end

function session_metadatas:select_by_sid(sid)
  local qs = fmt(
    "SELECT * FROM session_metadatas WHERE sid = %s;",
    kong.db.connector:escape_literal(sid))

  return kong.db.connector:query(qs, "read")
end

return session_metadatas
