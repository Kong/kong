pipeline {
  agent {
    node {
      label 'hybrid'
    }
  }
  options {
      timeout(time: 45, unit: 'MINUTES')
  }
  environment {
    GITHUB_TOKEN = credentials('GITHUB_TOKEN')
    BINTRAY = credentials('bintray')
    REDHAT = credentials('redhat')
    PRIVATE_KEY_FILE = credentials('kong.private.gpg-key.asc')
    PRIVATE_KEY_PASSWORD = credentials('kong.private.gpg-key.asc.password')
    // This cache dir will contain files owned by root, and user ubuntu will
    // not have permission over it. We still need for it to survive between
    // builds, so /tmp is also not an option. Try $HOME for now, iterate
    // on that
    CACHE_DIR = "$HOME/kong-distributions-cache"
    //KONG_VERSION = """${sh(
    //  returnStdout: true,
    //  script: '[ -n $TAG_NAME ] && echo $TAG_NAME | grep -o -P "\\d+\\.\\d+\\.\\d+\\.\\d+" || echo -n $BRANCH_NAME | grep -o -P "\\d+\\.\\d+\\.\\d+\\.\\d+"'
    //)}"""
    // XXX: Can't bother to fix this now. This works, right? :)
    KONG_VERSION = "2.1.0.0"
  }
  stages {
    // choice between internal, rc1, rc2, rc3, rc4 ....,  GA
    stage('Checkpoint') {
      steps {
        script {
          def input_params = input(message: "Should I continue this build?",
          parameters: [
            // [$class: 'TextParameterDefinition', defaultValue: '', description: 'custom build', name: 'customername'],
            choice(name: 'RELEASE_SCOPE',
            choices: 'internal-preview\nrc1\nrc2\nrc3\nrc4\nrc5\nGA',
            description: 'What is the release scope?'),
          ])
          env.RELEASE_SCOPE = input_params
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
                allOf {
                    buildingTag()
                    not { triggeredBy 'TimerTrigger' }
                }
            }
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
        stage('Release Per Commit') {
            when {
                beforeAgent true
                anyOf { branch 'master'; branch 'next' }
            }
            agent {
                node {
                    label 'docker-compose'
                }
            }
            environment {
                KONG_PACKAGE_NAME = "kong"
                KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                BINTRAY_USR = 'kong-inc_travis-ci@kong'
                BINTRAY_KEY = credentials('bintray_travis_key')
                DEBUG = 0
            }
            steps {
                sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                sh 'make setup-kong-build-tools'
                sh 'KONG_VERSION=`git rev-parse --short HEAD` RELEASE_DOCKER_ONLY=true PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=latest make release'
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
                        sh 'RESTY_IMAGE_TAG=bionic make release'
                        sh 'RESTY_IMAGE_TAG=focal make release'
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
                        sh 'PACKAGE_TYPE=src RESTY_IMAGE_BASE=src make release'
                        sh 'PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=1 make release'
                        sh 'PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=amazonlinux RESTY_IMAGE_TAG=1 make release'
                    }
                }
            }
        }
      }
    }
    // This can be run in different nodes in the future \0/
    stage('Build & Push Packages') {
      steps {
        parallel (
          centos7: {
            sh "./dist/dist.sh build centos:7 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:7 -e -R ${env.RELEASE_SCOPE}"
          },
          centos8: {
            sh "./dist/dist.sh build centos:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:8 -e -R ${env.RELEASE_SCOPE}"
          },
          debian8: {
            sh "./dist/dist.sh build debian:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:8 -e -R ${env.RELEASE_SCOPE}"
          },
          debian9: {
            sh "./dist/dist.sh build debian:9 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:9 -e -R ${env.RELEASE_SCOPE}"
          },
          ubuntu1604: {
            sh "./dist/dist.sh build ubuntu:16.04 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:16.04 -e -R ${env.RELEASE_SCOPE}"
          },
          ubuntu1804: {
            sh "./dist/dist.sh build ubuntu:18.04 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:18.04 -e -R ${env.RELEASE_SCOPE}"
          },
          ubuntu2004: {
            sh "./dist/dist.sh build ubuntu:20.04 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:20.04 -e -R ${env.RELEASE_SCOPE}"
          },
          amazonlinux1: {
            sh "./dist/dist.sh build amazonlinux:1 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p amazonlinux:1 -e -R ${env.RELEASE_SCOPE}"
          },
          amazonlinux2: {
            sh "./dist/dist.sh build amazonlinux:2 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p amazonlinux:2 -e -R ${env.RELEASE_SCOPE}"
          },
          alpine: {
            sh "./dist/dist.sh build alpine ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p alpine -e -R ${env.RELEASE_SCOPE}"
          },
          rhel7: {
            sh "./dist/dist.sh build rhel:7 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel:7 -e -R ${env.RELEASE_SCOPE}"
          },
          rhel8: {
            sh "./dist/dist.sh build rhel:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -V -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel:8 -e -R ${env.RELEASE_SCOPE}"
          },
        )
      }
    }
    stage("Build & Push Docker Images") {
      steps {
        parallel (
          // beware! $KONG_VERSION might have an ending \n that swallows everything after it
          alpine: {
            sh "./dist/dist.sh bintray-release -u $BINTRAY_USR -k $BINTRAY_PSW -l -p alpine -e -R ${env.RELEASE_SCOPE} -v $KONG_VERSION"
            // Docker with anonymous reports off. jenkins has no permission + is old method
            sh "./dist/dist.sh bintray-release -u $BINTRAY_USR -k $BINTRAY_PSW -l -p alpine -e -R ${env.RELEASE_SCOPE} -a -v $KONG_VERSION"
          },
          centos7: {
            sh "./dist/dist.sh bintray-release -u $BINTRAY_USR -k $BINTRAY_PSW -p centos -e -R ${env.RELEASE_SCOPE} -v $KONG_VERSION"
            // Docker with anonymous reports off. jenkins has no permission + is old method
            sh "./dist/dist.sh bintray-release -u $BINTRAY_USR -k $BINTRAY_PSW -p centos -e -R ${env.RELEASE_SCOPE} -a -v $KONG_VERSION"
          },
          rhel: {
            sh "./dist/dist.sh bintray-release -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel -e -R ${env.RELEASE_SCOPE} -v $KONG_VERSION"
            // Docker with anonymous reports off. jenkins has no permission + is old method
            sh "./dist/dist.sh bintray-release -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel -e -R ${env.RELEASE_SCOPE} -a -v $KONG_VERSION"
          },
        )
      }
    }
  }
}
