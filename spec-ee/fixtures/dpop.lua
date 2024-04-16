-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jwa = "kong.openid-connect.jwa"

-- hash == HAvngAt2DlJLxgc7-r5FNlejviK9SirZ8SH4-tvPU9c
local CLIENT_KEY = {
  p = "3mwz_NSaJ1h5T3fPnAUq608-VfQI76gZi-s7t0gcmK0nwqMeZtuDSXF8euq3VV6-nwEArsYIougHU29sh73lJDnlmww78fwvim64zP_ZTWBNy-4Igxb5V60Ke3nA50LgHmsD7wsFTSKYKr07CgO5Vlh3W7SWGOG5o_-DeGbonPE",
  kty = "RSA",
  q = "wrZnSIxmJiKEgXrL45R_RiO-mthoKOPSS8TKkqEbSZl4fKKqgV1PIxIIot5gG27G34dBJutiuX_zcuTMrTlN-3Seoa7h_dI66V8kvTrJdCIuWfThR_uGnitgRvpXT9iJ6bDk5bo4XQ6tUo9pO35kEOjIoC2gw3qzuq6a-mW2wGU",
  d = "H1pg3MDIn0rqKwoUF1pyO5fT58zOzvI8PPUka2KX_7Ute7FU7ML1rPfozJQBvCUdOfjF5zSJNd_OELAWhIvn72B7kh8iZcrn4LjhIVuquXpsldqvQeYAMGSNsbKBmeQauMwsCBdtYdOx2Ijh9f5TtiaRI3CmX_yTuQgSYfR5MQO1INxnkL3fj9jFX5sCUHqHOdv1pg02VytezZ9-R4uzRmW6T5Jc2y37MAg_YRUDvAGM9uUj3dXok8r9Ox7EiPp7N-KqCj5HZoyxzaCtBykEF2TvsjmStQtUEkHEv3yCL9XeLb0kVY84EfSCuBUHP98xaMdE1cUXFK_t2Sec6bnfgQ",
  e = "AQAB",
  use = "sig",
  kid = "test",
  qi = "x2osCFlaRU4IMTWf-hWzWfcpE5qnV9Dj9184js4eEQZufQagcxNiJEvGl7boOAvqL36mZlfevc0nKNBjLtB9P6Zdxs-DqcNOuUdhSaBfSDsw4Vcy0qbnuSeTEXXEjegrNhoMQfuXigaaeMOXDPFSf59B36oM4EP1IApisn-fzEg",
  dp = "JeYsCZW0WqXxrb_NiVk8EfJjvcOiTivHhpbjivxnmwBOORUQVhhrS3Vh75PU_1_wfSlvk1g9Gn0M2oOu64ZI6B5RaFTyVe5Rr3XkWVHzFgMl3mzF2IhunijnE1kQrJcxlx1HA1FOavFNGmM6Dx_JUdQrKl4gAUddGXutTDPEyRE",
  alg = "RS512",
  dq = "uajnTrvg4tfi9Ps70mLUAPMwWcGjf-nLqceZSLspo8IcqusIHZX1UYFujq3vgfjc1GLJcuzbE_m3DoSvzTRo8S2_3Hc-saF13vSDuZOGZ5_4BnqDHPnu4H6HrOYjvtTAm_26JHquJ71I8wIf20Sm8aClPGaFdh9XpNe8mqnF2ik",
  n = "qSx6DyAxPLveO90UDaCDT1WwJyI94GgaSXYEersmXcZb1E2-nxYDdIEct437B2_c6KWT1TkgjSb9sSIrhB5x9__kvT5FqFj6zqdjvaqutZ9tT4dhF6y_g1MhDcncF-UeaXILIlgMVdkLAckrGYJVVFA-7445FvOkj2cjU1Beikot20W__H6k2_6O_CRpiwNXm0UY-K3j0fmKvFb4EfsH9qOiZ0-ui8GR8lSVvbflKzbbEbkPzTGpPwoDieKdoM5LyEUhpSlaWK6qJa6NYxq1tx1TLxymfuuPcfASMVl2Yx5zQXRHBaR4WWoCQ9ODB5VGCX6okUcGC-SB_FhTt9CrFQ"
}

