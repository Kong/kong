-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- imports
--

local cjson = require("cjson")
local gzip = require("kong.tools.gzip")

--
-- public vars
--

-- some previously generated text embeddings for mocking, using OpenAI's
-- text-embedding-3-small model and 4 dimensions.
local known_text_embeddings = {
  ["dog"] = { 0.56267416, -0.20551957, -0.047182854, 0.79933304 },
  ["cat"] = { 0.4653789, -0.42677408, -0.29335415, 0.717795 },
  ["capacitor"] = { 0.350534, -0.025470039, -0.9204002, -0.17129119 },
  ["smell"] = { 0.23342973, -0.08322083, -0.8492907, -0.46614397 },
  ["Non-Perturbative Quantum Field Theory and Resurgence in Supersymmetric Gauge Theories"] = {
    -0.6826024,
    -0.08655233,
    -0.72073454,
    -0.084287055,
  },
  ["taco"] = { -0.4407651, -0.85174876, -0.27901474, -0.048999753 },
  ["If it discuss any topic about Amazon"] = { -0.86724466, 0.36718428, -0.21300745, -0.26017338 },
  ["If it discuss any topic about Microsoft"] = { -0.8649115, 0.2526763, -0.41767937, -0.11673351 },
  ["If it discuss any topic about Google"] = { -0.8108202, -0.22810346, -0.3790472, -0.38322666 },
  ["If it discuss any topic about Apple"] = { -0.8892975, 0.30626073, -0.336221, 0.048061296 },
  ["tell me something about Microsoft"] = { -0.48062202, -0.4189232, -0.7663229, -0.07908846 },
  ["tell me something about Amazon"] = { -0.9346679, 0.10783355, -0.13593763, -0.31030443 },
  ["tell me something about Google"] = { -0.3132111, -0.87082464, -0.33971936, -0.16779166 },
}

--
-- public functions
--

local function mock_embeddings(opts)
  if opts.method ~= "POST" then
    return nil, "Only POST method is supported"
  end

  if opts.headers["Content-Type"] ~= "application/json" then
    return nil, "Only application/json content type is supported"
  end

  if opts.headers["Accept-Encoding"] ~= "gzip" then
    return nil, "Only gzip encoding is supported"
  end

  local request_body = cjson.decode(opts.body)

  if not request_body.dimensions then
    request_body.dimensions = 4
  end
  if request_body.dimensions ~= 4 then
    return nil, "Only 4 dimensions are supported"
  end

  local prompt = request_body.input
  local embedding = known_text_embeddings[prompt]
  if not embedding then
    return nil, "Invalid prompt"
  end

  local response_body = {
    data = {
      { embedding = embedding },
    },
  }

  local encoded_response_body = cjson.encode(response_body)
  local gzipped_response_body = gzip.deflate_gzip(encoded_response_body)

  return {
    status = 200,
    body = gzipped_response_body,
    headers = {
      ["Content-Encoding"] = "gzip",
    },
  }
end

--
-- module
--

return {
  -- vars
  known_text_embeddings = known_text_embeddings,

  -- functions
  mock_embeddings = mock_embeddings,
}
