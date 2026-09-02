/**
 * Reusable Android build+test+archive pipeline, shared across every Android project's
 * Jenkins job. A project's entire Jenkins job body is just:
 *
 *   @Library('android-ci') _
 *   androidBuildPipeline(
 *       repoUrl: 'https://github.com/arifhossenbdiop/some-project.git',
 *       credentialsId: 'some-credential-id'
 *   )
 *
 * No Dockerfile or Jenkinsfile needs to exist in the project's own repo.
 */
def call(Map config) {
    def repoUrl = config.repoUrl ?: error("androidBuildPipeline: 'repoUrl' is required")
    def credentialsId = config.credentialsId ?: error("androidBuildPipeline: 'credentialsId' is required")

    def branch = config.branch ?: 'main'
    def buildTask = config.buildTask ?: 'assembleDebug'
    def testTask = config.testTask ?: 'testDebugUnitTest'
    def testResultsGlob = config.testResultsGlob ?: "app/build/test-results/${testTask}/*.xml"
    def apkGlob = config.apkGlob ?: 'app/build/outputs/apk/debug/*.apk'
    def sdkVolume = config.sdkVolume ?: 'android-sdk-cache'
    def gradleVolume = config.gradleVolume ?: 'android-gradle-cache'
    def dockerImage = config.image ?: 'android-generic-build:latest'
    def projectName = config.projectName ?: (repoUrl.tokenize('/').last() - '.git')
    def apkDir = apkGlob.substring(0, apkGlob.lastIndexOf('/'))
    def outputMetadataJson = config.outputMetadataJson ?: "${apkDir}/output-metadata.json"
    def dockerArgs = "-v ${sdkVolume}:/opt/android-sdk -v ${gradleVolume}:/home/builder/.gradle"

    pipeline {
        agent none

        options {
            timestamps()
            disableConcurrentBuilds()
        }

        stages {
            stage('Fix Cache Ownership') {
                // The named cache volumes are also used by local scripts/build-apk.sh
                // runs, which build as a different host UID. Gradle's own daemon
                // registry does an internal chmod() on its state directory, which the
                // OS only permits for the file's owner (or root) no matter how open the
                // permission bits already are - so ownership itself has to move to
                // whichever UID is about to build (here, whatever UID Jenkins runs as)
                // before every build, not just once.
                agent any
                steps {
                    sh "docker run --rm ${dockerArgs} ${dockerImage} " +
                       'chown -R $(id -u):$(id -g) /opt/android-sdk /home/builder/.gradle'
                }
            }
            stage('Checkout') {
                agent { docker { image dockerImage; args dockerArgs } }
                steps {
                    git branch: branch, url: repoUrl, credentialsId: credentialsId
                }
            }
            stage('Build') {
                agent { docker { image dockerImage; args dockerArgs } }
                steps {
                    sh "./gradlew ${buildTask} --stacktrace"
                }
            }
            stage('Package') {
                // Renames the APK using AGP's own output-metadata.json (versionName,
                // variantName) instead of guessing/parsing build.gradle - this is the
                // same file AGP writes next to the APK for every variant build, so it
                // works regardless of how a project derives its own version scheme.
                agent { docker { image dockerImage; args dockerArgs } }
                steps {
                    script {
                        def versionName = sh(
                            script: "grep -oE '\"versionName\"[[:space:]]*:[[:space:]]*\"[^\"]*\"' '${outputMetadataJson}' | sed -E 's/.*\"([^\"]*)\"\$/\\1/'",
                            returnStdout: true
                        ).trim()
                        def variantName = sh(
                            script: "grep -oE '\"variantName\"[[:space:]]*:[[:space:]]*\"[^\"]*\"' '${outputMetadataJson}' | sed -E 's/.*\"([^\"]*)\"\$/\\1/'",
                            returnStdout: true
                        ).trim()
                        def buildDate = sh(script: 'date +%Y%m%d', returnStdout: true).trim()
                        env.RENAMED_APK = "${apkDir}/${projectName}-${versionName}-${buildDate}-${variantName}.apk"
                        sh "cp ${apkGlob} '${env.RENAMED_APK}'"
                    }
                }
            }
            stage('Unit Test') {
                agent { docker { image dockerImage; args dockerArgs } }
                steps {
                    sh "./gradlew ${testTask} --stacktrace"
                }
                post {
                    always {
                        junit testResultsGlob
                    }
                    success {
                        archiveArtifacts artifacts: env.RENAMED_APK, fingerprint: true
                    }
                }
            }
        }
    }
}
