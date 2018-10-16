local string_array = {
  type = "array",
  default = {},
  elements = { type = "string" },
}


local colon_string_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$" },
}



local string_record = {
  type = "record",
  fields = {
    { json = string_array },
    { headers = string_array },
  },
}


local colon_string_record = {
  type = "record",
  fields = {
    { json = colon_string_array },
    { headers = colon_string_array },
  },
}


return {
  name = "response-transformer",
  fields = {
    { config = {
        type = "record",
        fields = {
          { remove = string_record },
          { replace = colon_string_record },
          { add = colon_string_record },
          { append = colon_string_record },
        },
      },
    },
  },
}

