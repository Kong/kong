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
    # This cache dir will contain files owned by root, and user ubuntu will
    # not have permission over it. We still need for it to survive between
    # builds, so /tmp is also not an option. Try $HOME for now, iterate
    # on that
    CACHE_DIR = "$HOME/kong-distributions-cache"
    //KONG_VERSION = """${sh(
    //  returnStdout: true,
    //  script: '[ -n $TAG_NAME ] && echo $TAG_NAME | grep -o -P "\\d+\\.\\d+\\.\\d+\\.\\d+" || echo -n $BRANCH_NAME | grep -o -P "\\d+\\.\\d+\\.\\d+\\.\\d+"'
    //)}"""
    // Can't bother to fix this now. This works, right? :)
    KONG_VERSION = "1.5.0.0"
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
        }
      }
    }
    stage('Prepare Kong Distributions') {
      //when {
      //  expression { BRANCH_NAME ==~ /^(release\/)?.*/}
      //}
      steps {
        //echo "Kong version: $KONG_VERSION"
        echo "Release scope ${env.RELEASE_SCOPE}"
        checkout([$class: 'GitSCM',
          // This is like this now, for internal preview
          // We should tune this thing to either use a branch_name or a tag
          branches: [[name: env.BRANCH_NAME]],
          extensions: [[$class: 'WipeWorkspace']],
          userRemoteConfigs: [[url: 'git@github.com:Kong/kong-distributions.git',
            credentialsId: 'kong-distributions-deploy-key']]
        ])
      }
    }
    stage('Build & Push Packages') {
      //when {
      //  expression { BRANCH_NAME ==~ /^(release\/)?.*/ }
      //}
      steps {
        parallel (
          centos6: {
            sh "./package.sh centos:6 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:6 -e -R ${env.RELEASE_SCOPE}"
          },
          centos7: {
            sh "./package.sh centos:7 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:7 -e -R ${env.RELEASE_SCOPE}"
          },
          centos8: {
            sh "./package.sh centos:8 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:8 -e -R ${env.RELEASE_SCOPE}"
          },
          debian8: {
            sh "./package.sh debian:8 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:8 -e -R ${env.RELEASE_SCOPE}"
          },
          debian9: {
            sh "./package.sh debian:9 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:9 -e -R ${env.RELEASE_SCOPE}"
          },
          // ubuntu1404: {
          //   sh "./package.sh ubuntu:14.04.2 ${env.RELEASE_SCOPE}"
          //   // sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:14.04.2 -e -R ${env.RELEASE_SCOPE}"
          // },
          ubuntu1604: {
            sh "./package.sh ubuntu:16.04 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:16.04 -e -R ${env.RELEASE_SCOPE}"
          },
          // ubuntu1704: {
          //   sh "./package.sh ubuntu:17.04 ${env.RELEASE_SCOPE}"
          //   // sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:17.04 -e -R ${env.RELEASE_SCOPE}"
          // },
          ubuntu1804: {
            sh "./package.sh ubuntu:18.04 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:18.04 -e -R ${env.RELEASE_SCOPE}"
          },
          amazonlinux1: {
            sh "./package.sh amazonlinux:1 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p amazonlinux:1 -e -R ${env.RELEASE_SCOPE}"
          },
          amazonlinux2: {
            sh "./package.sh amazonlinux:2 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p amazonlinux:2 -e -R ${env.RELEASE_SCOPE}"
          },
          alpine: {
            sh "./package.sh alpine ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p alpine -e -R ${env.RELEASE_SCOPE}"
          },
          rhel6: {
            sh "./package.sh rhel:6 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel:6 -e -R ${env.RELEASE_SCOPE}"
          },
          rhel7: {
            sh "./package.sh rhel:7 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel:7 -e -R ${env.RELEASE_SCOPE}"
          },
          rhel8: {
            sh "./package.sh rhel:8 ${env.RELEASE_SCOPE}"
            sh "./release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel:8 -e -R ${env.RELEASE_SCOPE}"
          },
        )
      }
    }
    stage("Prepare Docker Kong EE") {
      //when {
      //  expression { BRANCH_NAME ==~ /^(release\/)?.*/ }
      //}
      steps {
        checkout([$class: 'GitSCM',
            extensions: [[$class: 'WipeWorkspace']],
            userRemoteConfigs: [[url: 'git@github.com:Kong/docker-kong-ee.git',
            credentialsId: 'docker-kong-ee-deploy-key']]
        ])
      }
    }
    stage("Build & Push Docker Images") {
      //when {
      //  expression {
      //    expression { BRANCH_NAME ==~ /^release\/.*/ }
      //  }
      //}
      steps {
        parallel (
          // beware! $KONG_VERSION might have an ending \n that swallows everything after it
          alpine: {
            sh "./bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -l -p alpine -e -R ${env.RELEASE_SCOPE} -v $KONG_VERSION"
            sh "./bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -l -p alpine -e -R ${env.RELEASE_SCOPE} -a -v $KONG_VERSION"
          },
          centos7: {
            sh "./bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos -e -R ${env.RELEASE_SCOPE} -v $KONG_VERSION"
            sh "./bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos -e -R ${env.RELEASE_SCOPE} -a -v $KONG_VERSION"
          },
          rhel: {
            sh "./bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel -e -R ${env.RELEASE_SCOPE} -v $KONG_VERSION"
            sh "./bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel -e -R ${env.RELEASE_SCOPE} -a -v $KONG_VERSION"
          },
        )
      }
    }
  }
}
