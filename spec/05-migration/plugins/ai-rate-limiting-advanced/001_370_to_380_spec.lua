-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- The: '001_370_to_380' migration deprecates redis.timeout in plugin configuration.
-- However ai-rate-limiting-advanced was introduced in 3.7 whereas
-- the upgrade tests start at 2.8 or 3.4. So there's no way to setup the plugin with redis_options
-- config in version 3.7 (with timeout field) and verify if the migration to 3.8 works.
-- However the redis config is shared across various plugins and the migration code was tested there:
-- (rate-limiting-advanced, graphql-rate-limiting-advanced, proxy-cache-advanced)
pending("Skipped", function() end)
