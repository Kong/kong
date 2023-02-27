local x = 0

local function increment()
	-- using closure as a counter in closed environment
	x = x + 1
	return x
end

local function simulate_key_rotation()
	local n = increment()
	local old =
	'{"keys":[{"kty":"RSA","kid":"5962e7a059c7f5c0c0d56cbad51fe64ceeca67c6","alg":"RS256","use":"sig","e":"AQAB","n":"lHW8Q4I2Qcz1PdtkiCBeeoZHTdjrw8c9sqGODztqaEvggSBl-wcBnLisXIulEkwtCvEwdx4VW4173yi5LLFc47Z1J6-1z9O0xaja7FQNG5xkSYtjOxJyPY7sqDnt9mcoMZEcBf_XB0Uc6Vp-JyQHKM3t1LjK_IrlzruU8UCLw6T654uQfEap9xtV8xuWhlPOdq8psqGTD1rev0ZIqXWVaBlsJ9f7M9k_pSA6YmujjxzzlZ4ASP97yNzudu8vSHdT_BL0aEc81-SgtJbw6IAAzcOoA-e6oFQuzoMJ0FhbgJ5H5A9aUtMHX9qXXVIRefzy3bkGtxTvwuJt3FyesHpxzQ"},{"e":"AQAB","kid":"1337","n":"yyy","alg":"RS256","use":"sig","kty":"RSA"}]}'
	local new =
	'{"keys":[{"kty":"RSA","kid":"5962e7a059c7f5c0c0d56cbad51fe64ceeca67c6","alg":"RS256","use":"sig","e":"AQAB","n":"lHW8Q4I2Qcz1PdtkiCBeeoZHTdjrw8c9sqGODztqaEvggSBl-wcBnLisXIulEkwtCvEwdx4VW4173yi5LLFc47Z1J6-1z9O0xaja7FQNG5xkSYtjOxJyPY7sqDnt9mcoMZEcBf_XB0Uc6Vp-JyQHKM3t1LjK_IrlzruU8UCLw6T654uQfEap9xtV8xuWhlPOdq8psqGTD1rev0ZIqXWVaBlsJ9f7M9k_pSA6YmujjxzzlZ4ASP97yNzudu8vSHdT_BL0aEc81-SgtJbw6IAAzcOoA-e6oFQuzoMJ0FhbgJ5H5A9aUtMHX9qXXVIRefzy3bkGtxTvwuJt3FyesHpxzQ"},{"e":"AQAB","kid":"1337","n":"xxx","alg":"RS256","use":"sig","kty":"RSA"}]}'
	ngx.header.content_type = "application/jwk-set+json"
	if n % 2 == 0 then
		ngx.say(old)
	else
		ngx.say(new)
	end
	ngx.exit(ngx.OK)
end

return {
	simulate_key_rotation = simulate_key_rotation
}
