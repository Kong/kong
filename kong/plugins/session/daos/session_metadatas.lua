local session_metadatas = {}

function session_metadatas:select_by_audience_and_subject(audience, subject)
  return self.strategy:select_by_audience_and_subject(audience, subject)
end

function session_metadatas:select_by_sid(sid)
  local cache_key = kong.db.sessions:cache_key(sid)
  local session = kong.cache:get(cache_key) or {}

  local res = {}
  for row in kong.db.session_metadatas:each_for_session({ id = session.id }) do
    table.insert(res, row)
  end
  return res
end

return session_metadatas
