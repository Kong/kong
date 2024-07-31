-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "jwt_signer_jwks" ALTER COLUMN "keys" SET DATA TYPE JSONB[] USING
          (ARRAY[keys->0,  keys->1,  keys->2,  keys->3,  keys->4,  keys->5,  keys->6,  keys->7,  keys->8,  keys->9,
                 keys->10, keys->11, keys->12, keys->13, keys->14, keys->15, keys->16, keys->17, keys->18, keys->19,
                 keys->20, keys->21, keys->22, keys->23, keys->24, keys->25, keys->26, keys->27, keys->28, keys->29,
                 keys->30, keys->31, keys->32, keys->33, keys->34, keys->35, keys->36, keys->37, keys->38, keys->39,
                 keys->40, keys->41, keys->42, keys->43, keys->44, keys->45, keys->46, keys->47, keys->48, keys->49
              ])[0:(JSONB_ARRAY_LENGTH(keys))]::jsonb[];
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_FUNCTION THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "jwt_signer_jwks" ALTER COLUMN "previous" SET DATA TYPE JSONB[] USING
          (ARRAY[previous->0,  previous->1,  previous->2,  previous->3,  previous->4,
                 previous->5,  previous->6,  previous->7,  previous->8,  previous->9,
                 previous->10, previous->11, previous->12, previous->13, previous->14,
                 previous->15, previous->16, previous->17, previous->18, previous->19,
                 previous->20, previous->21, previous->22, previous->23, previous->24,
                 previous->25, previous->26, previous->27, previous->28, previous->29,
                 previous->30, previous->31, previous->32, previous->33, previous->34,
                 previous->35, previous->36, previous->37, previous->38, previous->39,
                 previous->40, previous->41, previous->42, previous->43, previous->44,
                 previous->45, previous->46, previous->47, previous->48, previous->49
              ])[0:(JSONB_ARRAY_LENGTH(previous))]::jsonb[];
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_FUNCTION THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
  },
}
