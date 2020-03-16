local match = string.match
return function(location, pattern)
    return match(location, pattern)
end