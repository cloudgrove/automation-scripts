#!/bin/bash

SCRIPT_DIR="$(cd $(dirname $0) && pwd)"
. ${SCRIPT_DIR}/../../../helpers/cleaners.sh
. ${SCRIPT_DIR}/../../../helpers/loaders.sh
. ${SCRIPT_DIR}/../../../helpers/domains/terraform.sh

load_project_variables
load_color_variables
remove_docker_containers $DOCKER_IMAGE
terraform_clean_artifacts
