
#!/bin/bash

set -o errexit
set -o pipefail

source ./functions_github.sh

declare -A GITHUB_ENDPOINT=https://api.github.com

#set defaults
REPO_APP_NAME=app
INITIALIZATION_APP_REPO="https://github.com/Azure-Samples/azure-voting-app-redis.git"
WORKFLOW_STRATEGY=release-flow
INFRA_TERRAFORM=infra-terraform
INFRA_LIVE=infra-live

while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
    --org )
        shift; ORG=$1
        ;;
    -p | --project-name )
        shift; PROJECT_NAME=$1
        ;;
    -r | --repo-app-name )
        shift; REPO_APP_NAME=$1
        ;;
    -acr | --acr-name )
        shift; ACR_NAME=$1
        ;;
    -w | --workflow-strategy )
        shift; WORKFLOW_STRATEGY=$1
        ;;
    -a | --app-repo )
        shift; INITIALIZATION_APP_REPO=$1; SAMPLE=false;
        ;;
    --access-token ) 
        shift; ACCESS_TOKEN=$1
        ;;

esac; shift; done

if [[ "$1" == '--' ]]; then shift; fi

: "${ORG:?Provide <orgname> which will be used to form 'https://github.com/<orgname>'.  Create an org at https://docs.github.com/en/github/setting-up-and-managing-organizations-and-teams/creating-a-new-organization-from-scratch }"
: "${PROJECT_NAME:?variable empty or not defined.}"
: "${REPO_APP_NAME:?variable empty or not defined.}"
: "${ACR_NAME:?Please provide an ACR name.}"
: "${WORKFLOW_STRATEGY:?variable empty or not defined.}"
: "${ACCESS_TOKEN:?variable empty or not defined.}"
  
GITHUB_ORG="https://github.com/$ORG"
MANIFEST_REPO_NAME="manifest-live"

# If we pass in a local filepath, set APP_REPO to absolute filepath, if we pass in git url, keep git url as is
if [[ -d $INITIALIZATION_APP_REPO ]]; then 
    INITIALIZATION_APP_REPO=$(readlink -f $INITIALIZATION_APP_REPO); 
fi

echo -e "\x1B[32mYou have selected:"
echo -e "\t \x1B[32mOrg: \x1B[36m$GITHUB_ORG"
echo -e "\t \x1B[32mProject Name: \x1B[36m$PROJECT_NAME"
echo -e "\t \x1B[32mRepo Name: \x1B[36m$REPO_APP_NAME"
echo -e "\t \x1B[32mWorkflow Strategy: \x1B[36m$WORKFLOW_STRATEGY\x1B[0m (options: release-flow, ring-flow)"
echo -e "\t \x1B[32mRepository for App initialization: \x1B[36m$INITIALIZATION_APP_REPO"
echo -e "\t \x1B[32mArc Enabled: \x1B[36mfalse"
echo -ne "Proceed? [y/n]:\x1B[0m "
read proceed

if [[ "$proceed" != "y" ]]; then
  exit
fi

# 1. Create Repositories
echo "Creating GitHub project and repositories..."   
create_project_board $PROJECT_NAME $ORG $ACCESS_TOKEN

# create infra repositories
create_repository $INFRA_TERRAFORM $ORG $ACCESS_TOKEN
create_repository $INFRA_LIVE $ORG $ACCESS_TOKEN

# create gitops repos
create_repository $MANIFEST_REPO_NAME $ORG $ACCESS_TOKEN 
create_repository $REPO_APP_NAME $ORG $ACCESS_TOKEN 

# 2. configure app and pipelines
printf "\nConfiguring repositories...\n"
configure_manifest_repo $MANIFEST_REPO_NAME $ORG $WORKFLOW_STRATEGY $ACCESS_TOKEN
configure_app_repo $REPO_APP_NAME $ORG $INITIALIZATION_APP_REPO $WORKFLOW_STRATEGY $MANIFEST_REPO_NAME $ACCESS_TOKEN
