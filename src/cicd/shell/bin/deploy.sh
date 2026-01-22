#!/bin/bash

set -e

SCRIPT_DIR="$(cd $(dirname $0) && pwd)"
. ${SCRIPT_DIR}/../../../helpers/loaders.sh
. ${SCRIPT_DIR}/../../../helpers/deployers.sh

load_project_variables
deploy_to_ecs ${REPO_NAME} ${AWS_ECS_CLUSTER}
