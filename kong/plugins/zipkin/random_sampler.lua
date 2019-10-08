local random_sampler_methods = {}
local random_sampler_mt = {
  __name = "kong.plugins.zipkin.random_sampler";
  __index = random_sampler_methods;
}

local function new_random_sampler(conf)
  local sample_ratio = conf.sample_ratio
  assert(type(sample_ratio) == "number" and sample_ratio >= 0 and sample_ratio <= 1, "invalid sample_ratio")
  return setmetatable({
    sample_ratio = sample_ratio;
  }, random_sampler_mt)
end

function random_sampler_methods:sample(name) -- luacheck: ignore 212
  return math.random() < self.sample_ratio
end

return {
  new = new_random_sampler;
}
