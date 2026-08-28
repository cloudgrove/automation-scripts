#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../helpers/loaders.sh"
source "${SCRIPT_DIR}/../../../helpers/domains/awseda.sh"

load_project_variables
awseda_deploy_functions
awseda_deploy_graphql
