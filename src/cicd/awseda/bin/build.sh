#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../helpers/builders.sh"
source "${SCRIPT_DIR}/../../../helpers/loaders.sh"
source "${SCRIPT_DIR}/../../../helpers/logins.sh"

load_project_variables
if [ -n "${NPM_TOKEN:-}" ]; then
  log_into_npm
fi

if command -v docker >/dev/null 2>&1; then
  if [ -n "${DOCKER_USER:-}" ]; then
    log_into_docker_registry ""
  fi
  cd "${PROJECT_DIR}"
  build_artifacts
else
  echo " - Docker unavailable; running the AWS EDA build directly"
  cd "${PROJECT_DIR}/src"
  npm ci
  npm run test
  npm run lint
  "${SCRIPT_DIR}/package.sh"
fi
