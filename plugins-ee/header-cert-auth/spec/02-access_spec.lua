-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson   = require "cjson"
local pl_file = require "pl.file"
local utils   = require "kong.tools.utils"
local ngx_null = ngx.null

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local LOG_PATH = "/tmp/request.log." .. tostring(ngx.worker.pid())

local function get_log(res)
  local id = assert.response(res).has.header("x-request-id")

  local entry
  helpers.wait_until(function()
    local fh = io.open(LOG_PATH, "r")
    if fh then
      for line in fh:lines() do
        if line:find(id, nil, true) then
          entry = cjson.decode(line)
          return true
        end
      end
    end
  end, 5, 0.25)

  return entry
end

local CA = [[
-----BEGIN CERTIFICATE-----
MIIFsTCCA5mgAwIBAgIUdbhx3xkz+f798JXqZIqLCDE9Ev8wDQYJKoZIhvcNAQEL
BQAwYDELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMQswCQYDVQQHDAJTRjENMAsG
A1UECgwEa29uZzEMMAoGA1UECwwDRlRUMRowGAYDVQQDDBF3d3cucm9vdC5rb25n
LmNvbTAeFw0yNDA3MDgxMzQxNTVaFw0zNDA3MDYxMzQxNTVaMGAxCzAJBgNVBAYT
AlVTMQswCQYDVQQIDAJDQTELMAkGA1UEBwwCU0YxDTALBgNVBAoMBGtvbmcxDDAK
BgNVBAsMA0ZUVDEaMBgGA1UEAwwRd3d3LnJvb3Qua29uZy5jb20wggIiMA0GCSqG
SIb3DQEBAQUAA4ICDwAwggIKAoICAQCn5xk7t84f58SwaMECan0537Iyc3JvBGDC
U24zmC3FWZOiqisQdm4VUSC9s7xJotAXEDHBpfFZEjc3+f9081tKZ4m2NZqxOt0a
yNSAUH9BZ15Ziuz1nmd4dsWnUpb2E5jWDYT5EJTF14/M3mATKT+ViHfUnLolQ9MR
YvH4jcC24b45+rr5UsQHGV71FOQ7jE/GAjn0iXCtxTCdFFEstQrmCb36SSjgfpQS
7/B9uH9jxfDSgvd0QULQ0tCto0zjfNcT7h8k6Jz4SaWIUMQ9DU1mVajeOSmyEWCh
P7otdQzjdpTRHyoPiDZKSi0Vkpt6fgnziw61eglt14L/0doclu1FsdKJXrVSaPGG
9ZIYdvfzOH7yAEVnODw7kknKp2b2vkQUEoy8m1OPD+f8RxSjlpa6FGEVCGGEFvwL
v1U7jSy1PXMJVDJ5WNaDw/HrMQFpIE/+70x/YQiTxRM3uwyqgjn4s2rvBqaxoWaW
saR9BqhLpfG8aDKJV/lrot/8EaeBwxuWZ8/GjgJmIrUNo9bNPnythZMAxtAL/h5q
B1I4b5CPB5JHDGDj+5nlD/Sa7rwFu0gCEvTCQkS6xX/C8QXWzbfH3oKg0nedLxCz
VEEHRW+umWvdcftkEpN5sls7aU2TEm56AZqtDvSdErH0IvoJ2s3nDbC474OqxSJ/
gbGYVZvRdwIDAQABo2MwYTAdBgNVHQ4EFgQU+l8F1VuLfqeC13PGf2GINeMgapAw
HwYDVR0jBBgwFoAU+l8F1VuLfqeC13PGf2GINeMgapAwDwYDVR0TAQH/BAUwAwEB
/zAOBgNVHQ8BAf8EBAMCAYYwDQYJKoZIhvcNAQELBQADggIBABB2yXKUr2GyU8Up
nCLWEeNYQBYCK98dMyp8A727XfLrAZLLxEWpS8JLamJJAeVruh49lOHlt+tz9z4y
g+A/u2ttNdKzyH2+u7qp8PR2KvFbUFl+VJIE75hi8GUGynYs6n/ogICVh6Kq7wWH
ou3sPAIv9fK3fCDbJqoLjuX6BsKFv3mItAqtEaio+5gJMg82PZtW6+g/QNWnfGO8
Ox3lYCCcoU9tz38ZLVTG4FghMI5O+5kxMpp7yoIFIk8Jb7SZPoslV5Z7J5MA2K6Y
xvxAkJbINGp1KEgIrsHtifVU555ryg6zXyySp9Mtwig1ZKRwxlsKjiiraUZiDgBd
Wup2pQ3hr9rlapM8WcWEVkBO8QFyFXi/bsY8Hlsmfvbjcs7hTaBZSJkk7ov6ltk/
dUS9ZfjeAIaUkWo6e3/I8NbK2vLEFQiMYWmHvYZ91jqLgxZP+pL6alWZbWuTLdfX
RGOEc859lWXiCKK3bUhnLNRY7r4ooRKkwLULaT13wPlYRZEurLbpZXpyVshZRkyz
hBAfkdnlzTMQFYZ7oWRpWXKg9lMtRtubEoFrCCSueK0A328qJfMgMNwO9eGNrHYt
/LZpOKe8Qr+0MvihbW1PceyaBsY5RxlqO2+WzaGx4x1WxS0i0T3fKti7uZiO6Ofy
9kUZGHfrVNrptILwcZJpa8NV0lpl
-----END CERTIFICATE-----
]]

local intermediate_CA = [[
-----BEGIN CERTIFICATE-----
MIIFnTCCA4WgAwIBAgICEAAwDQYJKoZIhvcNAQELBQAwYDELMAkGA1UEBhMCVVMx
CzAJBgNVBAgMAkNBMQswCQYDVQQHDAJTRjENMAsGA1UECgwEa29uZzEMMAoGA1UE
CwwDRlRUMRowGAYDVQQDDBF3d3cucm9vdC5rb25nLmNvbTAeFw0yNDA3MDgxMzQx
NTZaFw0zNDA3MDYxMzQxNTZaMFsxCzAJBgNVBAYTAlVTMQswCQYDVQQIDAJDQTEN
MAsGA1UECgwEa29uZzEMMAoGA1UECwwDRlRUMSIwIAYDVQQDDBl3d3cuaW50ZXJt
ZWRpYXRlLmtvbmcuY29tMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
rtjKuoq8d7XQWZEKk4wkF/4wnRXJ56uoKRaV45lHAtLE2SPjeWt8L2Fjs2MpXCkp
2E2G7A9OjWTnsy+miSV7pP2DOtfgjc7OtnPNRbbipO6x5E8g/XoXZK+h8eYWcZHU
mjwYnBB2AqjUyx41ffjTSVWmky7tB+BTPzkk4SsQk0JJ1OIsT0EJEbYXil1UPVF1
Rxqal2C8skNqmM+zHQaw/T9/dbP3GjS7YcMSddV+obFFXuUZHU8K7Uo+NOzzxJap
eCaOxYYfFROfSsJ78qbU36XoVkGglmanHl1/8fPTo77xNmHV2KJr84ZBTcRl8fgp
mmxdEoNDXjLeVTGoF02C86fj46Sb9yW4NgVLHpoCOqCofa+BA0mB4EQJ0OQcSAJS
muX8edS2pSRue7pdwqHtYZhSLQK5qduFPF+acEDddTBkZeBlcEX1NsCgwmhRnyTT
FvrAsYOyxXrylSR8J53RapAwTBRA9ye5EGZS/BQBlZ5x2IfhnQiWkmkVYfJKCViV
GHLSr9B0keNEtchHLf3aou0gkPWQlpHJ6SfyI3d6tE+wAO+Hs1RLfbDarv7bXI38
ehQJbNuX1Ff00QfxyrGhPRFexTp6txG6br7N4A4otCyqtAY/uihdNNR0nkzGlheW
xbRKiF4qOR2hWXAm1dSlcSpeWPyjiEliKt7dH624YHkCAwEAAaNmMGQwHQYDVR0O
BBYEFCj41/9E/zACegmXiqXwBilwrbMXMB8GA1UdIwQYMBaAFPpfBdVbi36ngtdz
xn9hiDXjIGqQMBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMA0G
CSqGSIb3DQEBCwUAA4ICAQBAlbCHI77V+CMCbC2OWJK/Aa73x4aWGe2sVV3w8tiM
mBZSD6ejcwcZ+wNh85acioi+O/Ku2pMuCgrxdNGryM3vQLCiFus/3jc3K/UQoS0M
2lW12GE+7hGTk+uRNHvRwGdQKeUlqNTeVSJ+rBZ0qug2buBHAEt3IquFZ/vPhzpK
o3g79GgTGLO242skST7veuvdfoXdgINslGU4sJL4ra7IApb0niH17H6jZLQGpLIy
cY0u0+SWzqcXkA7khHHSCQN+DA3qoWN+ZkyXQSX3xpq0Op6ezXJphcZAgHVCC8We
pS6LcrXYWFJAoh29NJrZEgRJHWBElTDANgBSpElDIOfixq6Hkj2Bc3AiKsEGFCFg
VfTH7Iv4SNH0b0Pcpp7X6q6YvR+BDrDStOndbTzgUhap8Ktg+6+DJNfPQ8j+SQbU
TOpDVm1sqSbfwTcQlNtLFUtvDd7Ia6Qn0HreRhGCkWbGRrYWBsxBc0AaA6d+QoON
QRKv01Oi2iawMJ088jcceJ0AwnxOdGbkvHj8oqNnBrEI0wkS2W2uZhLll5yUKXLi
3Mn4YU2t6Se0M2ZAMuKM5p7UiOg5FZuyhGXW2CI43N/XlsBAuKPqjBeJnRtwau6X
eQylWzvxoqs2wN9V0TMdcwsQTDSOeWDwdrsi0yynt1z7hJI4OzAJqYeLrU2S9hgu
SA==
-----END CERTIFICATE-----
]]

