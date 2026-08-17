-- run this file, if want to reuse an infra and only do a cleanup at the end

local perf = require("spec.helpers.perf")

perf.use_defaults()

perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)