return {
  fields = {
    add = { type = "table", schema = {
        fields = {
          json = { type = "array" },
          headers = { type = "array" }
        }
      }
    },
    remove = { type = "table", schema = {
        fields = {
          json = { type = "array" },
          headers = { type = "array" }
        }
      }
    }
  }
}
