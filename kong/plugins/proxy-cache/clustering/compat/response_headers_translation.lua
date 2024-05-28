local function adapter(config_to_update)
    if config_to_update.response_headers["Age"] ~= nil then
        config_to_update.response_headers.age = config_to_update.response_headers["Age"]
        config_to_update.response_headers["Age"] = nil
        return true
    end

    return false
end

return {
    adapter = adapter
}
