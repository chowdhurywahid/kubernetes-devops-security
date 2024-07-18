pipeline {
    agent any
    tools {
        maven 'maven'
    }
    environment {
        IMAGE_NAME = 'numeric-app-demo:1.0'
        APP_NAME = 'numeric-app-demo'
    }

    stages {

    stage('Checkout') {
        steps {
            sh 'kubectl version -oyaml --client'
            sh 'java --version'
            sh 'pwd'
            git branch: 'main',
            credentialsId: 'git-loginssh',
            url: 'git@github.com:chowdhurywahid/kubernetes-devops-security.git'
        }
    }
        stage('build jar') {
            steps {
               script {
                  echo 'building application jar...'
                  sh 'mvn -DskipTests=true clean package'
               }
            }
        }
        stage('build and push image') {
            steps {
                script {
                    sh "docker build -t wahidc7/numeric-app-demo:1.0 ."
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-login', passwordVariable: 'PASS', usernameVariable: 'USER')]) {
                    sh 'docker login -u $USER -p $PASS'
                    sh "docker push wahidc7/numeric-app-demo:1.0"
                    }
                }
            }
        }
         stage('deploy') {
            steps {
                script {
                   echo 'deploying docker image...'
                   withKubeConfig([credentialsId: 'kubeconfig']) {
                   sh 'kubectl apply -f k8s_deployment_service.yaml'
                }
            }
         }
    }
} }
