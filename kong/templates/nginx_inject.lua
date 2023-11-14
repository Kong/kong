return [[
> if database == "off" then
lmdb_environment_path ${{LMDB_ENVIRONMENT_PATH}};
lmdb_map_size         ${{LMDB_MAP_SIZE}};
lmdb_validation_tag   $(lmdb_validation_tag);
> end
]]
