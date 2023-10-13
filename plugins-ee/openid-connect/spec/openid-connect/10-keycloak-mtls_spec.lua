-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ngx_ssl = require "ngx.ssl"
local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local cjson = require "cjson"

local PLUGIN_NAME = "openid-connect"
local KEYCLOAK_HOST = "keycloak"
local KEYCLOAK_SSL_PORT = 8443
local REALM_PATH = "/realms/demo"
local ISSUER_SSL_URL = "https://" .. KEYCLOAK_HOST .. ":" .. KEYCLOAK_SSL_PORT .. REALM_PATH .. "/.well-known/openid-configuration"
local KONG_CLIENT_ID = "kong"
local KONG_CLIENT_SECRET = "X5DGMNBb6NjEp595L9h5Wb2x7DC4jvwE"

local PROXY_PORT = 8000
local UPSTREAM_PORT = helpers.get_available_port()


local ROOT_CA_CERT = [[
-----BEGIN CERTIFICATE-----
MIIDHzCCAgegAwIBAgIUS9LvDXbMV9qVUqdF8pfHdsVz22cwDQYJKoZIhvcNAQEL
BQAwHjEcMBoGA1UEAwwTcm9vdC55b3VyZG9tYWluLmNvbTAgFw0yMzA5MjcwODQ2
MDFaGA8yMTIzMDkwMzA4NDYwMVowHjEcMBoGA1UEAwwTcm9vdC55b3VyZG9tYWlu
LmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMUq/OhSKsR2G7fz
j46rQFXpA5XJS8oWGmwRTSyHt+GJ4NAb4z4CxYe76FYkgY3yirOKau1vPNWb8O5R
2k0ijgVZ8iK+zHbnXNJiO4WEVp6V2hyss6HaXInteI+ghoxA2qEJnsV8ZXSMXTJM
YNpFEkaI25iKlEfWVU+8evIpX7ttbtnalWt2appy7rb+PuOudi0zv1e/+6MVtTKu
4tOiQ6EX4ynD+wlodRcjjsW5AwtMC5pbPmVqJDXIFiLA0R+yx87pRboffHZhHiD6
Q8L1HSZC3elObddKiF4BHZw/e4G1DGmzxZgOUPxndi6UE0ZOuH3DJa6W+I7vTqfB
aBQnlCUCAwEAAaNTMFEwHQYDVR0OBBYEFB3zuCXHhuvl0EgMgJ7Os7FwzaZUMB8G
A1UdIwQYMBaAFB3zuCXHhuvl0EgMgJ7Os7FwzaZUMA8GA1UdEwEB/wQFMAMBAf8w
DQYJKoZIhvcNAQELBQADggEBALzRxfnzOVXqxEVZx26L21vWy3myvWG7ZOUp1kQz
SwctLIKFzuoLVH+GN+kZQJ50kMycA+U1UFO8dRjSTHl64XyJknQAMvlIbTcu2K2q
ZkoIe2YYD3VmVS/FbDTCQrAVXwF+fS7k8gvT3A4hNNkaCR/pOG5dRATnWg+dJ1b+
yk4Mzob48zwyW7xEhjO4HigRUU+NPmNY6i11lOsPPjlLwrdZ2uUnYforcupHxz/f
EPTVwOymaXoBYdb228pUWyHm8WXP/+k5LQEfoteJ81n4hR9GioMiqGGdW14ev+Se
M86Hcd5BSowSPTbjT2RmrOqmCFEBey4edyrFhOzzPsPuD50=
-----END CERTIFICATE-----
]]


