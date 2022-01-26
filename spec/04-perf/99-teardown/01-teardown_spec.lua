-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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