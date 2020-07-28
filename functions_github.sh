#!/bin/bash

function create_project_board() {
    local projectBoardName=$1
    local organization=$2
    local accessToken=$3

    if ! project_board_exists $projectBoardName $organization $accessToken ; then
        curl --request POST \
            --url $GITHUB_ENDPOINT/orgs/$organization/projects \
            --header 'Authorization: token '$accessToken'' \
            --header 'Accept: application/vnd.github.inertia-preview+json' \
            --data '{"name":"'$projectBoardName'","private":true}' > /dev/null
        echo "  Project board '$projectBoardName' created"
    else
        echo "  Project board '$projectBoardName' already exists" 
    fi
}

function project_board_exists() {
    local projectBoardName=$1
    local organization=$2
    local accessToken=$3

    projectBoards=$(curl -s --request GET \
        --url $GITHUB_ENDPOINT/orgs/$organization/projects \
        --header "Accept: application/vnd.github.inertia-preview+json" \
        --header 'Authorization: token '$accessToken'')
    
    projectBoard=$(jq '.[] | select(.name == "'$projectBoardName'")' <<< $projectBoards)

    ! [[ -z "$projectBoard" ]]
}

function create_repository() {
    local repoName=$1
    local organization=$2
    local accessToken=$3

    if ! organization_repository_exists $repoName $organization $accessToken ; then
        curl -s --request POST \
            --url $GITHUB_ENDPOINT/orgs/$organization/repos $organization \
            --header 'Authorization: token '$accessToken'' \
            --header 'Accept: application/vnd.github.inertia-preview+json' \
            --data '{"name":"'$repoName'","private":true}' > /dev/null
        echo "  Repository '$repoName' created"
    else
        echo "  Repository '$repoName' already exists" 
    fi
}

function organization_repository_exists() {
    local repoName=$1
    local organization=$2
    local accessToken=$3

    orgRepository=$(curl -s --request GET \
        --url $GITHUB_ENDPOINT/repos/$organization/$repoName \
        --header "Accept: application/vnd.github.v3+json" \
        --header 'Authorization: token '$accessToken'')

    orgRepositoryId=$(jq '.id // empty' <<< $orgRepository)

    ! [[ -z "$orgRepositoryId" ]]
}

# function create_repo() {
#     local repoName=$1
#     local organization=$2

#     mkdir $repoName

#     pushd $repoName > /dev/null
    
#     git init
#     git add .
#     git commit -m "initial commit"
#     hub create -p -o $organization/$repoName

#     popd > /dev/null

#     rm -rf $repoName
# }

function configure_manifest_repo() {
    local repoName=$1
    local organization=$2
    local workflowStrategy=$3
    local accessToken=$4

    workDirectory="$(pwd)"
    REPO_HOME=$(mktemp -d)
    
    pushd $REPO_HOME > /dev/null

    repos=$(curl -s --request GET \
        --url $GITHUB_ENDPOINT/orgs/$organization/repos \
        --header "Accept: application/vnd.github.v3+json" \
        --header 'Authorization: token '$accessToken'')

    repo=$(jq '.[] | select(.name == "'$repoName'")' <<< $repos)
    sshUrl=$(jq -r '.ssh_url // empty' <<< $repo)

    git clone --quiet $sshUrl

    cp -rT "$workDirectory"/workflow-strategies/$workflowStrategy/manifest/ $repoName/

    pushd $repoName > /dev/null

    git add .
    git commit -m "copy files over" > /dev/null 2>&1 && git push origin master --quiet

    echo "  Repository '$repoName' configured"
    
    popd > /dev/null
    popd > /dev/null
}

function configure_app_repo() {
    local repoName=$1
    local organization=$2
    local APP_GIT="$3"
    local workflowStrategy=$4
    local manifestRepoName=$5
    local accessToken=$6
  
    workdir=$(pwd)
    REPO_HOME=$(mktemp -d)

    pushd $REPO_HOME > /dev/null
  
    repos=$(curl -s --request GET \
        --url $GITHUB_ENDPOINT/orgs/$organization/repos \
        --header "Accept: application/vnd.github.v3+json" \
        --header 'Authorization: token '$accessToken'')

    repo=$(jq '.[] | select(.name == "'$repoName'")' <<< $repos)
    sshUrl=$(jq -r '.ssh_url // empty' <<< $repo)

    git clone --quiet $sshUrl

    mkdir $repoName/.github/
    cp -r "$workdir"/workflow-strategies/$workflowStrategy/pipelines/* $repoName/.github/

    # terrible hack becuase cannot use ${{ parameters.manifestRepo }} as there is a bug "An error occurred while loading the YAML build pipeline. An item with the same key has already been added."
    # sed -i -e "s#git://gitops/manifest-live#git://$devopsorg/$manifestlive#g" $appname/.azuredevops/templates/automatic-release-template.yaml

    pushd $repoName > /dev/null

    git add .
    git commit -m "copy files over" > /dev/null 2>&1 && git remote add upstream $APP_GIT --quiet
    git fetch upstream > /dev/null
    git rebase upstream/master > /dev/null

    ## will fail on re-run after build policy is in place.  should remove then update then re-apply
    git push origin master > /dev/null
    
    echo "  Repository '$repoName' configured"
    
    popd > /dev/null
    popd > /dev/null
}


function configure_app_repo1() {
  local appname=$1
  local devopsorg=$2
  local APP_GIT="$3"
  local workflow_strategy=$4
  local manifestlive=$5
  shift 5
  local orgAndproj=("$@")
  
  workdir=$(pwd)
  echo $workdir
  REPO_HOME=$(mktemp -d)
  pushd $REPO_HOME
  sshurl=$(az repos show -r $appname "${orgAndproj[@]}" --query 'sshUrl' -o tsv)
  git clone $sshurl

  #TODO check if dir already has files... don't want to overwrite any customizations. Maybe show diff?
  mkdir $appname/.azuredevops/ || true
  cp -r "$workdir"/workflow-strategies/$workflow_strategy/pipelines/* $appname/.azuredevops/

  # terrible hack becuase cannot use ${{ parameters.manifestRepo }} as there is a bug "An error occurred while loading the YAML build pipeline. An item with the same key has already been added."
  sed -i -e "s#git://gitops/manifest-live#git://$devopsorg/$manifestlive#g" $appname/.azuredevops/templates/automatic-release-template.yaml

  pushd $appname
  git add .
  git commit -m "copy files over" || true #ignore failure
  git remote add upstream $APP_GIT
  git fetch upstream
  git rebase upstream/master

  ## will fail on re-run after build policy is in place.  should remove then update then re-apply
  git push origin master
  echo "finished"
  popd
  popd
}


