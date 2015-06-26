return {
  fields = {
    add = { type = "table",
    schema = {
      fields = {
        form = { type = "array" },
        headers = { type = "array" },
        querystring = { type = "array" }
      }
    }
    },
    remove = { type = "table",
      schema = {
        fields = {
          form = { type = "array" },
          headers = { type = "array" },
          querystring = { type = "array" }
        }
      }
    }
  }
}
