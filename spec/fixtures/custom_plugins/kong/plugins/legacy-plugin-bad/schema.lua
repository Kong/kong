-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
