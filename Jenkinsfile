pipeline {
  agent {
    node {
      label 'hybrid'
    }
  }
  options {
      timeout(time: 30, unit: 'MINUTES')
  }
  environment {
    GITHUB_TOKEN = credentials('GITHUB_TOKEN')
    BINTRAY = credentials('bintray')
    REDHAT = credentials('redhat')
    PRIVATE_KEY_FILE = credentials('kong.private.gpg-key.asc')
    PRIVATE_KEY_PASSWORD = credentials('kong.private.gpg-key.asc.password')
    KONG_VERSION = """${sh(
      returnStdout: true,
      script: '[ -n $TAG_NAME ] && echo $TAG_NAME | grep -o -P "\\d+\\.\\d+([.-]\\d+)?" || echo -n $BRANCH_NAME | grep -o -P "\\d+\\.\\d+([.-]\\d+)?"'
    )}"""
  }
  stages {
    // choice between internal, rc1, rc2, rc3, rc4 ....,  GA
    stage('Checkpoint') {
      steps {
        script {
          def input_params = input(message: "Kong version: $KONG_VERSION\nShould I continue this build?",
          parameters: [
            // [$class: 'TextParameterDefinition', defaultValue: '', description: 'custom build', name: 'customername'],
            choice(name: 'RELEASE_SCOPE',
            choices: 'internal-preview\nrc1\nrc2\nrc3\nrc4\nrc5\nGA',
            description: 'What is the release scope?'),
          ])
          env.RELEASE_SCOPE = input_params
        }
      }
    }
    stage('Prepare Kong Distributions') {
      when {
        expression { BRANCH_NAME ==~ /^(release\/).*/}
      }
      steps {
        echo "Kong version: $KONG_VERSION"
        echo "Release scope ${env.RELEASE_SCOPE}"
        checkout([$class: 'GitSCM',
          branches: [[name: env.BRANCH_NAME]],
          extensions: [[$class: 'WipeWorkspace']],
          userRemoteConfigs: [[url: 'git@github.com:Kong/kong-distributions.git',
            credentialsId: 'kong-distributions-deploy-key']]
        ])
        sh 'utilities/install_deps.sh'
      }
    }
    stage('Build & Push Packages') {
      when {
        expression { BRANCH_NAME ==~ /^release\/.*/ }
      }
      steps {
        parallel (
          centos6: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:6 --ee --custom ${env.RELEASE_SCOPE} --key-file $PRIVATE_KEY_FILE --key-password $PRIVATE_KEY_PASSWORD -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:6 -e -R ${env.RELEASE_SCOPE}"
          },
          centos7: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:7 --ee --custom ${env.RELEASE_SCOPE} --key-file $PRIVATE_KEY_FILE --key-password $PRIVATE_KEY_PASSWORD -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:7 -e -R ${env.RELEASE_SCOPE}"
          },
          debian8: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:8 --ee --custom ${env.RELEASE_SCOPE} -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:8 -e -R ${env.RELEASE_SCOPE}"
          },
          debian9: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:9 --ee --custom ${env.RELEASE_SCOPE} -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:9 -e -R ${env.RELEASE_SCOPE}"
          },
          ubuntu1404: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:14.04.2 --ee --custom ${env.RELEASE_SCOPE} -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:14.04.2 -e -R ${env.RELEASE_SCOPE}"
          },
          ubuntu1604: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:16.04 --ee --custom ${env.RELEASE_SCOPE} -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:16.04 -e -R ${env.RELEASE_SCOPE}"
          },
          ubuntu1704: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:17.04 --ee --custom ${env.RELEASE_SCOPE} -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:17.04 -e -R ${env.RELEASE_SCOPE}"
          },
          ubuntu1804: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:18.04 --ee --custom ${env.RELEASE_SCOPE} -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:18.04 -e -R ${env.RELEASE_SCOPE}"
          },
          amazonlinux: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p amazonlinux --ee --custom ${env.RELEASE_SCOPE} -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p amazonlinux -e -R ${env.RELEASE_SCOPE}"
          },
          alpine: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p alpine --ee --custom ${env.RELEASE_SCOPE} -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p alpine -e -R ${env.RELEASE_SCOPE}"
          },
          rhel6: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW --redhat-username $REDHAT_USR --redhat-password $REDHAT_PSW -p rhel:6 --ee --custom ${env.RELEASE_SCOPE} --key-file $PRIVATE_KEY_FILE --key-password $PRIVATE_KEY_PASSWORD -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel:6 -e -R ${env.RELEASE_SCOPE}"
          },
          rhel7: {
            sh "./package.sh -u $BINTRAY_USR -k $BINTRAY_PSW --redhat-username $REDHAT_USR --redhat-password $REDHAT_PSW -p rhel:7 --ee --custom ${env.RELEASE_SCOPE} --key-file $PRIVATE_KEY_FILE --key-password $PRIVATE_KEY_PASSWORD -V"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel:7 -e -R ${env.RELEASE_SCOPE}"
          },
        )
      }
    }
    stage("Prepare Docker Kong EE") {
      when {
        expression { BRANCH_NAME ==~ /^release\/.*/ }
      }
      steps {
        checkout([$class: 'GitSCM',
            extensions: [[$class: 'WipeWorkspace']],
            userRemoteConfigs: [[url: 'git@github.com:Kong/docker-kong-ee.git',
            credentialsId: 'docker-kong-ee-deploy-key']]
        ])
      }
    }
    stage("Build & Push Docker Images") {
      when {
        expression {
          expression { BRANCH_NAME ==~ /^release\/.*/ }
        }
      }
      steps {
        parallel (
          // beware! $KONG_VERSION might have an ending \n that swallows everything after it
          alpine: {
            sh "./bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -l -p alpine -e -R ${env.RELEASE_SCOPE} -v $KONG_VERSION"
          },
          centos7: {
            sh "./bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos -e -R ${env.RELEASE_SCOPE} -v $KONG_VERSION"
          },
          rhel: {
            sh "./bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel -e -R ${env.RELEASE_SCOPE} -v $KONG_VERSION"
          },
        )
      }
    }
  }
}
