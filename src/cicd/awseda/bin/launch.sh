#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../helpers/loaders.sh"

load_project_variables
export DOCKER_IMAGE
cd "${PROJECT_DIR}"
docker-compose up
