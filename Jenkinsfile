
def deployToASG(String asgName, String ltName, int warmPoolSize) {

    def ASG_NAME = asgName
    def LT_NAME  = ltName
    def rollbackRequired = false

    def ORIGINAL_LT_VERSION = ""
    def NEW_LT_VERSION = ""
    def ORIGINAL_INSTANCES = []
    def DESIRED_CAPACITY = 0

    try {
        echo "============================================"
        echo "Deploying AMI ${env.AMI_ID} to ${ASG_NAME}"
        echo "============================================"

        /* ---------- Capture ASG state ---------- */

        ORIGINAL_INSTANCES = sh(
            returnStdout: true,
            script: """
              aws autoscaling describe-auto-scaling-groups \
                --auto-scaling-group-names ${ASG_NAME} \
                --region ${ASG_REGION} |
              jq -r '.AutoScalingGroups[0].Instances[].InstanceId'
            """
        ).trim().split("\\n")

        DESIRED_CAPACITY = sh(
            returnStdout: true,
            script: """
              aws autoscaling describe-auto-scaling-groups \
                --auto-scaling-group-names ${ASG_NAME} \
                --region ${ASG_REGION} \
                --query 'AutoScalingGroups[0].DesiredCapacity' \
                --output text
            """
        ).trim().toInteger()

        /* ---------- Launch Template ---------- */

        ORIGINAL_LT_VERSION = sh(
            returnStdout: true,
            script: """
              aws ec2 describe-launch-templates \
                --launch-template-names ${LT_NAME} \
                --region ${ASG_REGION} |
              jq -r '.LaunchTemplates[0].DefaultVersionNumber'
            """
        ).trim()

        sh """
          aws ec2 create-launch-template-version \
            --launch-template-name ${LT_NAME} \
            --source-version ${ORIGINAL_LT_VERSION} \
            --launch-template-data ImageId=${env.AMI_ID} \
            --version-description "AMI rollout ${DATE_TAG}" \
            --region ${ASG_REGION}
        """

        NEW_LT_VERSION = sh(
            returnStdout: true,
            script: """
              aws ec2 describe-launch-template-versions \
                --launch-template-name ${LT_NAME} \
                --region ${ASG_REGION} |
              jq -r '.LaunchTemplateVersions | max_by(.VersionNumber).VersionNumber'
            """
        ).trim()

        sh """
          aws ec2 modify-launch-template \
            --launch-template-name ${LT_NAME} \
            --default-version ${NEW_LT_VERSION} \
            --region ${ASG_REGION}
        """

        /* ---------- Remove scale-in protection ---------- */

        sh """
          aws autoscaling update-auto-scaling-group \
            --auto-scaling-group-name ${ASG_NAME} \
            --no-new-instances-protected-from-scale-in \
            --region ${ASG_REGION}
        """


        sleep 15

        /* ---------- Start refresh (FAST + SAFE) ---------- */

        def minHealthy = 25
        def maxHealthy = 125
        def warmup     = 90

        // Faster replacement for small ASGs
        if (DESIRED_CAPACITY <= 3) {
            // FAST MODE (small ASG)
            minHealthy = 0
            maxHealthy = 100
            warmup     = 30
        } else {
            // FAST but SAFE
            minHealthy = 25
            maxHealthy = 125
            warmup     = 30
        }


        if (warmPoolSize > 0) {
            sh """
              aws autoscaling delete-warm-pool \
                --auto-scaling-group-name ${ASG_NAME} \
                --region ${ASG_REGION}
            """
        }



        sh """
          aws autoscaling start-instance-refresh \
            --auto-scaling-group-name ${ASG_NAME} \
            --strategy Rolling \
            --preferences MinHealthyPercentage=${minHealthy},MaxHealthyPercentage=${maxHealthy},InstanceWarmup=${warmup} \
            --region ${ASG_REGION}
        """

        /* ---------- REAL Progress Tracking ---------- */

        timeout(time: 30, unit: 'MINUTES') {

            while (true) {
                sleep env.SleepDuration.toInteger()

                def refreshStatus = sh(
                    returnStdout: true,
                    script: """
                      aws autoscaling describe-instance-refreshes \
                        --auto-scaling-group-name ${ASG_NAME} \
                        --region ${ASG_REGION} \
                        --query 'InstanceRefreshes[0].Status' \
                        --output text
                    """
                ).trim()

                echo "Instance refresh status: ${refreshStatus}"

                if (refreshStatus in ['Failed', 'Cancelled']) {
                    error "Instance refresh ${refreshStatus} for ${ASG_NAME}"
                }

//                 def oldLtInstances = sh(
//                     returnStdout: true,
//                     script: """
//                       aws autoscaling describe-auto-scaling-groups \
//                         --auto-scaling-group-names ${ASG_NAME} \
//                         --region ${ASG_REGION} |
//                       jq -r '
//                         .AutoScalingGroups[0].Instances[]
//                         | select(.LaunchTemplate.Version=="${ORIGINAL_LT_VERSION}")
//                         | .InstanceId
//                       ' | wc -l
//                     """
//                 ).trim().toInteger()
//
//                 def replaced = DESIRED_CAPACITY - oldLtInstances
//                 if (replaced < 0) { replaced = 0 }
//
//                 echo "Replacement progress: ${replaced}/${DESIRED_CAPACITY} instances updated"

                if (refreshStatus == 'Successful' || oldLtInstances == 0) {
                    echo "All instances running latest launch template"
                    break
                }
            }
        }

        /* ---------- Restore warm pool ---------- */

        if (warmPoolSize > 0) {
            sh """
              aws autoscaling put-warm-pool \
                --auto-scaling-group-name ${ASG_NAME} \
                --min-size ${warmPoolSize} \
                --region ${ASG_REGION}
            """
        }

        echo "AMI deployment successful for ${ASG_NAME}"

    } catch (err) {
        rollbackRequired = true
        echo "Deployment failed for ${ASG_NAME}: ${err}"
    }

    /* ---------- Rollback ---------- */

    if (rollbackRequired) {
        echo "Rolling back ${ASG_NAME}"

        sh """
          aws autoscaling cancel-instance-refresh \
            --auto-scaling-group-name ${ASG_NAME} \
            --region ${ASG_REGION} || true
        """

        sh """
          aws ec2 modify-launch-template \
            --launch-template-name ${LT_NAME} \
            --default-version ${ORIGINAL_LT_VERSION} \
            --region ${ASG_REGION}
        """

        error "Rollback completed for ${ASG_NAME}"
    }
}



