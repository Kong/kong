-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Invalid module (syntax error) for utils.load_module_if_exists unit tests.
-- Assert that load_module_if_exists throws an error helps for development, where one could
-- be confused as to the reason why his or her plugin doesn't load. (not implemented or has an error)

local a = "hello",