local CA_MULTI = [[
-----BEGIN CERTIFICATE-----
MIIFoTCCA4mgAwIBAgIUQDBLwIychoRbVRO44IzBBk9R4oYwDQYJKoZIhvcNAQEL
BQAwWDELMAkGA1UEBhMCVVMxEzARBgNVBAgMCkNhbGlmb3JuaWExFTATBgNVBAoM
DEtvbmcgVGVzdGluZzEdMBsGA1UEAwwUS29uZyBUZXN0aW5nIFJvb3QgQ0EwHhcN
MTkwNTAyMTkzNDQyWhcNMzkwNDI3MTkzNDQyWjBYMQswCQYDVQQGEwJVUzETMBEG
A1UECAwKQ2FsaWZvcm5pYTEVMBMGA1UECgwMS29uZyBUZXN0aW5nMR0wGwYDVQQD
DBRLb25nIFRlc3RpbmcgUm9vdCBDQTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
AgoCggIBAMp6IggUp3aSNRbLAac8oOkrbUnFuxtlKGYgg8vfA2UU71qTktigdwO6
Kod0/M+daO3RDqJJXQL2rD14NDO3MaextICanoQSEe+nYyMFUIk+QplXLD3fbshU
nHoJcMS2w0x4cm1os4ebxR2Evndo6luz39ivcjau+BL+9iBAYL1g6+eGOjcSy7ft
1nAMvbxcQ7dmbAH2KP6OmF8cok+eQWVqXEjqtVx5GDMDlj1BjX6Kulmh/vhNi3Hr
NEi+kPrw/YtRgnqnN0sv3NnAyKnantxy7w0TDicFjiBsSIhjB5aUfWYErBR+Nj/m
uumwc/kRJcHWklqDzxrZKCIyOyWcE5Dyjjr46cnF8HxhYwgZcwkmgTtaXOLpBMlo
XUTgOQrWpm9HYg2vOJMMA/ZPUJ2tJ34/4RgiA00EJ5xG8r24suZmT775l+XFLFzp
Ihxvs3BMbrWsXlcZkI5neNk7Q/1jLoBhWeTYjMpUS7bJ/49YVGQZFs3xu2IcLqeD
5WsB1i+EqBAI0jm4vWEynsyX+kS2BqAiDtCsS6WYT2q00DTeP5eIHh/vHsm75jJ+
yUEb1xFxGnNevLKNTcHUeXxPUnowdC6wqFnaJm7l09qVGDom7tLX9i6MCojgpAP0
hMpBxzh8jLxHh+zZQdiORSFdYxNnlnWwbic2GUJruiQVLuhpseenAgMBAAGjYzBh
MB0GA1UdDgQWBBQHT/IIheEC2kdBxI/TfGqUxWJw9zAfBgNVHSMEGDAWgBQHT/II
heEC2kdBxI/TfGqUxWJw9zAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB
hjANBgkqhkiG9w0BAQsFAAOCAgEAqXZjy4EltJCRtBmN0ohAHPWqH4ZJQCI2HrM3
wHB6c4oPWcJ+M2PfmYPUJo9VMjvn4S3sZuAysyoHduvRdGDnElW4wglL1xxpoUOx
FqoZUoYWV8hDFmUTWM5b4CtJxOPdTAd8VgypulM3iUEzBQrjR6tnMOdkiFMOmVag
0/Nnr+Tcfk/crMCx3xsVnisYjJoQBFBH4UY+gWE/V/MS1Sya4/qTbuuCUq+Qym5P
r8TkWAJlg7iVVLbZ2j94VUdpiQPWJEGMtJck/NEmOTruhhQlT7c1u/lqXCGj7uci
LmhLsBVmdtWT9AWS8Rl7Qo5GXbjxKIaP3IM9axhDLm8WHwPRLx7DuIFEc+OBxJhz
wkr0g0yLS0AMZpaC6UGbWX01ed10U01mQ/qPU5uZiB0GvruwsYWZsyL1QXUeqLz3
/KKrx3XsXjtBu3ZG4LAnwuxfeZCNw9ofg8CqF9c20ko+7tZAv6DCu9UL+2oZnEyQ
CboRDwpnAlQ7qJVSp2xMgunO3xxVMlhD5LZpEJz1lRT0nQV3uuLpMYNM4FS9OW/X
MZSzwHhDdCTDWtc/iRszimOnYYV8Y0ubJcb59uhwcsHmdfnwL9DVO6X5xyzb8wsf
wWaPbub8SN2jKnT0g6ZWuca4VwEo1fRaBkzSZDqXwhkBDWP8UBqLXMXWHdZaT8NK
0NEO74c=
-----END CERTIFICATE-----
]]

local CA_MULTI_INTER = [[
-----BEGIN CERTIFICATE-----
MIICsjCCAZqgAwIBAgICEAAwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHUm9v
dC1jYTAgFw0yMjEwMTkxNDQzNDVaGA8yMTIyMDkyNTE0NDM0NVowEjEQMA4GA1UE
AwwHSW50ZXJtLjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ6uSUl/
FBmIzbq+UD1HROTiJ+ftJa0KwgEg0JwsKbd+9Ne92MlNNzG9glO8eWlIRsZTlkz9
DxDXFJIMRqP7Fn9ZPeOAi2/VH+xIctBaIRcF/E/RwwrxnKOpaJvXOFudUg+YIPjP
H59Wof4PQMU9ijArc6KNRuVlMDQlC9MSaX9lhUzO4Nk8IT9rmLi0Z5O0KK+mFkWv
uN2uL9TqEumvea+Y5JKDitJxwFmGjGB18GIoKT0fOZVio/xyMuv7t7PybzE87wsd
bACkqO48pwwIMC/TCpeWaxZ1+sSoT3zZXdD+tua/MLIM2ubrmBZFJKYP8mxOqUgK
D29gWpcuZAIlrnUCAwEAAaMQMA4wDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQsF
AAOCAQEAVHSP6GPjLmvAuyOWncRKgBWJaP17UF0lZYIkJDW258nTqmQD2FMlNrp5
l/r/5pkl45BOsf3kxsqjZNx/1QuyLfeb6R7BIWMSzdFvNuzYjqyfQHADxTuq6cCA
3/eZ+fQA8da6LSLeIH+zKftNjDLjqAEVziID4ZQd1U2tHTMgFwNjlAH/ydAtqmdN
HkWpdejvtYnUSWQrcJZN/C/vFGukNly06LFRd71iTHyPWg+8nybJXFOMfrW6qfMi
SRAb/oQJaOMxXNrpXEQv/vbO8BK3LGmq2Bm2WIVFUhDKEdOqSvmeWoa8eM0bKT39
fs6geD+F2d4dQAUspVmBp1z6nlb/FA==
-----END CERTIFICATE-----
]]


local intermediate_CA_cert = [[
-----BEGIN CERTIFICATE-----
MIICsjCCAZqgAwIBAgICEAAwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHUm9v
dC1jYTAgFw0yMjEwMTkxNDQzNDVaGA8yMTIyMDkyNTE0NDM0NVowEjEQMA4GA1UE
AwwHSW50ZXJtLjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ6uSUl/
FBmIzbq+UD1HROTiJ+ftJa0KwgEg0JwsKbd+9Ne92MlNNzG9glO8eWlIRsZTlkz9
DxDXFJIMRqP7Fn9ZPeOAi2/VH+xIctBaIRcF/E/RwwrxnKOpaJvXOFudUg+YIPjP
H59Wof4PQMU9ijArc6KNRuVlMDQlC9MSaX9lhUzO4Nk8IT9rmLi0Z5O0KK+mFkWv
uN2uL9TqEumvea+Y5JKDitJxwFmGjGB18GIoKT0fOZVio/xyMuv7t7PybzE87wsd
bACkqO48pwwIMC/TCpeWaxZ1+sSoT3zZXdD+tua/MLIM2ubrmBZFJKYP8mxOqUgK
D29gWpcuZAIlrnUCAwEAAaMQMA4wDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQsF
AAOCAQEAVHSP6GPjLmvAuyOWncRKgBWJaP17UF0lZYIkJDW258nTqmQD2FMlNrp5
l/r/5pkl45BOsf3kxsqjZNx/1QuyLfeb6R7BIWMSzdFvNuzYjqyfQHADxTuq6cCA
3/eZ+fQA8da6LSLeIH+zKftNjDLjqAEVziID4ZQd1U2tHTMgFwNjlAH/ydAtqmdN
HkWpdejvtYnUSWQrcJZN/C/vFGukNly06LFRd71iTHyPWg+8nybJXFOMfrW6qfMi
SRAb/oQJaOMxXNrpXEQv/vbO8BK3LGmq2Bm2WIVFUhDKEdOqSvmeWoa8eM0bKT39
fs6geD+F2d4dQAUspVmBp1z6nlb/FA==
-----END CERTIFICATE-----
]]

local example_dot_test_CA = [[
-----BEGIN CERTIFICATE-----
MIIDlzCCAn+gAwIBAgIUT5Leyi0wONaznFBFod91rGzcatUwDQYJKoZIhvcNAQEL
BQAwWzELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMQswCQYDVQQHDAJTRjENMAsG
A1UECgwEa29uZzEMMAoGA1UECwwDRlRUMRUwEwYDVQQDDAxrb25ndGVzdHJvb3Qw
HhcNMjQwMzAxMjE1NDMwWhcNMzQwMjI3MjE1NDMwWjBbMQswCQYDVQQGEwJVUzEL
MAkGA1UECAwCQ0ExCzAJBgNVBAcMAlNGMQ0wCwYDVQQKDARrb25nMQwwCgYDVQQL
DANGVFQxFTATBgNVBAMMDGtvbmd0ZXN0cm9vdDCCASIwDQYJKoZIhvcNAQEBBQAD
ggEPADCCAQoCggEBAK9N4qErsI1j+YxXwmorXlGxhBfmONrMt4xspdhHI0JO84os
apRNys6sObJt0gGGDS2kcwSvhi8aKS0eedjO5nP7VZbw06OebTNdOGa5/TXC5ALf
KmR660AH9VcPWS/8ArYbiAWdPKsFB5RHiywzi2YrO1+x1v1kDXE+T3QTTJyv6d7Z
uWJfmIaR2E7UVxZ7KZfxAeUnW4jhnxFvS+vG6hadly78k2NVY6Xdc1YuCuF2tB+Q
VciKe171X6KGl/WhJyuWcX1Ixn/v/C63iYZQ3bc7S+L6PHQpBZ+6QFGVXry9ohng
8QTgVUNoPwEPuHflvOoaP90WzMSY6xlc9RJP/lECAwEAAaNTMFEwHQYDVR0OBBYE
FJu3/dFOcc11+TwBJKBXI/fIKpYLMB8GA1UdIwQYMBaAFJu3/dFOcc11+TwBJKBX
I/fIKpYLMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAITdjzW4
ERBKwWCSslCLxIYydFwo+PwKe6G0/EPA7h8qYp7JrUOBClwEs0pmb1dNbVPm1svF
eiafrzGxuFLjBQE2xSOsiZxvtkOx+IY7/TsVLVDaTsRDELzQdAtBtOaWaxnI+OYF
CK8mflxn67oL3d1jNSDdS1fGXfGauTT71Lg2JFTtHSpYWy8/lSA3ekaqD4IhBbXa
/Fz6bxxgWlk34U2zhd2ngIhxaU1SpDsHPycgUzkAaEPpQbWT+CJ5EzzWLHacttAv
j6/KzWk9uCuufr+1CZbv0OT6UywnCHHchxgA/feiZhEzFEfOocCL2RKOqx09wqsh
KTEH7cRqH+FlGsE=
-----END CERTIFICATE-----
]]

