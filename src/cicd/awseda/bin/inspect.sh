#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../helpers/loaders.sh"

load_project_variables
DOCKER_BUILD_ARG_CLAUSE=$(echo " ${DOCKER_BUILD_ARGS}" | sed "s/[ ][ ]*/ --build-arg /g")
INSPECT_STAGE="builder"
cd "${PROJECT_DIR}"
docker build ${DOCKER_BUILD_ARG_CLAUSE} --target "${INSPECT_STAGE}" -t "${DOCKER_IMAGE}:${INSPECT_STAGE}" .
docker run -it "${DOCKER_IMAGE}:${INSPECT_STAGE}" sh
