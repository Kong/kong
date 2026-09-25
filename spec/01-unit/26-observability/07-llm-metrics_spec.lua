local function reload_module(name)
  package.loaded[name] = nil
  return require(name)
end


describe("kong.llm.plugin.observability metrics", function()
  local o11y

  before_each(function()
    _G.ngx.ctx = {}
    o11y = reload_module("kong.llm.plugin.observability")
  end)

  it("falls back to prompt + completion when total is not set", function()
    o11y.metrics_set("llm_prompt_tokens_count", 3)
    o11y.metrics_set("llm_completion_tokens_count", 7)

    assert.equal(10, o11y.metrics_get("llm_total_tokens_count"))
  end)

  it("uses the provider's total when set, even if it differs from the sum", function()
    -- models with reasoning/hidden tokens report a total that is greater than
    -- prompt + completion; the reported total must win
    o11y.metrics_set("llm_prompt_tokens_count", 3)
    o11y.metrics_set("llm_completion_tokens_count", 7)
    o11y.metrics_set("llm_total_tokens_count", 298)

    assert.equal(298, o11y.metrics_get("llm_total_tokens_count"))
  end)
end)
