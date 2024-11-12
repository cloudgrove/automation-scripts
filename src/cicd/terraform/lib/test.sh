#!/bin/bash

SCRIPT_DIR="$(cd $(dirname $0) && pwd)"
. ${SCRIPT_DIR}/../../../helpers/detectors.sh
. ${SCRIPT_DIR}/../../../helpers/loaders.sh
. ${SCRIPT_DIR}/../../../helpers/logins.sh
. ${SCRIPT_DIR}/../../../helpers/domains/terraform.sh

load_project_variables
load_deployment_variables
load_color_variables
terraform_init_validate
terraform_format
check_cloud_provider_creds && terraform_plan_examples || echo ' - Skipping example plans'