local INTERMEDIATE_CA_CERT = [[
-----BEGIN CERTIFICATE-----
MIIDJzCCAg+gAwIBAgIUGJzjzGqQ0kBGQoled6IQnwy9rggwDQYJKoZIhvcNAQEL
BQAwHjEcMBoGA1UEAwwTcm9vdC55b3VyZG9tYWluLmNvbTAgFw0yMzA5MjcwODQ2
MDJaGA8yMTIzMDkwMzA4NDYwMlowJjEkMCIGA1UEAwwbaW50ZXJtZWRpYXRlLnlv
dXJkb21haW4uY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAkwhb
4Zy2iiVRxpBE7dcaOXuBnSsnwnC+0SA0YeaNHTEKbrYYPkoQl+56w447GH6sAToa
yjrFDS/bmZyPnugdM6rFM34hDkR4yeBFMXjcPplY6NWB6ZVff7mx1aCMgHLhDpr8
nlkgGuqHZefm3fSbmbaDNXQZib6+ADef5W4XE8VpMuw2zq1KafcBzDN6Pj+7kSNG
qhg24KWNGprXdGuuHoxaZG2pqnjs+fWG+0nlbYcFoHBCBNO3b0XpbIBzePi/JwXg
7t/j9V4U75lQyb55PMEiNippUYjyWr+MU8Gv9Ze0SUd7BC35smghmzzg9p47k1aw
Fu2V6lSIBj7s+DszGQIDAQABo1MwUTAdBgNVHQ4EFgQU+J2B9kno5+9xzUxqQX/x
MipT/iQwHwYDVR0jBBgwFoAUHfO4JceG6+XQSAyAns6zsXDNplQwDwYDVR0TAQH/
BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAwoqvzkBl37C0CIk3+zLd8+a5egZY
py2aSQOGL6EfqtSExJndc6KFbO5gRPKl4CJvnIc1Mia+Sb5XJTs/R9fG475HtNNY
tcykcQCLv3cGgLLxITrSVaKAasY8IrwSuRl8N7bivxmN8h7y7XKJZRnLvFvc2y2Q
RJlUfjLK9rNam9NksBxjWEF5Tu0fHyyHlksbrd7LH76yqerUq7mEcWM+dduI4XUb
CQtFcRMPeATWXHWqTWzKx51XWraczLhkNFMIFgyknX3nCEpqe+scatwZeQcEmCGr
EwpEubSG3nXe22vVtHr295tAi3vHc0bsYZg4Jv+rK3QfeSj58Jvi523SEA==
-----END CERTIFICATE-----
]]

