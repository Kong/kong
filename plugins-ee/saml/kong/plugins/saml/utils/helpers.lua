-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

--- reformats the input into a PEM formatted certificate
function _M.format_cert(input)
  local result
  input = string.gsub(input, "\n", "")
  if input and #input > 0 then
    local t = { "-----BEGIN CERTIFICATE-----" }
    local start = 1
    local size = #input
    while start <= size do
      t[#t+1] = input:sub(start, start + 63)
      start = start + 64
    end
    t[#t+1] = "-----END CERTIFICATE-----\n"

    result = table.concat(t, "\n")
  end

  return result
end

function _M.format_key(input)
  local result
  input = string.gsub(input, "\n", "")
  if input and #input > 0 then
    local t = { "-----BEGIN RSA PRIVATE KEY-----" }
    local start = 1
    local size = #input
    while start <= size do
      t[#t+1] = input:sub(start, start + 63)
      start = start + 64
    end
    t[#t+1] = "-----END RSA PRIVATE KEY-----\n"
    result = table.concat(t, "\n")
  end

  return result
end

function _M.render_request_form(binding_verb, uri, data)
  local verb_used = "POST"
  if binding_verb ~= nil then
    verb_used = binding_verb
  end

  local html = [[
    <html>
    <head><title>Working...</title></head>
    <body>
    <form method="]] .. verb_used .. [[" action="]] .. uri .. "\">"

  if type(data) == "table" and data ~= nil then
    for key, value in pairs(data) do
      html = html .. "<input type=\"hidden\" name=\"" .. key .. "\" value=\"" .. value .. "\" />"
    end
  end

  html = html .. [[
    <noscript><p>Script is disabled. Click Submit to continue.</p></noscript>
    <input type="submit" value="Submit" style="display: none;"/>
    </form>
    <script language="javascript">window.setTimeout('document.forms[0].submit()', 0);</script>
    </body>
    </html>
  ]]
  ngx.header.content_type = "text/html"
  ngx.say(html)
  ngx.exit(200)
end

function _M.build_request_path()

  return kong.request.get_scheme() .. "://" ..kong.request.get_host() .. ":"
    .. kong.request.get_port() .. kong.request.get_path()

end

return _M
