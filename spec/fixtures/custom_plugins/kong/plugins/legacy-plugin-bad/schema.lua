-- regression test from #4392

return {
  no_consumer = true,
  fields = {
    foo = {
      -- an underspecified table with no 'schema' will default
      -- to a map of string to string
      type = "table",
      required = false,
      -- this default will not match that default
      default = {
        foo = 123,
        bar = "bla",
      }
    }
  },
  self_check = function()
    return true
  end
}