local url_encoded_header_value = "-----BEGIN%20CERTIFICATE-----%0AMIIFIjCCAwqgAwIBAgICIAEwDQYJKoZIhvcNAQELBQAwYDELMAkGA1UEBhMCVVMx%0AEzARBgNVBAgMCkNhbGlmb3JuaWExFTATBgNVBAoMDEtvbmcgVGVzdGluZzElMCMG%0AA1UEAwwcS29uZyBUZXN0aW5nIEludGVybWlkaWF0ZSBDQTAeFw0xOTA1MDIyMDAz%0AMTFaFw0yOTA0MjgyMDAzMTFaMFMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIDApDYWxp%0AZm9ybmlhMRUwEwYDVQQKDAxLb25nIFRlc3RpbmcxGDAWBgNVBAMMD2Zvb0BleGFt%0AcGxlLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJldMxsZHDxA%0ARpbSXdIFZiTf8D0dYgsPnsmx5tVjA%2FzrVBSVBPO9KunaXNm4Z6JWmUwenzFGbzWP%0ANLfbLn4khuoczzqSru5XfbyH1HrD0cd5lkf44Dw1%2FotfIFDBleiR%2FOWEiAxwS4zi%0AxIajNyvLr3gC5dv%2BF%2BJuWpW1yVQxybIDQWoI25xpd3%2BZkXO%2BOLkToo%2BYpuwIDlUj%0A6Rkm5kbqoxDpaDihA2bsAqjNG7G%2BSHthaNyACsQsU%2Ft6BHSWzHumScN0CxJ%2BTeVH%0AfTZklelItZ6YP0B0RQjzvSGA423UgALzqJglGPe8UDjm3BMlg2xhTfnfy1J6Vmbt%0A5jx6FOXUARsCAwEAAaOB8jCB7zAJBgNVHRMEAjAAMBEGCWCGSAGG%2BEIBAQQEAwIF%0AoDAzBglghkgBhvhCAQ0EJhYkT3BlblNTTCBHZW5lcmF0ZWQgQ2xpZW50IENlcnRp%0AZmljYXRlMB0GA1UdDgQWBBRTzNOmhGRXaZamxVfnlKXarIOEmDAfBgNVHSMEGDAW%0AgBQLDgQOl%2FhtYk8k8DvGb9IKO40RETAOBgNVHQ8BAf8EBAMCBeAwHQYDVR0lBBYw%0AFAYIKwYBBQUHAwIGCCsGAQUFBwMEMCsGA1UdEQQkMCKBD2Zvb0BleGFtcGxlLmNv%0AbYEPYmFyQGV4YW1wbGUuY29tMA0GCSqGSIb3DQEBCwUAA4ICAQBziDuVjU0I1CwO%0Ab1Cx2TJpzi3l5FD%2FozrMZT6F3EpkJFGZWgXrsXHz%2F0qKTrsbB2m3%2Ffcyd0lwQ5Lh%0Afz8X1HPrwXa3BqZskNu1vOUNiqAYWvQ5gtbpweJ96LzMSYVGLK78NigYTtK%2BRgq3%0AAs5CVfLXDBburrQNGyRTsilCQDNBvIpib0eqg%2FHJCNDFMPrBzTMPpUutyatfpFH2%0AUwTiVBfA14YYDxZaetYWeksy28XH6Uj0ylyz67VHND%2BgBMmQNLXQHJTIDh8JuIf2%0Aec6o4HrtyyuRE3urNQmcPMAokacm4NKw2%2Bog6Rg1VS%2FpckaSPOlSEmNnKFiXStv%2B%0AAVd77NGriUWDFCmnrFNOPOIS019W0oOk6YMwTUDSa86Ii6skCtBLHmp%2FcingkTWg%0A7KEbdT1uVVPgseC2AFpQ1BWJOjjtyW3GWuxERIhuab9%2FckTz6BuIiuK7mfsvPBrn%0ABqjZyt9WAx8uaWMS%2FZrmIj3fUXefaPtl27jMSsiU5oi2vzFu0xiXJb6Jr7RQxD3O%0AXRnycL%2FchWnp7eVV1TQS%2BXzZ3ZZQIjckDWX4E%2BzGo4o9pD1YC0eytbIlSuqYVr%2Ft%0AdZmD2gqju3Io9EXPDlRDP2VIX9q1euF9caz1vpLCfV%2BF8wVPtZe5p6JbNugdgjix%0AnDZ2sD2xGXy6%2FfNG75oHveYo6MREFw%3D%3D%0A-----END%20CERTIFICATE-----%0A-----BEGIN%20CERTIFICATE-----%0AMIIFmjCCA4KgAwIBAgICEAAwDQYJKoZIhvcNAQELBQAwWDELMAkGA1UEBhMCVVMx%0AEzARBgNVBAgMCkNhbGlmb3JuaWExFTATBgNVBAoMDEtvbmcgVGVzdGluZzEdMBsG%0AA1UEAwwUS29uZyBUZXN0aW5nIFJvb3QgQ0EwHhcNMTkwNTAyMTk0MDQ4WhcNMjkw%0ANDI5MTk0MDQ4WjBgMQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEV%0AMBMGA1UECgwMS29uZyBUZXN0aW5nMSUwIwYDVQQDDBxLb25nIFRlc3RpbmcgSW50%0AZXJtaWRpYXRlIENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA0dnj%0AoHlJmNM94vQnK2FIIQJm9OAVvyMtAAkBKL7Cxt8G062GHDhq6gjQ9enuNQE0l3Vv%0AmSAh7N9gNlma6YbRB9VeG54BCuRQwCxveOBiwQvC2qrTzYI34kF%2FAeflrDOdzuLb%0Azj5cLADKXGCbGDtrSPKUwdlkuLs3pRr%2FYAyIQr7zJtlLz%2BE0GBYp0GWnLs0FiLSP%0AqSBWllC9u8gt2MiKyNlXw%2BkZ8lofOehCJzfFr6qagVklPw%2B8IpU6OGmRLFQVwVhp%0AzdAJmAGmSo%2FAGNKGqDdjzC4N2l4uYGH6n2KmY2yxsLBGZgwtLDst3fK4a3Wa5Tj7%0AcUwCcGLGtfVTaIXZYbqQ0nGsaYUd%2Fmhx3B3Jk1p3ILZ72nVYowhpj22ipPGal5hp%0AABh1MX3s%2FB%2B2ybWyDTtSaspcyhsRQsS6axB3DwLOLRy5Xp%2FkqEdConCtGCsjgm%2BU%0AFzdupubXK%2BKIAmTKXDx8OM7Af%2FK7kLDfFTre40sEB6fwrWwH8yFojeqkA%2FUqhn5S%0ACzB0o4F3ON0xajsw2dRCziiq7pSe6ALLXetKpBr%2BxnVbUswH6BANUoDvh9thVPPx%0A1trkv%2BOuoJalkruZaT%2B38%2BiV9xwdqxnR7PUawqSyvrEAxjqUo7dDPsEuOpx1DJjO%0AXwRJCUjd7Ux913Iks24BqpPhEQz%2FrZzJLBApRVsCAwEAAaNmMGQwHQYDVR0OBBYE%0AFAsOBA6X%2BG1iTyTwO8Zv0go7jRERMB8GA1UdIwQYMBaAFAdP8giF4QLaR0HEj9N8%0AapTFYnD3MBIGA1UdEwEB%2FwQIMAYBAf8CAQAwDgYDVR0PAQH%2FBAQDAgGGMA0GCSqG%0ASIb3DQEBCwUAA4ICAQAWzIvIVM32iurqM451Amz0HNDG9j84cORnnaRR5opFTr3P%0AEqI3QkgCyP6YOs9t0QSbA4ur9WUzd3c9Ktj3qRRgTE%2B98JBOPO0rv%2BKjj48aANDV%0A5tcbI9TZ9ap6g0jYr4XNT%2BKOO7E8QYlpY%2FwtokudCUDJE9vrsp1on4Bal2gjvCdh%0ASU0C1lnj6q6kBdQSYHrcjiEIGJH21ayVoNaBVP%2FfxyCHz472w1xN220dxUI%2FGqB6%0Apjcuy9cHjJHJKJbrkdt2eDRAFP5cILXc3mzUoGUDHY2JA1gtOHV0p4ix9R9AfI9x%0AsnBEFiD8oIpcQay8MJH%2Fz3NLEPLoBW%2BJaAAs89P%2Bjcppea5N9vbiAkrPi687BFTP%0APWPdstyttw6KrvtPQR1%2BFsVFcGeTjo32%2FUrckJixdiOEZgHk%2BdeXpp7JoRdcsgzD%0A%2BokrsG79%2FLgS4icLmzNEp0IV36QckEq0%2BALKDu6BXvWTkb5DB%2FFUrovZKJgkYeWj%0AGKogyrPIXrYi725Ff306124kLbxiA%2B6iBbKUtCutQnvut78puC6iP%2Ba2SrfsbUJ4%0AqpvBFOY29Mlww88oWNGTA8QeW84Y1EJbRkHavzSsMFB73sxidQW0cHNC5t9RCKAQ%0AuibeZgK1Yk7YQKXdvbZvXwrgTcAjCdbppw2L6e0Uy%2BOGgNjnIps8K460SdaIiA%3D%3D%0A-----END%20CERTIFICATE-----"

