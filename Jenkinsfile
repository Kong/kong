pipeline {
    agent none
    triggers {
        cron(env.BRANCH_NAME == 'master' | env.BRANCH_NAME == 'next' ? '@daily' : '')
    }
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
        DOCKER_KONG_VERSION = "fix/various_fixes"
    }
    stages {
        stage('Release Per Commit') {
            when {
                beforeAgent true
                allOf {
                    anyOf { branch 'feat/docker-releases'; branch 'next' }
                }
            }
            agent {
                node {
                    label 'docker-compose'
                }
            }
            environment {
                KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                BINTRAY_USR = 'kong-inc_travis-ci@kong'
                BINTRAY_KEY = credentials('bintray_travis_key')
                DEBUG = 0
            }
            steps {
                sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                sh 'make setup-kong-build-tools'
                sh 'KONG_VERSION=`git rev-parse --short HEAD` RELEASE_DOCKER_ONLY=true PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=latest make debug'
            }
            post {
                always {
                    sh 'docker images'
                    sh 'docker push mashape/kong-build-tools:kong-packaged-alpine-latest-e1fe0b710-`git rev-parse --short HEAD`-`git rev-parse --short HEAD`-21'
                    sh 'docker push mashape/kong-build-tools:kong-alpine-latest-e1fe0b710-`git rev-parse --short HEAD`-`git rev-parse --short HEAD`-21'
                }
            }
        }
    }
}
