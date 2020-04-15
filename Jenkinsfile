pipeline {
    agent none
    triggers {
        cron(env.BRANCH_NAME == 'master' | env.BRANCH_NAME == 'next' ? '@daily' : '')
    }
    options {
        retry(1)
        parallelsAlwaysFailFast()
        timeout(time: 2, unit: 'HOURS')
    }
    environment {
        UPDATE_CACHE = "true"
        DOCKER_CREDENTIALS = credentials('dockerhub')
        DOCKER_USERNAME = "${env.DOCKER_CREDENTIALS_USR}"
        DOCKER_PASSWORD = "${env.DOCKER_CREDENTIALS_PSW}"
        KONG_PACKAGE_NAME = "kong"
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
                    label 'docker-compose'
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
            /* the above when statement evaluates to:
                if (
                  ( buildingtag && not cron ) ||
                  ( ( branch = master || branch = next) && cron )
                )
            */
            parallel {
                stage('dbless') {
                    agent {
                        node {
                            label 'docker-compose'
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
                            label 'docker-compose'
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
                            label 'docker-compose'
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
                            label 'docker-compose'
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
        stage('Nightly Releases') {
            when {
                beforeAgent true
                allOf {
                    triggeredBy 'TimerTrigger'
                    anyOf { branch 'master'; branch 'next' }
                }
            }
            parallel {
                stage('Ubuntu Xenial Release') {
                    agent {
                        node {
                            label 'docker-compose'
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
                        DOCKER_MACHINE_ARM64_NAME = "jenkins-kong-${env.BUILD_NUMBER}"
                        REPOSITORY_OS_NAME = "${env.BRANCH_NAME}"
                        KONG_PACKAGE_NAME = "kong-${env.BRANCH_NAME}"
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` make nightly-release'
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
                            label 'docker-compose'
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
                        REPOSITORY_OS_NAME = "${env.BRANCH_NAME}"
                        KONG_PACKAGE_NAME = "kong-${env.BRANCH_NAME}"
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` RESTY_IMAGE_TAG=bionic BUILDX=false make nightly-release'
                    }
                }
                stage('Centos Releases') {
                    agent {
                        node {
                            label 'docker-compose'
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
                        REPOSITORY_OS_NAME = "${env.BRANCH_NAME}"
                        KONG_PACKAGE_NAME = "kong-${env.BRANCH_NAME}"
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'cp $PRIVATE_KEY_FILE ../kong-build-tools/kong.private.gpg-key.asc'
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` RESTY_IMAGE_TAG=6 make nightly-release'
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` RESTY_IMAGE_TAG=7 make nightly-release'
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` RESTY_IMAGE_TAG=8 make nightly-release'
                    }
                }
                stage('RedHat Releases') {
                    agent {
                        node {
                            label 'docker-compose'
                        }
                    }
                    environment {
                        PACKAGE_TYPE = 'rpm'
                        RESTY_IMAGE_BASE = 'rhel'
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        REDHAT_CREDENTIALS = credentials('redhat')
                        REDHAT_USERNAME = "${env.REDHAT_USR}"
                        REDHAT_PASSWORD = "${env.REDHAT_PSW}"
                        BINTRAY_USR = 'kong-inc_travis-ci@kong'
                        BINTRAY_KEY = credentials('bintray_travis_key')
                        PRIVATE_KEY_FILE = credentials('kong.private.gpg-key.asc')
                        PRIVATE_KEY_PASSPHRASE = credentials('kong.private.gpg-key.asc.password')
                        REPOSITORY_OS_NAME = "${env.BRANCH_NAME}"
                        KONG_PACKAGE_NAME = "kong-${env.BRANCH_NAME}"
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'cp $PRIVATE_KEY_FILE ../kong-build-tools/kong.private.gpg-key.asc'
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` RESTY_IMAGE_TAG=7 make nightly-release'
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` RESTY_IMAGE_TAG=8 make nightly-release'
                    }
                }
                stage('Debian Releases') {
                    agent {
                        node {
                            label 'docker-compose'
                        }
                    }
                    environment {
                        PACKAGE_TYPE = 'deb'
                        RESTY_IMAGE_BASE = 'debian'
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        BINTRAY_USR = 'kong-inc_travis-ci@kong'
                        BINTRAY_KEY = credentials('bintray_travis_key')
                        REPOSITORY_OS_NAME = "${env.BRANCH_NAME}"
                        KONG_PACKAGE_NAME = "kong-${env.BRANCH_NAME}"
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` RESTY_IMAGE_TAG=jessie make nightly-release'
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` RESTY_IMAGE_TAG=stretch make nightly-release'
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` RESTY_IMAGE_TAG=buster make nightly-release'
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly KONG_VERSION=`date +%Y-%m-%d` RESTY_IMAGE_TAG=bullseye make nightly-release'
                    }
                }
                stage('Other Releases'){
                    agent {
                        node {
                            label 'docker-compose'
                        }
                    }
                    environment {
                        PACKAGE_TYPE = 'deb'
                        RESTY_IMAGE_BASE = 'debian'
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        BINTRAY_USR = 'kong-inc_travis-ci@kong'
                        BINTRAY_KEY = credentials('bintray_travis_key')
                        KONG_PACKAGE_NAME = "kong-${env.BRANCH_NAME}"
                        REPOSITORY_OS_NAME = "${env.BRANCH_NAME}"
                        DEBUG = 0
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly PACKAGE_TYPE=src RESTY_IMAGE_BASE=src KONG_VERSION=`date +%Y-%m-%d` make nightly-release'
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=1 KONG_VERSION=`date +%Y-%m-%d` make nightly-release'
                        sh 'REPOSITORY_NAME=`basename ${GIT_URL%.*}`-nightly PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=amazonlinux RESTY_IMAGE_TAG=1 KONG_VERSION=`date +%Y-%m-%d` make nightly-release'
                    }
                }
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
                            label 'docker-compose'
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
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
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
                            label 'docker-compose'
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
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'RESTY_IMAGE_TAG=bionic make release'
                    }
                }
                stage('Centos Releases') {
                    agent {
                        node {
                            label 'docker-compose'
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
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'cp $PRIVATE_KEY_FILE ../kong-build-tools/kong.private.gpg-key.asc'
                        sh 'RESTY_IMAGE_TAG=6 make release'
                        sh 'RESTY_IMAGE_TAG=7 make release'
                        sh 'RESTY_IMAGE_TAG=8 make release'
                    }
                }
                stage('RedHat Releases') {
                    agent {
                        node {
                            label 'docker-compose'
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
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'cp $PRIVATE_KEY_FILE ../kong-build-tools/kong.private.gpg-key.asc'
                        sh 'RESTY_IMAGE_TAG=7 make release'
                        sh 'RESTY_IMAGE_TAG=8 make release'
                    }
                }
                stage('Debian Releases') {
                    agent {
                        node {
                            label 'docker-compose'
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
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'RESTY_IMAGE_TAG=jessie make release'
                        sh 'RESTY_IMAGE_TAG=stretch make release'
                        sh 'RESTY_IMAGE_TAG=buster make release'
                        sh 'RESTY_IMAGE_TAG=bullseye make release'
                    }
                }
                stage('Other Releases'){
                    agent {
                        node {
                            label 'docker-compose'
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
                        dir('../kong-build-tools'){ sh 'make setup-ci' }
                        sh 'PACKAGE_TYPE=src RESTY_IMAGE_BASE=src make release'
                        sh 'PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=1 make release'
                        sh 'PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=amazonlinux RESTY_IMAGE_TAG=1 make release'
                    }
                }
            }
        }
    }
}