-- x5t_s256 hh_XBSxIT3qG46n5igJA0MsFEgXosYoWvzeRZfRCknY
local USER_CERT_STR = [[
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

local USER_KEY_STR = [[
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC5A29JR/LlFH4o
hRduJju1oO6AFlCzrR56Cv1iHrDtas3z2axBn1IIT2SoX2HyQQI4cwBK9E5F8VyS
JO6db9xknCVKb0kbVPJAiqqfh7hdabErlC8rmJ0wyOcLlzgSjrLNkVN8VnRc9jLo
Oi27GdIOQGMZPPLGg7TNDoVdNheJEYqS7ZyrLeTUde0nibXbJL4MldQQrF773grN
LeSNX8pMr8G6TYc7+ldVDxw6udOh/VWk9EmepibttNijXkrYm5td3Jl5VTGD+Vd6
2jdX+GZSgLn+nKez728z+SvHTo3PX0zn95tq8o5Ri9UrKCuGdqgY5vGu5utWdJeq
sv8OEaonAgMBAAECggEAEXXihc71fGsfsOFGoc2X6v9CIvJ4MUzQSIJLAXyWBAIF
Z9MOL69ChahAfqdpzfwWoo8v4uMFlBJAQ0abAl6xNQmLd2fjRWIR7sdnbODZJG+6
GbvFa97eTuFW9MATuaSf+UiS0XQzTSarDUGYWUUJjvDCqXoYC2YYpRWOvopBVF0b
VnwhCAhEDlCPI5dmSCYAtcQpJAHYUjcKsOgL1VH6AZFQPrcFhBc9EnJcKcTo0Lrn
dNUJ4fqTPMZC05UpqBhr2A/k243tA2OtY0r6dHV7ENDE6a2LbwlTAGIHsKNfT8YD
OpqVqtpo/KWB+9jVDKvzh1u2lIqdbJrsVtQ4a5hZYQKBgQDSy0nMDwIfHbu7Yb8e
TpLWOD3zwSroMmhlqnYkV6N3eTM/byVjGTutOciO4WcsLyP2mqok9OnlM279/Cs4
f2N8vOi3FJBtO2uav4WuJPy9ZB6pBVRd81+KY2mRhxKmp6xocotE97eTT493zUkz
XtNulYIl2Hkm6AQgY0N+ZxrdNwKBgQDgsMXmNY0+QpoD59/0aBfZ2VtbW4JxnFQ0
mNtmFnPLP/Ug5pEjomczHzsvmBvz/phMN+w9dIeZYM61HlJaW3N53+sc5rPF7Q1a
bj77YJkWZY2UNFPfb/wg182PoJaiBud1TL58jXf/JPtNyggoOs0lGE59RJojqWgG
SxidGFeSkQKBgFAPS8EH9jtRNKsPjeH538Ui6Uy6EgzMkGAEpQhajMhkrPUrxpxj
ygmZx7WUoHXklZkk1vhgWLFnnoEylEvJ/kQzD4PxeIU0K0ND+IbSn3djHk39qzRf
qerKpR7TmV7Ykh+9WW3hU8TMU+YhfurW2iDHAf5TwHfpaR/P86N/j3FzAoGBAMgp
0nLNvCD91hSqqWEipjTFJFSThfZN7NnaXoFoeQlU1bvUivGyyLrLFL/GgwhvAx/L
JeJtgCsMCblh5L1oAMxOxTW+8+Hb1ux7kBICsP45w9GGeD1xlqtvdEmCJw76lZFy
p7Nvl7mtKU7YL0IfeAeWyr1fsu0YCnqoxamVONZxAoGBAJy7nEjTVij9nmkMKGjm
MM7yIkcdIXNMFDw7Tbecrt6e50wTZEJhqfloghGyHEXI4tnBqt36OduxyeqBnv8e
pDbfU/KpVKSzt+MPB+wIOV5ksg60behg6x82KdooI+gJ9SWG3Ou73XhmDje8ssxU
taW8qv1lggdpySX4Q4TtYMua
-----END PRIVATE KEY-----
]]

local USER_CERT = ngx_ssl.parse_pem_cert(USER_CERT_STR)
local USER_KEY = ngx_ssl.parse_pem_priv_key(USER_KEY_STR)

-- x5t_s256 S7mEqyMUtjPZ-xK9HqK2sEoeFjNOz0IB7IGY_KzwQIE
local USER_CERT_STR_2 = [[
-----BEGIN CERTIFICATE-----
MIICvjCCAaYCFE8AcNjBACReSIJ7/McD2OXC8AOrMA0GCSqGSIb3DQEBCwUAMCYx
JDAiBgNVBAMMG2ludGVybWVkaWF0ZS55b3VyZG9tYWluLmNvbTAgFw0yMzEwMDMw
NzMyNTVaGA8yMTIzMDkwOTA3MzI1NVowDzENMAsGA1UEAwwEa29uZzCCASIwDQYJ
KoZIhvcNAQEBBQADggEPADCCAQoCggEBAMs09++evhu5QMfVPioTxmUae11rjrb2
gO1ePfqV5+BNRaez/DorwrkeeZCF+Xr4b0pLa11EEIAy29SCmv/hjRu3UN9lXFd9
b257gUebNmnQEjnPS9IpjS4aWw2sLsxSQyYpTZ8jHOJo4f4Et/C2y/fU+ZjIcJlp
Vf9kiEkS3FBPkciSjF5ycloxJIH7WRextklAxzxBzzopIYJB7N8ja/d9RIdmPdoe
ynVG2Q7lVox0LshYtBSBeLSwF9EMKsoErgo0IqB8uE0fFoCrR0ZGgAY01Tjy4Rh/
cYF38zM3F4ZsBPIKJVdvnQdw2ZW0dyTEdE15RvghmiJX4SiVlbKQJMcCAwEAATAN
BgkqhkiG9w0BAQsFAAOCAQEAfdpR5TPUCu6flTuMYpmBtvUdDLtwSuQbRFx7f/Ef
RiG4Afsnp9zXVleU1Iq2nc25zT+NyV3dCnqHraVGi9RkRfQ1XuQxqRjzGZruczhh
hVOixw2qNN8T2TGh8CCELvXgUWiAOi4njO/5XtXqxaa4tM5rVQjKsTE7FXuzeNAw
TZqocFwISUFvZBoXMSnSE+z715/O355bJ9K0eQEu5dM/3KXAtEN3lSMsmCDdBt1v
pFQyW2rTsV6ysz1Z1xFDHOGP1DhWx+oM8Uio0rt43m3Sa2iTn3akEG+WtVbpIurl
NSltGjOcPVsTtLDcgepBcrsx0IU7wNlkshkX3Z82U9CyTQ==
-----END CERTIFICATE-----
]]

local USER_KEY_STR_2 = [[
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDLNPfvnr4buUDH
1T4qE8ZlGntda4629oDtXj36lefgTUWns/w6K8K5HnmQhfl6+G9KS2tdRBCAMtvU
gpr/4Y0bt1DfZVxXfW9ue4FHmzZp0BI5z0vSKY0uGlsNrC7MUkMmKU2fIxziaOH+
BLfwtsv31PmYyHCZaVX/ZIhJEtxQT5HIkoxecnJaMSSB+1kXsbZJQMc8Qc86KSGC
QezfI2v3fUSHZj3aHsp1RtkO5VaMdC7IWLQUgXi0sBfRDCrKBK4KNCKgfLhNHxaA
q0dGRoAGNNU48uEYf3GBd/MzNxeGbATyCiVXb50HcNmVtHckxHRNeUb4IZoiV+Eo
lZWykCTHAgMBAAECggEADJncRh+x6kYynjG7CSDwzJQ30jM5Rl9C33VYopFpL5+b
Eis3GORdztz07OFh9x4wyIqkvcPawhhlSWhP9E4oUe+sNC4067f7kP5XpfkaBrXA
a5VPPlkVSCaaPt7OiB0RzOwCxDuJLwESAo6IWYT8YQHz+GV1lg3SJ2Q0j1N8Ff68
3nmXfyrAptUHLepmCyNPNJ5cTkBkkVDG9eGb22Cz27NSlsfW+tCoK2My9S1GYzkL
PM1NGvhTN0qCEeLl2CHZzt7gRr0NT1HYtbw6W8OQHVyBzQDGjNunEw6KLmIAq3im
8LptdRuRfgkhVjHWAOY8BC7RNdjJvyoFeXF6alDsAQKBgQDrT6KIMXgBKpUX3Q1M
JMKQxbQ5aimWAUUfqCUdvOtKwToKLdJHVyMmqmEOuwcLFOn4KpFNv86k2WSbY3cI
MttUrZTHvwlHonqVPEr9NFMqjjaRS9JbUtnFxZhi6coHx475eY74pZBAEnGpZ6Gi
VdDm9GlIKIc+roWWHCYesxNONwKBgQDdErw9EqHCuVSdl7pmTQ29NBSPCr5YW9Re
KC/ZZviuinjAxMN5Xjfsm9G8spgF5G0U/P0zaoeabpZ8p7nwgoTxgV3lnRVz6zMe
BJGrVJnkh1L6wqJQgPkToE6ajzWwKBpfiolmLEO8GZ54yhgcMfXDHexhSe8LVFcK
U453Q08V8QKBgQCnRHJqkY+WdKiK0A11xOOxeXgFIBvzj2+Ncz7/Bp3TA8u4FJ5X
K+/GunJHwFbfX7x5NfkX5XKE6CuF8YxZfZ0/cixCWN/F1g+BKdy8ZIeBxpmvatBb
LmezGCScm0eLhCVz3R7uTPJfOT0miI3zEUFwCukT7AtHWVOIQvYt+GmOvQKBgHag
mg/vkoup5WTXSTeh+1BexPVo33EMfa20xNBU9/a46UkPjJDw5PN7PZWTBA6NX5dW
lgvkCzXsR6ZGXnlXoDzznU4b96oHOJvP+dbFA/tkPju++1hVjNJiQCuh0z5elqBT
95yy/fnOiYHpd/yRNn5n7TLbeIFM1ZP9+EG5BZQRAoGBAIfOKJ+6oRwhGLiq6Cnr
9NhPXBjXF+YTBHqNP53EoEq3lM1XvYgP/N3zmwFeWHoV3MRa9UoS9iJ9dYL96/RT
zHrFceI9y6LN3MNmn/heRFhocwa+0q7SKfonuduuc4wMa/yJWftuVmZm3z2KTEy5
yR5Nho7rSAQfuIxSGga1RUM/
-----END PRIVATE KEY-----
]]

local USER_CERT_2 = ngx_ssl.parse_pem_cert(USER_CERT_STR_2)
local USER_KEY_2 = ngx_ssl.parse_pem_priv_key(USER_KEY_STR_2)

-- key generated with a same CA to the correct one
-- x5t_s256 oDLR7Uo02EQ928ECU87wRgGmZU8-9s_kf06OfdiglAo
local RANDOM_CERT = [[
-----BEGIN CERTIFICATE-----
MIICwjCCAaoCFDTJk8FARG5sxanHl3L0Lblpa+RqMA0GCSqGSIb3DQEBCwUAMCYx
JDAiBgNVBAMMG2ludGVybWVkaWF0ZS55b3VyZG9tYWluLmNvbTAgFw0yMzA5Mjcw
ODQ2MDJaGA8yMTIzMDkwMzA4NDYwMlowEzERMA8GA1UEAwwIa2V5Y2xvYWswggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDcXrc2v8aPpaOqfDgGsQtwvY+i
2qbG+3EDvmv4fVAdcOowU1o5F4E7vue394LS9Fl60giso7K/OjYBfw9wbQORY4Sn
E2ElviL0tO5m7DD3yA//YUCj52LJFXt5HRywHRcRQYTJq7xCzih+ggColdexDX3S
Uflbq698aHfdn6gb1bcZBxFo4LvO35x46p7xT33kOQKgFaJ2TDJ259MwasamPOHJ
qG7pG0BtPmCdaeLAYZj+7OsAqTumMrXwK7ajOlpqJw/8SyHqq2xaDKnrBlaxNQhm
cwqBxcWFVRkjnvJlMp4gYLgb/2QAii14DyS9qdG5+SeqimRSN65XxQ7KIduNAgMB
AAEwDQYJKoZIhvcNAQELBQADggEBAHg7OrXpAkLCZwqH9FTeElW9kBxZC3IioBjR
e99DIavt1Gd4mB3s2ZxTOeeg5WR7jDIM4NMbNbSJdNjOUFXje0Mj5aK1n8H9F7fT
kxgesMq4xryjRaELillAxIcqfjyw5tPLdPsUcUFrYZuEaXzDzVD5HCiO8xv5L5AS
OiIjGdARQ8WTDqmPyPwSECIG6eZ7/Aowk57ddtj4RI+9HP8Esh8Ttm2+GqO5sEMq
+IF3+iJUQbVNuxQWP8N2FRm2KkE+TvvPrijRnjdFNKTjSpFMrUFTzRatydtodI6P
f5geFlaTDSopdj5pC5v9Xw1ut1Bqve6Xf7l2L9mK7HkAYxEW1Fk=
-----END CERTIFICATE-----
]]

local RANDOM_KEY = [[
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDcXrc2v8aPpaOq
fDgGsQtwvY+i2qbG+3EDvmv4fVAdcOowU1o5F4E7vue394LS9Fl60giso7K/OjYB
fw9wbQORY4SnE2ElviL0tO5m7DD3yA//YUCj52LJFXt5HRywHRcRQYTJq7xCzih+
ggColdexDX3SUflbq698aHfdn6gb1bcZBxFo4LvO35x46p7xT33kOQKgFaJ2TDJ2
59MwasamPOHJqG7pG0BtPmCdaeLAYZj+7OsAqTumMrXwK7ajOlpqJw/8SyHqq2xa
DKnrBlaxNQhmcwqBxcWFVRkjnvJlMp4gYLgb/2QAii14DyS9qdG5+SeqimRSN65X
xQ7KIduNAgMBAAECggEAEb4MeTt6hKE86qKCrkM93Q9eC6oYCGhBIqCHt+N6+kvX
hxmG55bVYFaP+HdUkKB8vc9ARIoPf6bzpy4wM4iLY37ENOFyDmRfEx2oHiBBFwoE
A7c0SZ39DZyNquQlpaZJ76k7RDNv/l7z0q+r1ubtjUM9UJwp++/4Ood8sxrCIa9u
cdBv9+CJvfZQRLaaeTec3MxJ0/wYPownfrrXFQTI8MYVaY4ccJaLyCyCQbODDlPQ
WAKdpsF9UyV/1ILB9T2/rxMY/iHxU50z1d6zIqQGpZoDizPV1JHfwTdcIl3G62mc
NNzv9HFDIjC/Icvfz98CHxG8oz8zUQmS5z8FM5g5IQKBgQDezefEYnaFg2xquLV1
VkjIWAQmOOlGgQBTM2bOwIhsAulCSJ2QZs/cPuGf+DFsoo0mabq55zC6cT1NT8UV
uKFgk7T/zDLXnav5erNk2zWihRAwqTzHEjDukvF6LzIWCRPWaU4i3lawNDwcOJ3q
y+w/xOMJOxTmT8AZtXTza3fT3QKBgQD9M/YMNyArWqhI9wOLeRvPaV0sJtftskZp
chzQh9upIrsscHLRLm78IC5l3CD3eH1/LnaXyr66qy3JXnZG3m8cAJGlAKwyQgHg
hHNMhFIuhrFwHtu6pZIny8nOE/1nQT2IvckECQghsP7lb1QJwUfeRVclWY+2bGKT
W2i1I4zDcQKBgE5CrSJCI7eKDk7+Sl7IzA/zOqHiY64sKd0PtRDyd/jYnO53a0EJ
nAGU5NO37kRmZIYVpU0fc/JJTGsXlfanP6gYuf8PztwFuh6Lhu/qP9CyRJmTGJIk
RaPHYaK1aTZsQdeSbau5xWFnN6YCDRYoQvezRLw9UH4FjUh6gHXwTcrRAoGAJlN3
KuItPGK8lk7Neo8aZorMT6KRjKkvf0aGlgn6dd+L9W4P8xnUMtWsMD7hvpO+a0Hd
MZy+wgKnK5Pg01lX+CUd5pvzdKgJILLrwOlGh0RcF1yUZewp81wlb8wWz0pQxiH0
C2hSksb3zkLLta5L8pkMV9r2peZCBYwQjVqUNAECgYAdhi+X+Un+U56vsETjbHmt
Kpg9RJIV9Yy5IM3oj7+hVcjdBNy54sHD95F7I4uQ3q9XmUQENl1kdWvAAlR2xaMe
Fqw5OLpDViA4O/v3PowZL+cFbCtbmTEVNyboiCjKoiC5Fv3LnzePVsQO/6Z/XGL7
3yQdnIbOUTqk948/fT0Mjg==
-----END PRIVATE KEY-----
]]

local RANDOM_SSL_CLIENT_CERT = ngx_ssl.parse_pem_cert(RANDOM_CERT)
local RANDOM_SSL_CLIENT_PRIV_KEY = ngx_ssl.parse_pem_priv_key(RANDOM_KEY)

local function get_jwt_from_token_endpoint()
  local path = REALM_PATH .. "/protocol/openid-connect/token"

  local keycloak_client = helpers.http_client({
    scheme = "https",
    host = KEYCLOAK_HOST,
    port = KEYCLOAK_SSL_PORT,
    ssl_verify = false,
    ssl_client_cert = USER_CERT,
    ssl_client_priv_key = USER_KEY,
  })

  local res = assert(keycloak_client:send {
    method = "POST",
    path = path,
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = ngx.encode_args({
      client_id = KONG_CLIENT_ID,
      client_secret = KONG_CLIENT_SECRET,
      grant_type = "client_credentials"
    }),
  })

  local body = assert.res_status(200, res)
  assert.not_nil(body)
  body = cjson.decode(body)
  assert.is_string(body.access_token)
  keycloak_client:close()

  return body.access_token
end

for _, mtls_plugin  in ipairs({"tls-handshake-modifier", "mtls-auth"}) do
for _, auth_method in ipairs({ "bearer", "introspection" }) do
for _, strategy in helpers.all_strategies() do
  describe("proof of possession (mtls) strategy: #" .. strategy .. " auth_method: #" .. auth_method .. " mtls plugin: #" .. mtls_plugin, function()
    local upstream
    local clients
    local JWT

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "ca_certificates",
        "plugins",
      }, {
        mtls_plugin,
        PLUGIN_NAME,
      })

      upstream = http_mock.new(UPSTREAM_PORT)
      upstream:start()

      local service = assert(bp.services:insert {
        name = "mock-service",
        port = UPSTREAM_PORT,
        host = "localhost",
      })
      local route = assert(bp.routes:insert {
        service = service,
        paths   = { "/" },
      })

      if mtls_plugin == "mtls-auth" then
        local root_ca_cert = assert(bp.ca_certificates:insert({
          cert = ROOT_CA_CERT,
        }))

        local intermediate_ca_cert = assert(bp.ca_certificates:insert({
          cert = INTERMEDIATE_CA_CERT,
        }))

        assert(bp.plugins:insert {
          route = route,
          name = "mtls-auth",
          config = {
            ca_certificates = {
              root_ca_cert.id,
              intermediate_ca_cert.id,
            },
            skip_consumer_lookup = true,
          }
        })
      else
        assert(bp.plugins:insert {
          route = route,
          name = "tls-handshake-modifier",
        })
      end
      -- workaround for validation. The table is created when spec.helpers is
      -- loaded, before we can use the helpers.get_db_utils to tell what
      -- plugins are installed
      kong.configuration.loaded_plugins[mtls_plugin] = true
      assert(bp.plugins:insert {
        route  = route,
        name   = PLUGIN_NAME,
        config = {
          issuer                     = ISSUER_SSL_URL,
          client_id                  = {
            KONG_CLIENT_ID,
          },
          client_secret              = {
            KONG_CLIENT_SECRET,
          },
          proof_of_possession_mtls = "strict",
          authorization_query_args_names = {
            "tls_client_auth",
          },
          authorization_query_args_values = {
            "true",
          },
          auth_methods = { auth_method, "session" },
        },
      })
      assert(helpers.start_kong({
        database = strategy,
        plugins = "bundled," .. mtls_plugin .. "," .. PLUGIN_NAME,
        proxy_listen = "0.0.0.0:" .. PROXY_PORT .. " http2 ssl",
        lua_ssl_trusted_certificate = mtls_plugin == "mtls-auth"
        and "/kong-plugin/.pongo/root_ca.crt,/kong-plugin/.pongo/intermediate_ca.crt" or nil,
      }))

      clients = {}
      clients.valid_client = helpers.http_client({
        scheme = "https",
        host = "127.0.0.1",
        port = PROXY_PORT,
        ssl_verify = false,
        ssl_client_cert = USER_CERT,
        ssl_client_priv_key = USER_KEY,
      })
      clients.valid_client_2 = helpers.http_client({
        scheme = "https",
        host = "127.0.0.1",
        port = PROXY_PORT,
        ssl_verify = false,
        ssl_client_cert = USER_CERT_2,
        ssl_client_priv_key = USER_KEY_2,
      })
      -- malicious users without a valid cert (should not be able to access)
      clients.malicious_client_1 = helpers.http_client({
        scheme = "https",
        host = "127.0.0.1",
        port = PROXY_PORT,
        ssl_verify = false,
      })

      clients.malicious_client_2 = helpers.http_client({
        scheme = "https",
        host = "127.0.0.1",
        port = PROXY_PORT,
        ssl_verify = false,
        ssl_client_cert = RANDOM_SSL_CLIENT_CERT,
        ssl_client_priv_key = RANDOM_SSL_CLIENT_PRIV_KEY,
      })

      JWT = get_jwt_from_token_endpoint()
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
      upstream:stop()
      for _, client in pairs(clients) do
        client:close()
      end
    end)

    for _, test_client in ipairs{"valid_client", "valid_client_2", "malicious_client_1", "malicious_client_2"} do
      it("Cert chain works with " .. test_client, function()
        local res = assert(clients[test_client]:send {
          path = "/",
          headers = {
            Authorization = "Bearer " .. JWT,
          }
        })

        if test_client == "valid_client" then
          assert.res_status(200, res)
        else
          assert.res_status(401, res)
          if mtls_plugin ~= "mtls-auth" or test_client == "valid_client_2" then
            -- the other clients are blocked during the initial handshake if `mtls-auth` is configured
            assert.matches("invalid_token", res.headers["WWW-Authenticate"])
          end
        end
      end)

      it("validates token possession when `session` auth_method is used by #" .. test_client, function()
        -- session initialization with a valid token by `valid_client`
        local res = assert(clients.valid_client:send {
          path = "/",
          headers = {
            Authorization = "Bearer " .. JWT,
          }
        })
        assert.res_status(200, res)

        local cookies = res.headers["set-cookie"]
        local user_session_header_table = {}
        if type(cookies) == "table" then
          -- multiple cookies can be expected
          for i, cookie in ipairs(cookies) do
            user_session_header_table[i] = string.sub(cookie, 0, string.find(cookie, ";") -1)
          end
        else
            user_session_header_table[1] = string.sub(cookies, 0, string.find(cookies, ";") -1)
        end

        -- clients use the valid session to access the protected resource
        res = assert(clients[test_client]:send {
          path = "/",
          headers = {
            Cookie = user_session_header_table
          }
        })

        -- only the valid client should be able to access
        if test_client == "valid_client" then
          assert.res_status(200, res)

        else
          assert.res_status(401, res)

          -- the other clients are blocked during the initial handshake if `mtls-auth` is configured
          if mtls_plugin ~= "mtls-auth" or test_client == "valid_client_2" then
            assert.matches("invalid_token", res.headers["WWW-Authenticate"])
          end
        end
      end)
    end
  end)
end
end
end