local base64_encoded_header_value = "MIIFMDCCAxigAwIBAgICEAAwDQYJKoZIhvcNAQELBQAweTELMAkGA1UEBhMCR0IxEDAOBgNVBAgMB0VuZ2xhbmQxEjAQBgNVBAoMCUFsaWNlIEx0ZDEoMCYGA1UECwwfQWxpY2UgTHRkIENlcnRpZmljYXRlIEF1dGhvcml0eTEaMBgGA1UEAwwRQWxpY2UgTHRkIFJvb3QgQ0EwHhcNMTkwNzEwMjIzNzE0WhcNMjAwNzE5MjIzNzE0WjB5MQswCQYDVQQGEwJHQjEQMA4GA1UECAwHRW5nbGFuZDESMBAGA1UECgwJQWxpY2UgTHRkMSgwJgYDVQQLDB9BbGljZSBMdGQgQ2VydGlmaWNhdGUgQXV0aG9yaXR5MRowGAYDVQQDDBFBbGljZSBMdGQgUm9vdCBDQTCCAR4wDQYJKoZIhvcNAQEBBQADggELADCCAQYCgf4L5Pg9ApoNSh6NO8e93na6yJ74Q5K2INfLLZxMQHLl4wxkeKhrnTxhL3P+3BX/I6+69M1N7wo3L/5q69p0Jjt7A0NBatZD+mrR0lUM6fEAXwqoBffhgoA3K+3e4MtPSnYlsf+ivBOA+X9RIvCpjWCT9cnSU1n5O1d+flLo+E+j8C7BMG3Q4nPRBpM9HtsY5NgsQJ2XZYFoBg72WZtSHuH4JET6omicCce4Maw76NXzwQo5sVPdPKPPX9apaEsX+z37zN1MOStLYbMRn/FbSK7KDJVjsiiDen04ny9GRGrWtNByV6Rm7Ifk596Q68wVs2FOAY5IivBDLBO299psLwIDAQABo4HFMIHCMAkGA1UdEwQCMAAwEQYJYIZIAYb4QgEBBAQDAgWgMDMGCWCGSAGG+EIBDQQmFiRPcGVuU1NMIEdlbmVyYXRlZCBDbGllbnQgQ2VydGlmaWNhdGUwHQYDVR0OBBYEFHrkjU1qFIU646YKNOBKXvIO8zkSMB8GA1UdIwQYMBaAFMGzDZpdYeW8oMiVLqC2Sj62naUQMA4GA1UdDwEB/wQEAwIF4DAdBgNVHSUEFjAUBggrBgEFBQcDAgYIKwYBBQUHAwQwDQYJKoZIhvcNAQELBQADggIBAH8BlJzHGluYj5XXAiV7RIhtlVRJxL9Cfr3WIpwKr1BJJXsPQzu8s10f8k4691ZFoTTDvjs/6qkYt4FxZhlrmCxS+mocRIqfEeyud4anFm5PAUX4QmuvX2Z0uxV18xCpT3/9apDJRACiY02AP0AEOhAemD7T4Dbpr518V+BWveNVfieoGFD7k6OvUShDYf0KOMvvjEjatoM6it6ill6KjqJLQ7cgOU5DzHUjoAzg7Lwtdt6KpTZhiYQa+Abe5jlLPGOnluaUmZktlfy7TOJtmmo5nE9i2Ad7O15YF1J+kqEvIeeB34YNGu8nI7RxYUneVOc3XGSlVvKLMPtJoW9MVFoLMfDQuG22cFjWajftCpCc2+lBoMYgSbPNo06nXATmZIzF8A3XWQd3DLzvltq4s1apTXcuZAnaJFU5A7FjPIyIaXjSXJCVZ7uQkUkBJS3qavKa38m8+Fi3ss5cYgVzbJZ0TdHpzG1fvG/ngWKbIFR/jpdlA37Oku2hIxRkmXTG2tjeqAh/eIAWyZclKNuloSV39RcBG/e9LwiI9naTlJEnaz4GUkr0TjXp2AEOV950kEblqsQ0h00Dl3+aq4Ld4+6gKBAtSufFCh14ci67hez1gww5Y73Ih13uatoCALomghs67Aix5oL1AwPnrnYohWKbG8iG1dwsa769Llvr9IFM"

local base64_encoded_header_value2 = "MIIDkDCCAnigAwIBAgIUE5yjcui4Ep07c3w/e5tyd7hANpYwDQYJKoZIhvcNAQELBQAwWzELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMQswCQYDVQQHDAJTRjENMAsGA1UECgwEa29uZzEMMAoGA1UECwwDRlRUMRUwEwYDVQQDDAxrb25ndGVzdHJvb3QwHhcNMjQwMzAxMjIyNzI2WhcNMzQwMjI3MjIyNzI2WjBZMQswCQYDVQQGEwJVUzELMAkGA1UECAwCQ0ExCzAJBgNVBAcMAlNGMQ0wCwYDVQQKDARLT05HMQwwCgYDVQQLDANFTkcxEzARBgNVBAMMCmtvbmdjbGllbnQwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASusf2oEvfEtHjVLFo7A5cX/IWfAnlZgIjRU/vjf26c1FV5dEgJQD84f0kYCRQof7whmihvbPDbYfJ0C1XxnHuWo4IBFzCCARMwFwYDVR0RBBAwDoIMZXhhbXBsZS50ZXN0MAwGA1UdEwEB/wQCMAAwHQYDVR0OBBYEFFTBrChdyFoE3UT9ZVnvmxGj6mfFMIGYBgNVHSMEgZAwgY2AFJu3/dFOcc11+TwBJKBXI/fIKpYLoV+kXTBbMQswCQYDVQQGEwJVUzELMAkGA1UECAwCQ0ExCzAJBgNVBAcMAlNGMQ0wCwYDVQQKDARrb25nMQwwCgYDVQQLDANGVFQxFTATBgNVBAMMDGtvbmd0ZXN0cm9vdIIUT5Leyi0wONaznFBFod91rGzcatUwDgYDVR0PAQH/BAQDAgWgMCAGA1UdJQEB/wQWMBQGCCsGAQUFBwMCBggrBgEFBQcDATANBgkqhkiG9w0BAQsFAAOCAQEAj0/A4QwtaxNiFd62/2k51I9M7dity6m1ZfZj02UGx0plJA4L9uCDJxhDMjgKZrxQT/xAat+8c0f+7Xhr/dbUA/GIF4Kv8JsIHNBNxudsbpBIm/lsFICKbnrDZEEI0ldeOE8RnLU4tWUWR8Nc6Jr5XOingBY1B1G2F/IC7BxR1KHiH8naIXjUrZ4r5aKTMMvYqXGvuEz7AdKyRN2f3ambd2sHXXTLnKoTQuoadc4A9Se4oDMeWHHp1f1ewq6aSfZV3zDYLgC9WOM5SXkmQPpXrZyC3wfyAJWn1mw3hNelXkA0MPn+OhOwDK2nB9KNww3oGzHN7b8tORDsbYsT0WGSKA=="

local base64_encoded_header_value3 = "MIIFNTCCAx2gAwIBAgICEAEwDQYJKoZIhvcNAQELBQAwWzELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMQ0wCwYDVQQKDARrb25nMQwwCgYDVQQLDANGVFQxIjAgBgNVBAMMGXd3dy5pbnRlcm1lZGlhdGUua29uZy5jb20wHhcNMjQwNzA4MTU0MDU4WhcNMjUwNzA4MTU0MDU4WjBkMQswCQYDVQQGEwJVUzELMAkGA1UECAwCQ0ExCzAJBgNVBAcMAlNGMQ0wCwYDVQQKDARrb25nMQwwCgYDVQQLDANGVFQxHjAcBgNVBAMMFW9jc3AtdmFsaWRAa29uZ2hxLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKlE6ZxI3HDZGG+ikyDHJue4oH1f8WcP1BK1eBiACVETN5eVbPKfa6iayX8aDCeVi+Mbb3TtYLhL8t5l10B/+ZXsclpa8QfAcOhJuGWk/C/VGsYGNpsStzHERhEusz7G8LgfZdb4zjP16LtlcjvFfVe8H+NF29Cfk/fRFJx6uyudH5DdLBDULUUuO3u5u5iVzBuWwjZDAifUuICQRCi5UfDXGniuJR7IGbXtXukUviFCLcqOGtSudumyb8hD+ozd23lUCLt8BwvwIZ0DuEQe/F/JplvIi4BrPOCswuCX57svHQ8uwdnnk9l6cNwTseUxGDztqdX6WJjbV5ki0dy5RD8CAwEAAaOB+TCB9jAJBgNVHRMEAjAAMBEGCWCGSAGG+EIBAQQEAwIFoDAzBglghkgBhvhCAQ0EJhYkT3BlblNTTCBHZW5lcmF0ZWQgQ2xpZW50IENlcnRpZmljYXRlMB0GA1UdDgQWBBSE2aVrcyxHmfunegxa/RsSTurpbjAfBgNVHSMEGDAWgBQo+Nf/RP8wAnoJl4ql8AYpcK2zFzAOBgNVHQ8BAf8EBAMCBeAwHQYDVR0lBBYwFAYIKwYBBQUHAwIGCCsGAQUFBwMEMDIGCCsGAQUFBwEBBCYwJDAiBggrBgEFBQcwAYYWaHR0cDovL29jc3BzZXJ2ZXI6MjU2MDANBgkqhkiG9w0BAQsFAAOCAgEAik33a/8spuzdjafiPd3K3Rr8qQtzTEo/S9A6YJB9fYrM4079KWN6NIQLNI/dqIEmCor4mxwS+QwiyIXE/EAVg3tAS4/f7G8v7xjwxBuT/HFodSndfblCrnVQvvhUt3toEOwMmMThe6uWyCqoO3VSybQIvkmZxjPDCy3xqTd3DTYDIUPia323xyxvpo9O3q0HAxI3lcZIKcc729psxlXNgiHfNFqwhGiV2kaUgj/7OD+qKKRB9bKtnt9ZIOlOE3zdpZsfNAyKcLFWhMdMf/KKVw+ROnLMm6iCkvEal7VQjNvz8KF9MeeRNrqh6tS6hOEWsXlkn9yZx365h00v6iF7ouJhZuqaFU2nMLpnEbUMaGEnk5jj3p8tNh5GWVtkmVf+i8ccVbiHme4/kzDYdEl8bbxk/+zXJYrkH8QE919w5nQL8eIBPhAmgKjFtanf72B9iRQthUeGT3GP1MGo4k8ZbNB2accR5JyvL2l+HmnZIj14BcDpgHlvqpbb1y8AuhHLjdVGUgsMoNX0ppgJ4/TXT45GKi7Jre6mOI3zIU3rgd830ZgEIFQPmAbaboJ2a2VykdEy1/O3iChsaDpklbSp/yv+ljTCpj0Fe8/NJk0uqDHpvLYqOhISYTohx10qRF20dT6u1m6pMJETLlDE64n0R0JJmn98+LSYO++umTeszZQ="

