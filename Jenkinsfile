// def deployToASG(String asgName, String ltName, int warmPoolSize) {
//
//     def ASG_NAME = asgName
//     def LAUNCHTEMPLATE_NAME = ltName
//     def WARM_POOL_SIZE = warmPoolSize
//
//     def rollback = false
//     def ASG_new_desired = 0
//     def LT_latest_version = ""
//     def LT_default_version = ""
//
//     def ORIGINAL_desired = 0
//     def ORIGINAL_min = 0
//
//     try {
//
//         def initialASG = sh(
//             returnStdout: true,
//             script: "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${ASG_NAME} --region ${ASG_REGION}"
//         ).trim()
//
//         ORIGINAL_desired = sh(
//             returnStdout: true,
//             script: "echo '${initialASG}' | jq .AutoScalingGroups[0].DesiredCapacity"
//         ).trim().toInteger()
//
//         ORIGINAL_min = sh(
//             returnStdout: true,
//             script: "echo '${initialASG}' | jq .AutoScalingGroups[0].MinSize"
//         ).trim().toInteger()
//
//         echo "================================================"
//         echo "Deploying AMI ${env.AMI_ID} to ASG: ${ASG_NAME}"
//         echo "================================================"
//
//         /* ---------- Launch Template Update ---------- */
//         sh """
//           aws ec2 create-launch-template-version \
//             --launch-template-name ${LAUNCHTEMPLATE_NAME} \
//             --source-version '\$Default' \
//             --version-description "AMI update ${DATE_TAG}" \
//             --launch-template-data ImageId=${env.AMI_ID} \
//             --region ${ASG_REGION}
//         """
//
//         sh """
//           aws ec2 describe-launch-template-versions \
//             --launch-template-name ${LAUNCHTEMPLATE_NAME} \
//             --region ${ASG_REGION} > lt_described_${ASG_NAME}.out
//         """
//
//         LT_latest_version = sh(
//             returnStdout: true,
//             script: "jq -r '.LaunchTemplateVersions | max_by(.VersionNumber) | .VersionNumber' lt_described_${ASG_NAME}.out"
//         ).trim()
//
//         LT_default_version = sh(
//             returnStdout: true,
//             script: "jq -r '.LaunchTemplateVersions[] | select(.DefaultVersion==true) | .VersionNumber' lt_described_${ASG_NAME}.out"
//         ).trim()
//
//         if (LT_latest_version == LT_default_version) {
//             error "Latest Launch Template version already default"
//         }
//
//         sh """
//           aws ec2 modify-launch-template \
//             --launch-template-name ${LAUNCHTEMPLATE_NAME} \
//             --default-version ${LT_latest_version} \
//             --region ${ASG_REGION}
//         """
//
//         /* ---------- Warm Pool ---------- */
//         sh """
//           aws autoscaling put-warm-pool \
//             --auto-scaling-group-name ${ASG_NAME} \
//             --min-size ${WARM_POOL_SIZE} \
//             --max-group-prepared-capacity ${WARM_POOL_SIZE} \
//             --region ${ASG_REGION}
//         """
//
//         /* ---------- Scale Up ---------- */
//         def ASG_Described = sh(
//             returnStdout: true,
//             script: "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${ASG_NAME} --region ${ASG_REGION}"
//         ).trim()
//
//         def CURRENT_desired = sh(
//             returnStdout: true,
//             script: "echo '${ASG_Described}' | jq .AutoScalingGroups[0].DesiredCapacity"
//         ).trim().toInteger()
//
//         def CURRENT_max = sh(
//             returnStdout: true,
//             script: "echo '${ASG_Described}' | jq .AutoScalingGroups[0].MaxSize"
//         ).trim().toInteger()
//
//         ASG_new_desired = CURRENT_desired * 2
//
//         sh """
//           aws autoscaling update-auto-scaling-group \
//             --auto-scaling-group-name ${ASG_NAME} \
//             --min-size ${ASG_new_desired} \
//             --max-size ${Math.max(CURRENT_max, ASG_new_desired + 1)} \
//             --desired-capacity ${ASG_new_desired} \
//             --region ${ASG_REGION}
//         """
//
//         /* ---------- EC2 Health ---------- */
//         if (!params.SKIP_HEALTHCHECK) {
//             timeout(time: 10, unit: 'MINUTES') {
//                 while (true) {
//                     sleep env.SleepDuration.toInteger()
//
//                     def healthy = sh(
//                         returnStdout: true,
//                         script: """
//                           aws autoscaling describe-auto-scaling-groups \
//                             --auto-scaling-group-names ${ASG_NAME} \
//                             --region ${ASG_REGION} |
//                           jq '[.AutoScalingGroups[0].Instances[] |
//                               select(.HealthStatus=="Healthy" and .LifecycleState=="InService")] | length'
//                         """
//                     ).trim().toInteger()
//
//                     echo "EC2 Healthy: ${healthy}/${ASG_new_desired}"
//                     if (healthy >= ASG_new_desired) break
//                 }
//             }
//         } else {
//             echo "SKIPPING EC2 health check (test mode)"
//         }
//
//         /* ---------- Target Group Health ---------- */
//         def TG_ARN = sh(
//             returnStdout: true,
//             script: """
//               aws autoscaling describe-auto-scaling-groups \
//                 --auto-scaling-group-names ${ASG_NAME} \
//                 --region ${ASG_REGION} |
//               jq -r '.AutoScalingGroups[0].TargetGroupARNs[0] // empty'
//             """
//         ).trim()
//
//         if (TG_ARN && !params.SKIP_HEALTHCHECK) {
//             timeout(time: 10, unit: 'MINUTES') {
//                 while (true) {
//                     sleep env.SleepDuration.toInteger()
//
//                     def TG_Healthy = sh(
//                         returnStdout: true,
//                         script: """
//                           aws elbv2 describe-target-health \
//                             --target-group-arn ${TG_ARN} \
//                             --region ${ASG_REGION} |
//                           jq '[.TargetHealthDescriptions[] |
//                               select(.TargetHealth.State=="healthy")] | length'
//                         """
//                     ).trim().toInteger()
//
//                     echo "TG Healthy: ${TG_Healthy}/${ASG_new_desired}"
//                     if (TG_Healthy >= ASG_new_desired) break
//                 }
//             }
//         } else if (TG_ARN) {
//             echo "⚠️ SKIPPING Target Group health check (test mode)"
//         }
//
//
//     } catch (err) {
//         rollback = true
//         echo "Failure for ASG: ${ASG_NAME}"
//         echo err.toString()
//     } finally {
//         echo "Cleaning up temporary files for ASG: ${ASG_NAME}"
//
//         sh """
//           rm -f lt_described_${ASG_NAME}.out || true
//         """
//     }
//
//     if (rollback) {
//         echo "Rolling back ASG: ${ASG_NAME}"
//
//         sh """
//           aws ec2 modify-launch-template \
//             --launch-template-name ${LAUNCHTEMPLATE_NAME} \
//             --default-version ${LT_default_version} \
//             --region ${ASG_REGION}
//         """
//
//         sh """
//           aws autoscaling update-auto-scaling-group \
//             --auto-scaling-group-name ${ASG_NAME} \
//             --desired-capacity ${ORIGINAL_desired} \
//             --min-size ${ORIGINAL_min} \
//             --region ${ASG_REGION}
//         """
//
//         error "Rollback completed for ${ASG_NAME}"
//     }
//
//     sh """
//       aws autoscaling update-auto-scaling-group \
//         --auto-scaling-group-name ${ASG_NAME} \
//         --desired-capacity ${ORIGINAL_desired} \
//         --min-size ${ORIGINAL_min} \
//         --region ${ASG_REGION}
//     """
//
//     echo "Deployment completed for ASG: ${ASG_NAME}"
// }


