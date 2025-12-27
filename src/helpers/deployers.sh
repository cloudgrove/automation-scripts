#!/bin/bash

#
# Tags the built image with the provided tag and pushes it to the registry specified in $DOCKER_IMAGE_PREFIX.
#
function push_docker_image() {
  local tag=${1:-experimental}
  docker tag ${DOCKER_IMAGE} ${DOCKER_IMAGE}:${tag}
  docker push ${DOCKER_IMAGE}:${tag}
  echo " - Done pushing ${DOCKER_IMAGE}:${tag}"
}

#
# Tags the built image with the provided tag and pushes it to AWS ECR.
#
function push_docker_image_to_ecr() {
  local tag=${1:-experimental}
  local account="$(aws sts get-caller-identity --query 'Account' --output text)"
  local registry="${account}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  local image=${registry}/${REPO_NAME}:${tag}
  docker tag ${DOCKER_IMAGE} ${image}
  docker push ${image}
  echo " - Done pushing ${image}"
}

#
# Deploys the specified service to AWS ECS.
#
function deploy_to_ecs() {
  local service=${1}
  local cluster=${2}
  local services=$(aws ecs list-services --cluster ${cluster} --query 'serviceArns[]' --output text)
  [[ ! "${services[*]}" =~ "$service" ]] && { echo "The target service '${service}' is not found... Skipping deployment..."; exit; }
  aws ecs update-service --cluster ${cluster} --service ${service} --force-new-deployment --query 'service.taskDefinition'
}

#
# Deploys the target artifact to S3, replicates it in the `current/` directory, and invalidates the CloudFront distribution cache.
#
function deploy_to_s3() {
  if [ -n "${AWS_S3_BUCKET}" ]; then
    cd ${PROJECT_DIR}/src
    VERSION=$(npm version | sed -n "2s/'//g; 2s/,//; 2p" | awk '{print $NF}')
    VERSION_DIR="s3://${AWS_S3_BUCKET}/${AWS_S3_PROJECT_DIR}/${VERSION}"
    CURRENT_DIR="s3://${AWS_S3_BUCKET}/${AWS_S3_PROJECT_DIR}/current"
    cd ..
    push_to_s3 ${DOCKER_ARTIFACT_SUBDIR} ${VERSION_DIR} ${AWS_S3_DEPLOYMENT_MANIFEST}
    aws s3 rm --recursive ${CURRENT_DIR}
    aws s3 cp --recursive ${VERSION_DIR} ${CURRENT_DIR}
  fi
  if [ -n "${TARGET_CNAME}" ]; then
    AWS_CLOUDFRONT_DISTRIBUTION_ID="$(aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '${TARGET_CNAME}')].Id" --output text)"
    echo " - Invalidating CloudFront distribution ${AWS_CLOUDFRONT_DISTRIBUTION_ID} for ${TARGET_CNAME}"
    aws cloudfront create-invalidation --distribution-id ${AWS_CLOUDFRONT_DISTRIBUTION_ID} --paths "/*"
  fi
  echo -e "${GREEN} ✓ S3 deployment complete! ${NC}"
}

#
# Pushes files to S3.
#
function push_to_s3() {
  local source=${1}
  local destination=${2}
  local manifest=${3}
  if [[ -f "$manifest" ]]; then
    echo -e "${BLUE} - Deploying files using manifest: ${manifest} ${NC}"
    local default_cache=$(yq '.default_cache_control' "$manifest")
    local groups_count=$(yq '.file_groups | length' "$manifest")
    for i in $(seq 0 $((groups_count - 1))); do
      local name=$(yq ".file_groups[$i].name" "$manifest")
      local cache=$(yq ".file_groups[$i].cache_control // \"$default_cache\"" "$manifest")
      local content_type=$(yq ".file_groups[$i].content_type // \"\"" "$manifest")
      local -a sync_args=(--cache-control "$cache")
      [[ -n "$content_type" && "$content_type" != "null" ]] && sync_args+=(--content-type "$content_type" --metadata-directive REPLACE)
      while read -r exclude; do [[ -n "$exclude" ]] && sync_args+=(--exclude "$exclude"); done < <(yq -r ".file_groups[$i].exclude_patterns[]" "$manifest")
      while read -r include; do [[ -n "$include" ]] && sync_args+=(--include "$include"); done < <(yq -r ".file_groups[$i].include_patterns[]" "$manifest")
      echo -e "${BLUE} - Deploying ${name}... ${NC}"
      aws s3 sync "$source" "$destination" "${sync_args[@]}"
      echo -e "${GREEN}   ✓ ${name} deployed! ${NC}"
    done
  else
    echo -e "${BLUE} - Deploying files with basic sync... ${NC}"
    aws s3 sync "$source" "$destination"
  fi
}
