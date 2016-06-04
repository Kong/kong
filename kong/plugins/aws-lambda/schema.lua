local function check_invocation_type(given_value, given_config, col, tbl, schema, opts)
	if given_value ~= "RequestResponse" then
		return false, "not supported"
	end
end

local function check_log_type(given_value, given_config)
	if given_value ~= "None" then
		return false, "not supported"
	end
end

local function check_qualifier(given_value, given_config)
	if given_value ~= nil then
		return false, "not supported"
	end
end

return {
	no_consumer = true,
	fields = {
		aws_region = {
			type = "string",
			required = true },
		function_name = {
			type = "string",
			required = true },
		--qualifier = {
		--	type = "string",
		--	required = false,
		--	default = "$LATEST",
		--	func = check_qualifier },
		--invocation_type = {
		--	type = "string",
		--	required = false,
		--	default = "RequestResponse",
		--	enum = {"Event", "RequestResponse", "DryRun"},
		--	func = check_invocation_type },
		--log_type = {
		--	type = string,
		--	required = false,
		--	default = "None",
		--	enum = {"None", "Tail"},
		--	func = check_log_type },
		body = {
			type = string,
			required = false,
			default = nil },
		--client_context = {
		--	type = string,
		--	required = false,
		--	default = nil },
		aws_access_key = {
			type = string,
			required = false,
			default = nil },
		aws_secret_key = {
			type = string,
			required = false,
			default = nil }
	}
}
