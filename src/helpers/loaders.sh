#
# Loads the project environment variables to be used by the invoking script.
#
function load_project_variables() {
  cd $(dirname $0)
  cd $(git rev-parse --show-toplevel)/..
  PROJECT_DIR=$(git rev-parse --show-toplevel)
  PROJECT_ENV_FILE=${PROJECT_DIR}/project.env
  REPO_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  REPO_NAME=$(basename $(git remote get-url origin) .git)
  eval "$(cat $PROJECT_ENV_FILE)"
  DOCKER_IMAGE="${DOCKER_IMAGE_PREFIX}${REPO_NAME}"
  echo " - Done loading project variables"
}

#
# Loads the deployment variables to be used by the invoking script.
#
function load_deployment_variables() {
  REPO_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  REPO_COMMIT_SHA=$(git rev-parse --short HEAD)
  DOCKER_IMAGE_TAG="${REPO_BRANCH}-${REPO_COMMIT_SHA}"
  GITHUB_BASE_URI=$([ ! -z "${GITHUB_ACCESS_TOKEN}" ] && echo "https://${GITHUB_ACCESS_TOKEN}@github.com/$GITHUB_ORG" || echo "git@github.com:$GITHUB_ORG")
  BUILD_NUMBER=$CIRCLE_BUILD_NUM
  [[ ${REPO_BRANCH} = "master" ]] && ENVIRONMENT="prod" || ENVIRONMENT="beta"
  echo " - Done loading deployment variables"
}

#
# Loads the color variables
#
function load_color_variables() {
  BLUE='\033[0;34m'
  GREEN='\033[0;32m'
  LIGHT_BLUE='\033[1;34m'
  LIGHT_GREEN='\033[1;32m'
  LIGHT_PURPLE='\033[1;35m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  NO_COLOR='\033[0m' # No Color
}
