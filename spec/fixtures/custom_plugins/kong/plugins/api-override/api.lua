-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong


return {
  ["/routes"] = {
    schema = kong.db.routes.schema,
    GET = function(_, _, _, parent)
      kong.response.set_header("Kong-Api-Override", "ok")
      return parent()
    end,
    POST = function(_, _, _, parent)
      kong.response.set_header("Kong-Api-Override", "ok")
      return parent()
    end,
  },
  ["/services"] = {
    schema = kong.db.services.schema,
    methods = {
      GET = function(_, _, _, parent)
        kong.response.set_header("Kong-Api-Override", "ok")
        return parent()
      end
    }
  }
}
