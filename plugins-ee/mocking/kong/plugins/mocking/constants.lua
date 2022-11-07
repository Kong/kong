-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = {
  DEFAULT_CONTENT_TYPE = "application/json; charset=utf-8",
  BEHAVIORAL_HEADER_NAMES = {
    delay = 'X-Kong-Mocking-Delay',
    example_id = 'X-Kong-Mocking-Example-Id',
    status_code = 'X-Kong-Mocking-Status-Code',
  }
}

return constants
