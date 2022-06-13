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
        PULP_HOST_PROD = "https://api.download-dev.konghq.com"
        PULP_PROD = credentials('PULP_DEV')
        PULP_HOST_STAGE = "https://api.download-dev.konghq.com"
        PULP_STAGE = credentials('PULP_DEV')
        GITHUB_TOKEN = credentials('github_bot_access_token')
        DEBUG = 0
    }
    stages {
        stage('Release') {
            when {
                beforeAgent true
                branch 'fix/2.8.1-focal-arm64-only'
            }
            parallel {
                stage('Ubuntu Xenial') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        PACKAGE_TYPE = 'deb'
                        RESTY_IMAGE_BASE = 'ubuntu'
                        RESTY_IMAGE_TAG = 'focal'
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
                        sh 'TAG=2.8.1 DOCKER_MACHINE_ARM64_NAME="jenkins-kong-"`cat /proc/sys/kernel/random/uuid` make release'
                    }
                }
            }
        }
    }
}
