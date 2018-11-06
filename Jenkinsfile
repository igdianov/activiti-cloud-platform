pipeline {
	
    agent {
	    kubernetes {
	        // Change the name of jenkins-maven label to be able to use yaml configuration snippet
	        label "maven-jenkins"
	        // Inherit from Jx Maven pod template
	        inheritFrom "maven"
	        // Add scheduling configuration to Jenkins builder pod template
	        yaml """
spec:
  nodeSelector:
    cloud.google.com/gke-preemptible: true

  # It is necessary to add toleration to GKE preemtible pool taint to the pod in order to run it on that node pool
  tolerations:
  - key: gke-preemptible
    operator: Equal
    value: true
    effect: NoSchedule

  # Create sidecar container with gsutil to publish chartmuseum index.yaml to Google bucket storage 
  volumes:
  - name: gsutil-volume
    secret:
      secretName: gsutil-secret
      items:
      - key: .boto
        path: .boto

  containers:
  - name: gsutil
    image: introproventures/gsutil
    command:
    - /bin/sh
    - -c
    args:
    - cat
    workingDir: /home/jenkins
    securityContext:
      privileged: false
    tty: true
    resources:
      requests:
        cpu: 128m
        memory: 256Mi
      limits:
    volumeMounts:
      - mountPath: /home/jenkins
        name: workspace-volume
      - name: gsutil-volume
        mountPath: /root/.boto
        subPath: .boto
"""        
        } 
    }
    
    environment {
      ORG                   = "introproventures"
      APP_NAME              = "activiti-cloud-query-graphql-platform"
      CHARTMUSEUM_CREDS     = credentials("jenkins-x-chartmuseum")
      CHARTMUSEUM_GS_BUCKET = "introproventures"
      PROMOTE_HELM_REPO_URL = "https://storage.googleapis.com/introproventures"
      GITHUB_CHARTS_REPO    = "https://github.com/igdianov/helm-charts.git"
      GITHUB_HELM_REPO_URL = "https://igdianov.github.io/helm-charts"
    }
    stages {
      stage("CI Build and push snapshot") {
        when {
          branch "PR-*"
        }
        environment {
          PREVIEW_VERSION = "0.0.0-SNAPSHOT-$BRANCH_NAME-$BUILD_NUMBER"
          PREVIEW_NAMESPACE = "$APP_NAME-$BRANCH_NAME".toLowerCase()
          HELM_RELEASE = "$PREVIEW_NAMESPACE".toLowerCase()
        }
        steps {
          dir("/home/jenkins/activiti-cloud-query-graphql-platform") {
              
              checkout scm
              
              container("maven") {
                sh "make preview"
              }
          }
        }
      }
      stage("Build Release") {
        when {
          branch "master"
        }
        steps {
          // Working directory name must match with chart name
          dir("/home/jenkins/activiti-cloud-query-graphql-platform") {
              
              checkout scm
              
              container("maven") {
                // ensure we're not on a detached head
                sh "make checkout"
    
                // so we can retrieve the version in later steps
                sh "make next-version"
                
                // Let's build first
                sh "make build"
    
                // Let's make tag in Git
                sh "make tag"

                // Publish release to Github
                sh "make changelog"
                
                // Release Helm chart in Chartmuseum  
                sh "make release"

                // Let's release in Github Charts Repo
                sh "make release/github"
                
              }
              container("gsutil") {
                // Generate and publish chartmuseum index.yaml to Google storage bucket
                sh "make release/gs-bucket"
              }

              // Try consuming published charts
              container("maven") {
                // Let's test helm chart repos 
                sh "helm init --client-only"
                sh "helm repo add ${CHARTMUSEUM_GS_BUCKET} ${PROMOTE_HELM_REPO_URL}"
                sh "helm repo add ${APP_NAME} ${GITHUB_HELM_REPO_URL}"
                sh "helm repo update"
                input "Pause here"
              }

            }
          }
      }
      stage("Promote to Environments") {
        when {
          branch "master"
        }
        steps {
            dir("/home/jenkins/activiti-cloud-query-graphql-platform") {

                container("maven") {
                  // Let's promote to environments 
                  sh "make promote"
                }
            }
        }
      }
    }
    post {
        always {
            cleanWs()
        }
/*
        failure {

		input """Pipeline failed. 
We will keep the build pod around to help you diagnose any failures. 

Select Proceed or Abort to terminate the build pod"""
        }
*/	

    }
}
