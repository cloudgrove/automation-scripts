#!/bin/bash

SCRIPT_DIR="$(cd $(dirname $0) && pwd)"
source ${SCRIPT_DIR}/../../../helpers/domains/terraform.sh
source ${SCRIPT_DIR}/../../../helpers/loaders.sh

load_project_variables
load_deployment_variables
terraform_apply
