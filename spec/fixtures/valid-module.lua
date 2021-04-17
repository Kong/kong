-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Valid module (exposing data and having a global variable) for utils.load_module_if_exists unit tests.
-- Assert that load_module_if_exists returns a module if it was valid

local _M = {
  exposed = "All your base are belong to us."
}

return _M