local CLIENT_KEY_PUBLIC = {
  kty = "RSA",
  e = "AQAB",
  use = "sig",
  kid = "test",
  alg = "RS512",
  n = "qSx6DyAxPLveO90UDaCDT1WwJyI94GgaSXYEersmXcZb1E2-nxYDdIEct437B2_c6KWT1TkgjSb9sSIrhB5x9__kvT5FqFj6zqdjvaqutZ9tT4dhF6y_g1MhDcncF-UeaXILIlgMVdkLAckrGYJVVFA-7445FvOkj2cjU1Beikot20W__H6k2_6O_CRpiwNXm0UY-K3j0fmKvFb4EfsH9qOiZ0-ui8GR8lSVvbflKzbbEbkPzTGpPwoDieKdoM5LyEUhpSlaWK6qJa6NYxq1tx1TLxymfuuPcfASMVl2Yx5zQXRHBaR4WWoCQ9ODB5VGCX6okUcGC-SB_FhTt9CrFQ"
}

-- hash == wM3HnqLyId6Mdph9R6tXpNvVCNt8YIdL2utHsximdXo
local CLIENT_KEY2 = {
  p = "_gyDtXWWBukWNGY56KkShmpyy7LbvEla8P_OEyHzq6Q2CMtF5ON0hl5tn27PuJW_GZb8LZFwks50iCTdmPeDf3G-vEJG7p929p0Wq2Aw-XEFDqwt1UJ75u8S1Bi-PeA6G6tvrSRh0g8UtASveUPLA-STgdYmdjgZuNUMp2ZpHds",
  kty = "RSA",
  q = "vh6Drg7BvdNbwWrRBbga7CSbZVByjhFgDfHao2jFFLY5_8d5iKP5tC2Bv9s9FDr3prCW-Y581iRmekW5IKq1wMkCCppmRRbzKHGuzEcK5q6FgLSkqBhFXlZMES1cbGVesfPFtUZL-Wr3Io-Fm363YZJUMwduv_MgAZem76j6gAU",
  d = "SzB89kWLwUTB6EzWTYcMiphYdNBh3pj6_VTuDmMgg-na_9A1xPfQkhj7oAFepGwHTUO0XHl3bJS8fi8XzUnrPMUIYNeunu0EQwu4cHG24Nf0zCb2ZkxpULsx5ZCG9V3cn712b5OA9j1uMofzuJyrjI2X8BUaSS7aA-r_hCJo-1jo2sncJ646Rx9PneAgn1HzEuxOwdYy3VuuW8bq1ufYtc04MqJNzLT-KkznEv5H3wBAzO8oEdaLRUXiUWxBMYXTdqcGVWpl0IAS7kpqTUujY_gtNiW-LZBuNWRYL5uRHBaYGeDtMSafR6_tOwzqVT2ZIegVZ282mdL_BtOrzeM8cQ",
  e = "AQAB",
  use = "sig",
  kid = "test",
  qi = "xot6uLK9LGwhZQxaA-D8IJ8J8fHd-VBUX9ReJanEMvkVD2TREYFSKepNvPcKMWdq2cqA10W8R8igYgvYAwwH8WEf0NSnxVRXP1TpnzTwFOffRoml1PYeGqc46zweXlnw0FZLUxDqvT7nUCXsdkq9k7Zk_ND1TRolxLkUDuatx9s",
  dp = "YngDTQBIqGEMBD9jTrTJw2PbHu0ykmZ0Y1kjTPMp-Wtqrjnr2232KmbLYrKWvNr9-TM2h4sJ8T0omeSAJ9w4EdvKrDmcOL2CZNA6iy57jROrfCZslW5xi-86gw8cHeudWkA2xwuFBuBli-kNApmuRNICAp84xTW1cpjRkMj3EWU",
  alg = "RS512",
  dq = "PZBYB7cTmcqlfb5_LSDu5uT7xRUF42dQ-XMF38B_gTN5GJCZlFu08lmCGISABNsLctjgKrOvTRDAdnu5dRCShnkQxio1T84cs04M0m125DhDVugoIZ6qZ9_-BdnwgdFZlrpfnVHELGIs4O4kz7N64oel6FhRzqqGBL38-sJ3S5k",
  n = "vKuR5T8VdDu0JTvp6R3WQtEefptI5RLGpMjtn_6T6toEhm6UDlNyZ3tNYlIL26RzH5xGLoRcWg8u-obP4KbKVTLhxTrTCTC-29ToJPQsK_p86d2P9a1PMGfYVI2oqoSTySGQCTGA8sCCUpcf5nDqtAJRaNRJxSl0BSVgxe8m7gyO3J9c8gH22wCzCiUMNeEdr1YI2Nq3TjCN5-O0nngOfR2A4KMB25hxd98ndTrWUNyzgoWJ0VLyTrVd9Qh9RdfU-_zo79sV-6wKsYMJmOc8KDOhfq_9sNbVADwxjMqXrzyDNlc69LlJX1a2XFHVSST4cgkpo07lD3aV19ItbtkVRw"
}

