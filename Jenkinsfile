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
      GS_BUCKET_CHARTS_REPO = "introproventures"
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
          container("maven") {
            sh "make build"
          }
          container("gsutil") {
            sh "make gs-bucket-charts-repo"
          }
          container("maven") {
            sh "make github-charts-repo"

            // Let's test helm chart repos 
            sh "helm init --client-only"
            sh "helm repo add ${GS_BUCKET_CHARTS_REPO} https://storage.googleapis.com/${GS_BUCKET_CHARTS_REPO}"
            sh "helm repo add ${APP_NAME} https://igdianov.github.io/${APP_NAME}"
            sh "helm repo update"
          }
        }
      }
      stage("Build Release") {
        when {
          branch "master"
        }
        steps {
          container("maven") {
            // ensure we're not on a detached head
            sh "make checkout"

            // so we can retrieve the version in later steps
            sh "make next-version"
            
            // Let's build first
            sh "make build"

            // Let's make tag in Git
            sh "make tag"
            
            // Let's deploy to Github
            sh "make github-charts-repo"
          }
        }
      }
      stage("Promote to Environments") {
        when {
          branch "master"
        }
        steps {
            container("maven") {
              // Publish release to Github
              sh "make changelog"
              
              // Release Helm chart in Chartmuseum  
              sh "make release"
            }
            container("gsutil") {
              // Generate and publish chartmuseum index.yaml to Google storage bucket: ${GS_BUCKET_CHARTS_REPO}
              // To consume published Helm charts from Google storage bucket use:
              // helm init --client-only 
              // helm repo add ${GS_BUCKET_CHARTS_REPO} https://storage.googleapis.com/${GS_BUCKET_CHARTS_REPO}"
               
              sh "make gs-bucket-charts-repo"

              // Let's test Google storage bucket charts repo
              sh "helm init --client-only"
              sh "helm repo add ${GS_BUCKET_CHARTS_REPO} https://storage.googleapis.com/${GS_BUCKET_CHARTS_REPO}"

            }
            container("maven") {
              // Let's promote to environments 
              sh "make promote"
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
