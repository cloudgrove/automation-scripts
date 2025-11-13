#!/bin/bash

set -e

SCRIPT_DIR="$(cd $(dirname $0) && pwd)"
. ${SCRIPT_DIR}/../../../helpers/loaders.sh
. ${SCRIPT_DIR}/../../../helpers/logins.sh

load_project_variables
log_into_npm

cd ${PROJECT_DIR}
[ ! -z "${DOCKER_ARTIFACT_SUBDIR}" ] && cd ${DOCKER_ARTIFACT_SUBDIR} || true
[ ! -z "${NPM_VERSION_PREID}" ] && sed -E -i "s/(\"version\": \"[^\"]*)(\")/\1-${NPM_VERSION_PREID}\2/" package.json
[ ! -z "${NPM_REPO_ACCESS}" ] && npm publish --access ${NPM_REPO_ACCESS} || npm publish
