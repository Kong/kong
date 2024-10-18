-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jwt_signer_jwks = {}

function jwt_signer_jwks:page(_, size, offset, options)
  if kong.configuration.database == "off" then
    return self.strategy:page(size, offset, options)
  end

  return self.super.page(self, size, offset, options)
end

function jwt_signer_jwks:select_by_name(name, options)
  if kong.configuration.database == "off" then
    return self.strategy:select_by_name(name, options)
  end

  return self.super.select_by_name(self, name, options)
end

return jwt_signer_jwks
