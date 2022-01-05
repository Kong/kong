-- run this file, if want to reuse an infra and only do a cleanup at the end

local perf = require("spec.helpers.perf")

perf.set_log_level(ngx.DEBUG)
--perf.set_retry_count(3)

local driver = os.getenv("PERF_TEST_DRIVER") or "docker"

if driver == "terraform" then
  perf.use_driver("terraform", {
    provider = "equinix-metal",
    tfvars = {
      -- Kong Benchmarking
      metal_project_id = os.getenv("PERF_TEST_METAL_PROJECT_ID"),
      -- TODO: use an org token
      metal_auth_token = os.getenv("PERF_TEST_METAL_AUTH_TOKEN"),
      -- metal_plan = "baremetal_1",
      -- metal_region = "sjc1",
      -- metal_os = "ubuntu_20_04",
    }
  })
else
  perf.use_driver(driver)
end

perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)