local url_encoded_header_value_partial = "-----BEGIN%20CERTIFICATE-----%0AMIIFNTCCAx2gAwIBAgICEAEwDQYJKoZIhvcNAQELBQAwWzELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMQ0wCwYDVQQKDARrb25nMQwwCgYDVQQLDANGVFQxIjAgBgNVBAMMGXd3dy5pbnRlcm1lZGlhdGUua29uZy5jb20wHhcNMjQwNzA4MTU0MDU4WhcNMjUwNzA4MTU0MDU4WjBkMQswCQYDVQQGEwJVUzELMAkGA1UECAwCQ0ExCzAJBgNVBAcMAlNGMQ0wCwYDVQQKDARrb25nMQwwCgYDVQQLDANGVFQxHjAcBgNVBAMMFW9jc3AtdmFsaWRAa29uZ2hxLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKlE6ZxI3HDZGG%2BikyDHJue4oH1f8WcP1BK1eBiACVETN5eVbPKfa6iayX8aDCeVi%2BMbb3TtYLhL8t5l10B%2F%2BZXsclpa8QfAcOhJuGWk%2FC%2FVGsYGNpsStzHERhEusz7G8LgfZdb4zjP16LtlcjvFfVe8H%2BNF29Cfk%2FfRFJx6uyudH5DdLBDULUUuO3u5u5iVzBuWwjZDAifUuICQRCi5UfDXGniuJR7IGbXtXukUviFCLcqOGtSudumyb8hD%2Bozd23lUCLt8BwvwIZ0DuEQe%2FF%2FJplvIi4BrPOCswuCX57svHQ8uwdnnk9l6cNwTseUxGDztqdX6WJjbV5ki0dy5RD8CAwEAAaOB%2BTCB9jAJBgNVHRMEAjAAMBEGCWCGSAGG%2BEIBAQQEAwIFoDAzBglghkgBhvhCAQ0EJhYkT3BlblNTTCBHZW5lcmF0ZWQgQ2xpZW50IENlcnRpZmljYXRlMB0GA1UdDgQWBBSE2aVrcyxHmfunegxa%2FRsSTurpbjAfBgNVHSMEGDAWgBQo%2BNf%2FRP8wAnoJl4ql8AYpcK2zFzAOBgNVHQ8BAf8EBAMCBeAwHQYDVR0lBBYwFAYIKwYBBQUHAwIGCCsGAQUFBwMEMDIGCCsGAQUFBwEBBCYwJDAiBggrBgEFBQcwAYYWaHR0cDovL29jc3BzZXJ2ZXI6MjU2MDANBgkqhkiG9w0BAQsFAAOCAgEAik33a%2F8spuzdjafiPd3K3Rr8qQtzTEo%2FS9A6YJB9fYrM4079KWN6NIQLNI%2FdqIEmCor4mxwS%2BQwiyIXE%2FEAVg3tAS4%2Ff7G8v7xjwxBuT%2FHFodSndfblCrnVQvvhUt3toEOwMmMThe6uWyCqoO3VSybQIvkmZxjPDCy3xqTd3DTYDIUPia323xyxvpo9O3q0HAxI3lcZIKcc729psxlXNgiHfNFqwhGiV2kaUgj%2F7OD%2BqKKRB9bKtnt9ZIOlOE3zdpZsfNAyKcLFWhMdMf%2FKKVw%2BROnLMm6iCkvEal7VQjNvz8KF9MeeRNrqh6tS6hOEWsXlkn9yZx365h00v6iF7ouJhZuqaFU2nMLpnEbUMaGEnk5jj3p8tNh5GWVtkmVf%2Bi8ccVbiHme4%2FkzDYdEl8bbxk%2F%2BzXJYrkH8QE919w5nQL8eIBPhAmgKjFtanf72B9iRQthUeGT3GP1MGo4k8ZbNB2accR5JyvL2l%2BHmnZIj14BcDpgHlvqpbb1y8AuhHLjdVGUgsMoNX0ppgJ4%2FTXT45GKi7Jre6mOI3zIU3rgd830ZgEIFQPmAbaboJ2a2VykdEy1%2FO3iChsaDpklbSp%2Fyv%2BljTCpj0Fe8%2FNJk0uqDHpvLYqOhISYTohx10qRF20dT6u1m6pMJETLlDE64n0R0JJmn98%2BLSYO%2B%2BumTeszZQ%3D%0A-----END%20CERTIFICATE-----"

local url_encoded_header_value_missing_full = "-----BEGIN%20CERTIFICATE-----%0AMIIFIjCCAwqgAwIBAgICIAEwDQYJKoZIhvcNAQELBQAwYDELMAkGA1UEBhMCVVMx%0AEzARBgNVBAgMCkNhbGlmb3JuaWExFTATBgNVBAoMDEtvbmcgVGVzdGluZzElMCMG%0AA1UEAwwcS29uZyBUZXN0aW5nIEludGVybWlkaWF0ZSBDQTAeFw0xOTA1MDIyMDAz%0AMTFaFw0yOTA0MjgyMDAzMTFaMFMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIDApDYWxp%0AZm9ybmlhMRUwEwYDVQQKDAxLb25nIFRlc3RpbmcxGDAWBgNVBAMMD2Zvb0BleGFt%0AcGxlLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJldMxsZHDxA%0ARpbSXdIFZiTf8D0dYgsPnsmx5tVjA%2FzrVBSVBPO9KunaXNm4Z6JWmUwenzFGbzWP%0ANLfbLn4khuoczzqSru5XfbyH1HrD0cd5lkf44Dw1%2FotfIFDBleiR%2FOWEiAxwS4zi%0AxIajNyvLr3gC5dv%2BF%2BJuWpW1yVQxybIDQWoI25xpd3%2BZkXO%2BOLkToo%2BYpuwIDlUj%0A6Rkm5kbqoxDpaDihA2bsAqjNG7G%2BSHthaNyACsQsU%2Ft6BHSWzHumScN0CxJ%2BTeVH%0AfTZklelItZ6YP0B0RQjzvSGA423UgALzqJglGPe8UDjm3BMlg2xhTfnfy1J6Vmbt%0A5jx6FOXUARsCAwEAAaOB8jCB7zAJBgNVHRMEAjAAMBEGCWCGSAGG%2BEIBAQQEAwIF%0AoDAzBglghkgBhvhCAQ0EJhYkT3BlblNTTCBHZW5lcmF0ZWQgQ2xpZW50IENlcnRp%0AZmljYXRlMB0GA1UdDgQWBBRTzNOmhGRXaZamxVfnlKXarIOEmDAfBgNVHSMEGDAW%0AgBQLDgQOl%2FhtYk8k8DvGb9IKO40RETAOBgNVHQ8BAf8EBAMCBeAwHQYDVR0lBBYw%0AFAYIKwYBBQUHAwIGCCsGAQUFBwMEMCsGA1UdEQQkMCKBD2Zvb0BleGFtcGxlLmNv%0AbYEPYmFyQGV4YW1wbGUuY29tMA0GCSqGSIb3DQEBCwUAA4ICAQBziDuVjU0I1CwO%0Ab1Cx2TJpzi3l5FD%2FozrMZT6F3EpkJFGZWgXrsXHz%2F0qKTrsbB2m3%2Ffcyd0lwQ5Lh%0Afz8X1HPrwXa3BqZskNu1vOUNiqAYWvQ5gtbpweJ96LzMSYVGLK78NigYTtK%2BRgq3%0AAs5CVfLXDBburrQNGyRTsilCQDNBvIpib0eqg%2FHJCNDFMPrBzTMPpUutyatfpFH2%0AUwTiVBfA14YYDxZaetYWeksy28XH6Uj0ylyz67VHND%2BgBMmQNLXQHJTIDh8JuIf2%0Aec6o4HrtyyuRE3urNQmcPMAokacm4NKw2%2Bog6Rg1VS%2FpckaSPOlSEmNnKFiXStv%2B%0AAVd77NGriUWDFCmnrFNOPOIS019W0oOk6YMwTUDSa86Ii6skCtBLHmp%2FcingkTWg%0A7KEbdT1uVVPgseC2AFpQ1BWJOjjtyW3GWuxERIhuab9%2FckTz6BuIiuK7mfsvPBrn%0ABqjZyt9WAx8uaWMS%2FZrmIj3fUXefaPtl27jMSsiU5oi2vzFu0xiXJb6Jr7RQxD3O%0AXRnycL%2FchWnp7eVV1TQS%2BXzZ3ZZQIjckDWX4E%2BzGo4o9pD1YC0eytbIlSuqYVr%2Ft%0AdZmD2gqju3Io9EXPDlRDP2VIX9q1euF9caz1vpLCfV%2BF8wVPtZe5p6JbNugdgjix%0AnDZ2sD2xGXy6%2FfNG75oHveYo6MREFw%3D%3D%0A-----END%20CERTIFICATE-----"

-- FIXME: in case of FIPS build, the nginx refuses to send invalid client certificate to upstream
-- thus we skip the test for now
-- TODO
local bad_client_tests
if helpers.is_fips_build() then
  bad_client_tests = pending
else
  bad_client_tests = it
end

