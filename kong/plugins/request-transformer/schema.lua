return {
  fields = {
    remove = {
      type = "table",
      schema = {
        fields = {
          form = {type = "array", default = {}},
          headers = {type = "array", default = {}},
          querystring = {type = "array", default = {}}
        }
      }
    },
    replace = {
      type = "table",
      schema = {
        fields = {
          form = {type = "array", default = {}},
          headers = {type = "array", default = {}},
          querystring = {type = "array", default = {}}
        }
      }
    },
    add = {
      type = "table",
      schema = {
        fields = {
          form = {type = "array", default = {}},
          headers = {type = "array", default = {}},
          querystring = {type = "array", default = {}}
        }
      }
    },
    append = {
      type = "table",
      schema = {
        fields = {
          headers = {type = "array", default = {}},
          querystring = {type = "array", default = {}}
        }
      }
    }
  }
}
