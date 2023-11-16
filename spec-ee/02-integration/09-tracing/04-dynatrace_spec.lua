-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_stringx       = require "pl.stringx"
local pl_utils         = require "pl.utils"
local cjson            = require "cjson"
local helpers          = require "spec.helpers"
local http             = require "resty.http"

local DT_ENV_ID        = os.getenv("DT_ENV_ID")
local EXTENSION_NAME   = "custom:com.konghq.extension.prometheus-kong"
local OneAgent_URL     = string.format("https://%s.live.dynatrace.com/api/v1/oneagents", DT_ENV_ID)
local OneAgentConf_URL = string.format(
                           "https://%s.live.dynatrace.com/api/v2/extensions/%s/monitoringConfigurations",
                           DT_ENV_ID, EXTENSION_NAME)
local METRICS_URL      = string.format("https://%s.live.dynatrace.com/api/v2/metrics/query", DT_ENV_ID)
local ENTITY_URL       = string.format("https://%s.live.dynatrace.com/api/v2/entities", DT_ENV_ID)
local API_TOKEN        = os.getenv("DT_API_TOKEN")
local AUTHENTICATION   = string.format("Api-Token %s", API_TOKEN)

local function http_request(url, query, headers, method, body)
  local httpc = http.new()
  url = query and url .. "?" .. query or url
  local res, err = httpc:request_uri(url, {
    method = method or "GET",
    ssl_verify = false,
    headers = headers,
    body = body,
  })
  assert(res, err)
  assert(res.status == 200, "request failed: " .. res.status .. " " .. res.reason .. ", body: " .. res.body)
  httpc:close()
  return cjson.decode(res.body)
end

local function get_ci_hostname()
  local ok, _, stdout, stderr = pl_utils.executeex("hostname")
  assert(ok, stderr)
  return pl_stringx.rstrip(stdout)
end

describe("dynatrace", function()
  local host_id, query, res_body
  local dt_test = os.getenv("DT_TEST")
  if not dt_test or dt_test == '' then
    print("DT_TEST is not set, test is skipped")
    return
  end

  lazy_setup(function()
    assert(DT_ENV_ID)
    assert(API_TOKEN)
    -- hostname pattern: runner-self-hosted-runner-2-worker-14
    local ci_hostname = get_ci_hostname()
    assert(ci_hostname, "can not get ci hostname")

    -- check_OneAgent_ready
    query = "availabilityState=MONITORED"
    repeat
      res_body = http_request(OneAgent_URL, query, {
        ["Authorization"] = AUTHENTICATION,
        ["Content-Type"] = "application/json",
      })
      for _, host in ipairs(res_body.hosts or {}) do
        local host_info = host.hostInfo
        if host_info.displayName == ci_hostname and host.active == true then
            host_id = host_info.entityId
          break
        end
      end

      query = type(res_body.nextPageKey) == 'string' and "nextPageKey=" .. res_body.nextPageKey
    until type(res_body.nextPageKey) ~= 'string' or host_id

    assert.is_not_nil(host_id)

    -- push monitoring configurations
    local monitoring_conf = string.format('[{"scope":"%s","value":{"enabled":true,"description":"test","version":"1.0.2","featureSets":["all","global"],"activationContext":"LOCAL","activationTags":[],"prometheusLocal":{"endpoints":[{"url":"http://localhost:8001/metrics","authentication":{"scheme":"none","skipVerifyHttps":false}}]}}}]', host_id)

    http_request(OneAgentConf_URL, nil, {
      ["Authorization"] = AUTHENTICATION,
      ["Content-Type"] = "application/json"},
      "POST",
      monitoring_conf
    )

    -- start kong with DT ENV
    helpers.start_kong(
      { DT_NGINX_FORCE_RUNTIME_INSTRUMENTATION = "on" }
    )
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("check metrics", function()
    -- get process_instance_id
    local process_instance_id
    query = 'entitySelector=type("process_group_instance"),detectedName("nginx")&from=now-1h/h&fields=+fromRelationships'
    repeat
      res_body = http_request(ENTITY_URL, query, {
        ["Authorization"] = AUTHENTICATION,
        ["Content-Type"] = "application/json",
      })

      for _, entity in ipairs(res_body.entities or {}) do
        local hosts = entity.fromRelationships.isProcessOf
        for _, host in ipairs(hosts) do
          if host_id == host.id then
            process_instance_id = entity.entityId
            break
          end
        end

        if process_instance_id then
          break
        end
      end

      query = type(res_body.nextPageKey) == 'string' and "nextPageKey=" .. res_body.nextPageKey
    until type(res_body.nextPageKey) ~= 'string' or process_instance_id

    assert.is_not_nil(process_instance_id)

    -- get metrics
    local metric_selector = string.format(
      "metricSelector=builtin:tech.generic.cpu.usage:filter(eq(\"dt.entity.process_group_instance\",%s)):avg",
      process_instance_id)

    res_body = http_request(METRICS_URL, metric_selector, {
      ["Authorization"] = AUTHENTICATION,
      ["Content-Type"] = "application/json",
    })

    -- check metrics
    local results = res_body and res_body.result
    assert(type(results) == 'table', "result in body is not a table")
    assert(results and #results > 0, "results in body is empty")
    local dataset = results[1].data
    assert(type(dataset) == 'table', "data in result is not a table")
    assert(dataset and #dataset > 0, "dataset in result is empty")
    local values = dataset[1].values
    assert(type(values) == 'table', "values in data is not a table")
    assert(values and #values > 0, "values in data is empty")

    local has_valid_value
    for _, value in ipairs(values) do
      if value then
        has_valid_value = true
        break
      end
    end

    assert(has_valid_value, "no metrics in data")
  end)
end)
