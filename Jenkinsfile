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
        KONG_PACKAGE_NAME = "kong"
        DOCKER_CLI_EXPERIMENTAL = "enabled"
    }
    stages {
        stage('Build Kong') {
            when {
                beforeAgent true
                anyOf {
                    allOf {
                        buildingTag()
                        not { triggeredBy 'TimerTrigger' }
                    }
                    allOf {
                        triggeredBy 'TimerTrigger'
                        anyOf { branch 'master'; branch 'next' }
                    }
                }
            }
            agent {
                node {
                    label 'bionic'
                }
            }
            environment {
                KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
            }
            steps {
                sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                sh 'make setup-kong-build-tools'
                dir('../kong-build-tools') { sh 'make kong-test-container' }
            }
        }
        stage('Integration Tests') {
            when {
                beforeAgent true
                allOf {
                    buildingTag()
                    not { triggeredBy 'TimerTrigger' }
                }
            }
            parallel {
                stage('dbless') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        TEST_DATABASE = "off"
                        TEST_SUITE = "dbless"
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        dir('../kong-build-tools') {
                            sh 'make test-kong'
                        }
                    }
                }
                stage('postgres') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        TEST_DATABASE = 'postgres'
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        dir('../kong-build-tools') {
                            sh 'make test-kong'
                        }
                    }
                }
                stage('postgres plugins') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        TEST_DATABASE = 'postgres'
                        TEST_SUITE = 'plugins'
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        dir('../kong-build-tools'){
                            sh 'make test-kong'
                        }
                    }
                }
                stage('cassandra') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        TEST_DATABASE = 'cassandra'
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        dir('../kong-build-tools'){
                            sh 'make test-kong'
                        }
                    }
                }
            }
        }
        stage('Release Per Commit') {
            when {
                beforeAgent true
                anyOf { branch 'master'; branch 'next' }
            }
            agent {
                node {
                    label 'bionic'
                }
            }
            environment {
                KONG_PACKAGE_NAME = "kong"
                KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                BINTRAY_USR = 'kong-inc_travis-ci@kong'
                BINTRAY_KEY = credentials('bintray_travis_key')
                AWS_ACCESS_KEY = credentials('AWS_ACCESS_KEY')
                AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
                CACHE = "false"
                UPDATE_CACHE = "true"
                DEBUG = "0"
                RELEASE_DOCKER_ONLY="true"
                PACKAGE_TYPE="apk"
                RESTY_IMAGE_BASE="alpine"
                RESTY_IMAGE_TAG="latest"
            }
            steps {
                sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                sh 'make setup-kong-build-tools'
                sh 'KONG_VERSION=`git rev-parse --short HEAD` DOCKER_MACHINE_ARM64_NAME="jenkins-kong-"`cat /proc/sys/kernel/random/uuid` make release'
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
                stage('Ubuntu Xenial Release') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        PACKAGE_TYPE = 'deb'
                        RESTY_IMAGE_BASE = 'ubuntu'
                        RESTY_IMAGE_TAG = 'xenial'
                        CACHE = 'false'
                        UPDATE_CACHE = 'true'
                        USER = 'travis'
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        BINTRAY_USR = 'kong-inc_travis-ci@kong'
                        BINTRAY_KEY = credentials('bintray_travis_key')
                        AWS_ACCESS_KEY = credentials('AWS_ACCESS_KEY')
                        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'make release'
                    }
                    post {
                        cleanup {
                            dir('../kong-build-tools'){ sh 'make cleanup-build' }
                        }
                    }
                }
                stage('Ubuntu Releases') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        PACKAGE_TYPE = 'deb'
                        RESTY_IMAGE_BASE = 'ubuntu'
                        RESTY_IMAGE_TAG = 'bionic'
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        BINTRAY_USR = 'kong-inc_travis-ci@kong'
                        BINTRAY_KEY = credentials('bintray_travis_key')
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'RESTY_IMAGE_TAG=bionic make release'
                        sh 'RESTY_IMAGE_TAG=focal make release'
                    }
                }
                stage('Centos Releases') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        PACKAGE_TYPE = 'rpm'
                        RESTY_IMAGE_BASE = 'centos'
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        BINTRAY_USR = 'kong-inc_travis-ci@kong'
                        BINTRAY_KEY = credentials('bintray_travis_key')
                        PRIVATE_KEY_FILE = credentials('kong.private.gpg-key.asc')
                        PRIVATE_KEY_PASSPHRASE = credentials('kong.private.gpg-key.asc.password')
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'cp $PRIVATE_KEY_FILE ../kong-build-tools/kong.private.gpg-key.asc'
                        sh 'RESTY_IMAGE_TAG=6 make release'
                        sh 'RESTY_IMAGE_TAG=7 make release'
                        sh 'RESTY_IMAGE_TAG=8 make release'
                    }
                }
                stage('RedHat Releases') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        PACKAGE_TYPE = 'rpm'
                        RESTY_IMAGE_BASE = 'rhel'
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        BINTRAY_USR = 'kong-inc_travis-ci@kong'
                        BINTRAY_KEY = credentials('bintray_travis_key')
                        PRIVATE_KEY_FILE = credentials('kong.private.gpg-key.asc')
                        PRIVATE_KEY_PASSPHRASE = credentials('kong.private.gpg-key.asc.password')
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'cp $PRIVATE_KEY_FILE ../kong-build-tools/kong.private.gpg-key.asc'
                        sh 'RESTY_IMAGE_TAG=7 make release'
                        sh 'RESTY_IMAGE_TAG=8 make release'
                    }
                }
                stage('Debian Releases') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        PACKAGE_TYPE = 'deb'
                        RESTY_IMAGE_BASE = 'debian'
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        BINTRAY_USR = 'kong-inc_travis-ci@kong'
                        BINTRAY_KEY = credentials('bintray_travis_key')
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'RESTY_IMAGE_TAG=jessie make release'
                        sh 'RESTY_IMAGE_TAG=stretch make release'
                        sh 'RESTY_IMAGE_TAG=buster make release'
                        sh 'RESTY_IMAGE_TAG=bullseye make release'
                    }
                }
                stage('Other Releases'){
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        PACKAGE_TYPE = 'deb'
                        RESTY_IMAGE_BASE = 'debian'
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        BINTRAY_USR = 'kong-inc_travis-ci@kong'
                        BINTRAY_KEY = credentials('bintray_travis_key')
                        AWS_ACCESS_KEY = credentials('AWS_ACCESS_KEY')
                        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'PACKAGE_TYPE=src RESTY_IMAGE_BASE=src make release'
                        sh 'PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=amazonlinux RESTY_IMAGE_TAG=1 make release'
                        sh 'PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=amazonlinux RESTY_IMAGE_TAG=2 make release'
                        sh 'CACHE=false DOCKER_MACHINE_ARM64_NAME="kong-"`cat /proc/sys/kernel/random/uuid` PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3 make release'
                    }
                }
            }
        }
        stage('Post Packaging Steps') {
            when {
                beforeAgent true
                allOf {
                    buildingTag()
                    not { triggeredBy 'TimerTrigger' }
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
                        GITHUB_TOKEN = credentials('github_bot_access_token')
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
                        GITHUB_TOKEN = credentials('github_bot_access_token')
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
                        GITHUB_TOKEN = credentials('github_bot_access_token')
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
