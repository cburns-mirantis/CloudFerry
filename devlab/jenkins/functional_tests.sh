#!/bin/bash

set -e
set -x 

export WORKSPACE="${WORKSPACE:-$( cd $( dirname "$0" ) && cd ../../../ && pwd)}"
export CF_DIR=$WORKSPACE/CloudFerry
export JOB_NAME="${JOB_NAME:-cloudferry-functional-tests}"
export JOB_REGEX="cloudferry-functional-tests*"
export BUILD_NUMBER="${BUILD_NUMBER:-$[ 1 + $[ RANDOM % 1000 ]]}"
export BUILD_NAME="-$(echo $JOB_NAME | sed s/cloudferry/cf/)-${BUILD_NUMBER}"
export VIRTUALBOX_NETWORK_NAME="vn-${JOB_NAME}-${BUILD_NUMBER}"

trap 'clean_exit $LINENO $BASH_COMMAND; exit' SIGHUP SIGINT SIGQUIT SIGTERM EXIT
clean_exit()
{
    pushd ${CF_DIR}/devlab
    vboxmanage list vms
    vagrant status
    vboxmanage list vms | grep "${BUILD_NAME:1:${#BUILD_NAME}}"
    if [ $? -ne 0 ]; then
        exit 1
    fi 
    vboxmanage list vms | grep "${BUILD_NAME:1:${#BUILD_NAME}}" | awk -F'_' '{print $2}' | xargs -t -I {} vagrant destroy {} --force
    vboxmanage list vms
    vagrant status
    popd
}

echo "Preparing environment"
pushd $CF_DIR

if [[ $JOB_NAME =~ $JOB_REGEX ]]; then
    git remote update
    # cloudferry source dir is not deleted after job finish, so if
    # pull request cannot be automatically rebased, we must abort it explicitly and
    # exit with failure. In case rebase succeeded, functional test should # move on.
    git pull --rebase origin devel || ( git rebase --abort && exit 1 )
elif  [ "$JOB_NAME" = "cloudferry-release-builder" ]; then
    echo "Job ${JOB_NAME} is running, 'git remote update' and 'git pull --rebase origin devel' was performed previously"
else
    echo "JOB_NAME defined incorrectly"
    exit 1
fi

echo "Put all steps below"
${CF_DIR}/devlab/jenkins/setup_lab.sh

echo "Create code archive"
cd ${WORKSPACE}/
rm -f CloudFerry.tar.gz
tar cvfz CloudFerry.tar.gz CloudFerry/

${CF_DIR}/devlab/jenkins/copy_code_to_cf.sh
${CF_DIR}/devlab/jenkins/gen_load_and_migration.sh
${CF_DIR}/devlab/jenkins/nosetests.sh
