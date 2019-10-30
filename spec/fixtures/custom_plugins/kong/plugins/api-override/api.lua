local kong = kong


return {
  ["/routes"] = {
    schema = kong.db.routes.schema,
    GET = function(_, _, _, parent)
      kong.response.set_header("Kong-Api-Override", "ok")
      return parent()
    end,
    POST = function(_, _, _, parent)
      kong.response.set_header("Kong-Api-Override", "ok")
      return parent()
    end,
  },
}