for _, strategy in strategies() do if strategy ~= "cassandra" then
  describe("Plugin: header-cert-auth (access) [#" .. strategy .. "]", function()
    local proxy_client, admin_client, proxy_ssl_client
    local bp, db
    local consumer, service, route_base64_encoded, route_aws_alb
    local consumer_multiple_certs, route_aws_alb_multiple_certs, ca_multi, ca_multi_intermediate
    local customized_consumer
    local plugin_multi
    local anonymous_user
    local default_consumer, default_consumer_route, example_test_ca_cert, default_consumer_by_username_route
    local no_default_consumer_route, nameless_default_consumer, nameless_default_consumer_route
    local no_match_default_consumer_route, bad_config_default_consumer_custom_id_route

    local ca_cert, intermediate_ca_cert
    local db_strategy = strategy ~= "off" and strategy or nil

    -- a non-existant consumer UUID
    local NOT_A_CONSUMER_UUID = '1bbbe5fc-4d55-420b-bd8a-298526f288c7'

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "ca_certificates",
        "header_cert_auth_credentials",
      }, { "header-cert-auth", })

      anonymous_user = bp.consumers:insert {
        username = "anonymous@example.com",
      }

      consumer = bp.consumers:insert {
        username = "ocsp-valid@konghq.com"
      }

      consumer_multiple_certs = bp.consumers:insert {
        username = "foo@example.com"
      }

      customized_consumer = bp.consumers:insert {
        username = "customized@example.com"
      }

      default_consumer = bp.consumers:insert {
        username = "default@example.com"
      }

      nameless_default_consumer = bp.consumers:insert {
        custom_id = "i-have-no-name",
        username = ngx_null,
      }

      service = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      route_base64_encoded = bp.routes:insert {
        hosts   = { "example.com.base64_encoded" },
        service = { id = service.id, },
      }

      route_aws_alb = bp.routes:insert {
        hosts   = { "example.com.url_encoded" },
        service = { id = service.id, },
      }

      route_aws_alb_multiple_certs = bp.routes:insert {
        hosts   = { "example.com.url_encoded.multiple-certs" },
        service = { id = service.id, },
      }

      default_consumer_route = bp.routes:insert {
        hosts   = { "example.test" },
        headers = {
          defaultconsumerbyuuid = {"true"},
        },
        service = { id = service.id, },
      }

      default_consumer_by_username_route = bp.routes:insert {
        hosts   = { "example.test" },
        headers = {
          defaultconsumerbyusername = {"true"},
        },
        service = { id = service.id, },
      }

      no_default_consumer_route = bp.routes:insert {
        hosts   = { "example.test" },
        headers = {
          noconsumer = {"true"},
        },
        service = { id = service.id, },
      }

      nameless_default_consumer_route = bp.routes:insert {
        hosts   = { "example.test" },
        headers = {
          namelessconsumer = {"true"},
        },
        service = { id = service.id, },
      }

      no_match_default_consumer_route = bp.routes:insert {
        hosts   = { "example.test" },
        headers = {
          nomatchconsumer = {"true"},
        },
        service = { id = service.id, },
      }

      bad_config_default_consumer_custom_id_route = bp.routes:insert {
        hosts   = { "example.test" },
        headers = {
          badconfigcustomid = {"true"},
        },
        service = { id = service.id, },
      }

      ca_cert = assert(db.ca_certificates:insert({
        cert = CA,
      }))

      intermediate_ca_cert = assert(db.ca_certificates:insert({
        cert = intermediate_CA,
      }))

      ca_multi = assert(db.ca_certificates:insert({
        cert = CA_MULTI,
      }))

      ca_multi_intermediate = assert(db.ca_certificates:insert({
        cert = CA_MULTI_INTER,
      }))

      example_test_ca_cert = assert(db.ca_certificates:insert({
        cert = example_dot_test_CA,
      }))

      assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = route_base64_encoded.id },
        config = {
          ca_certificates = { ca_cert.id, intermediate_ca_cert.id },
          certificate_header_name = "ssl-client-cert",
          certificate_header_format = "base64_encoded",
          revocation_check_mode = "SKIP",
          secure_source = false,
        },
      })

      assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = route_aws_alb.id },
        config = {
          ca_certificates = { ca_cert.id, intermediate_ca_cert.id },
          certificate_header_name = "ssl-client-cert",
          certificate_header_format = "url_encoded",
          revocation_check_mode = "SKIP",
          secure_source = false,
        },
      })

      plugin_multi = assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = route_aws_alb_multiple_certs.id },
        config = {
          ca_certificates = { ca_multi.id, ca_multi_intermediate.id },
          certificate_header_name = "ssl-client-cert",
          certificate_header_format = "url_encoded",
          revocation_check_mode = "SKIP",
          secure_source = false,
        },
      })

      assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = default_consumer_route.id },
        config = {
          ca_certificates = { example_test_ca_cert.id },
          certificate_header_name = "ssl-client-cert",
          certificate_header_format = "base64_encoded",
          revocation_check_mode = "SKIP",
          secure_source = false,
          default_consumer = default_consumer.id
        },
      })

      assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = default_consumer_by_username_route.id },
        config = {
          ca_certificates = { example_test_ca_cert.id },
          certificate_header_name = "ssl-client-cert",
          certificate_header_format = "base64_encoded",
          revocation_check_mode = "SKIP",
          secure_source = false,
          default_consumer = "default@example.com",
        },
      })

      assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = no_default_consumer_route.id },
        config = {
          ca_certificates = { example_test_ca_cert.id },
          certificate_header_name = "ssl-client-cert",
          certificate_header_format = "base64_encoded",
          revocation_check_mode = "SKIP",
          secure_source = false,
        },
      })

      assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = nameless_default_consumer_route.id },
        config = {
          ca_certificates = { example_test_ca_cert.id },
          certificate_header_name = "ssl-client-cert",
          certificate_header_format = "base64_encoded",
          revocation_check_mode = "SKIP",
          secure_source = false,
          default_consumer = nameless_default_consumer.id,
        },
      })

      assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = no_match_default_consumer_route.id },
        config = {
          ca_certificates = { example_test_ca_cert.id },
          certificate_header_name = "ssl-client-cert",
          certificate_header_format = "base64_encoded",
          revocation_check_mode = "SKIP",
          secure_source = false,
          default_consumer = NOT_A_CONSUMER_UUID,
        },
      })

      assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = bad_config_default_consumer_custom_id_route.id },
        config = {
          ca_certificates = { example_test_ca_cert.id },
          certificate_header_name = "ssl-client-cert",
          certificate_header_format = "base64_encoded",
          revocation_check_mode = "SKIP",
          secure_source = false,
          default_consumer = "i-have-no-name", -- using custom_id is not supported
        },
      })

      bp.plugins:insert({
        name = "pre-function",
        config = {
          header_filter = {[[
            ngx.header["x-request-id"] = ngx.var.request_id
          ]]},
        },
      })

      bp.plugins:insert {
        route = { id = route_aws_alb_multiple_certs.id },
        name     = "file-log",
        config   = {
          reopen = true,
          path   = LOG_PATH,
          custom_fields_by_lua = {
            request_id = [[return ngx.var.request_id]],
          }
        },
      }

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "header-cert-auth,file-log,pre-function",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      proxy_ssl_client = helpers.proxy_ssl_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      if proxy_ssl_client then
        proxy_ssl_client:close()
      end

      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("valid certificate", function()
      it("returns HTTP 200 on https request if certificate validation passed with base64_encoded format", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.base64_encoded",
            ["ssl-client-cert"] = base64_encoded_header_value3
          },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("ocsp-valid@konghq.com", json.headers["x-consumer-username"])
        assert.equal(consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-2", json.headers["x-consumer-custom-id"])
      end)

      it("returns HTTP 200 on https request if certificate validation passed with url_encoded format with partial chain certificate", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded",
            ["ssl-client-cert"] = url_encoded_header_value_partial
          },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("ocsp-valid@konghq.com", json.headers["x-consumer-username"])
        assert.equal(consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-2", json.headers["x-consumer-custom-id"])
      end)

      it("returns HTTP 200 on https request if certificate validation passed with url_encoded format using multi chain certificate", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            ["ssl-client-cert"] = url_encoded_header_value
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo@example.com", json.headers["x-consumer-username"])
        assert.equal(consumer_multiple_certs.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-3", json.headers["x-consumer-custom-id"])
      end)

      it("returns HTTP 401 on https request if certificate validation failed", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com.base64_encoded",
            ["ssl-client-cert"] = base64_encoded_header_value
          }
        })
        assert.res_status(401, res)
      end)

      it("returns HTTP 200 on https request if certificate validation passed with default_consumer set (using UUID)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            defaultconsumerbyuuid = {"true"},
            ["Host"] = "example.test",
            ["ssl-client-cert"] = base64_encoded_header_value2
          },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("default@example.com", json.headers["x-consumer-username"])
        assert.equal(default_consumer.id, json.headers["x-consumer-id"])
        assert.equal("example.test,kongclient", json.headers["x-client-cert-san"])
        assert.equal("C=US/CN=kongclient/L=SF/O=KONG/OU=ENG/ST=CA", json.headers["x-client-cert-dn"])
      end)

      it("returns HTTP 200 on https request if certificate validation passed with default_consumer set (using username)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            defaultconsumerbyusername = {"true"},
            ["Host"] = "example.test",
            ["ssl-client-cert"] = base64_encoded_header_value2
          },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("default@example.com", json.headers["x-consumer-username"])
        assert.equal(default_consumer.id, json.headers["x-consumer-id"])
        assert.equal("example.test,kongclient", json.headers["x-client-cert-san"])
        assert.equal("C=US/CN=kongclient/L=SF/O=KONG/OU=ENG/ST=CA", json.headers["x-client-cert-dn"])
      end)


      it("returns HTTP 401 on https request if certificate validation passed with default_consumer not set", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            noconsumer = {"true"},
            ["Host"] = "example.test",
            ["ssl-client-cert"] = base64_encoded_header_value2
          },
        })
        assert.res_status(401, res)
      end)

      it("returns HTTP 200 on https request if certificate validation passed with default_consumer set and the consumer has no username", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            namelessconsumer = {"true"},
            ["Host"] = "example.test",
            ["ssl-client-cert"] = base64_encoded_header_value2
          },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("i-have-no-name", json.headers["x-consumer-custom-id"])
        assert.is_nil(json.headers["x-consumer-username"])
        assert.equal(nameless_default_consumer.id, json.headers["x-consumer-id"])
        assert.equal("example.test,kongclient", json.headers["x-client-cert-san"])
        assert.equal("C=US/CN=kongclient/L=SF/O=KONG/OU=ENG/ST=CA", json.headers["x-client-cert-dn"])
      end)

      it("returns HTTP 401 on https request if certificate validation passed with default_consumer set to non-matching consumer id", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            nomatchconsumer = {"true"},
            ["Host"] = "example.test",
            ["ssl-client-cert"] = base64_encoded_header_value2
          },
        })
        assert.res_status(401, res)
      end)

      it("returns HTTP 401 on https request if certificate validation passed with default_consumer set to custom_id", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            badconfigcustomid = {"true"},
            ["Host"] = "example.test",
            ["ssl-client-cert"] = base64_encoded_header_value2
          },
        })
        assert.res_status(401, res)
      end)

      it("overrides client_verify field in basic log serialize so it contains sensible content #4626", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com.url_encoded.multiple-certs",
            ["ssl-client-cert"] = url_encoded_header_value
          }
        })
        assert.res_status(200, res)

        local log_message = get_log(res)
        assert.equal("SUCCESS", log_message.request.tls.client_verify)
      end)
    end)

    describe("custom credential", function()
      local plugin_id
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "POST",
          path    = "/consumers/" .. customized_consumer.id  .. "/header-cert-auth",
          body    = {
            subject_name   = "foo@example.com",
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        plugin_id = json.id
      end)
      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "DELETE",
          path    = "/consumers/" .. customized_consumer.id  .. "/header-cert-auth/" .. plugin_id,
        }))
        assert.res_status(204, res)
      end)

      it("overrides auto-matching", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            ["ssl-client-cert"] = url_encoded_header_value
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("customized@example.com", json.headers["x-consumer-username"])
        assert.equal(customized_consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-4", json.headers["x-consumer-custom-id"])
      end)
    end)

    describe("HTTPS", function()
      it("accepts https requests", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            ["ssl-client-cert"] = url_encoded_header_value
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo@example.com", json.headers["x-consumer-username"])
        assert.equal(consumer_multiple_certs.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-3", json.headers["x-consumer-custom-id"])
      end)

      bad_client_tests("returns HTTP 401 on https request if certificate validation failed", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            -- only 1 certificate is sent, full chain is required for plugin_multi
            ["ssl-client-cert"] = url_encoded_header_value_missing_full
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.same({ message = "TLS certificate failed verification" }, json)
      end)
    end)

    describe("custom credential with ca_certificate", function()
      local plugin_id
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "POST",
          path    = "/consumers/" .. customized_consumer.id  .. "/header-cert-auth",
          body    = {
            subject_name   = "foo@example.com",
            ca_certificate = { id = ca_multi.id },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        plugin_id = json.id
      end)
      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "DELETE",
          path    = "/consumers/" .. customized_consumer.id  .. "/header-cert-auth/" .. plugin_id,
        }))
        assert.res_status(204, res)
      end)

      it("overrides auto-matching", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            ["ssl-client-cert"] = url_encoded_header_value
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("customized@example.com", json.headers["x-consumer-username"])
        assert.equal(customized_consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-4", json.headers["x-consumer-custom-id"])
      end)
    end)

    describe("custom credential with invalid ca_certificate", function()
      local plugin_id
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "POST",
          path    = "/consumers/" .. customized_consumer.id  .. "/header-cert-auth",
          body    = {
            subject_name   = "foo@example.com",
            ca_certificate = { id = ca_cert.id },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        plugin_id = json.id
      end)
      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "DELETE",
          path    = "/consumers/" .. customized_consumer.id  .. "/header-cert-auth/" .. plugin_id,
        }))
        assert.res_status(204, res)
      end)

      -- Falls through to step 2 of https://docs.konghq.com/hub/kong-inc/header-cert-auth/#matching-behaviors
      -- This is header-cert-auth doc but should also apply for header-cert-auth
      it("falls back to auto-matching", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            ["ssl-client-cert"] = url_encoded_header_value
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo@example.com", json.headers["x-consumer-username"])
        assert.equal(consumer_multiple_certs.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-3", json.headers["x-consumer-custom-id"])
      end)
    end)

    describe("skip consumer lookup with valid certificate", function()
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin_multi.id,
          body    = {
            config = { skip_consumer_lookup = true, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)

      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin_multi.id,
          body    = {
            config = { skip_consumer_lookup = false, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)

      it("returns HTTP 200 on https request if certificate validation passed", function()
        assert.eventually(function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Host"]            = "example.com.url_encoded.multiple-certs",
              ["ssl-client-cert"] = url_encoded_header_value
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_nil(json.headers["x-consumer-username"])
          assert.is_nil(json.headers["x-consumer-id"])
          assert.is_nil(json.headers["x-consumer-custom-id"])
          assert.not_nil(json.headers["x-client-cert-san"])
          assert.not_nil(json.headers["x-client-cert-dn"])
        end).with_timeout(3)
            .has_no_error("Invalid response code")
      end)

      bad_client_tests("returns HTTP 401 on https request if certificate validation failed", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            -- only 1 certificate is sent, full chain is required for plugin_multi
            ["ssl-client-cert"] = url_encoded_header_value_missing_full
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.same({ message = "TLS certificate failed verification" }, json)
      end)
    end)

    describe("use skip_consumer_lookup with authenticated_group_by", function()
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin_multi.id,
          body    = {
            config = {
              skip_consumer_lookup = true,
              authenticated_group_by = ngx.null,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)
      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin_multi.id,
          body    = {
            config = {
              skip_consumer_lookup = false,
              authenticated_group_by = "CN",
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)
      it("doesn't fail when authenticated_group_by = null", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            ["ssl-client-cert"] = url_encoded_header_value
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.headers["x-consumer-username"])
        assert.is_nil(json.headers["x-consumer-id"])
        assert.is_nil(json.headers["x-consumer-custom-id"])
        assert.not_nil(json.headers["x-client-cert-san"])
        assert.not_nil(json.headers["x-client-cert-dn"])
      end)
    end)

    describe("config.anonymous", function()
      lazy_setup(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin_multi.id,
          body    = {
            config = { anonymous = anonymous_user.id, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)
      lazy_teardown(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin_multi.id,
          body    = {
            config = { anonymous = nil, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)
      end)

      it("works with right credentials and anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            ["ssl-client-cert"] = url_encoded_header_value
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo@example.com", json.headers["x-consumer-username"])
        assert.equal(consumer_multiple_certs.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-3", json.headers["x-consumer-custom-id"])
      end)

      bad_client_tests("works with wrong credentials and anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            -- only 1 certificate is sent, full chain is required for plugin_multi
            ["ssl-client-cert"] = url_encoded_header_value_missing_full
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("anonymous@example.com", json.headers["x-consumer-username"])
        assert.equal(anonymous_user.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-1", json.headers["x-consumer-custom-id"])
        assert.equal("true", json.headers["x-anonymous-consumer"])
      end)

      it("works with http (no mTLS handshake)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            -- only 1 certificate is sent, full chain is required for plugin_multi
            ["ssl-client-cert"] = url_encoded_header_value_missing_full
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("anonymous@example.com", json.headers["x-consumer-username"])
        assert.equal(anonymous_user.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-1", json.headers["x-consumer-custom-id"])
        assert.equal("true", json.headers["x-anonymous-consumer"])
      end)

      it("logging with https (incomplete certificate chain)", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            -- only 1 certificate is sent, full chain is required for plugin_multi
            ["ssl-client-cert"] = url_encoded_header_value_missing_full
          }
        })
        assert.res_status(200, res)

        local log_message = get_log(res)
        assert.equal("FAILED:unable to get local issuer certificate", log_message.request.tls.client_verify)
      end)


      it("errors when anonymous user doesn't exist", function()
        local nonexisting_anonymous = "00000000-0000-0000-0000-000000000000"
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin_multi.id,
          body    = {
            config = { anonymous = nonexisting_anonymous, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)

        assert.eventually(function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Host"]            = "example.com.url_encoded.multiple-certs",
              -- only 1 certificate is sent, full chain is required for plugin_multi
              ["ssl-client-cert"] = url_encoded_header_value_missing_full
            }
          })
          local body = cjson.decode(assert.res_status(500, res))
          assert.same("anonymous consumer " .. nonexisting_anonymous .. " is configured but doesn't exist", body.message)
        end).with_timeout(3)
            .has_no_error("Invalid response code")
      end)
    end)

    describe("errors", function()
      lazy_setup(function()
        -- Here we truncate the ca_certificates table, simulating a scenario where
        -- the ca_certificate referenced does not exist in the db
        db:truncate("ca_certificates")
        local res = assert(admin_client:send({
          method  = "DELETE",
          path    = "/cache",
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(204, res)
      end)

      it("errors when CA doesn't exist", function()
        local uuid = utils.uuid()
        assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. plugin_multi.id,
          body    = {
            config = { ca_certificates = { uuid, }, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            ["ssl-client-cert"] = url_encoded_header_value
          }
        })
        -- expected worker crash
        assert.res_status(500, res)
        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.matches("CA Certificate '" .. uuid .. "' does not exist", err_log, nil, true)

      end)
    end)
  end)

  describe("Plugin: header-cert-auth (access) with filter [#" .. strategy .. "]", function()
    local proxy_client, admin_client
    local proxy_ssl_client_foo, proxy_ssl_client_bar, proxy_ssl_client_alice
    local bp, db
    local service
    local ca_cert
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "ca_certificates",
        "header_cert_auth_credentials",
        "workspaces",
      }, { "header-cert-auth", })

      bp.consumers:insert {
        username = "foo@example.com"
      }

      bp.consumers:insert {
        username = "customized@example.com"
      }

      service = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      assert(bp.routes:insert {
        hosts   = { "foo.test" },
        service = { id = service.id, },
        snis = { "foo.test" },
      })

      assert(bp.routes:insert {
        hosts   = { "bar.test" },
        service = { id = service.id, },
        snis = { "bar.test" },
      })

      ca_cert = assert(db.ca_certificates:insert({
        cert = CA_MULTI,
      }))

      assert(bp.plugins:insert {
        name = "header-cert-auth",
        config = {
          ca_certificates = { ca_cert.id, },
          certificate_header_name = "ssl-client-cert",
          secure_source = false,
          certificate_header_format = "url_encoded",
        },
        service = { id = service.id, },
      })

      local service2 = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      assert(bp.routes:insert {
        hosts   = { "alice.test" },
        service = { id = service2.id, },
        snis = { "alice.test" },
      })

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,header-cert-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      proxy_ssl_client_foo = helpers.proxy_ssl_client(nil, "foo.test")
      proxy_ssl_client_bar = helpers.proxy_ssl_client(nil, "bar.test")
      proxy_ssl_client_alice = helpers.proxy_ssl_client(nil, "alice.test")
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      if proxy_ssl_client_foo then
        proxy_ssl_client_foo:close()
      end

      if proxy_ssl_client_bar then
        proxy_ssl_client_bar:close()
      end

      if proxy_ssl_client_alice then
        proxy_ssl_client_alice:close()
      end

      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("request certs for specific routes", function()
      it("request cert for host foo", function()
        local res = assert(proxy_ssl_client_foo:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "foo.test",
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate header was sent" }, json)
      end)

      it("request cert for host bar", function()
        local res = assert(proxy_ssl_client_bar:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "bar.test"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate header was sent" }, json)
      end)

      it("do not request cert for host alice", function()
        local res = assert(proxy_ssl_client_alice:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "alice.test"
          }
        })
        assert.res_status(200, res)
      end)
    end)
    describe("request certs for all routes", function()
      it("request cert for all request", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/routes",
          body = {
            hosts   = { "all.test" },
            service = { id = service.id, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)

        helpers.wait_until(function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/cache/header-cert-auth:cert_enabled_snis",
          })
          res:read_body()
          return res.status == 404
        end)

        -- wait until the route take effect
        helpers.wait_until(function()
          res = assert(proxy_ssl_client_bar:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Host"] = "all.test"
            }
          })

          res:read_body()
          return res.status ~= 404
        end)

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate header was sent" }, json)
      end)
    end)
  end)

  describe("Plugin: header-cert-auth (access) with filter [#" .. strategy .. "] non default workspace", function()
    local proxy_client, admin_client
    local proxy_ssl_client_foo, proxy_ssl_client_example
    local bp, db
    local service, workspace, consumer
    local ca_cert
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "ca_certificates",
        "header_cert_auth_credentials",
        "workspaces",
      }, { "header-cert-auth", })

      workspace = assert(db.workspaces:insert({ name = "test_ws_" .. utils.uuid()}))

      consumer = bp.consumers:insert({
        username = "foo@example.com"
      },  { workspace = workspace.id })

      service = bp.services:insert({
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }, { workspace = workspace.id })

      assert(bp.routes:insert({
        snis   = { "example.com" },
        service = { id = service.id, },
        paths = { "/get" },
        strip_path = false,
      }, { workspace = workspace.id }))

      assert(bp.routes:insert({
        service = { id = service.id, },
        paths = { "/anotherroute" },
      }, { workspace = workspace.id }))

      ca_cert = assert(db.ca_certificates:insert({
        cert = CA_MULTI,
      }, { workspace = workspace.id }))

      assert(bp.plugins:insert({
        name = "header-cert-auth",
        config = {
          ca_certificates = { ca_cert.id, },
          certificate_header_name = "ssl-client-cert",
          certificate_header_format = "url_encoded",
          secure_source = false,
      },
        service = { id = service.id, },
      }, { workspace = workspace.id }))

      -- in default workspace:
      local service2 = bp.services:insert({
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      })

      assert(bp.routes:insert({
        service = { id = service2.id, },
        paths = { "/default" },
      }))

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,header-cert-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      proxy_ssl_client_foo = helpers.proxy_ssl_client(nil, "foo.test")
      proxy_ssl_client_example = helpers.proxy_ssl_client(nil, "example.com")
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      if proxy_ssl_client_foo then
        proxy_ssl_client_foo:close()
      end

      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("filter cache is isolated per workspace", function()
      it("doesn't request cert for route that's in a different workspace", function()
        -- this maps to the default workspace
        local res = assert(proxy_ssl_client_foo:send {
          method  = "GET",
          path    = "/default",
          headers = {
            ["Host"] = "foo.test"
          }
        })
        assert.res_status(200, res)
      end)

      it("request cert for route applied the plugin", function()
        local res = assert(proxy_ssl_client_foo:send {
          method  = "GET",
          path    = "/anotherroute",
          headers = {
            ["Host"] = "foo.test"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate header was sent" }, json)
      end)

      it("still request cert for route applied the plugin", function()
        local res = assert(proxy_ssl_client_example:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"] = "example.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No required TLS certificate header was sent" }, json)
      end)

      it("returns HTTP 200 on https request if certificate validation passed", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com.url_encoded.multiple-certs",
            ["ssl-client-cert"] = url_encoded_header_value
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo@example.com", json.headers["x-consumer-username"])
        assert.equal(consumer.id, json.headers["x-consumer-id"])
        assert.equal("consumer-id-1", json.headers["x-consumer-custom-id"])
      end)
    end)
  end)

  describe("Plugin: header-cert-auth (access) [#" .. strategy .. "]", function()
    local bp, db
    local service, route, plugin
    local ca_cert
    local db_strategy = strategy ~= "off" and strategy or nil
    local proxy_client

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "ca_certificates",
        "header_cert_auth_credentials",
      }, { "header-cert-auth", })

      service = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      route = bp.routes:insert {
        hosts   = { "example.com" },
        service = { id = service.id, },
      }

      ca_cert = assert(db.ca_certificates:insert({
        cert = intermediate_CA_cert,
      }))

      plugin = assert(bp.plugins:insert {
        name = "header-cert-auth",
        route = { id = route.id },
        config = {
          ca_certificates = { ca_cert.id, },
          certificate_header_name = "ssl-client-cert",
          secure_source = false,
          certificate_header_format = "url_encoded",
          skip_consumer_lookup = true,
          allow_partial_chain = true,
        },
      })

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,header-cert-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("valid partial chain", function()
      it("allow certificate verification with only an intermediate certificate", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]            = "example.com",
            ["ssl-client-cert"] = "-----BEGIN%20CERTIFICATE-----%0AMIICoTCCAYkCAhABMA0GCSqGSIb3DQEBCwUAMBIxEDAOBgNVBAMMB0ludGVybS4w%0AIBcNMjIxMDE5MTQ0MzQ1WhgPMjEyMjA5MjUxNDQzNDVaMBgxFjAUBgNVBAMMDTEu%0AZXhhbXBsZS5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCvaDAc%0AC%2FcQ3KoGcSdtCPLUSLkhSeKNe2PIVdYcGGODySaRhk6zVcoyEoPwwPHvP6QurAlI%0Aj2DPnP9Jk0nJ9SEygYfq0JyC%2BvVkaurxG622KtDG1HVybIyeDC%2BcqdeYFKpTqaS2%0AlNKZcwlNh9q%2F%2FZ6RWyJYgcWkao0eMFH5OI37PdwQ17L4g2YdxaWtL2e8y6wzoSzs%0AEAX9tJkBaf6pX05ovA4fMF2lB4yRAMY7VsIZ6Qouq%2BXiftXzmlY%2FfIVF8%2BSGMiU4%0Azmp5FFhbZQZP%2FJLcYRrHuYUmiGx53dVNYiO50DJaiUiUptj72XAjl%2Bcjmn659W0W%0AVAguDjFwNvyUH6DBAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAHi%2Bx1LThKx9qeR1%0AeoNwmLRh8ufHE4Vi519oAKQ58wFVNtHnJFoxzJTPOse62oNqWpDk4tp%2FDOuH75uC%0AeMqvG4QYlNlp6NmowKoPZjGqi9XpuQTv6SDfAulQR0ogpa1DSZ4tzqN0V%2BaxziPk%0A0T6RLU9LJjPxOpOjPJ3vKixo8jj671XSGQYl16gb0TUEnzITbCrH4Eq9flJfKvaX%0AYh3AwKT6GQZxi1ZUCb2Vy44g9iJ5webmqSIXC5jlcNHID48rFsO17%2FWv7pdjsRhO%0A5o7ch9muz3DfZPdeYugSoPl52MmggVQ7FRo1g4LvEluZtzRf1HODz71V6hnK%2Fnug%0AeANuiAY%3D%0A-----END%20CERTIFICATE-----",
          }
        })
        assert.res_status(200, res)
      end)

      it("turn allow_partial_chain from true to false, reject the request", function()
        local res = assert(helpers.admin_client():send({
          method  = "PATCH",
          path    = "/routes/" .. route.id .. "/plugins/" .. plugin.id,
          body    = {
            config = { allow_partial_chain = false, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)

        assert.eventually(function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Host"]            = "example.com",
              ["ssl-client-cert"] = "-----BEGIN%20CERTIFICATE-----%0AMIICoTCCAYkCAhABMA0GCSqGSIb3DQEBCwUAMBIxEDAOBgNVBAMMB0ludGVybS4w%0AIBcNMjIxMDE5MTQ0MzQ1WhgPMjEyMjA5MjUxNDQzNDVaMBgxFjAUBgNVBAMMDTEu%0AZXhhbXBsZS5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCvaDAc%0AC%2FcQ3KoGcSdtCPLUSLkhSeKNe2PIVdYcGGODySaRhk6zVcoyEoPwwPHvP6QurAlI%0Aj2DPnP9Jk0nJ9SEygYfq0JyC%2BvVkaurxG622KtDG1HVybIyeDC%2BcqdeYFKpTqaS2%0AlNKZcwlNh9q%2F%2FZ6RWyJYgcWkao0eMFH5OI37PdwQ17L4g2YdxaWtL2e8y6wzoSzs%0AEAX9tJkBaf6pX05ovA4fMF2lB4yRAMY7VsIZ6Qouq%2BXiftXzmlY%2FfIVF8%2BSGMiU4%0Azmp5FFhbZQZP%2FJLcYRrHuYUmiGx53dVNYiO50DJaiUiUptj72XAjl%2Bcjmn659W0W%0AVAguDjFwNvyUH6DBAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAHi%2Bx1LThKx9qeR1%0AeoNwmLRh8ufHE4Vi519oAKQ58wFVNtHnJFoxzJTPOse62oNqWpDk4tp%2FDOuH75uC%0AeMqvG4QYlNlp6NmowKoPZjGqi9XpuQTv6SDfAulQR0ogpa1DSZ4tzqN0V%2BaxziPk%0A0T6RLU9LJjPxOpOjPJ3vKixo8jj671XSGQYl16gb0TUEnzITbCrH4Eq9flJfKvaX%0AYh3AwKT6GQZxi1ZUCb2Vy44g9iJ5webmqSIXC5jlcNHID48rFsO17%2FWv7pdjsRhO%0A5o7ch9muz3DfZPdeYugSoPl52MmggVQ7FRo1g4LvEluZtzRf1HODz71V6hnK%2Fnug%0AeANuiAY%3D%0A-----END%20CERTIFICATE-----",
            }
          })
          assert.res_status(401, res)
        end).with_timeout(3)
            .has_no_error("Invalid response code")
      end)

      it("turn allow_partial_chain from false to true, accept the request again", function()
        local res = assert(helpers.admin_client():send({
          method  = "PATCH",
          path    = "/routes/" .. route.id .. "/plugins/" .. plugin.id,
          body    = {
            config = { allow_partial_chain = true, },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)

        assert.eventually(function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              ["Host"]            = "example.com",
              ["ssl-client-cert"] = "-----BEGIN%20CERTIFICATE-----%0AMIICoTCCAYkCAhABMA0GCSqGSIb3DQEBCwUAMBIxEDAOBgNVBAMMB0ludGVybS4w%0AIBcNMjIxMDE5MTQ0MzQ1WhgPMjEyMjA5MjUxNDQzNDVaMBgxFjAUBgNVBAMMDTEu%0AZXhhbXBsZS5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCvaDAc%0AC%2FcQ3KoGcSdtCPLUSLkhSeKNe2PIVdYcGGODySaRhk6zVcoyEoPwwPHvP6QurAlI%0Aj2DPnP9Jk0nJ9SEygYfq0JyC%2BvVkaurxG622KtDG1HVybIyeDC%2BcqdeYFKpTqaS2%0AlNKZcwlNh9q%2F%2FZ6RWyJYgcWkao0eMFH5OI37PdwQ17L4g2YdxaWtL2e8y6wzoSzs%0AEAX9tJkBaf6pX05ovA4fMF2lB4yRAMY7VsIZ6Qouq%2BXiftXzmlY%2FfIVF8%2BSGMiU4%0Azmp5FFhbZQZP%2FJLcYRrHuYUmiGx53dVNYiO50DJaiUiUptj72XAjl%2Bcjmn659W0W%0AVAguDjFwNvyUH6DBAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAHi%2Bx1LThKx9qeR1%0AeoNwmLRh8ufHE4Vi519oAKQ58wFVNtHnJFoxzJTPOse62oNqWpDk4tp%2FDOuH75uC%0AeMqvG4QYlNlp6NmowKoPZjGqi9XpuQTv6SDfAulQR0ogpa1DSZ4tzqN0V%2BaxziPk%0A0T6RLU9LJjPxOpOjPJ3vKixo8jj671XSGQYl16gb0TUEnzITbCrH4Eq9flJfKvaX%0AYh3AwKT6GQZxi1ZUCb2Vy44g9iJ5webmqSIXC5jlcNHID48rFsO17%2FWv7pdjsRhO%0A5o7ch9muz3DfZPdeYugSoPl52MmggVQ7FRo1g4LvEluZtzRf1HODz71V6hnK%2Fnug%0AeANuiAY%3D%0A-----END%20CERTIFICATE-----",
            }
          })
          assert.res_status(200, res)
        end).with_timeout(3)
            .has_no_error("Invalid response code")
      end)
    end)
  end)
end end
