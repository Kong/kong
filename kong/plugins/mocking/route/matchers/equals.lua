local lower = string.lower
return function(location, pattern, insensitive)
    if location and insensitive then
        location = lower(location)
        pattern  = lower(pattern)
    end
    return location == pattern
end