pipeline {
    agent any

    parameters {
        text(
            name: 'FLEETS',
            description: 'Fleet configuration JSON',
            defaultValue: '''
[
  { "asg": "zen-test-streaming-asg", "lt": "lt-zen-test-streaming", "warm_pool": 2 },
  { "asg": "zen-test-platform-asg", "lt": "launchtemplate-zen-test-platform", "warm_pool": 3 },
  { "asg": "zen-test-platform-commit-log-asg", "lt": "lt-zen-test-platform-commit-log", "warm_pool": 2 }
]
'''
        )
        booleanParam(
            name: 'SKIP_HEALTHCHECK',
            defaultValue: true,
            description: 'Skip ASG & Target Group health checks (testing only)'
        )
    }

    environment {
        GODEBUG = "netdns=go"
        PATH = "/opt/homebrew/bin:${env.PATH}"
        SleepDuration = 10
        DATE_TAG = "$BUILD_TIMESTAMP"
    }

    stages {

        stage('Terraform Init & Plan') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aditya-demo',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                      export AWS_DEFAULT_REGION=$ASG_REGION
                      export AWS_EC2_METADATA_DISABLED=true

                      terraform init
                      terraform plan \
                        -var "DATE=$DATE_TAG" \
                        -var "INSTANCE_ID=$INSTANCE_ID" \
                        -var "ASG_Region=$ASG_REGION"
                    '''
                }
            }
        }


        stage('Approval') {
            steps {
                input message: 'Apply Terraform?'
            }
        }

        stage('Terraform Apply (AMI Creation)') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aditya-demo',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                      export AWS_DEFAULT_REGION=$ASG_REGION
                      export AWS_EC2_METADATA_DISABLED=true

                      terraform apply --auto-approve \
                        -var "DATE=$DATE_TAG" \
                        -var "INSTANCE_ID=$INSTANCE_ID" \
                        -var "ASG_Region=$ASG_REGION"

                      terraform output -raw autoscaling_id > output.txt
                    '''
                }
            }
        }


        stage('Deploy AMI to Fleets (Parallel)') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aditya-demo',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    script {
                        env.AMI_ID = sh(
                            script: 'cat output.txt',
                            returnStdout: true
                        ).trim()

                        // Write fleets JSON to file
                        writeFile file: 'fleets.json', text: params.FLEETS

                        int batchSize = 3
                        int index = 0

                        while (true) {
                            def batch = sh(
                                script: """
                                  jq -c '.[$index:$index+$batchSize][]' fleets.json
                                """,
                                returnStdout: true
                            ).trim()

                            if (!batch) {
                                break
                            }

                            def parallelJobs = [:]

                            batch.split("\\n").each { line ->
                                def asg = sh(
                                    script: "echo '${line}' | jq -r .asg",
                                    returnStdout: true
                                ).trim()

                                def lt = sh(
                                    script: "echo '${line}' | jq -r .lt",
                                    returnStdout: true
                                ).trim()

                                def warmPool = sh(
                                    script: "echo '${line}' | jq -r .warm_pool",
                                    returnStdout: true
                                ).trim().toInteger()

                                parallelJobs["Deploy-${asg}"] = {
                                    deployToASG(asg, lt, warmPool)
                                }
                            }

                            parallel parallelJobs
                            index += batchSize
                        }
                    }
                }
            }
        }



        stage('Copy Image To DR Region') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aditya-demo',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                      export AWS_DEFAULT_REGION=$ASG_REGION

                      aws ec2 copy-image \
                        --region $DR_REGION \
                        --name "ami-$DATE_TAG" \
                        --source-region $ASG_REGION \
                        --source-image-id $AMI_ID
                    '''
                }
            }
        }

    }

    post {
        always {
            sh 'rm -rf .terraform* *tfstate*'
        }
    }
}

