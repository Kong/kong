-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local client_jwk = {
  p =
  "2OZf9JxDwXpXLokSpjFq81XZfrG1_cSqzi-ZMzbiqpVKdBYhZ77SfV2xsgK7kAxo_4Jh0Bh3MFt9NvYll8pE6VBDVPRLmAIcv7-UMkSVbUnRdltT5ElROViTy57iJO3BlzOiFHENhA_DnQrDRVtLuPFyMZVYHXuWWTfJveXh2xU",
  kty = "RSA",
  q =
  "sC8S3S-rKb2GFzfmSNDw5thy-2sLWMKPPWloN5jIWqHB2OumYzzUR_2TLkrf4SBQ-69qbfamoce8El_ipRnBbJRzd-qO8kjgRgK9_v_trxmcDiqb__Mivyu2J0a2-13VyS12tFAM9DVfewcR10V_bNsxV15WaMNmqslpHuHyPkk",
  d =
  "QRes9v86K0SMfBLLalyDMR5BUdI8uF_e6vmYCU9i7kYkGMGdwEVy9ZJ5Zz8EptbUuUpH3lCnstEyCZJ92CFieGAiw95S9BQNqKYaQJi2vnWopPHExDmNy6p2opSzaskBh0UlgVfQ_9bCHaXC-L-63lg1vqm3Lb2vGhqfKCJ_n1O8Y078l2Bp1zf8t3kAT7yix7qvO7HO_8JcWXecMpnZp2BYvUTUC5x58UGz30JzIuhsZqEGjiYInSJ5NyUuiC5sYrSW87ClsmrsM3QtieEekceqdCPimIcNyL6hetQ_sEeAVNsX7Pr1Ptf68cLmFf5SygLsqPZn4QUzOhmX5IHPQQ",
  e = "AQAB",
  use = "sig",
  kid = "test",
  qi =
  "jZMzMywer5cauHZSdSa0bUBh1pm3Xs3-hGYz87He9at8rgwJOrbExn3gnt7j0YOqgbto3hRa5c15dW5zijElhLxlOfYm3Mx8iqjx6wZwCzgh0_gcGg0K2z9NyFo5jr9cx4ADFPQbeBg1nJuSDCSM4dKZDRIoea67ZOlD0nVX31U",
  dp =
  "1WUidujfCJWy_IfDn1rzXGDUUP_Ki9dYLO9LjMWtECM9UyUKzKVDNjBeSULDAiATlX7TeQb5DMyWTuKxbbuFPP7In-aSEQXS_xwfU62CTjnYKNgFm44-qWrqTeUNnUOFuZsFFZN8trdDv1f9clk2EMkLjpjeTnNvImvuwjRPl1k",
  alg = "RS512",
  dq =
  "V2pz3KUbMvGjR3_n1bc93_wDSPW6woZ-VcUn_XXj6vwZV0zM2K5E0ZdiYHSsEmJbbBWEJB1eXiThDujeZnaZ_wrFI_mQhWxdQr93j79iKh_1yx2fG2aClgHVNjWi8qODQHc7T4nsc3rL7hn64ynLaLJ1D9lx3DcfiJu4eac372k",
  n =
  "lUZEP2Nan3nFork1tElu5V8-pwsvMibfAau3ADpM6OqBF4n08eSeHeWC2uZltQkLKaU_n-dm0INUv72QDJsaZ-ZNCc9LST_HNoQQ5qPH86RDPmMEus_OdKJ7V57gxJzWonwzJ3sDdGW1QjK1Hb8kHnwM46uPoHHF_Iottc6oUXIiXQ18hTFFsKtpeSUl6PsA76j3pvxOLPFhJPtgZ2p9WhwDmiav6oK4XXgyhxolkF7kBVNSIqZrGI4_KAuxVpZiX3t-4pzHV4Rh6_YBmA9OgdVJ3WfKjGiPpz8YA4PmhXPND2nFXm4_GUWm3_QIhD1Cyk6jO8RRUUEZI59Xz1CO_Q"
}

local client_jwk_public = {
  kty = "RSA",
  e = "AQAB",
  use = "sig",
  kid = "test",
  alg = "RS512",
  n =
  "lUZEP2Nan3nFork1tElu5V8-pwsvMibfAau3ADpM6OqBF4n08eSeHeWC2uZltQkLKaU_n-dm0INUv72QDJsaZ-ZNCc9LST_HNoQQ5qPH86RDPmMEus_OdKJ7V57gxJzWonwzJ3sDdGW1QjK1Hb8kHnwM46uPoHHF_Iottc6oUXIiXQ18hTFFsKtpeSUl6PsA76j3pvxOLPFhJPtgZ2p9WhwDmiav6oK4XXgyhxolkF7kBVNSIqZrGI4_KAuxVpZiX3t-4pzHV4Rh6_YBmA9OgdVJ3WfKjGiPpz8YA4PmhXPND2nFXm4_GUWm3_QIhD1Cyk6jO8RRUUEZI59Xz1CO_Q"
}

