-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- run this file, if want to reuse an infra and only do a cleanup at the end

local perf = require("spec.helpers.perf")

perf.use_defaults()

perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)