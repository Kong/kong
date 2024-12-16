local session_metadatas = {}

function session_metadatas:select_by_audience_and_subject(audience, subject)
  return self.strategy:select_by_audience_and_subject(audience, subject)
end

function session_metadatas:select_by_sid(sid)
  return self.strategy:select_by_sid(sid)
end

return session_metadatas
