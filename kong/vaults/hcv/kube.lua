-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

----
-- This file exists to provide interface methods for Kubernetes operations.
-- It should be moved to its own utils package ASAP.
----


local pl_file = require "pl.file"


local function get_service_account_token(token_file)
  -- return the kubernetes service account jwt or err
  return pl_file.read(token_file or "/run/secrets/kubernetes.io/serviceaccount/token")
end


return {
  get_service_account_token = get_service_account_token,
}
