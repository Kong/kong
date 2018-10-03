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
    KONG_VERSION = """${sh(
      returnStdout: true,
      script: '[ -n $TAG_NAME ] && echo $TAG_NAME | grep -o -P "\\d+\\.\\d+([.-]\\d+)?" || echo $BRANCH_NAME | grep -o -P "\\d+\\.\\d+([.-]\\d+)?"'
    )}"""
    BUILD_ARG = """${sh(
      returnStdout: true,
      script: '[ -n "$(echo $BRANCH_NAME | grep -o -P \"^release/\\d+\\.\\d+([.-]\\d+)?\")" ] && echo "-i" || echo ""'
    )}"""
  }
  stages {
    stage('Prepare Kong Distributions') {
      when {
        expression { BRANCH_NAME ==~ /^(release\/)?\d+.\d+(-\d+)?$/ }
      }
      steps {
        echo "Kong version: $KONG_VERSION"
        echo "Build arg: $BUILD_ARG"
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
        expression { BRANCH_NAME ==~ /^(release\/)?\d+.\d+(-\d+)?$/ }
      }
      steps {
        parallel (
          centos6: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:6 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:6 -e $BUILD_ARG'
          },
          centos7: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:7 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos:7 -e $BUILD_ARG'
          },
          debian7: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:7 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:7 -e $BUILD_ARG'
          },
          debian8: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:8 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:8 -e $BUILD_ARG'
          },
          debian9: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:9 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p debian:9 -e $BUILD_ARG'
          },
          ubuntu1204: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:12.04.5 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:12.04.5 -e $BUILD_ARG'
          },
          ubuntu1404: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:14.04.2 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:14.04.2 -e $BUILD_ARG'
          },
          ubuntu1604: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:16.04 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:16.04 -e $BUILD_ARG'
          },
          ubuntu1704: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:17.04 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:17.04 -e $BUILD_ARG'
          },
          ubuntu1804: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:18.04 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p ubuntu:18.04 -e $BUILD_ARG'
          },
          amazonlinux: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p amazonlinux --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p amazonlinux -e $BUILD_ARG'
          },
          alpine: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p alpine --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p alpine -e $BUILD_ARG'
          },
          rhel6: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW --redhat-username $REDHAT_USR --redhat-password $REDHAT_PSW -p rhel:6 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel:6 -e $BUILD_ARG'
          },
          rhel7: {
            sh './package.sh -u $BINTRAY_USR -k $BINTRAY_PSW --redhat-username $REDHAT_USR --redhat-password $REDHAT_PSW -p rhel:7 --ee $BUILD_ARG'
            sh './release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel:7 -e $BUILD_ARG'
          },
        )
      }
    }
    stage("Prepare Docker Kong EE") {
      when {
        expression { BRANCH_NAME ==~ /^(release\/)?\d+.\d+(-\d+)?$/ }
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
        expression { BRANCH_NAME ==~ /^(release\/)?\d+.\d+(-\d+)?$/ }
      }
      steps {
        parallel (
          alpine: {
            sh './bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p alpine -e -v $KONG_VERSION $BUILD_ARG'
          },
          centos7: {
            sh './bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p centos -e -v $KONG_VERSION $BUILD_ARG'
          },
          rhel: {
            sh './bintray-release.sh -u $BINTRAY_USR -k $BINTRAY_PSW -p rhel -e -v $KONG_VERSION $BUILD_ARG'
          },
        )
      }
    }
  }
}
