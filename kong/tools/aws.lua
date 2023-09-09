local concurrency = require("kong.concurrency")

-- require resty.aws.config to have it capture any pertinent environment variables
require("resty.aws.config")

local resty_aws = require("resty.aws")

return function(options)
    return concurrency.get_worker_singleton(
            "AWS",
            function()
                return resty_aws(options)
            end)
end
