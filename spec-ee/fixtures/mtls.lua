-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- hash == hh_XBSxIT3qG46n5igJA0MsFEgXosYoWvzeRZfRCknY
local CLIENT_CERT = [[
-----BEGIN CERTIFICATE-----
MIICvjCCAaYCFHYzBjKWczsVgX/S8QMBtuG63E7/MA0GCSqGSIb3DQEBCwUAMCYx
JDAiBgNVBAMMG2ludGVybWVkaWF0ZS55b3VyZG9tYWluLmNvbTAgFw0yMzA5Mjcw
ODQ2MDNaGA8yMTIzMDkwMzA4NDYwM1owDzENMAsGA1UEAwwEa29uZzCCASIwDQYJ
KoZIhvcNAQEBBQADggEPADCCAQoCggEBALkDb0lH8uUUfiiFF24mO7Wg7oAWULOt
HnoK/WIesO1qzfPZrEGfUghPZKhfYfJBAjhzAEr0TkXxXJIk7p1v3GScJUpvSRtU
8kCKqp+HuF1psSuULyuYnTDI5wuXOBKOss2RU3xWdFz2Mug6LbsZ0g5AYxk88saD
tM0OhV02F4kRipLtnKst5NR17SeJtdskvgyV1BCsXvveCs0t5I1fykyvwbpNhzv6
V1UPHDq506H9VaT0SZ6mJu202KNeStibm13cmXlVMYP5V3raN1f4ZlKAuf6cp7Pv
bzP5K8dOjc9fTOf3m2ryjlGL1SsoK4Z2qBjm8a7m61Z0l6qy/w4RqicCAwEAATAN
BgkqhkiG9w0BAQsFAAOCAQEADAZlkXFXaSj3NK9MGtRlP6la05/sVGGbEHG3JeYd
d2TjQDVJCgY3eceP2fxpwKxzQdOzPd4EfbhDbpOYqV5+cZdlZBYX/Yz0lBOknTTS
5ywSPq/rnU6FSGdnHxY+Edkz+oKiu3ADOMdatZ1pPyFslGTsY48/bj5/+jlnTx2u
yfuX1qRM2B/YFv1P4NkTjEgjbFM7J313RBGkVws+TN6HwEQS8a6FpNt1JdHrhj8O
+jqcl6m9M4/KysxCladGVo6WTMVr3Yq2m+J3rYkaJkK5w16gMaYvx2iDVr/aaAUB
EjkqX1fpGhhkqsLSggd1CZsLyOAlQ6b/q+JBeeyY0SD08w==
-----END CERTIFICATE-----
]]

-- "x5t#S256": "hh_XBSxIT3qG46n5igJA0MsFEgXosYoWvzeRZfRCknY"
local CERT_ACCESS_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI" ..
"xMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJjbmYiOnsie" ..
"DV0I1MyNTYiOiJoaF9YQlN4SVQzcUc0Nm41aWdKQTBNc0ZFZ1hvc1lvV3Z6ZVJaZlJDa25ZIn1" ..
"9.huU_oO4QCv13bVnV31L7P1bz60wVOiPsMn_e8KSN7S0"

-- "x5t#S256": "hh_XBSxIT3qG46n5igJA0MsFEgXosYoWvzeRZfRCknZ"
local WRONG_CERT_ACCESS_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzd" ..
"WIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJjbmY" ..
"iOnsieDV0I1MyNTYiOiJoaF9YQlN4SVQzcUc0Nm41aWdKQTBNc0ZFZ1hvc1lvV3Z6ZVJaZlJDa" ..
"25aIn19.NhJmrrhQyXxzQ0hGxwxjLgXpKbPx1oTjJwmlRcsX7KE"

local NO_CERT_ACCESS_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIi" ..
"OiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwR" ..
"JSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

local CERT_INTROSPECTION_DATA = {
  active = true,
  aud = { "kong" },
  client_id = "kong",
  cnf = {
    ["x5t#S256"] = "hh_XBSxIT3qG46n5igJA0MsFEgXosYoWvzeRZfRCknY",
  },
  sub = "kong",
  token_type = "access_token",
}

local WRONG_CERT_INTROSPECTION_DATA = {
  active = true,
  aud = { "kong" },
  client_id = "kong",
  cnf = {
    ["x5t#S256"] = "hh_XBSxIT3qG46n5igJA0MsFEgXosYoWvzeRZfRCknZ",
  },
  sub = "kong",
  token_type = "access_token",
}

local NO_CERT_INTROSPECTION_DATA = {
  active = true,
  aud = { "kong" },
  client_id = "kong",
  sub = "kong",
  token_type = "access_token",
}


return {
  CLIENT_CERT = CLIENT_CERT,
  CERT_ACCESS_TOKEN = CERT_ACCESS_TOKEN,
  WRONG_CERT_ACCESS_TOKEN = WRONG_CERT_ACCESS_TOKEN,
  NO_CERT_ACCESS_TOKEN = NO_CERT_ACCESS_TOKEN,
  CERT_INTROSPECTION_DATA = CERT_INTROSPECTION_DATA,
  WRONG_CERT_INTROSPECTION_DATA = WRONG_CERT_INTROSPECTION_DATA,
  NO_CERT_INTROSPECTION_DATA = NO_CERT_INTROSPECTION_DATA,
}
