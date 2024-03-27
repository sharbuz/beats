#!/usr/bin/env bash

source .buildkite/scripts/common.sh

set -euo pipefail

pipelineName="pipeline.metricbeat-dynamic.yml"

echo "Add the mandatory and extended tests without additional conditions into the pipeline"
if are_conditions_met_mandatory_tests; then
  cat > $pipelineName <<- YAML

steps:

  - group: "Mandatory Tests"
    key: "mandatory-tests"
    steps:
      - label: ":linux: Ubuntu Unit Tests"
        key: "mandatory-linux-unit-test"
        command: "cd $BEATS_PROJECT_NAME && mage build unitTest"
        agents:
          provider: "gcp"
          image: "${IMAGE_UBUNTU_X86_64}"
          machineType: "${GCP_DEFAULT_MACHINE_TYPE}"
        artifact_paths: "${BEATS_PROJECT_NAME}/build/*.*"

      - label: ":go: Go Intergration Tests"
        key: "mandatory-int-test"
        command: "cd $BEATS_PROJECT_NAME && mage goIntegTest"
        env:
          MODULE: $MODULE
        agents:
          provider: "gcp"
          image: "${IMAGE_UBUNTU_X86_64}"
          machineType: "${GCP_HI_PERF_MACHINE_TYPE}"
        artifact_paths: "${BEATS_PROJECT_NAME}/build/*.*"

      - label: ":python: Python Integration Tests"
        key: "mandatory-python-int-test"
        command: "cd $BEATS_PROJECT_NAME && mage pythonIntegTest"
        env:
          MODULE: $MODULE
        agents:
          provider: "gcp"
          image: "${IMAGE_UBUNTU_X86_64}"
          machineType: "${GCP_HI_PERF_MACHINE_TYPE}"
        artifact_paths: "${BEATS_PROJECT_NAME}/build/*.*"

      - label: ":negative_squared_cross_mark: Cross compile"
        key: "mandatory-cross-compile"
        command: "make -C $BEATS_PROJECT_NAME crosscompile"
        agents:
          provider: "gcp"
          image: "${IMAGE_UBUNTU_X86_64}"
          machineType: "${GCP_DEFAULT_MACHINE_TYPE}"
        artifact_paths: "${BEATS_PROJECT_NAME}/build/*.*"

      - label: ":windows: Windows 2016/2022 Unit Tests - {{matrix.image}}"
        command:
          - "Set-Location -Path $BEATS_PROJECT_NAME"
          - "New-Item -ItemType Directory -Force -Path 'build'"
          - "mage unitTest"
        key: "mandatory-win-unit-tests"
        agents:
          provider: "gcp"
          image: "{{matrix.image}}"
          machine_type: "${GCP_WIN_MACHINE_TYPE}"
          disk_size: 100
          disk_type: "pd-ssd"
        matrix:
          setup:
            image:
              - "${IMAGE_WIN_2016}"
              - "${IMAGE_WIN_2022}"
        artifact_paths: "${BEATS_PROJECT_NAME}/build/*.*"

# echo "Add the extended windows tests into the pipeline"
# TODO: ADD conditions from the main pipeline

  - group: "Extended Windows Tests"
    key: "extended-win-tests"
    steps:
      - label: ":windows: Windows Unit Tests - {{matrix.image}}"
        command:
          - "Set-Location -Path $BEATS_PROJECT_NAME"
          - "New-Item -ItemType Directory -Force -Path 'build'"
          - "mage unitTest"
        key: "extended-win-unit-tests"
        agents:
          provider: "gcp"
          image: "{{matrix.image}}"
          machineType: "${GCP_WIN_MACHINE_TYPE}"
          disk_size: 100
          disk_type: "pd-ssd"
        matrix:
          setup:
            image:
              - "${IMAGE_WIN_10}"
              - "${IMAGE_WIN_11}"
              - "${IMAGE_WIN_2019}"
        artifact_paths: "${BEATS_PROJECT_NAME}/build/*.*"
YAML
else
  echo "The conditions don't match to requirements for generating pipeline steps."
  exit 0
fi

echo "Check and add the Extended Tests into the pipeline"
if are_conditions_met_macos_tests; then
  cat >> $pipelineName <<- YAML

  - group: "Extended Tests"
    key: "extended-tests"
    steps:
      - label: ":mac: MacOS Unit Tests"
        key: "extended-macos-unit-tests"
        command: ".buildkite/scripts/unit_tests.sh"
        agents:
          provider: "orka"
          imagePrefix: "${IMAGE_MACOS_X86_64}"
        artifact_paths: "${BEATS_PROJECT_NAME}/build/*.*"
YAML

fi

echo "Check and add the Packaging into the pipeline"
if are_conditions_met_packaging; then
  cat >> $pipelineName <<- YAML

  - wait: ~
    depends_on:
      - step: "mandatory-tests"
        allow_failure: false

  - group: "Packaging"    # TODO: check conditions for future the main pipeline migration: https://github.com/elastic/beats/pull/28589
    key: "packaging"
    steps:
      - label: ":linux: Packaging Linux"
        key: "packaging-linux"
        command: "cd $BEATS_PROJECT_NAME && mage package"
        agents:
          provider: "gcp"
          image: "${IMAGE_UBUNTU_X86_64}"
          machineType: "${GCP_HI_PERF_MACHINE_TYPE}"
          disk_size: 100
          disk_type: "pd-ssd"
        env:
          PLATFORMS: "${PACKAGING_PLATFORMS}"

      - label: ":linux: Packaging ARM"
        key: "packaging-arm"
        command: "cd $BEATS_PROJECT_NAME && mage package"
        agents:
          provider: "aws"
          imagePrefix: "${IMAGE_UBUNTU_ARM_64}"
          instanceType: "${AWS_ARM_INSTANCE_TYPE}"
        env:
          PLATFORMS: "${PACKAGING_ARM_PLATFORMS}"
          PACKAGES: "docker"

YAML
fi

echo "--- Printing dynamic steps"     #TODO: remove if the pipeline is public
cat $pipelineName

echo "--- Loading dynamic steps"
buildkite-agent pipeline upload $pipelineName
