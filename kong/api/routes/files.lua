return {
  ["/files"] = {
    -- List all files stored in the portal file system
    GET = function(self, db, _, parent)
      if not self.args.uri.size then
        self.args.uri.size = 100
      end

      return parent()
    end,
  },
}
