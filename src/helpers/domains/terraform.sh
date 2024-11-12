#
# Deletes Terraform-generated directories and files.
#
function terraform_clean_artifacts() {
  local dir='.terraform'
  if [ -d ${PROJECT_DIR} ]; then
    find ${PROJECT_DIR} -type d -name ${dir} | sed "s|^${PROJECT_DIR}/||" | sed "s|/\\${dir}||" | sort --unique | while read path; do
      terraform_clean_artifact "${path}/*.tfplan*"
      terraform_clean_artifact "${path}/*.tfstate*"
      terraform_clean_artifact "${path}/.terraform"
    done
  fi || { printf "${RED}Cleaning Terraform artifacts failed!${NO_COLOR}\n"; exit 1; }
  echo " - Done cleaning Terraform artifacts"
}

#
# Deletes the specified Terraform artifact.
#
function terraform_clean_artifact() {
  local path=${1}
  printf " - ${RED}Deleting ${NO_COLOR}${BLUE}${path}${NO_COLOR}\n"
  rm -rf ${PROJECT_DIR}/${path}
}

#
# Initializes Terraform workspaces within the repo and validates the syntax of their files.
#
function terraform_init_validate() {
  local success=true
  find ${PROJECT_DIR}/src -not -path '*/\.*' -type f -name "*.tf" -printf '%h\n' | sed "s~^${PROJECT_DIR}/~~" | sed "s~^${PROJECT_DIR}/~~" | sort -u | while read -r directory ; do
    printf " - Initializing ${BLUE}${directory}/${NO_COLOR}\n"
    terraform -chdir="${PROJECT_DIR}/$directory" init -backend=false -input=false > /dev/null && printf "${LIGHT_GREEN}Success!${NO_COLOR} Directory initialized.\n" || { success=false; }
    printf " - Validating ${BLUE}${directory}/${NO_COLOR}\n"
    terraform -chdir="${PROJECT_DIR}/$directory" validate || { success=false; printf "\n"; }
    $success
  done || { printf "${RED}Syntax validation failed!${NO_COLOR}\n"; exit 1; }
  printf " - ${LIGHT_BLUE}Syntax validation passed!${NO_COLOR}\n"
}

#
# Formats the Terraform code.
#
function terraform_format() {
  local success=true
  find ${PROJECT_DIR}/src -not -path '*/\.*' -type f -name "*.tf" -printf '%h\n' | sed "s~^${PROJECT_DIR}/~~" | sort -u | while read -r directory ; do
    printf " - Format-checking ${BLUE}${directory}/${NO_COLOR}\n"
    terraform -chdir="${PROJECT_DIR}/$directory" fmt -check -write=false -diff=true && printf "${LIGHT_GREEN}Success!${NO_COLOR} Formatting is correct.\n" || { success=false; printf "\n"; }
    $success
  done || { printf "${RED}Some terraform files must be formatted. Run 'terraform fmt --write=true --diff=true' on the target directory.${NO_COLOR}\n"; exit 1; }
  printf " - ${LIGHT_BLUE}Format checks passed!${NO_COLOR}\n"
}

#
# Returns the absolute path of the Terraform working directory.
#
function terraform_dir() {
  [ -n "${ENV_CONFIG_SUBDIR}" ] && TARGET_SUBDIR=${ENV_CONFIG_SUBDIR}/${ENVIRONMENT} || TARGET_SUBDIR='src'
  echo ${DOCKER_PROJECT_DIR}/${TARGET_SUBDIR}
}

#
# Returns the name of the target Terraform workspace.
#
function terraform_workspace() {
  echo ${REPO_NAME}-${ENVIRONMENT}
}

#
# Generates the Terraform plan.
#
function terraform_plan() {
  [[ "${REPO_BRANCH}" == 'master' || "${REPO_BRANCH}" == 'release_'* ]] && ENVIRONMENT='prod' || ENVIRONMENT='beta'
  [ "${SET_TF_WORKSPACE}" != 'false' ] && export TF_WORKSPACE=`terraform_workspace` || unset TF_WORKSPACE
  cd `terraform_dir`
  terraform init
  terraform plan -compact-warnings
}

#
# Generates the Terraform plan for every subdirectory in the `examples/` directory.
#
function terraform_plan_examples() {
  find ${PROJECT_DIR}/src/examples -not -path '*/\.*' -type f -name "*.tf" -printf '%h\n' | sed "s~^${PROJECT_DIR}/~~" | sort -u | while read -r directory ; do
    printf "Planning ${BLUE}${directory}/${NO_COLOR}\n"
    terraform -chdir="${PROJECT_DIR}/$directory" init
    terraform -chdir="${PROJECT_DIR}/$directory" plan -compact-warnings
  done || { printf "${RED}One or more examples failed plan generation.${NO_COLOR}\n"; exit 1; }
  printf " - ${LIGHT_BLUE}Plan generation complete.${NO_COLOR}\n"
}

#
# Applies the Terraform plan.
#
function terraform_apply() {
  [ "${SET_TF_WORKSPACE}" != 'false' ] && export TF_WORKSPACE=`terraform_workspace` || unset TF_WORKSPACE
  docker run --workdir `terraform_dir` --env TF_WORKSPACE ${DOCKER_IMAGE} apply --auto-approve
}
