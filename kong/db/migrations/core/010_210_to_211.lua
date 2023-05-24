-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- this migration is empty and makes little sense
-- it contained a Cassandra specific migration at one point
-- this is left as is to not mess up existing migrations in installations worldwide
-- see commit 8a214df628b3c754b1446e94f98eeb7609942761 for history
return {
  postgres = {
    up = [[ SELECT 1 ]],
  },
}
