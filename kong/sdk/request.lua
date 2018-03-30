local function new(_SDK_REQUEST, major_version)
  -- instance of this major version of this SDK module

  -- declare any necessary upvalue here, like reused tables
  -- ...

  -- declare functions below
  -- ...

  function _SDK_REQUEST.get_thing()
    -- here, we can branch out if we ever need to break something:
    if major_version >= 1 then
      -- do something that would be breaking for next version
      return "hello v1"
    end

    -- do the previon version thing
    return "hello v0"
  end
end

return {
  namespace = "request",
  new = new,
}
