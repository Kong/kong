dockerCPImage=$(GW_IMAGE)
kongCloudPullPassword=$(DOCKERHUB_KONGCLOUD_PULL_PSW)
composeGeneratorFolderName=gateway-docker-compose-generator
composeGeneratorFolderPath=${PWD}/${composeGeneratorFolderName}
 
host=ec2-18-118-37-120.us-east-2.compute.amazonaws.com
ip=18.118.37.120
secret=$(shell [ -f ./testec2.pem ] && echo testec2.pem)
ssh=ssh -i ${secret} ec2-user@${host}
sshLight=ssh -o StrictHostKeyChecking=no -i ${secret} ec2-user@${host}

clear_ec2_docker_volumes:
	@echo "Removing EC2 Docker volumes"
	${ssh} 'docker volume rm $$(docker volume ls -q)'
	@echo "Finished Removing EC2 Docker volumes"

start_gw:
	@echo "Starting Gateway"
	cd ${composeGeneratorFolderPath}; make start
	@echo "Started Gateway"

stop_gw:
	@echo "Stopping Gateway"
	cd ${composeGeneratorFolderPath}; make stop; make clean
	@echo "Gateway was successfully stopped"

set_env_variables:
	cd ${composeGeneratorFolderPath}; export ${envVars}; make generate

custom_start_gw: stop_gw set_env_variables start_gw

set_docker_cp_image:
	@echo "Updating EC2 Docker Control Plane Image"
	${ssh} 'grep -qxF GW_IMAGE=${dockerCPImage} ./gw/.env || echo GW_IMAGE=${dockerCPImage} > ./gw/.env'
	@echo "Finished updating EC2 Docker Control Plane Image"

reset_docker_image_vars:
	@echo "Deleting EC2 GW_IMAGE variable from .env file"
	${sshLight} "echo 'Resetting EC2 environment variables' && : > ./gw/.env"
	@echo "Finished Deleting EC2 GW_IMAGE variable from .env file"

login_with_kongcloudpull:
	@echo "Logging in with kongcloud pull credentials"
	${ssh} 'echo "${kongCloudPullPassword}" | docker login -u "kongcloudpull" --password-stdin || true'

update_kong_container_env_var:
# usage: kongVars="-e KONG_PORTAL=on -e KONG_VITALS=on" make gwContainerName=kong-cp update_kong_container_env_var
	@echo "Updating Kong container environment variable"
	docker exec ${kongVars} $$(docker ps -aqf name=$(gwContainerName)) kong reload

get_kong_container_logs:
	@echo "Reading kong container logs"
	docker logs $$(docker ps -aqf name=$(gwContainerName)) --tail 4 &> logs.txt
