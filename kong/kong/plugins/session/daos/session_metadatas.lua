local session_metadatas = {}

function session_metadatas:select_by_audience_and_subject(audience, subject)
  return self.strategy:select_by_audience_and_subject(audience, subject)
end

return session_metadatas
