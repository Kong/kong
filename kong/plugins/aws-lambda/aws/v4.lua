-- Performs AWSv4 Signing
-- http://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html

local openssl_hmac_new = require "openssl.hmac".new
local openssl_digest_new = require "openssl.digest".new

local Algorithm = "AWS4-HMAC-SHA256"
local function HMAC(key, msg)
	return openssl_hmac_new(key, "sha256"):final(msg)
end
local function Hash(str)
	return openssl_digest_new("sha256"):final(str)
end
local HexEncode do -- From prosody's util.hex
	local char_to_hex = {};
	for i = 0, 255 do
		local char = string.char(i)
		local hex = string.format("%02x", i)
		char_to_hex[char] = hex
	end
	function HexEncode(str)
		return (str:gsub(".", char_to_hex))
	end
end

local function percent_encode(char)
	return string.format("%%%02X", string.byte(char))
end

local urldecode do
	local function urldecode_helper(c)
		return string.char(tonumber(c, 16))
	end
	function urldecode(str)
		return (str:gsub("%%(%x%x)", urldecode_helper))
	end
end

-- Trim 12 from http://lua-users.org/wiki/StringTrim
local function Trimall(s)
	local from = s:match"^%s*()"
	return from > #s and "" or s:match(".*%S", from)
end

