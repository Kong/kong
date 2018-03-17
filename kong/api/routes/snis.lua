return {
  -- deactivate endpoint (use /certificates/sni instead)
  ["/snis/:snis/certificate"] = {
    before = function(self, db, helpers)
      return helpers.responses.send_HTTP_NOT_FOUND()
    end
  },
}
