#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../helpers/cleaners.sh"
source "${SCRIPT_DIR}/../../../helpers/loaders.sh"

load_project_variables
if command -v docker-compose >/dev/null 2>&1; then
  remove_docker_containers "${DOCKER_IMAGE}"
fi
cd "${PROJECT_DIR}/src"
npm run clean --if-present
echo " - Done cleaning!"
