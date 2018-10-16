-- This is a unit test but it's kept in the intergration test directory by purpose.
-- In this way all the vitals tests are together, and more likely to notice a Vitals change that impacts the tsdb strategy.

local utils = require "kong.tools.utils"

describe("vitals Prometheus strategy", function()
  local cjson = require "cjson"
  local common_stats_sample = {
    -- prometheus v1 format
    cjson.decode([[
      {
        "status": "success",
        "data": {
          "resultType": "matrix",
          "result": [{
            "metric": {"instance":"localhost:65555"},
            "values": [
              [1527892620, "2699"],
              [1527892680, "27402"],
              [1527892740, "27402"],
              [1527892800, "27402"],
              [1527892860, "27402"],
              [1527892920, "27402"]
            ]
          }]
        }
      }
    ]]).data.result,
    -- the followings are identical in format thus not pretty-printed
    cjson.decode('{"status":"success","data":{"resultType":"matrix","result":[{"metric":{"instance":"localhost:65555"},"values":[[1527892620,"5770"],[1527892680,"50789"],[1527892740,"50789"],[1527892800,"50789"],[1527892860,"50789"],[1527892920,"50789"]]}]}}').data.result,
    cjson.decode('{"status":"success","data":{"resultType":"matrix","result":[{"metric":{"instance":"localhost:65555"},"values":[[1527892620,"0"],[1527892680,"1"],[1527892740,"1"],[1527892800,"1"],[1527892860,"1"],[1527892920,"1"]]}]}}').data.result,
    cjson.decode('{"status":"success","data":{"resultType":"matrix","result":[{"metric":{"instance":"localhost:65555"},"values":[[1527892620,"4548"],[1527892680,"3099"],[1527892740,"3099"],[1527892800,"3099"],[1527892860,"3099"],[1527892920,"3099"]]}]}}').data.result,
    cjson.decode('{"status":"success","data":{"resultType":"matrix","result":[{"metric":{"instance":"localhost:65555"},"values":[[1527892620,"-1"],[1527892680,"43"],[1527892740,"45"],[1527892800,"45"],[1527892860,"45"],[1527892920,"45"]]}]}}').data.result,
    cjson.decode('{"status":"success","data":{"resultType":"matrix","result":[{"metric":{"instance":"localhost:65555"},"values":[[1527892620,"93"],[1527892680,"203"],[1527892740,"203"],[1527892800,"203"],[1527892860,"203"],[1527892920,"203"]]}]}}').data.result,
    cjson.decode('{"status":"success","data":{"resultType":"matrix","result":[{"metric":{"instance":"localhost:65555"},"values":[[1527892620,"95"],[1527892680,"11386"],[1527892740,"11386"],[1527892800,"11386"],[1527892860,"11386"],[1527892920,"11386"]]}]}}').data.result,
    cjson.decode('{"status":"success","data":{"resultType":"matrix","result":[{"metric":{"instance":"localhost:65555"},"values":[[1527892620,"3030.5333333333333"],[1527892680,"1352.1333333333334"],[1527892740,"1361.9"],[1527892800,"1361.9"],[1527892860,"1361.9"],[1527892920,"1361.9"]]}]}}').data.result,
    cjson.decode('{"status":"success","data":{"resultType":"matrix","result":[{"metric":{"instance":"localhost:65555"},"values":[[1527892620,"25.066666666666666"],[1527892680,"102.66666666666667"],[1527892740,"103.03333333333333"],[1527892800,"103.03333333333333"],[1527892860,"103.03333333333333"],[1527892920,"103.03333333333333"]]}]}}').data.result,
  }

  local status_code_sample = {
    cjson.decode([[
      {
        "status": "success",
        "data": {
          "resultType": "matrix",
          "result": [{
            "metric": {
              "status_code": "200"
            },
            "values": [
              [1527892620, "19"],
              [1527892680, "1171"],
              [1527892740, "1171"],
              [1527892800, "1171"],
              [1527892860, "1171"],
              [1527892920, "1171"]
            ]
          }, {
            "metric": {
              "status_code": "201"
            },
            "values": [
              [1527892620, "5"],
              [1527892680, "1186"],
              [1527892740, "1186"],
              [1527892800, "1186"],
              [1527892860, "1186"],
              [1527892920, "1186"]
            ]
          }, {
            "metric": {
              "status_code": "302"
            },
            "values": [
              [1527892620, "4"],
              [1527892680, "1148"],
              [1527892740, "1148"],
              [1527892800, "1148"],
              [1527892860, "1148"],
              [1527892920, "1148"]
            ]
          }, {
            "metric": {
              "status_code": "401"
            },
            "values": [
              [1527892620, "5"],
              [1527892680, "1131"],
              [1527892740, "1131"],
              [1527892800, "1131"],
              [1527892860, "1131"],
              [1527892920, "1131"]
            ]
          }, {
            "metric": {
              "status_code": "403"
            },
            "values": [
              [1527892620, "22"],
              [1527892680, "2159"],
              [1527892740, "2159"],
              [1527892800, "2159"],
              [1527892860, "2159"],
              [1527892920, "2159"]
            ]
          }, {
            "metric": {
              "status_code": "404"
            },
            "values": [
              [1527892620, "8"],
              [1527892680, "1145"],
              [1527892740, "1145"],
              [1527892800, "1145"],
              [1527892860, "1145"],
              [1527892920, "1145"]
            ]
          }, {
            "metric": {
              "status_code": "429"
            },
            "values": [
              [1527892620, "11"],
              [1527892680, "1102"],
              [1527892740, "1102"],
              [1527892800, "1102"],
              [1527892860, "1102"],
              [1527892920, "1102"]
            ]
          }, {
            "metric": {
              "status_code": "499"
            },
            "values": [
              [1527892680, "33"],
              [1527892740, "33"],
              [1527892800, "33"],
              [1527892860, "33"],
              [1527892920, "33"]
            ]
          }, {
            "metric": {
              "status_code": "500"
            },
            "values": [
              [1527892620, "13"],
              [1527892680, "1158"],
              [1527892740, "1158"],
              [1527892800, "1158"],
              [1527892860, "1158"],
              [1527892920, "1158"]
            ]
          }, {
            "metric": {
              "status_code": "503"
            },
            "values": [
              [1527892620, "8"],
              [1527892680, "1152"],
              [1527892740, "1152"],
              [1527892800, "1152"],
              [1527892860, "1152"],
              [1527892920, "1152"]
            ]
          }]
        }
      }
    ]]).data.result,
  }

  local status_code_key_by_sample = {
    cjson.decode([[
      {
        "status": "success",
        "data": {
          "resultType": "matrix",
          "result": [{
            "metric": {
              "route_id": "00cdfbbe-6cae-43cf-951a-693f939e4bb9",
              "status_code": "401"
            },
            "values": [
              [1527892800, "3"],
              [1527892860, "3"],
              [1527892920, "3"]
            ]
          }, {
            "metric": {
              "route_id": "00cdfbbe-6cae-43cf-951a-693f939e4bb9",
              "status_code": "403"
            },
            "values": [
              [1527892800, "2"],
              [1527892860, "2"],
              [1527892920, "2"]
            ]
          }, {
            "metric": {
              "route_id": "02c391cd-5705-435d-9498-d7cfc40c4c76",
              "status_code": "200"
            },
            "values": [
              [1527892800, "1"],
              [1527892860, "1"],
              [1527892920, "1"]
            ]
          }, {
            "metric": {
              "route_id": "02c391cd-5705-435d-9498-d7cfc40c4c76",
              "status_code": "401"
            },
            "values": [
              [1527892800, "1"],
              [1527892860, "1"],
              [1527892920, "1"]
            ]
          }, {
            "metric": {
              "route_id": "02c391cd-5705-435d-9498-d7cfc40c4c76",
              "status_code": "404"
            },
            "values": [
              [1527892800, "1"],
              [1527892860, "1"],
              [1527892920, "1"]
            ]
          }, {
            "metric": {
              "route_id": "14194f72-ad9e-4c0e-a6c8-4168da3218b0",
              "status_code": "201"
            },
            "values": [
              [1527892800, "2"],
              [1527892860, "2"],
              [1527892920, "2"]
            ]
          }, {
            "metric": {
              "route_id": "14194f72-ad9e-4c0e-a6c8-4168da3218b0",
              "status_code": "302"
            },
            "values": [
              [1527892800, "1"],
              [1527892860, "1"],
              [1527892920, "1"]
            ]
          }, {
            "metric": {
              "route_id": "14194f72-ad9e-4c0e-a6c8-4168da3218b0",
              "status_code": "401"
            },
            "values": [
              [1527892800, "2"],
              [1527892860, "2"],
              [1527892920, "2"]
            ]
          }, {
            "metric": {
              "route_id": "14194f72-ad9e-4c0e-a6c8-4168da3218b0",
              "status_code": "403"
            },
            "values": [
              [1527892800, "1"],
              [1527892860, "1"],
              [1527892920, "1"]
            ]
          }]
        }
      }
    ]]).data.result,
  }

  local consumer_stats_sample = {
    -- prometheus v1 format
    cjson.decode('{"status":"success","data":{"resultType":"matrix","result":[{"metric":{"instance":"localhost:65555"},"values":[[1527892620,"2699"],[1527892680,"12342"],[1527892740,"15463"],[1527892800,"27453"],[1527892860,"38464"],[1527892920,"49573"]]}]}}').data.result
  }

  local query_parameters = {
    -- level, expected_duration_seconds, expected_interval (seconds), passed_in_interval (seconds)
    { "seconds", 5  * 60, 30, 1 },     -- 5min
    { "minutes", 30 * 60, 60, 60 },  -- 30min
    { "minutes", 60 * 60, 60, 60 },  -- 60min
    { "minutes", 6  * 3600, 60, 60 },  -- 6h
    { "minutes", 12 * 3600, 60, 60 }, -- 12h
  }

  local level, expected_duration_seconds, expected_interval, passed_in_interval

  describe("generates query parameter for", function()

    local prometheus = require "kong.vitals.prometheus.strategy"
    
    local prom_query = prometheus.query

    setup(function()
      stub(prometheus, "translate_vitals_stats")
      stub(prometheus, "translate_vitals_status")
    end)
  
    teardown(function()
      prometheus.translate_vitals_stats:revert()
      prometheus.translate_vitals_status:revert()
      -- revert in teardown to ensure we revert even when error occurs
      prometheus.query = prom_query
    end)

    for _, v in ipairs(query_parameters) do
      level, expected_duration_seconds, expected_interval, passed_in_interval = unpack(v)
      it("duration " .. expected_duration_seconds .. "  cluster level common stats", function()
        local expected_start_ts
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {"cache_datastore_hits_total", "sum(kong_cache_datastore_hits_total{})", true},
            {"cache_datastore_misses_total", "sum(kong_cache_datastore_misses_total{})", true},
            {"latency_proxy_request_min_ms", "min(kong_latency_proxy_request_min{})"},
            {"latency_proxy_request_max_ms", "max(kong_latency_proxy_request_max{})"},
            {"latency_upstream_min_ms", "min(kong_latency_upstream_min{})"},
            {"latency_upstream_max_ms", "max(kong_latency_upstream_max{})"},
            {"requests_proxy_total", "sum(kong_requests_proxy{})", true},
            {"latency_proxy_request_avg_ms", "sum(rate(kong_latency_proxy_request_sum{}[1m])) / sum(rate(kong_latency_proxy_request_count{}[1m])) * 1000"},
            {"latency_upstream_avg_ms", "sum(rate(kong_latency_upstream_sum{}[1m])) / sum(rate(kong_latency_upstream_count{}[1m])) * 1000"}
          })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555, cluster_level = true})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_stats(level, "cluster", nil)
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. "  node level common stats", function()
        local expected_start_ts
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {"cache_datastore_hits_total", "sum by (instance)(kong_cache_datastore_hits_total{})", true},
            {"cache_datastore_misses_total", "sum by (instance)(kong_cache_datastore_misses_total{})", true},
            {"latency_proxy_request_min_ms", "min by (instance)(kong_latency_proxy_request_min{})"},
            {"latency_proxy_request_max_ms", "max by (instance)(kong_latency_proxy_request_max{})"},
            {"latency_upstream_min_ms", "min by (instance)(kong_latency_upstream_min{})"},
            {"latency_upstream_max_ms", "max by (instance)(kong_latency_upstream_max{})"},
            {"requests_proxy_total", "sum by (instance)(kong_requests_proxy{})", true},
            {"latency_proxy_request_avg_ms", "sum by (instance)(rate(kong_latency_proxy_request_sum{}[1m])) / sum by (instance)(rate(kong_latency_proxy_request_count{}[1m])) * 1000"},
            {"latency_upstream_avg_ms", "sum by (instance)(rate(kong_latency_upstream_sum{}[1m])) / sum by (instance)(rate(kong_latency_upstream_count{}[1m])) * 1000"}
          })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555, cluster_level = false})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_stats(level, "cluster", nil)
        assert.is_nil(err)

        local prom = prometheus.new(nil, {host = "notahost", port = 65555})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_stats(level, "cluster", nil)
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. "  with customed start_ts  common stats", function()
        local expected_start_ts
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {"cache_datastore_hits_total", "sum(kong_cache_datastore_hits_total{})", true},
            {"cache_datastore_misses_total", "sum(kong_cache_datastore_misses_total{})", true},
            {"latency_proxy_request_min_ms", "min(kong_latency_proxy_request_min{})"},
            {"latency_proxy_request_max_ms", "max(kong_latency_proxy_request_max{})"},
            {"latency_upstream_min_ms", "min(kong_latency_upstream_min{})"},
            {"latency_upstream_max_ms", "max(kong_latency_upstream_max{})"},
            {"requests_proxy_total", "sum(kong_requests_proxy{})", true},
            {"latency_proxy_request_avg_ms", "sum(rate(kong_latency_proxy_request_sum{}[1m])) / sum(rate(kong_latency_proxy_request_count{}[1m])) * 1000"},
            {"latency_upstream_avg_ms", "sum(rate(kong_latency_upstream_sum{}[1m])) / sum(rate(kong_latency_upstream_count{}[1m])) * 1000"}
          })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555, cluster_level = true})

        expected_start_ts = 1500000000
        local _, err = prom:select_stats(level, "cluster", nil, expected_start_ts)
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. "  overall status codes", function()
        local expected_start_ts
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {"status_code", "sum(kong_status_code{}) by (status_code)", true},
          })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_status_codes({
          duration = expected_interval,
        })
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. "  status codes per service", function()
        local expected_start_ts
        local uuid = utils.uuid()
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {"status_code", 'sum(kong_status_code{service="' .. uuid .. '"}) by (status_code)', true},
          })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_status_codes({
          duration = passed_in_interval,
          entity_type = "service",
          entity_id = uuid,
        })
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. "  status codes per consumer", function()
        local expected_start_ts
        local uuid = utils.uuid()
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {
              "status_code",
              'sum(kong_status_code_per_consumer{consumer="' .. uuid ..'",route_id!=""}) by (status_code)',
              true
            },
          })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_status_codes({
          duration = passed_in_interval,
          entity_type = "consumer",
          entity_id = uuid,
        })
        assert.is_nil(err)  
      end)

      it("duration " .. expected_duration_seconds .. "  status codes per route", function()
        local expected_start_ts
        local uuid = utils.uuid()
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {
              "status_code",
              'sum(kong_status_code_per_consumer{route_id="' .. uuid .. '"}) by (status_code)',
              true
            },
          })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_status_codes({
          duration = passed_in_interval,
          entity_type = "route",
          entity_id = uuid,
        })
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. "  status codes per consumer per route", function()
        local expected_start_ts
        local uuid = utils.uuid()
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {
              "status_code",
              'sum(kong_status_code_per_consumer{consumer="' .. uuid .. '",route_id!=""}) by (status_code, route_id)',
              true
            },
          })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_status_codes({
          duration = passed_in_interval,
          entity_type = "consumer_route",
          entity_id = uuid,
        })
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. "  status codes per workspace", function()
        local expected_start_ts
        local uuid = utils.uuid()
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {"status_code", 'sum(kong_status_code_per_workspace{workspace="' .. uuid .. '"}) by (status_code)', true},
          })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_status_codes({
          duration = passed_in_interval,
          entity_type = "workspace",
          entity_id = uuid,
        })
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. " with customed start_ts  status codes", function()
        local expected_start_ts
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {"status_code", "sum(kong_status_code{}) by (status_code)", true},
          })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555})

        expected_start_ts = 1500000000
        local _, err = prom:select_status_codes({
          duration = expected_interval,
          start_ts = expected_start_ts
        })
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. "  cluster level consumer stats", function()
        local expected_start_ts
        local uuid = utils.uuid()
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {"requests_consumer_total", 'sum(kong_status_code_per_consumer{consumer="' .. uuid .. '", route_id!="", })', true},
           })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555, cluster_level = true})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_consumer_stats({
          duration = passed_in_interval,
          consumer_id = uuid,
        })
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. "  node level consumer stats", function()
        local expected_start_ts
        local uuid = utils.uuid()
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {"requests_consumer_total", 'sum(kong_status_code_per_consumer{consumer="' .. uuid .. '", route_id!="", })', true},
           })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555, cluster_level = false})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_consumer_stats({
          duration = passed_in_interval,
          consumer_id = uuid,
        })
        assert.is_nil(err)

        local prom = prometheus.new(nil, {host = "notahost", port = 65555})

        expected_start_ts = ngx.time() - expected_duration_seconds
        local _, err = prom:select_consumer_stats({
          duration = passed_in_interval,
          consumer_id = uuid,
        })
        assert.is_nil(err)
      end)

      it("duration " .. expected_duration_seconds .. " with customed start_ts  consumer stats", function()
        local expected_start_ts
        local uuid = utils.uuid()
        -- don't use assert.spy().was_called_with to have a better visibility on what's different
        prometheus.query = function(_, start_ts, metrics, interval)
          assert.equals(expected_start_ts, start_ts)
          assert.same(metrics, {
            {"requests_consumer_total", 'sum(kong_status_code_per_consumer{consumer="' .. uuid .. '", route_id!="", })', true},
           })
          assert.equals(expected_interval, interval)
        end

        local prom = prometheus.new(nil, {host = "notahost", port = 65555, cluster_level = true})

        expected_start_ts = 1500000000
        local _, err = prom:select_consumer_stats({
          duration = passed_in_interval,
          start_ts = expected_start_ts,
          consumer_id = uuid,
        })
        assert.is_nil(err)
      end)

    end
  end)

  describe("catches error", function()

    local prometheus = require "kong.vitals.prometheus.strategy"
    local http = require "resty.http"

    setup(function()
      local dummy_client = setmetatable({}, {
        __index = function(_, k, ...)
          return function(...)
            return true, nil
          end
        end
      })
      stub(http, "new").returns(dummy_client, nil)
    end)
  
    teardown(function()
      http.new:revert()
    end)

    for _, v in ipairs(query_parameters) do
      level, expected_duration_seconds, expected_interval, passed_in_interval = unpack(v)

      it("duration " .. expected_duration_seconds .. " , start_ts is not a number", function()
        local prom = prometheus.new({host = "notahost", port = 65555})

        local invalid_start_ts = { "wow", {}, ngx.time, cjson.null }

        for i = 1, #invalid_start_ts + 1, 1 do -- #invalid_start_ts + 1 to also test nil
          local ok, err = prom:query(invalid_start_ts[i], {}, 30)

          assert.is_nil(ok)
          assert.equals("expect first paramter to be a number", err)
        end

      end)

      it("duration " .. expected_duration_seconds .. " , metrics_query is not a table", function()
        local prom = prometheus.new({host = "notahost", port = 65555})

        local invalid_metrics_query = { "wow", 1, ngx.time, cjson.null }

        for i = 1, #invalid_metrics_query + 1, 1 do -- #invalid_metrics_query + 1 to also test nil
          local ok, err = prom:query( ngx.time() - 30, invalid_metrics_query[i], 30)

          assert.is_nil(ok)
          assert.equals("expect second paramter to be a table", err)
        end
      end)

      it("duration " .. expected_duration_seconds .. " , start_ts is not from past", function()
        local prom = prometheus.new({host = "notahost", port = 65555})

        local ok, err = prom:query(ngx.time(), {}, 30)

        assert.is_nil(ok)
        assert.equals("expect first parameter to be a timestamp in the past", err)

        local ok, err = prom:query(ngx.time() + 30, {}, 30)

        assert.is_nil(ok)
        assert.equals("expect first parameter to be a timestamp in the past", err)

      end)

    end

    describe("calling prometheus API", function()

      local prometheus = require "kong.vitals.prometheus.strategy"
      local http = require "resty.http"

      local always_returns_true = {
        __index = function(_, k, ...)
          return function(...)
            return true, nil
          end
        end
      }

      local function object_only_error_on(method)
        local object = {}
        object[method] = function()
          return nil, method .. " error"
        end
        return setmetatable(object, always_returns_true)
      end
  
      for _, v in ipairs(query_parameters) do
        level, expected_duration_seconds, expected_interval, passed_in_interval = unpack(v)
  
        it("duration " .. expected_duration_seconds .. " , http.new error", function()
          stub(http, "new").returns(nil, "http.new error")
  
          local prom = prometheus.new({host = "notahost", port = 65555})
          local ok, err = prom:query(ngx.time() - 30, { "label", "sum()", true }, 30)
  
          assert.is_nil(ok)
          assert.equals("error initializing resty http: http.new error", err)
  
          http.new:revert()
        end)

        it("duration " .. expected_duration_seconds .. " , client.connect error", function()
          stub(http, "new").returns(object_only_error_on("connect"), nil)
  
          local prom = prometheus.new({host = "notahost", port = 65555})
          local ok, err = prom:query(ngx.time() - 30, { "label", "sum()", true }, 30)
  
          assert.is_nil(ok)
          assert.equals("error connecting Prometheus: connect error", err)
  
          http.new:revert()
        end)

        it("duration " .. expected_duration_seconds .. " , client.request error", function()
          stub(http, "new").returns(object_only_error_on("request"), nil)
  
          local prom = prometheus.new({host = "notahost", port = 65555})
          local ok, err = prom:query(ngx.time() - 30, { "label", "sum()", true }, 30)
  
          assert.is_nil(ok)
          assert.equals("request Prometheus failed: request error", err)
  
          http.new:revert()
        end)

        it("duration " .. expected_duration_seconds .. " , client.read_body error", function()
          -- returns a client
          -- which will return [a object that will return error when calling read_body] when calling request
          stub(http, "new").returns(setmetatable({
            request = function()
              return object_only_error_on("read_body"), nil
            end
          }, always_returns_true), nil)
  
          local prom = prometheus.new({host = "notahost", port = 65555})
          local ok, err = prom:query(ngx.time() - 30, { "label", "sum()", true }, 30)
  
          assert.is_nil(ok)
          assert.equals("read Prometheus response failed: read_body error", err)
  
          http.new:revert()
        end)

        it("duration " .. expected_duration_seconds .. " , client.read_body returns invalid json", function()
          -- returns a client
          -- which will return [a object that will return invalid json when calling read_body] when calling request
          stub(http, "new").returns(setmetatable({
            request = function()
              return setmetatable({
                read_body = function()
                  return "----{}", nil
                end
              }, always_returns_true), nil
            end
          }, always_returns_true), nil)
  
          local prom = prometheus.new({host = "notahost", port = 65555})
          local ok, err = prom:query(ngx.time() - 30, { "label", "sum()", true }, 30)
  
          assert.is_nil(ok)
          assert.equals("json decode failed Expected value but found invalid number at character 1", err)
  
          http.new:revert()
        end)

        it("duration " .. expected_duration_seconds .. " , client.read_body returns invalid json", function()
          -- returns a client
          -- which will return [a object that will valid json with error message when calling read_body] when calling request
          stub(http, "new").returns(setmetatable({
            request = function()
              return setmetatable({
                read_body = function()
                  return [[{"status": "failed", "errorType": "StrangeError", "error": "oops"}]], nil
                end
              }, always_returns_true), nil
            end
          }, always_returns_true), nil)

          local prom = prometheus.new({host = "notahost", port = 65555})
          local ok, err = prom:query(ngx.time() - 30, { "label", "sum()", true }, 30)

          assert.is_nil(ok)
          assert.equals("Prometheus reported StrangeError: oops", err)

          http.new:revert()
        end)
      end
    end)
  end)

  describe("translates", function()
    local prometheus = require "kong.vitals.prometheus.strategy"
    setup(function()
      -- the last variable should be synced with the sample json below
      stub(prometheus, "query").returns(common_stats_sample, nil, 120)
    end)
  
    teardown(function()
      prometheus.query:revert()
    end)

    it("cluster level common stats", function()
      local prom = prometheus.new(nil, {host = "notahost", port = 65555, cluster_level = true})
      local ok, err = prom:select_stats("minutes", "cluster", nil)
      assert.is_nil(err)

      assert.same(cjson.decode([[
        {
          "meta": {
            "earliest_ts": 1527892620,
            "latest_ts": 1527892920,
            "interval": "minutes",
            "interval_width": 60,
            "level": "cluster",
            "stat_labels": [
              "cache_datastore_hits_total",
              "cache_datastore_misses_total",
              "latency_proxy_request_min_ms",
              "latency_proxy_request_max_ms",
              "latency_upstream_min_ms",
              "latency_upstream_max_ms",
              "requests_proxy_total",
              "latency_proxy_request_avg_ms",
              "latency_upstream_avg_ms"
            ],
            "nodes": {
              "cluster": {
                "hostname": "cluster"
              }
            }
          },
          "stats": {
            "cluster": {
              "1527892680": [24703, 45019, 1, 3099, 43, 203, 11291, 1352, 102],
              "1527892740": [0, 0, 1, 3099, 45, 203, 0, 1361, 103],
              "1527892920": [0, 0, 1, 3099, 45, 203, 0, 1361, 103],
              "1527892860": [0, 0, 1, 3099, 45, 203, 0, 1361, 103],
              "1527892620": [null, null, 0, 4548, -1, 93, null, 3030, 25],
              "1527892800": [0, 0, 1, 3099, 45, 203, 0, 1361, 103]
            }
          }
        }
      ]]), ok)
    end)

    it("node level common stats", function()
      local prom = prometheus.new(nil, {host = "notahost", port = 65555})
      local ok, err = prom:select_stats("minutes", "cluster", nil)
      assert.is_nil(err)

      local prom = prometheus.new(nil, {host = "notahost", port = 65555, cluster_level = false})
      local ok_explicit_arg, err = prom:select_stats("minutes", "cluster", nil)
      assert.is_nil(err)
      assert.same(ok, ok_explicit_arg)

      assert.same(cjson.decode([[
        {
          "meta": {
            "earliest_ts": 1527892620,
            "latest_ts": 1527892920,
            "interval": "minutes",
            "interval_width": 60,
            "level": "node",
            "stat_labels": [
              "cache_datastore_hits_total",
              "cache_datastore_misses_total",
              "latency_proxy_request_min_ms",
              "latency_proxy_request_max_ms",
              "latency_upstream_min_ms",
              "latency_upstream_max_ms",
              "requests_proxy_total",
              "latency_proxy_request_avg_ms",
              "latency_upstream_avg_ms"
            ],
            "nodes": {
              "localhost:65555": {
                "hostname": "localhost:65555"
              }
            }
          },
          "stats": {
            "localhost:65555": {
              "1527892680": [24703, 45019, 1, 3099, 43, 203, 11291, 1352, 102],
              "1527892740": [0, 0, 1, 3099, 45, 203, 0, 1361, 103],
              "1527892920": [0, 0, 1, 3099, 45, 203, 0, 1361, 103],
              "1527892860": [0, 0, 1, 3099, 45, 203, 0, 1361, 103],
              "1527892620": [null, null, 0, 4548, -1, 93, null, 3030, 25],
              "1527892800": [0, 0, 1, 3099, 45, 203, 0, 1361, 103]
            }
          }
        }
      ]]), ok)
    end)
  end)

  describe("translates", function()
    local prometheus = require "kong.vitals.prometheus.strategy"
    local cjson = require "cjson"
    setup(function()
      -- the last variable should be synced with the sample json below
      stub(prometheus, "query").returns(status_code_sample, nil, 120)
    end)
  
    teardown(function()
      prometheus.query:revert()
    end)

    it("status code", function()
      local prom = prometheus.new(nil, {host = "notahost", port = 65555})
      -- we feed in per minute sample so we query for duration for minute
      local ok, err = prom:select_status_codes({ duration = 60, entity = ""})
      assert.is_nil(err)
      assert.same(cjson.decode([[
        {
          "meta": {
            "interval": "minutes",
            "interval_width": 60,
            "stat_labels": ["status_code"],
            "nodes": {
              "cluster": {
                "hostname": "cluster"
              }
            },
            "level": "cluster"
          },
          "stats": {
            "cluster": {
              "1527892680": {
                "404": 1137,
                "401": 1126,
                "503": 1144,
                "500": 1145,
                "302": 1144,
                "429": 1091,
                "403": 2137,
                "200": 1152,
                "201": 1181
              },
              "1527892740": {
                "404": 0,
                "401": 0,
                "503": 0,
                "499": 0,
                "500": 0,
                "403": 0,
                "429": 0,
                "302": 0,
                "200": 0,
                "201": 0
              },
              "1527892920": {
                "404": 0,
                "401": 0,
                "503": 0,
                "499": 0,
                "500": 0,
                "403": 0,
                "429": 0,
                "302": 0,
                "200": 0,
                "201": 0
              },
              "1527892860": {
                "404": 0,
                "401": 0,
                "503": 0,
                "499": 0,
                "500": 0,
                "403": 0,
                "429": 0,
                "302": 0,
                "200": 0,
                "201": 0
              },
              "1527892620": {},
              "1527892800": {
                "404": 0,
                "401": 0,
                "503": 0,
                "499": 0,
                "500": 0,
                "403": 0,
                "429": 0,
                "302": 0,
                "200": 0,
                "201": 0
              }
            }
          }
        }
      ]]), ok)
    end)

    it("status code with merged classes", function()
      local prom = prometheus.new(nil, {host = "notahost", port = 65555})
      -- we feed in per minute sample so we query for duration for minute
      local ok, err = prom:select_status_codes({ duration = 60, entity_type = "cluster"})
      assert.is_nil(err)
      assert.same(ok, cjson.decode([[
        {
          "meta": {
            "interval": "minutes",
            "interval_width": 60,
            "stat_labels": ["status_code"],
            "nodes": {
              "cluster": {
                "hostname": "cluster"
              }
            },
            "level": "cluster"
          },
          "stats": {
            "cluster": {
              "1527892680": {
                "3xx": 1144,
                "4xx": 5491,
                "5xx": 2289,
                "2xx": 2333
              },
              "1527892740": {
                "3xx": 0,
                "4xx": 0,
                "5xx": 0,
                "2xx": 0
              },
              "1527892920": {
                "3xx": 0,
                "4xx": 0,
                "5xx": 0,
                "2xx": 0
              },
              "1527892860": {
                "3xx": 0,
                "4xx": 0,
                "5xx": 0,
                "2xx": 0
              },
              "1527892620": {},
              "1527892800": {
                "3xx": 0,
                "4xx": 0,
                "5xx": 0,
                "2xx": 0
              }
            }
          }
        }
      ]]))
    end)
  end)

  describe("translates", function()
    local prometheus = require "kong.vitals.prometheus.strategy"
    local cjson = require "cjson"
    setup(function()
      -- the last variable should be synced with the sample json below
      stub(prometheus, "query").returns(status_code_key_by_sample, nil, 120)
    end)
  
    teardown(function()
      prometheus.query:revert()
    end)

    it("status code with key_by", function()
      local prom = prometheus.new(nil, {host = "notahost", port = 65555})
      -- we feed in per minute sample so we query for duration for minute
      local ok, err = prom:select_status_codes({
        duration = 60,
        entity_type = "consumer_route",
        entity_id = utils.uuid(),
        key_by = "route_id",
      })
      assert.is_nil(err)
      assert.same(cjson.decode([[
        {
          "meta": {
            "interval": "minutes",
            "interval_width": 60,
            "stat_labels": ["status_code"],
            "nodes": {},
            "level": "cluster"
          },
          "stats": {
            "14194f72-ad9e-4c0e-a6c8-4168da3218b0": {
              "1527892860": {
                "403": 0,
                "401": 0,
                "302": 0,
                "201": 0
              },
              "1527892920": {
                "403": 0,
                "401": 0,
                "302": 0,
                "201": 0
              },
              "1527892800": {}
            },
            "00cdfbbe-6cae-43cf-951a-693f939e4bb9": {
              "1527892860": {
                "403": 0,
                "401": 0
              },
              "1527892920": {
                "403": 0,
                "401": 0
              },
              "1527892800": {}
            },
            "02c391cd-5705-435d-9498-d7cfc40c4c76": {
              "1527892860": {
                "404": 0,
                "401": 0,
                "200": 0
              },
              "1527892920": {
                "404": 0,
                "401": 0,
                "200": 0
              },
              "1527892800": {}
            }
          }
        }
      ]]), ok)
    end)
  end)

  describe("translates", function()
    local prometheus = require "kong.vitals.prometheus.strategy"
    setup(function()
      -- the last variable should be synced with the sample json below
      stub(prometheus, "query").returns(consumer_stats_sample, nil, 120)
    end)
  
    teardown(function()
      prometheus.query:revert()
    end)

    it("cluster level consumer stats", function()
      local prom = prometheus.new(nil, {host = "notahost", port = 65555, cluster_level = true})
      local ok, err = prom:select_consumer_stats("minutes", "cluster", nil)
      assert.is_nil(err)
      assert.same(cjson.decode([[
      {
        "meta": {
          "earliest_ts": 1527892620,
          "latest_ts": 1527892920,
          "interval": "seconds",
          "interval_width": 15,
          "level": "cluster",
          "nodes": {
              "cluster": {
                "hostname": "cluster"
              }
          },
          "stat_labels": [
            "requests_consumer_total"
          ]
        },
        "stats": {
          "cluster": {
            "1527892680": 9643,
            "1527892740": 3121,
            "1527892800": 11990,
            "1527892860": 11011,
            "1527892920": 11109
          }
        }
      }
      ]]), ok)
    end)

    pending("node level consumer stats", function()
      local prom = prometheus.new(nil, {host = "notahost", port = 65555})
      local ok, err = prom:select_consumer_stats("minutes", "cluster", nil)
      assert.is_nil(err)

      local prom = prometheus.new(nil, {host = "notahost", port = 65555, cluster_level = false})
      local ok_explicit_arg, err = prom:select_consumer_stats("minutes", "cluster", nil)
      assert.is_nil(err)
      assert.same(ok, ok_explicit_arg)

      assert.same(cjson.decode([[
      {
        "meta": {
          "earliest_ts": 1527892620,
          "latest_ts": 1527892920,
          "interval": "seconds",
          "interval_width": 30,
          "level": "node",
          "nodes": {
            "localhost:65555": {
              "hostname": "localhost:65555"
            }
          },
          "stat_labels": [
            "requests_consumer_total"
          ]
        },
        "stats": {
          "localhost:65555": {
            "1527892680": 9643,
            "1527892740": 3121,
            "1527892800": 11990,
            "1527892860": 11011,
            "1527892920": 11109
          }
        }
      }
      ]]), ok)
    end)
  end)

  describe("mocks", function()
    it("select_phone_home", function()
      local prometheus = require "kong.vitals.prometheus.strategy"
  
      local prom_instance = prometheus.new(nil, {host = "notahost", port = 65555})
      local s = spy.new(prom_instance.select_phone_home)

      s()

      assert.spy(s).was_returned_with({}, nil)

      s:revert()
    end)
  end)

  describe("mocks", function()
    it("node_exists", function()
      local prometheus = require "kong.vitals.prometheus.strategy"

      local prom_instance = prometheus.new(nil, {host = "notahost", port = 65555})
      local s = spy.new(prom_instance.node_exists)

      s()

      assert.spy(s).was_returned_with(true, nil)

      s:revert()
    end)

    it("init", function()
      local prometheus = require "kong.vitals.prometheus.strategy"

      local prom_instance = prometheus.new(nil, {host = "notahost", port = 65555})
      local s = spy.new(prom_instance.init)

      s()

      assert.spy(s).was_returned_with(true, nil)

      s:revert()
    end)

    it("a dummy function", function()
      local prometheus = require "kong.vitals.prometheus.strategy"

      local prom = prometheus.new(nil, {host = "notahost", port = 65555})
      local s = spy.new(prom.this_is_a_dummy_function)

      s()

      assert.spy(s).was_returned_with(true, nil)

      s:revert()
    end)
  end)
end)
