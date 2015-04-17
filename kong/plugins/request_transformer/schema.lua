local constants = require "kong.constants"

return {
  add = { require = "false", type = "table", schema = {
      form = { required = false, type = "table" },
      headers = { required = false, type = "table" },
      querystring = { required = false, type = "table" }
    }
  },
  remove = { require = "false", type = "table", schema = {
      form = { required = false, type = "table" },
      headers = { required = false, type = "table" },
      querystring = { required = false, type = "table" }
    }
  }
}