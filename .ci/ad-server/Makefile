# Test server for testing AD Mapping (INTF-1941)
build-ad-server:
	docker-compose up -d ad-server
	docker-compose exec -T ad-server sh setup-ad/setup.sh
	docker-compose exec -T ad-server bash setup-ad/add-seed-data.sh
	docker-compose exec -T ad-server samba -D

clone-plugin:
	git clone https://${GITHUB_TOKEN}:@github.com/Kong/kong-plugin-enterprise-ldap-auth.git ldap-auth-advanced
	cp -r ./ldap-auth-advanced/kong/plugins/* ../../kong/plugins/
	rm -rf ./ldap-auth-advanced