local CLIENT_KEY2_PUBLIC = {
  kty = "RSA",
  e = "AQAB",
  use = "sig",
  kid = "test",
  alg = "RS512",
  n = "vKuR5T8VdDu0JTvp6R3WQtEefptI5RLGpMjtn_6T6toEhm6UDlNyZ3tNYlIL26RzH5xGLoRcWg8u-obP4KbKVTLhxTrTCTC-29ToJPQsK_p86d2P9a1PMGfYVI2oqoSTySGQCTGA8sCCUpcf5nDqtAJRaNRJxSl0BSVgxe8m7gyO3J9c8gH22wCzCiUMNeEdr1YI2Nq3TjCN5-O0nngOfR2A4KMB25hxd98ndTrWUNyzgoWJ0VLyTrVd9Qh9RdfU-_zo79sV-6wKsYMJmOc8KDOhfq_9sNbVADwxjMqXrzyDNlc69LlJX1a2XFHVSST4cgkpo07lD3aV19ItbtkVRw"
}

-- "jkt": "HAvngAt2DlJLxgc7-r5FNlejviK9SirZ8SH4-tvPU9c"
local CERT_ACCESS_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." ..
"eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE" ..
"2MjM5MDIyLCJjbmYiOnsiamt0IjoiSEF2bmdBdDJEbEpMeGdjNy1yNUZObGVqdm" ..
"lLOVNpclo4U0g0LXR2UFU5YyJ9fQ." ..
"OHqhY9QCVBjWxa7FYMj9AMj5THTADUPq-av_H5e3AHk"

-- "jkt": "wM3HnqLyId6Mdph9R6tXpNvVCNt8YIdL2utHsximdXo"
local WRONG_CERT_ACCESS_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." ..
"eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5M" ..
"DIyLCJjbmYiOnsiamt0Ijoid00zSG5xTHlJZDZNZHBoOVI2dFhwTnZWQ050OFlJZEwydX" ..
"RIc3hpbWRYbyJ9fQ." ..
"dlu7x_rj20b-anaAr5TEBEWRr04htBQFITMYNeP-oJ0"

local NO_CERT_ACCESS_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIi" ..
"OiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwR" ..
"JSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

local CERT_INTROSPECTION_DATA = {
  active = true,
  aud = { "kong" },
  client_id = "kong",
  cnf = {
    ["jkt"] = "HAvngAt2DlJLxgc7-r5FNlejviK9SirZ8SH4-tvPU9c",
  },
  sub = "kong",
  token_type = "access_token",
}

local WRONG_CERT_INTROSPECTION_DATA = {
  active = true,
  aud = { "kong" },
  client_id = "kong",
  cnf = {
    ["jkt"] = "wM3HnqLyId6Mdph9R6tXpNvVCNt8YIdL2utHsximdXo",
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


local function sign_dpop_header(req, nonce, key, pub_key, iat, jti, alg)
  alg = alg or "SHA512"
  local jwt_token = jwa.sign(key.alg, key, {
    header = {
      typ = "dpop+jwt",
      alg = key.alg,
      jwk = pub_key,
    },
    payload = {
      jti = jti or "1234567890",
      htm = req.method,
      htu = req.uri,
      iat = iat or ngx.now(),
      nonce = nonce,
    },
  })
  return string.format("DPoP %s", jwt_token)
end



return {
  CLIENT_KEY = CLIENT_KEY,
  CLIENT_KEY_PUBLIC =  CLIENT_KEY_PUBLIC,
  CLIENT_KEY2 = CLIENT_KEY2,
  CLIENT_KEY2_PUBLIC = CLIENT_KEY2_PUBLIC,
  CERT_ACCESS_TOKEN = CERT_ACCESS_TOKEN,
  WRONG_CERT_ACCESS_TOKEN = WRONG_CERT_ACCESS_TOKEN,
  NO_CERT_ACCESS_TOKEN = NO_CERT_ACCESS_TOKEN,
  CERT_INTROSPECTION_DATA = CERT_INTROSPECTION_DATA,
  WRONG_CERT_INTROSPECTION_DATA = WRONG_CERT_INTROSPECTION_DATA,
  NO_CERT_INTROSPECTION_DATA = NO_CERT_INTROSPECTION_DATA,
  sign_dpop_header = sign_dpop_header,
}
