#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../helpers/loaders.sh"
source "${SCRIPT_DIR}/../../../helpers/logins.sh"

load_project_variables
if [ -n "${NPM_TOKEN:-}" ]; then
  log_into_npm
fi
cd "${PROJECT_DIR}/src"
npm ci
npm run test
npm run lint
