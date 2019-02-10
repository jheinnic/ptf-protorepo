#!/usr/bin/env /bin/bash
# This script is meant to build and compile every protocolbuffer for each
# service declared in this repository (as defined by sub-directories).
# It compiles using docker containers based on Namely's protoc image
# seen here: https://github.com/namely/docker-protoc

set -e

REPOPATH=${REPOPATH-/Users/jheinnic/Git/JchPtf/proto-builds}
CURRENT_FEATURE=${CIRCLE_FEATURE-"bootstrap"}

# Helper for adding a directory to the stack and echoing the result
function enterDir {
  echo "Entering $1"
  pushd $1 > /dev/null
}

# Helper for popping a directory off the stack and echoing the result
function leaveDir {
  echo "Leaving `pwd`"
  popd > /dev/null
}

# Enters the directory and starts the build / compile process for the services
# protobufs
function buildDir {
  currentDir="$1"
  echo "Building directory \"$currentDir\""

  enterDir $currentDir

  buildProtoForTypes $currentDir

  leaveDir
}

# Iterates through all of the languages listed in the services .protolangs file
# and compiles them individually
function buildProtoForTypes {
  target=${1%/}

  if [ -f .protolangs ]; then
    while read lang; do
      reponame="protorepo-$target-$lang"

      rm -rf $REPOPATH/$reponame

      echo "Cloning repo: git@github.com:jheinnic/$reponame.git"

      # Clone the repository down and set the branch to the automated one
      git clone https://github.com/jheinnic/$reponame $REPOPATH/$reponame
      initFlow $REPOPATH/$reponame
      setupBranch $REPOPATH/$reponame

      # Use the docker container for the language we care about and compile
      # docker run -v `pwd`:/defs namely/protoc-$lang
      ls -1 *.proto | xargs -I {} docker run -v `pwd`:/defs jheinnic/protoc-all -f {} -l $lang

      # Copy the generated files out of the pb-* path into the repository
      # that we care about
      cp -R gen/pb-$lang/* $REPOPATH/$reponame/

      commitAndPush $REPOPATH/$reponame
    done < .protolangs
  fi
}

# Finds all directories in the repository and iterates through them calling the
# compile process for each one
function buildAll {
  echo "Buidling service's protocol buffers"
  mkdir -p $REPOPATH
  for d in `ls -lad * | grep '^d' | awk '{ print $9 }'`; do
    buildDir $d
  done
}

function initFlow {
  enterDir $1

  # We always start with a fresh clone from git, and git-flow configuration is only stored locally, not
  # as a part of each repository, so it becomes necessary to re-apply the configuration during each run.
  cat << EOF >> .git/config
[gitflow "branch"]
        master = master
        develop = develop
[gitflow "prefix"]
        feature = feature/
        bugfix = bugfix/
        release = release/
        hotfix = hotfix/
        support = support/
        versiontag = v
[gitflow "path"]
        hooks = $1/.git/hooks
EOF

  git checkout develop
  # git ls-remote --heads --exit-code origin develop > $1/.git/refs/heads/develop

  leaveDir
}

function setupBranch {
  enterDir $1

  echo "Creating or tracking branch"

  if ! git flow feature track $CURRENT_FEATURE; then
    if ! git flow feature start $CURRENT_FEATURE; then
      echo "Could neither track nor start $CURRENT_FEATURE in freshly cloned repository.  Is it a legal name?"
      exit -1
    else
      echo "Initiated branch for $CURRENT_FEATURE feature"
    fi
  else 
    echo "Now tracking $CURRENT_FEATURE"
  fi

  # git checkout $CURRENT_FEATURE
  #
  # if git ls-remote --heads --exit-code origin $CURRENT_FEATURE; then
  #   echo "Branch exists on remote, pulling latest changes"
  #   git pull origin $CURRENT_FEATURE
  # fi

  leaveDir
}

function commitAndPush {
  enterDir $1

  git add -N .

  if ! git diff --exit-code > /dev/null; then
    git add .
    git commit -m "Auto Creation of Proto"
    git push origin HEAD
  else
    echo "No changes detected for $1"
  fi

  leaveDir
}

buildAll