def deployToASG(String asgName, String ltName, int warmPoolSize) {

    def ASG_NAME = asgName
    def LT_NAME  = ltName
    def rollbackRequired = false

    def ORIGINAL_LT_VERSION = ""
    def NEW_LT_VERSION = ""
    def ORIGINAL_INSTANCES = []

    try {
        echo "============================================"
        echo "Deploying AMI ${env.AMI_ID} to ${ASG_NAME}"
        echo "Environment = ${params.IS_PROD ? 'PROD' : 'NON-PROD'}"
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

        /* ---------- Ensure no refresh running ---------- */

        sh """
          aws autoscaling cancel-instance-refresh \
            --auto-scaling-group-name ${ASG_NAME} \
            --region ${ASG_REGION} || true
        """

        sleep 30

        /* ---------- Warm pool handling ---------- */

        if (!params.IS_PROD) {
            sh """
              aws autoscaling delete-warm-pool \
                --auto-scaling-group-name ${ASG_NAME} \
                --region ${ASG_REGION} || true
            """
        }

        /* ---------- Start refresh ---------- */

        def minHealthy = params.IS_PROD ? 90 : 0
        def warmup     = params.IS_PROD ? 300 : 0

        sh """
          aws autoscaling start-instance-refresh \
            --auto-scaling-group-name ${ASG_NAME} \
            --preferences MinHealthyPercentage=${minHealthy},InstanceWarmup=${warmup} \
            --region ${ASG_REGION}
        """

        /* ---------- REAL Progress Tracking ---------- */

        timeout(time: params.IS_PROD ? 30 : 15, unit: 'MINUTES') {

            while (true) {
                sleep env.SleepDuration.toInteger()

                def oldLtInstances = sh(
                    returnStdout: true,
                    script: """
                      aws autoscaling describe-auto-scaling-groups \
                        --auto-scaling-group-names ${ASG_NAME} \
                        --region ${ASG_REGION} |
                      jq -r '
                        .AutoScalingGroups[0].Instances[]
                        | select(.LaunchTemplate.Version=="${ORIGINAL_LT_VERSION}")
                        | .InstanceId
                      ' | wc -l
                    """
                ).trim().toInteger()

                def totalInstances = sh(
                    returnStdout: true,
                    script: """
                      aws autoscaling describe-auto-scaling-groups \
                        --auto-scaling-group-names ${ASG_NAME} \
                        --region ${ASG_REGION} |
                      jq '.AutoScalingGroups[0].Instances | length'
                    """
                ).trim().toInteger()

                def replaced = totalInstances - oldLtInstances

                echo "Replacement progress: ${replaced}/${totalInstances} instances updated"

                if (oldLtInstances == 0) {
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
        echo "⚠️ Rolling back ${ASG_NAME}"

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
  { "asg": "zen-prod-streaming-asg", "lt": "lt-zen-prod-streaming", "warm_pool": 2 },
  { "asg": "zen-prod-platform-asg", "lt": "launchtemplate-zen-prod-platform", "warm_pool": 3 }
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
        SleepDuration = 20
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

                        int batchSize = 2
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

