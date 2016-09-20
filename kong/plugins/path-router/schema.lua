return {
  fields = {
    querystring = { 
      mappings = {
        type = "table",
        name = {type = "string", required = true},
        value = {type = "string", required = true},
        forward_path = {type = "string", required = true},
        strip = {type="boolean"}
      }
    }
  }
}
