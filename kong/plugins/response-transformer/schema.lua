return {
  fields = {
    -- add: Add a value (to response headers or response JSON body) only if the key does not already exist.
    remove = { 
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}},
          headers = {type = "array", default = {}}
        }
      }
    },
    replace = {
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}},
          headers = {type = "array", default = {}}
        }
      }
    },
    add = {
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}},
          headers = {type = "array", default = {}}
        }
      }
    },
    append = { 
      type = "table", 
      schema = {
        fields = {
          json = {type = "array", default = {}},
          headers = {type = "array", default = {}}
        }
      }
    }
  }
}