local client2_jwk = {
  p = "0uCA8VaL5xxR8G2eFCo1ZfigXEDWS8IjWhB0jrIFsruRSEOo5ZvPq6AK23pI3-QwG05IZTyPegsJL_VXKiPzBXiPxCn1C_nlJY0EjYAdzPhQVub3Jv820cPIXWhgzCVmX1eU_gX1uU7BksHHViIPqQ180huyes4eDP0LVz2sisk",
  kty = "RSA",
  q = "ymSY6f7peJTh3i_IfQdoymrhuFT3PB6EOjDCEtaiKUfzC4iy4Sj4zlCAm4hvoo1O9Bl_qeGRVsFFz47JD66Kd1S0fJV-5ZmyroKy0h1vcwNudUWdNZlplQfg22I3GgNeWzte_xFF7kyv49BFkPPZ9VyAfDSdzN4ngv-JLkaFz1c",
  d = "nR5APnZezsNHk9kbHeq1Who_YQPikMlqNI39bEbTWq_eSsAkpgSIMQv8r_w76_9jL2ilYu26arWxi4ReEa8HvbIc9VxLRO392zw6JdPrNBVfWRw5YFkBf5V3_5B8VDjzmuUNpZHR6H92MhLJ7P3kqd6kIb9fJLFZlqkKQs-XPtfI4eTNfsuSkDLqaxGs6dRSc7za6wqnajJUuX0ThwEGRUjBEdx5fzCJH5_8-Y4DMb7qmgM24nNR9pHqhmSDJFDUSuqRNZEyZD-9wnl-A2rXMakNknll-4WkjlcccqzDSMoHpCyXkn5fduMrHuBSBqsIIWJCIVnwuSaOjCh8nlwBkQ",
  e = "AQAB",
  use = "sig",
  kid = "test2",
  qi = "RN8D_k4J2bx247FKfLsabNBczUDKE2YlJSru2viQJzy9doEPAd0WCMQ2da5xc3JubHmnnfpUWMcl4bcOOVlMSEIu57NSqy1N3xY52m_OztfceRc4R1Ri1i79mX17w2cFDGiE7HIQtWEmCw8ijN1-7JzJq1StkhtHgTFPGTXI2FE",
  dp = "C8HkrpAKwNn9X5BdDfbEf2j7V-ltiU_LtMvSE9qtIqf-k67iDdtAGuuTb2VEBuesHvmgY7Sas01GN9xP_dN_S0DLkz5boU1Pj2ZraJBKGRGHOTEreoskPVHTLBITw44aRRqW_grLBofzlwEi4hSIFv7fhL9ylhJD7ql1JmoT4rE",
  alg = "RS512",
  dq = "CKTZPw0rDYJWTzX9OxHI8PQ1pbjDQmcPQKj6cPGHxXmUMMbq1OD6F12q0Hm4QtoEKDq6kBfZLDpe7-lqPug2c7hDaRq9a7LvxbJBTuYA74mS-yE5AKQHtVy7xsLgFZVVP1I-0Wf8c5wE2xb3EaTIh0knF6bromdOirK9OiO67Us",
  n = "prgDZtlv66YmFnnyPkWbJFYi_Ozz2qmyAod4loa_lzsbGP3Db4wziSAs8mmrSbjYfX1U-OvIYKiykPiIim1F7EUQjF4GZX8luCUPmO8MLoqC2PMIXvGyBU84I2pz0a6ipxDs_5IkXDRNjHhEieyVfxVKz_8CSLphMohlJqRelGFtGMp89zu5ZQix1CA3UpMnAlQg_peDMob81VeYYus8S92moL110V8JPsiv7Ao4eQ6aUyS0dJZGW9dMckDaNz5kf9XppeKFP3X_d6mdUeDODRSH-O4bxA8mGR1tPWDXrelXn86r1969JSJtvwpsc3qwSueORH4hgu2A2B85ikixTw"
}

local client2_jwk_public = {
  kty = "RSA",
  e = "AQAB",
  use = "sig",
  kid = "test2",
  alg = "RS512",
  n = "prgDZtlv66YmFnnyPkWbJFYi_Ozz2qmyAod4loa_lzsbGP3Db4wziSAs8mmrSbjYfX1U-OvIYKiykPiIim1F7EUQjF4GZX8luCUPmO8MLoqC2PMIXvGyBU84I2pz0a6ipxDs_5IkXDRNjHhEieyVfxVKz_8CSLphMohlJqRelGFtGMp89zu5ZQix1CA3UpMnAlQg_peDMob81VeYYus8S92moL110V8JPsiv7Ao4eQ6aUyS0dJZGW9dMckDaNz5kf9XppeKFP3X_d6mdUeDODRSH-O4bxA8mGR1tPWDXrelXn86r1969JSJtvwpsc3qwSueORH4hgu2A2B85ikixTw"
}

return {
  client_jwk = client_jwk,
  client_jwk_public = client_jwk_public,
  client2_jwk = client2_jwk,
  client2_jwk_public = client2_jwk_public,
}