local function canonicalise_path(path)
	local segments = {}
	for segment in path:gmatch("/([^/]*)") do
		if segment == "" or segment == "." then
			segments = segments -- do nothing and avoid lint
		elseif segment == ".." then
			-- intentionally discards components at top level
			segments[#segments] = nil
		else
			segments[#segments+1] = urldecode(segment):gsub("[^%w%-%._~]", percent_encode)
		end
	end
	local len = #segments
	if len == 0 then return "/" end
	-- If there was a slash on the end, keep it there.
	if path:sub(-1, -1) == "/" then
		len = len + 1
		segments[len] = ""
	end
	segments[0] = ""
	segments = table.concat(segments, "/", 0, len)
	return segments
end

local function canonicalise_query_string(query)
	local q = {}
	for key, val in query:gmatch("([^&=]+)=?([^&]*)") do
		key = urldecode(key):gsub("[^%w%-%._~]", percent_encode)
		val = urldecode(val):gsub("[^%w%-%._~]", percent_encode)
		q[#q+1] = key .. "=" .. val
	end
	table.sort(q)
	return table.concat(q, "&")
end

local function derive_signing_key(kSecret, Date, Region, Service)
	local kDate = HMAC("AWS4" .. kSecret, Date)
	local kRegion = HMAC(kDate, Region)
	local kService = HMAC(kRegion, Service)
	local kSigning = HMAC(kService, "aws4_request")
	return kSigning
end

local function prepare_awsv4_request(tbl)
	local Domain = tbl.Domain or "amazonaws.com"
	assert(type(Domain) == "string", "bad field 'Domain' (string or nil expected)")
	local Region = tbl.Region
	assert(type(Region) == "string", "bad field 'Region' (string expected)")
	local Service = tbl.Service
	assert(type(Service) == "string", "bad field 'Service' (string expected)")
	local HTTPRequestMethod = tbl.method
	assert(type(HTTPRequestMethod) == "string", "bad field 'method' (string expected)")
	local CanonicalURI = tbl.CanonicalURI
	local path = tbl.path
	if CanonicalURI == nil and path ~= nil then
		assert(type(path) == "string", "bad field 'path' (string or nil expected)")
		CanonicalURI = canonicalise_path(path)
	elseif CanonicalURI == nil or CanonicalURI == "" then
		CanonicalURI = "/"
	end
	assert(type(CanonicalURI) == "string", "bad field 'CanonicalURI' (string or nil expected)")
	local CanonicalQueryString = tbl.CanonicalQueryString
	local query = tbl.query
	if CanonicalQueryString == nil and query ~= nil then
		assert(type(query) == "string", "bad field 'query' (string or nil expected)")
		CanonicalQueryString = canonicalise_query_string(query)
	end
	assert(type(CanonicalQueryString) == "string" or CanonicalQueryString == nil, "bad field 'CanonicalQueryString' (string or nil expected)")
	local req_headers = tbl.headers or {}
	assert(type(req_headers) == "table", "bad field 'headers' (table or nil expected)")
	local RequestPayload = tbl.body
	assert(type(RequestPayload) == "string" or RequestPayload == nil, "bad field 'body' (string or nil expected)")
	local AccessKey = tbl.AccessKey
	assert(type(Region) == "string", "bad field 'AccessKey' (string expected)")
	local SigningKey = tbl.SigningKey
	assert(type(SigningKey) == "string" or SigningKey == nil, "bad field 'SigningKey' (string or nil expected)")
	local SecretKey
	if SigningKey == nil then
		SecretKey = tbl.SecretKey
		if SecretKey == nil then
			assert(SecretKey, "either 'SigningKey' or 'SecretKey' must be provided")
		end
		assert(type(SecretKey) == "string", "bad field 'SecretKey' (string expected)")
	end
	local timestamp = tbl.timestamp or os.time()
	assert(type(timestamp) == "number", "bad field 'timestamp' (number or nil expected)")
	local tls = tbl.tls
	if tls == nil then tls = true end
	local port = tbl.port or (tls and 443 or 80)
	assert(type(port) == "number", "bad field 'port' (string or nil expected)")

	local RequestDate = os.date("!%Y%m%dT%H%M%SZ", timestamp)
	local Date = os.date("!%Y%m%d", timestamp)

	local host = Service .. "." .. Region .. "." .. Domain
	local host_header do -- If the "standard" port is not in use, the port should be added to the Host header
		local with_port
		if tls then
			with_port = port ~= 443
		else
			with_port = port ~= 80
		end
		if with_port then
			host_header = string.format("%s:%d", host, port)
		else
			host_header = host
		end
	end

	local headers = {
		["X-Amz-Date"] = RequestDate;
		Host = host_header;
	}
	local add_auth_header = true
	for k, v in pairs(req_headers) do
		assert(type(k) == "string", "bad field 'headers' (only string keys allowed)")
		k = k:gsub("%f[^%z-]%w", string.upper) -- convert to standard header title case
		if k == "Authorization" then
			add_auth_header = false
		elseif v == false then -- don't allow a default value for this header
			v = nil
		end
		headers[k] = v
	end

	-- Task 1: Create a Canonical Request For Signature Version 4
	-- http://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html
	local CanonicalHeaders, SignedHeaders do
		-- We structure this code in a way so that we only have to sort once.
		CanonicalHeaders, SignedHeaders = {}, {}
		local i = 0
		for name, value in pairs(headers) do
			if value then -- ignore headers with 'false', they are used to override defaults
				i = i + 1
				local name_lower = name:lower()
				SignedHeaders[i] = name_lower
				assert(CanonicalHeaders[name_lower] == nil, "header collision")
				CanonicalHeaders[name_lower] = Trimall(value)
			end
		end
		table.sort(SignedHeaders)
		for j=1, i do
			local name = SignedHeaders[j]
			local value = CanonicalHeaders[name]
			CanonicalHeaders[j] = name .. ":" .. value .. "\n"
		end
		SignedHeaders = table.concat(SignedHeaders, ";", 1, i)
		CanonicalHeaders = table.concat(CanonicalHeaders, nil, 1, i)
	end
	local CanonicalRequest =
		HTTPRequestMethod .. '\n' ..
		CanonicalURI .. '\n' ..
		(CanonicalQueryString or "") .. '\n' ..
		CanonicalHeaders .. '\n' ..
		SignedHeaders .. '\n' ..
		HexEncode(Hash(RequestPayload or ""))
	local HashedCanonicalRequest = HexEncode(Hash(CanonicalRequest))
	-- Task 2: Create a String to Sign for Signature Version 4
	-- http://docs.aws.amazon.com/general/latest/gr/sigv4-create-string-to-sign.html
	local CredentialScope = Date .. "/" .. Region .. "/" .. Service .. "/aws4_request"
	local StringToSign =
		Algorithm .. '\n' ..
		RequestDate .. '\n' ..
		CredentialScope .. '\n' ..
		HashedCanonicalRequest
	-- Task 3: Calculate the AWS Signature Version 4
	-- http://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
	if SigningKey == nil then
		SigningKey = derive_signing_key(SecretKey, Date, Region, Service)
	end
	local Signature = HexEncode(HMAC(SigningKey, StringToSign))
	-- Task 4: Add the Signing Information to the Request
	-- http://docs.aws.amazon.com/general/latest/gr/sigv4-add-signature-to-request.html
	local Authorization = Algorithm
		.. " Credential=" .. AccessKey .."/" .. CredentialScope
		.. ", SignedHeaders=" .. SignedHeaders
		.. ", Signature=" .. Signature
	if add_auth_header then
		headers.Authorization = Authorization
	end

	local target = path or CanonicalURI
	if query or CanonicalQueryString then
		target = target .. "?" .. (query or CanonicalQueryString)
	end
	local scheme = tls and "https" or "http"
	local url = scheme .. "://" .. host_header .. target

	return {
		url = url;
		host = host;
		port = port;
		tls = tls;
		method = HTTPRequestMethod;
		target = target;
		headers = headers;
		body = RequestPayload;
	}, {
		CanonicalURI = CanonicalURI;
		CanonicalQueryString = CanonicalQueryString;
		SignedHeaders = SignedHeaders;
		CanonicalHeaders = CanonicalHeaders;
		CanonicalRequest = CanonicalRequest;
		StringToSign = StringToSign;
		SigningKey = SigningKey;
		Signature = Signature;
		Authorization = Authorization;
	}
end

return {
	canonicalise_path = canonicalise_path;
	canonicalise_query_string = canonicalise_query_string;
	derive_signing_key = derive_signing_key;
	prepare_request = prepare_awsv4_request;
}
