local _M = {}

function _M.set_response_transformer_skipped()
  kong.ctx.shared.llm_skip_response_transformer = true
end

function _M.is_response_transformer_skipped()
  return not not kong.ctx.shared.llm_skip_response_transformer
end

function _M.set_prompt_decorated()
  kong.ctx.shared.llm_prompt_decorated = true
end

function _M.is_prompt_decorated()
  return not not kong.ctx.shared.llm_prompt_decorated
end

function _M.set_prompt_guarded()
  kong.ctx.shared.llm_prompt_guarded = true
end

function _M.is_prompt_guarded()
  return not not kong.ctx.shared.llm_prompt_guarded
end

function _M.set_prompt_templated()
  kong.ctx.shared.llm_prompt_templated = true
end

function _M.is_prompt_templated()
  return not not kong.ctx.shared.llm_prompt_templated
end

function _M.set_streaming_mode()
  kong.ctx.shared.llm_streaming_mode = true
end

function _M.is_streaming_mode()
  return not not kong.ctx.shared.llm_streaming_mode
end

function _M.set_parsed_response(response)
  kong.ctx.shared.llm_parsed_response = response
end

function _M.get_parsed_response()
  return kong.ctx.shared.llm_parsed_response
end

function _M.set_replacement_response(response)
  kong.ctx.shared.llm_replacement_response = response
end

function _M.get_replacement_response()
  return kong.ctx.shared.llm_replacement_response
end

function _M.set_request_analytics(tbl)
  kong.ctx.shared.llm_request_analytics = tbl
end

function _M.get_request_analytics()
  return kong.ctx.shared.llm_request_analytics
end

function _M.increase_prompt_tokens_count(by)
  local count = (kong.ctx.shared.llm_prompt_tokens_count or 0) + by
  kong.ctx.shared.llm_prompt_tokens_count = count
  return count
end

function _M.get_prompt_tokens_count()
  return kong.ctx.shared.llm_prompt_tokens_count
end

function _M.increase_response_tokens_count(by)
  local count = (kong.ctx.shared.llm_response_tokens_count or 0) + by
  kong.ctx.shared.llm_response_tokens_count = count
  return count
end

function _M.get_response_tokens_count()
  return kong.ctx.shared.llm_response_tokens_count
end

return _M