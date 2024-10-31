-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  ["/method_without_exit"] = {
    GET = function()
      kong.response.set_status(201)
      kong.response.set_header("x-foo", "bar")
      ngx.print("hello")
    end,
  },
  ["/parsed_params"] = {
    -- The purpose of the dummy filter is to let `parse_params`
    -- of api/api_helpers.lua to be called twice.
    before = function(self, db, helpers, parent)
    end,

    POST = function(self, db, helpers, parent)
      kong.response.exit(200, self.params)
    end,
  },
}
