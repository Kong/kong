#!/usr/bin/env lua

-- Simple standalone test for normalize_accept_encoding function
-- This can be run without the full Kong environment for quick validation

local function normalize_accept_encoding(accept_encoding_header)
  local lower = string.lower
  local match = string.match
  local sort = table.sort
  local concat = table.concat

  if not accept_encoding_header or accept_encoding_header == "" then
    return "none"
  end

  local header_lower = lower(accept_encoding_header)
  local encodings = {}
  
  for encoding in header_lower:gmatch("[^,]+") do
    encoding = match(encoding, "^%s*(.-)%s*$")
    local encoding_name = match(encoding, "^([^;]+)")
    if encoding_name then
      encoding_name = match(encoding_name, "^%s*(.-)%s*$")
      if encoding_name ~= "" and encoding_name ~= "*" then
        encodings[#encodings + 1] = encoding_name
      end
    end
  end

  if #encodings == 0 then
    return "none"
  end

  sort(encodings)
  return concat(encodings, ",")
end

-- Test cases
local tests = {
  -- Basic tests
  {input = nil, expected = "none", desc = "nil header"},
  {input = "", expected = "none", desc = "empty string"},
  {input = "   ", expected = "none", desc = "whitespace only"},
  {input = "gzip", expected = "gzip", desc = "single encoding"},
  {input = "  gzip  ", expected = "gzip", desc = "single encoding with whitespace"},
  
  -- Multiple encodings
  {input = "gzip, deflate, br", expected = "br,deflate,gzip", desc = "multiple encodings (sorted)"},
  {input = "br, deflate, gzip", expected = "br,deflate,gzip", desc = "multiple encodings different order"},
  
  -- Case sensitivity
  {input = "GZIP", expected = "gzip", desc = "uppercase"},
  {input = "Gzip", expected = "gzip", desc = "mixed case"},
  {input = "gZiP", expected = "gzip", desc = "weird case"},
  
  -- Quality values
  {input = "gzip;q=1.0, deflate;q=0.8", expected = "deflate,gzip", desc = "with quality values"},
  {input = "gzip ; q=1.0 , deflate ; q=0.8", expected = "deflate,gzip", desc = "quality with spaces"},
  
  -- Edge cases
  {input = "gzip, *", expected = "gzip", desc = "with wildcard"},
  {input = "*", expected = "none", desc = "only wildcard"},
  {input = "identity", expected = "identity", desc = "identity encoding"},
  
  -- Real-world examples
  {input = "gzip, deflate", expected = "deflate,gzip", desc = "common browser header"},
  {input = "gzip, deflate, br", expected = "br,deflate,gzip", desc = "modern browser header"},
  {input = "GZIP;q=1.0, Deflate;q=0.8, BR", expected = "br,deflate,gzip", desc = "mixed case with quality"},
}

-- Run tests
local passed = 0
local failed = 0

print("Running normalize_accept_encoding tests...\n")

for i, test in ipairs(tests) do
  local result = normalize_accept_encoding(test.input)
  local status = result == test.expected and "✓ PASS" or "✗ FAIL"
  
  if result == test.expected then
    passed = passed + 1
    print(string.format("%s Test %d: %s", status, i, test.desc))
  else
    failed = failed + 1
    print(string.format("%s Test %d: %s", status, i, test.desc))
    print(string.format("  Input:    %q", tostring(test.input)))
    print(string.format("  Expected: %q", test.expected))
    print(string.format("  Got:      %q", result))
  end
end

print(string.format("\n%d/%d tests passed", passed, passed + failed))

if failed > 0 then
  os.exit(1)
end

print("\nAll tests passed! ✓")
