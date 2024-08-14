-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = {
  AUTH_TYPE_CLIENT_SECRET_POST  = "client_secret_post",
  AUTH_TYPE_CLIENT_SECRET_BASIC = "client_secret_basic",
  AUTH_TYPE_CLIENT_SECRET_JWT   = "client_secret_jwt",
  AUTH_TYPE_NONE                = "none",

  GRANT_TYPE_CLIENT_CREDENTIALS = "client_credentials",
  GRANT_TYPE_PASSWORD           = "password",

  JWT_ALG_HS512                 = "HS512",
  JWT_ALG_HS256                 = "HS256",
}

constants.AUTH_TYPES = {
  constants.AUTH_TYPE_CLIENT_SECRET_POST,
  constants.AUTH_TYPE_CLIENT_SECRET_BASIC,
  constants.AUTH_TYPE_CLIENT_SECRET_JWT,
  constants.AUTH_TYPE_NONE
}

constants.GRANT_TYPES = {
  constants.GRANT_TYPE_CLIENT_CREDENTIALS,
  constants.GRANT_TYPE_PASSWORD,
}

constants.CLIENT_SECRET_JWT_ALGS = {
  constants.JWT_ALG_HS512,
  constants.JWT_ALG_HS256,
}

return constants
