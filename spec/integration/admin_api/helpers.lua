local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local assert = require "luassert"

local function send_content_types(url, method, body, res_status, res_body, options)
  if not options then options = {} end

  local form_response, form_status = http_client[method:lower()](url, body)
  assert.equal(res_status, form_status)

  if options.drop_db then
    spec_helper.drop_db()
  end

  local json_response, json_status = http_client[method:lower()](url, body, {["content-type"]="application/json"})
  assert.equal(res_status, json_status)

  if res_body then
    assert.same(res_body.."\n", form_response)
    assert.same(res_body.."\n", json_response)
  end

  local res_obj
  local status, res = pcall(function() res_obj = json.decode(json_response) end)
  if not status then
    error(res, 2)
  end

  return res_obj
end

return send_content_types
