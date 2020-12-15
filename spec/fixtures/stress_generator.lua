local stress_generator = {}
stress_generator.__index = stress_generator


local cjson = require "cjson"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local uuid = require "resty.jit-uuid"


local fmt = string.format
local tmp_root = os.getenv("TMPDIR") or "/tmp"


-- we need this to get random UUIDs
math.randomseed(os.time())


local attack_cmds = {
  ["http"] = "GET http://%s:%d%s",
}


function stress_generator.is_running(self)
  if self.finish_time == nil or self.finish_time <= os.time() then
    return false
  end

  return true
end


function stress_generator.get_results(self)
  if self.results ~= nil then
    return self.results
  end

  if self.results_filename == nil then
    return nil, "stress_generator was not run yet"
  end

  if stress_generator:is_running() then
    return nil, "stress_generator results not available yet"
  end

  local report_cmd = fmt("vegeta report -type=json %s 2>&1", self.results_filename)
  local report_pipe = io.popen(report_cmd)
  local output = report_pipe:read('*all')
  report_pipe:close()

  if pl_path.exists(self.results_filename) then
    pl_file.delete(self.results_filename)
  end


  local vegeta_results = cjson.decode(output)
  local results = {
    ["successes"] = 0,
    ["remote_failures"] = 0,
    ["proxy_failures"] = 0,
    ["failures"] = 0,
  }

  vegeta_results.status_codes = vegeta_results.status_codes or {}

  for status, count in pairs(vegeta_results.status_codes) do
    if status == "200" then
      results.successes = count
    elseif status == "502" or status == "504" then
      results.remote_failures = results.remote_failures + count
      results.failures = results.failures + count
    elseif status == "500" or status == "503" then
      results.proxy_failures = results.proxy_failures + count
      results.failures = results.failures + count
    else
      results.failures = results.failures + count
    end
  end

  self.results = results

  if self.debug then
    -- show pretty results
    local report_cmd = fmt("vegeta report %s 2>&1", self.results_filename)
    local report_pipe = io.popen(report_cmd)
    local output = report_pipe:read('*all')
    report_pipe:close()
    print(output)
  end

  return self.results
end


function stress_generator.run(self, uri, headers, duration, rate)
  if stress_generator:is_running() then
    return nil, "already running"
  end

  self.results_filename = fmt("%s/vegeta_%s", tmp_root, uuid())

  duration = duration or 1
  rate = rate or 100
  local attack_cmd = fmt(attack_cmds[self.protocol], self.host, self.port, uri)
  local req_headers = ""

  for name, value in pairs(headers) do
    req_headers = fmt("-header=%s:%s %s", name, value, req_headers)
  end

  local vegeta_cmd = fmt(
    "echo %s | vegeta attack %s -rate=%d -duration=%ds -workers=%d -timeout=5s -output=%s",
    attack_cmd, req_headers, rate, duration, self.workers, self.results_filename)

  self.pipe = io.popen(vegeta_cmd)
  -- we will rely on vegeta's duration
  self.finish_time = os.time() + duration
end


function stress_generator.new(protocol, host, port, workers, debug)
  if io.popen == nil then
    error("stress_generator is not supported in this platform", 2)
  end

  local self = setmetatable({}, stress_generator)

  protocol = protocol or "http"

  if protocol ~= "http" then
    error("stress_generator supports only http")
  end

  self.debug = debug == true
  self.host = host or "127.0.0.1"
  self.port = port or "80"
  self.protocol = protocol
  self.workers = workers or 10

  return self
end


return stress_generator
