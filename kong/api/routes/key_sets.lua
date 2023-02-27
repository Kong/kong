return {
  ["/key-sets/:key_sets/rotate"] = {
    -- Define a function to handle PATCH requests to the "/key-sets/:key_sets/rotate" route
    PATCH = function(self, db)
      -- Look up the key set specified in the URL parameters in the database
      local key_set, err  = db.key_sets:select_by_name(self.params.key_sets)
      -- If the key set could not be found, return a 404 Not Found response
      if not key_set then
        return kong.response.exit(404, { message = err })
      end
      -- Rotate the key set
      local rotate_ok, rotate_err = db.key_sets:rotate(key_set)
      -- If there was an error rotating the key set, return a 500 Internal Server Error response
      if rotate_err then
        return kong.response.exit(500, { error = rotate_err })
      end
      -- If the key set was rotated successfully, return a 200 OK response with a success message
      return kong.response.exit(200, { message = rotate_ok })
    end
  },
}
