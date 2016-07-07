--local function check_log_type(given_value, given_config)
--	if given_value ~= "None" then
--		return false, "not supported"
--	end
--end

return {
	no_consumer = true,
	fields = {
		aws_access_key = {
			type = string,
			required = false,
			default = nil },
		aws_secret_key = {
			type = string,
			required = false,
			default = nil },
		body = {
			type = string,
			required = false,
			default = nil }
		--log_type = {
		--	type = string,
		--	required = false,
		--	default = "None",
		--	enum = {"None", "Tail"},
		--	func = check_log_type },
		--client_context = {
		--	type = string,
		--	required = false,
		--	default = nil }
	}
}
