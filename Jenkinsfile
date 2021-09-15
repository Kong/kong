pipeline {
  agent {
    node {
      label 'hybrid'
    }
<<<<<<< HEAD
  }
  options {
      timeout(time: 45, unit: 'MINUTES')
  }
  environment {
    GITHUB_TOKEN = credentials('github_bot_access_token')
    REDHAT = credentials('redhat')
    PULP = credentials('PULP')
    DOCKERHUB_KONGCLOUD_PUSH = credentials('DOCKERHUB_KONGCLOUD_PUSH')
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
    KONG_VERSION = "2.5.1.0"
  }
  stages {
    // choice between internal, rc1, rc2, rc3, rc4 ....,  GA
    stage('Checkpoint') {
      steps {
        script {
          def input_params = input(
            message: "Kong Enteprise Edition",
            parameters: [
              // Add any needed input here (look for available parameters)
              // https://www.jenkins.io/doc/book/pipeline/syntax/
              choice(
                name: 'release_scope',
                description: 'What is the release scope?',
                choices: [
                  'internal-preview',
                  'beta1', 'beta2',
                  'rc1', 'rc2', 'rc3', 'rc4', 'rc5',
                  'ga'
                ]
              )
            ]
          )
          env.RELEASE_SCOPE = input_params
=======
    environment {
        UPDATE_CACHE = "true"
        DOCKER_CREDENTIALS = credentials('dockerhub')
        DOCKER_USERNAME = "${env.DOCKER_CREDENTIALS_USR}"
        DOCKER_PASSWORD = "${env.DOCKER_CREDENTIALS_PSW}"
        KONG_PACKAGE_NAME = "kong"
        DOCKER_CLI_EXPERIMENTAL = "enabled"
        PULP_HOST_PROD = "https://api.pulp.konnect-prod.konghq.com"
        PULP_PROD = credentials('PULP')
        PULP_HOST_STAGE = "https://api.pulp.konnect-stage.konghq.com"
        PULP_STAGE = credentials('PULP_STAGE')
        GITHUB_TOKEN = credentials('github_bot_access_token')
        DEBUG = 0
    }
    stages {
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
                KONG_PACKAGE_NAME = "kong"
                KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                AWS_ACCESS_KEY = credentials('AWS_ACCESS_KEY')
                AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
                CACHE = "false"
                UPDATE_CACHE = "true"
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
                stage('AmazonLinux') {
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
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=amazonlinux RESTY_IMAGE_TAG=1 make release'
                        sh 'PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=amazonlinux RESTY_IMAGE_TAG=2 make release'
                    }
                }
                stage('src & Alpine') {
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
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'PACKAGE_TYPE=src RESTY_IMAGE_BASE=src make release'
                        sh 'PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3.14 CACHE=false DOCKER_MACHINE_ARM64_NAME="kong-"`cat /proc/sys/kernel/random/uuid` make release'

                    }
                }
                stage('RedHat') {
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
                        PRIVATE_KEY_FILE = credentials('kong.private.gpg-key.asc')
                        PRIVATE_KEY_PASSPHRASE = credentials('kong.private.gpg-key.asc.password')
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'cp $PRIVATE_KEY_FILE ../kong-build-tools/kong.private.gpg-key.asc'
                        sh 'RESTY_IMAGE_TAG=7 make release'
                        sh 'RESTY_IMAGE_TAG=8 make release'
                    }
                }
                stage('CentOS') {
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
                        PRIVATE_KEY_FILE = credentials('kong.private.gpg-key.asc')
                        PRIVATE_KEY_PASSPHRASE = credentials('kong.private.gpg-key.asc.password')
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'cp $PRIVATE_KEY_FILE ../kong-build-tools/kong.private.gpg-key.asc'
                        sh 'RESTY_IMAGE_TAG=7 make release'
                        sh 'RESTY_IMAGE_TAG=8 make release'
                    }
                }
                stage('Debian OldStable') {
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
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'RESTY_IMAGE_TAG=jessie make release'
                        sh 'RESTY_IMAGE_TAG=stretch make release'
                    }
                }
                stage('Debian Stable & Testing') {
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
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'RESTY_IMAGE_TAG=buster make release'
                        sh 'RESTY_IMAGE_TAG=bullseye make release'
                    }
                }
                stage('Ubuntu') {
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
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'RESTY_IMAGE_TAG=bionic make release'
                        sh 'RESTY_IMAGE_TAG=focal make release'
                    }
                }
                stage('Ubuntu Xenial') {
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
                        AWS_ACCESS_KEY = credentials('AWS_ACCESS_KEY')
                        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'DOCKER_MACHINE_ARM64_NAME="jenkins-kong-"`cat /proc/sys/kernel/random/uuid` make release'
                    }
                    post {
                        cleanup {
                            dir('../kong-build-tools'){ sh 'make cleanup-build' }
                        }
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
>>>>>>> kong/master
        }
      }
    }
    // This can be run in different nodes in the future \0/
    stage('Build & Push Packages') {
      steps {
        parallel (
          centos7: {
            sh "./dist/dist.sh build centos:7 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh sign centos:7 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test centos:7 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p centos:7 -e -R ${env.RELEASE_SCOPE}"
          },
          centos8: {
            sh "./dist/dist.sh build centos:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh sign centos:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test centos:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p centos:8 -e -R ${env.RELEASE_SCOPE}"
          },
          debian8: {
            sh "./dist/dist.sh build debian:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test debian:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p debian:8 -e -R ${env.RELEASE_SCOPE}"
          },
          debian9: {
            sh "./dist/dist.sh build debian:9 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test debian:9 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p debian:9 -e -R ${env.RELEASE_SCOPE}"
          },
          ubuntu1604: {
            sh "./dist/dist.sh build ubuntu:16.04 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test ubuntu:16.04 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p ubuntu:16.04 -e -R ${env.RELEASE_SCOPE}"
          },
          ubuntu1804: {
            sh "./dist/dist.sh build ubuntu:18.04 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test ubuntu:18.04 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p ubuntu:18.04 -e -R ${env.RELEASE_SCOPE}"
          },
          ubuntu2004: {
            sh "./dist/dist.sh build ubuntu:20.04 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test ubuntu:20.04 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p ubuntu:20.04 -e -R ${env.RELEASE_SCOPE}"
          },
          amazonlinux1: {
            sh "./dist/dist.sh build amazonlinux:1 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh sign amazonlinux:1 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test amazonlinux:1 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p amazonlinux:1 -e -R ${env.RELEASE_SCOPE}"
          },
          amazonlinux2: {
            sh "./dist/dist.sh build amazonlinux:2 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh sign amazonlinux:2 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test amazonlinux:2 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p amazonlinux:2 -e -R ${env.RELEASE_SCOPE}"
          },
          alpine: {
            sh "./dist/dist.sh build alpine ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test alpine ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p alpine -e -R ${env.RELEASE_SCOPE}"
          },
          rhel7: {
            sh "./dist/dist.sh build rhel:7 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh sign rhel:7 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test rhel:7 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p rhel:7 -e -R ${env.RELEASE_SCOPE}"
          },
          rhel8: {
            sh "./dist/dist.sh build rhel:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh sign rhel:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh test rhel:8 ${env.RELEASE_SCOPE}"
            sh "./dist/dist.sh release -H prod -V -u $PULP_USR -k $PULP_PSW -p rhel:8 -e -R ${env.RELEASE_SCOPE}"
          },
        )
      }
    }
    stage("Build & Push Docker Images") {
      steps {
        parallel (
          // beware! $KONG_VERSION might have an ending \n that swallows everything after it
          alpine: {
            sh "./dist/dist.sh docker-hub-release -u $DOCKERHUB_KONGCLOUD_PUSH_USR \
                                                  -k $DOCKERHUB_KONGCLOUD_PUSH_PSW \
                                                  -pu $PULP_USR \
                                                  -pk $PULP_PSW \
                                                  -p alpine \
                                                  -R ${env.RELEASE_SCOPE} \
                                                  -v $KONG_VERSION"
          },
          centos7: {
            sh "./dist/dist.sh docker-hub-release -u $DOCKERHUB_KONGCLOUD_PUSH_USR \
                                                  -k $DOCKERHUB_KONGCLOUD_PUSH_PSW \
                                                  -pu $PULP_USR \
                                                  -pk $PULP_PSW \
                                                  -p centos \
                                                  -R ${env.RELEASE_SCOPE} \
                                                  -v $KONG_VERSION"
          },
          rhel: {
            sh "./dist/dist.sh docker-hub-release -u $DOCKERHUB_KONGCLOUD_PUSH_USR \
                                                  -k $DOCKERHUB_KONGCLOUD_PUSH_PSW \
                                                  -pu $PULP_USR \
                                                  -pk $PULP_PSW \
                                                  -p rhel \
                                                  -R ${env.RELEASE_SCOPE} \
                                                  -v $KONG_VERSION"
          },
        )
      }
    }
  }
}
