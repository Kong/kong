-- This data migration updates queue parameters so that they conform to the changes made in https://github.com/Kong/kong/pull/10840
-- The migration lives in a separate file so that it can be tested easily
return [[
update plugins
set config = jsonb_set(config, '{queue, max_batch_size}', to_jsonb(round((config->'queue'->>'max_batch_size')::numeric)))
where config->'queue'->>'max_batch_size' is not null;

update plugins
set config = jsonb_set(config, '{queue, max_entries}', to_jsonb(round((config->'queue'->>'max_entries')::numeric)))
where config->'queue'->>'max_entries' is not null;

update plugins
set config = jsonb_set(config, '{queue, max_bytes}', to_jsonb(round((config->'queue'->>'max_bytes')::numeric)))
where config->'queue'->>'max_bytes' is not null;

update plugins
set config = jsonb_set(config, '{queue, initial_retry_delay}', to_jsonb(least(greatest((config->'queue'->>'initial_retry_delay')::numeric, 0.001), 1000000)))
where config->'queue'->>'initial_retry_delay' is not null;

update plugins
set config = jsonb_set(config, '{queue, max_retry_delay}', to_jsonb(least(greatest((config->'queue'->>'max_retry_delay')::numeric, 0.001), 1000000)))
where config->'queue'->>'max_retry_delay' is not null;
]]
