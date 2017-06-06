OXD_STATE_OK = "\"status\":\"ok\""

local socket = require("socket")
local cjson = require "cjson"

local function isempty(s)
  return s == nil or s == ''
end

local function commandWithLengthPrefix(json)
  local lengthPrefix = "" .. json:len();

  while lengthPrefix:len() ~= 4 do
    lengthPrefix = "0" .. lengthPrefix
  end

  return lengthPrefix .. json
end

local _M = {}

function _M.execute(conf, commandAsJson, timeout)
  ngx.log(ngx.DEBUG, "oxd_host: " .. conf.oxd_host .. ", oxd_port: " .. conf.oxd_port)
  ngx.log(ngx.DEBUG, "uma_server_host: " .. conf.uma_server_host .. ", protection_document: " .. conf.protection_document)

  local host = socket.dns.toip(conf.oxd_host)
  ngx.log(ngx.DEBUG, "host: " .. host)

  local client = socket.connect(host, conf.oxd_port);

  local commandWithLengthPrefix = commandWithLengthPrefix(commandAsJson);
  ngx.log(ngx.DEBUG, "commandWithLengthPrefix: " .. commandWithLengthPrefix)

  client:settimeout(timeout)
  assert(client:send(commandWithLengthPrefix))
  local responseLength = client:receive("4")

  if responseLength == nil then -- sometimes if op_host does not reply or is down oxd calling it waits until timeout, since our timeout is 5 seconds we may got nil here.
  client:close();
  return "error"
  end

  ngx.log(ngx.DEBUG, "responseLength: " .. responseLength)

  local response = client:receive(tonumber(responseLength))
  ngx.log(ngx.DEBUG, "response: " .. response)

  client:close();
  ngx.log(ngx.DEBUG, "finished.")
  return response
end

function _M.checkaccess(conf, rpt, path, httpMethod)
  local commandAsJson = "{\"command\":\"uma_rs_check_access\",\"params\":{\"oxd_id\":\"" .. conf.oxd_id .. "\",\"rpt\":\"" .. rpt .. "\",\"path\":\"" .. path .. "\",\"http_method\":\"" .. httpMethod .. "\"}}";
  local response = _M.execute(conf, commandAsJson, 5)
  return cjson.decode(response)
end

--- Registers API on oxd server.
-- @param [ t y p e = t a b l e ] conf Schema configuration
-- @treturn boolean `ok`: A boolean describing if the registration was successfull or not
function _M.register(conf)
  ngx.log(ngx.DEBUG, "Registering on oxd ... ")

  local commandAsJson = "{\"command\":\"register_site\",\"params\":{\"scope\":[\"openid\",\"uma_protection\"],\"contacts\":[],\"op_host\":\"" .. conf.uma_server_host .. "\",\"authorization_redirect_uri\":\"https://client.example.com/cb\",\"redirect_uris\":null,\"response_types\":[\"code\"],\"client_name\":\"kong_uma_rs\",\"grant_types\":[\"authorization_code\"]}}";
  local response = _M.execute(conf, commandAsJson, 5)

  if string.match(response, OXD_STATE_OK) then
    local asJson = cjson.decode(response)
    local oxd_id = asJson["data"]["oxd_id"]

    ngx.log(ngx.DEBUG, "Registered successfully. oxd_id from oxd server: " .. oxd_id)

    if not isempty(oxd_id) then
      conf.oxd_id = oxd_id

      local resourcesWithoutBrackets = string.sub(conf.protection_document, 2, -2)
      local protectCommand = "{\"command\":\"uma_rs_protect\",\"params\":{\"oxd_id\":\"" .. oxd_id .. "\"," .. resourcesWithoutBrackets .. "}}";

      local response = _M.execute(conf, protectCommand, 5)

      if string.match(response, OXD_STATE_OK) then
        ngx.log(ngx.DEBUG, "Protection document registered successfully.")
        return true
      end
    end
  end

  return false
end

return _M
