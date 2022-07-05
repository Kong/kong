pipeline {
    agent none
    options {
        retry(1)
        timeout(time: 2, unit: 'HOURS')
    }
    environment {
        UPDATE_CACHE = "true"
        DOCKER_CREDENTIALS = credentials('dockerhub')
        DOCKER_USERNAME = "${env.DOCKER_CREDENTIALS_USR}"
        DOCKER_PASSWORD = "${env.DOCKER_CREDENTIALS_PSW}"
        DOCKER_CLI_EXPERIMENTAL = "enabled"
        // PULP_PROD and PULP_STAGE are used to do releases
        PULP_HOST_PROD = "https://api.pulp.konnect-prod.konghq.com"
        PULP_PROD = credentials('PULP')
        PULP_HOST_STAGE = "https://api.pulp.konnect-stage.konghq.com"
        PULP_STAGE = credentials('PULP_STAGE')
        GITHUB_TOKEN = credentials('github_bot_access_token')
        DEBUG = 0
    }
    stages {
        stage('Test The Package') {
            agent {
                node {
                    label 'bionic'
                }
            }
            when { changeRequest target: 'master' }
            environment {
                KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
            }
            steps {
                sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                sh 'make setup-kong-build-tools'
                sh 'cd ../kong-build-tools && make package-kong test'
            }
            
        }
        stage('Release Per Commit') {
            when {
                beforeAgent true
                anyOf { branch 'master'; }
            }
            agent {
                node {
                    label 'bionic'
                }
            }
            environment {
                KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                AWS_ACCESS_KEY = credentials('AWS_ACCESS_KEY')
                AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
                CACHE = "false"
                UPDATE_CACHE = "true"
                RELEASE_DOCKER_ONLY="true"
            }
            steps {
                sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                sh 'make setup-kong-build-tools'

                sh 'KONG_VERSION=`echo kong-*.rockspec | sed \'s,.*/,,\' | cut -d- -f2`-`git rev-parse --short HEAD` DOCKER_MACHINE_ARM64_NAME="jenkins-kong-"`cat /proc/sys/kernel/random/uuid` RELEASE_DOCKER=true make RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3.10 PACKAGE_TYPE=apk release'
                sh 'export KONG_VERSION=`echo kong-*.rockspec | sed \'s,.*/,,\' | cut -d- -f2`-`git rev-parse --short HEAD` && docker tag kong/kong:${KONG_VERSION}-alpine kong/kong:master-nightly-alpine'
                sh 'docker push kong/kong:master-nightly-alpine'

                sh 'KONG_VERSION=`echo kong-*.rockspec | sed \'s,.*/,,\' | cut -d- -f2`-`git rev-parse --short HEAD`-ubuntu20.04 DOCKER_MACHINE_ARM64_NAME="jenkins-kong-"`cat /proc/sys/kernel/random/uuid` RELEASE_DOCKER=true make RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=20.04 PACKAGE_TYPE=deb release'
                sh 'export KONG_VERSION=`echo kong-*.rockspec | sed \'s,.*/,,\' | cut -d- -f2`-`git rev-parse --short HEAD` && docker tag kong/kong:amd64-${KONG_VERSION}-ubuntu20.04 kong/kong:master-nightly-ubuntu20.04'
                sh 'docker push kong/kong:master-nightly-ubuntu20.04'
            }
        }
        stage('Release') {
            when {
                beforeAgent true
                allOf {
                    buildingTag()
                    not { triggeredBy 'TimerTrigger' }
                }
            }
            parallel {
                stage('RPM') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        PACKAGE_TYPE = "rpm"
                        PRIVATE_KEY_FILE = credentials('kong.private.gpg-key.asc')
                        PRIVATE_KEY_PASSPHRASE = credentials('kong.private.gpg-key.asc.password')
                        GITHUB_SSH_KEY = credentials('github_bot_ssh_key')
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'cp $PRIVATE_KEY_FILE ../kong-build-tools/kong.private.gpg-key.asc'
                        sh 'make RESTY_IMAGE_BASE=amazonlinux RESTY_IMAGE_TAG=2 release'
                        sh 'make RESTY_IMAGE_BASE=centos      RESTY_IMAGE_TAG=7 release'
                        sh 'make RESTY_IMAGE_BASE=rhel        RESTY_IMAGE_TAG=7 release'
                        sh 'make RESTY_IMAGE_BASE=rhel        RESTY_IMAGE_TAG=8 RELEASE_DOCKER=true release'
                    }
                }
                stage('DEB') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        PACKAGE_TYPE = "deb"
                        GITHUB_SSH_KEY = credentials('github_bot_ssh_key')
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'make RESTY_IMAGE_BASE=debian RESTY_IMAGE_TAG=9     release'
                        sh 'make RESTY_IMAGE_BASE=debian RESTY_IMAGE_TAG=10    release'
                        sh 'make RESTY_IMAGE_BASE=debian RESTY_IMAGE_TAG=11 RELEASE_DOCKER=true release'
                        sh 'make RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=18.04 release'
                        sh 'make RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=20.04 RELEASE_DOCKER=true release'
                    }
                }
                stage('SRC & Alpine') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        PACKAGE_TYPE = "rpm"
                        AWS_ACCESS_KEY = credentials('AWS_ACCESS_KEY')
                        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
                        GITHUB_SSH_KEY = credentials('github_bot_ssh_key')
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'make RESTY_IMAGE_BASE=src    RESTY_IMAGE_TAG=src  PACKAGE_TYPE=src release'
                        sh 'make RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3.10 PACKAGE_TYPE=apk DOCKER_MACHINE_ARM64_NAME="kong-"`cat /proc/sys/kernel/random/uuid` RELEASE_DOCKER=true release'
                    }
                }
            }
        }
        stage('Post Release Steps') {
            when {
                beforeAgent true
                allOf {
                    buildingTag()
                    not { triggeredBy 'TimerTrigger' }
                    expression { env.TAG_NAME ==~ /^\d+\.\d+\.\d+$/ }
                }
            }
            parallel {
                stage('PR Docker') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        GITHUB_SSH_KEY = credentials('github_bot_ssh_key')
                        SLACK_WEBHOOK = credentials('core_team_slack_webhook')
                        GITHUB_USER = "mashapedeployment"
                    }
                    steps {
                        sh './scripts/setup-ci.sh'
                        sh 'echo "y" | ./scripts/make-patch-release $TAG_NAME update_docker'
                    }
                    post {
                        failure {
                            script {
                                sh 'SLACK_MESSAGE="updating docker-kong failed" ./scripts/send-slack-message.sh'
                            }
                        }
                        success {
                            script {
                                sh 'SLACK_MESSAGE="updating docker-kong succeeded. Please review, approve and continue with the kong release script" ./scripts/send-slack-message.sh'
                            }
                        }
                    }
                }
                stage('PR Homebrew') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        GITHUB_SSH_KEY = credentials('github_bot_ssh_key')
                        SLACK_WEBHOOK = credentials('core_team_slack_webhook')
                        GITHUB_USER = "mashapedeployment"
                    }
                    steps {
                        sh './scripts/setup-ci.sh'
                        sh 'echo "y" | ./scripts/make-patch-release $TAG_NAME homebrew'
                    }
                    post {
                        failure {
                            script {
                                sh 'SLACK_MESSAGE="updating homebrew-kong failed" ./scripts/send-slack-message.sh'
                            }
                        }
                        success {
                            script {
                                sh 'SLACK_MESSAGE="updating homebrew-kong succeeded. Please review, approve and merge the PR" ./scripts/send-slack-message.sh'
                            }
                        }
                    }
                }
                stage('PR Vagrant') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        GITHUB_SSH_KEY = credentials('github_bot_ssh_key')
                        SLACK_WEBHOOK = credentials('core_team_slack_webhook')
                        GITHUB_USER = "mashapedeployment"
                    }
                    steps {
                        sh './scripts/setup-ci.sh'
                        sh 'echo "y" | ./scripts/make-patch-release $TAG_NAME vagrant'
                    }
                    post {
                        failure {
                            script {
                                sh 'SLACK_MESSAGE="updating kong-vagrant failed" ./scripts/send-slack-message.sh'
                            }
                        }
                        success {
                            script {
                                sh 'SLACK_MESSAGE="updating kong-vagrant succeeded. Please review, approve and merge the PR" ./scripts/send-slack-message.sh'
                            }
                        }
                    }
                }
                stage('PR Pongo') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        GITHUB_SSH_KEY = credentials('github_bot_ssh_key')
                        SLACK_WEBHOOK = credentials('core_team_slack_webhook')
                        GITHUB_USER = "mashapedeployment"
                    }
                    steps {
                        sh './scripts/setup-ci.sh'
                        sh 'echo "y" | ./scripts/make-patch-release $TAG_NAME pongo'
                    }
                    post {
                        always {
                            script {
                                sh 'SLACK_MESSAGE="pongo branch is pushed go open the PR at https://github.com/Kong/kong-pongo/branches" ./scripts/send-slack-message.sh'
                            }
                        }
                    }
                }
            }
        }
    }
}
