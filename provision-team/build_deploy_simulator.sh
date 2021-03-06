#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# -e: immediately exit if any command has a non-zero exit status
# -o: prevents errors in a pipeline from being masked
# IFS new value is less likely to cause confusing bugs when looping arrays or arguments (e.g. $@)
#script requires latest version of .netcore to be installed ()

usage() { echo "Usage: build_deploy_simulator.sh -n <team name> -t <image tag> -q <trip frequency> -d <dns host Url>" 1>&2; exit 1; }

declare teamName=""
declare imageTag="latest"
declare tripFrequency="1800"
declare dnsUrl=""

# Initialize parameters specified from command line
while getopts ":n:t:q:d:" arg; do
    case "${arg}" in
        n)
            teamName=${OPTARG}
        ;;
        t)
            imageTag=${OPTARG}
        ;;
        q)
            tripFrequency=${OPTARG}
        ;;
		 d)
            dnsUrl=${OPTARG}
        ;;
    esac
done
shift $((OPTIND-1))

if [[ -z "$tripFrequency" ]]; then
    echo "How often in ms a new trip will be simulated."
    read tripFrequency
    [[ "${tripFrequency:?}" ]]
fi

if [[ -z "$teamName" ]]; then
    echo "Enter a team name for the helm chart values filename:"
    read teamName
fi

if [ -z "$teamName" ]; then
    echo "missing teamName"
    usage
fi

if [[ -z "$dnsUrl" ]]; then
    echo "Public DNS address where the API will be hosted behind."
    echo "Enter public DNS name."
    read dnsUrl
    [[ "${dnsUrl:?}" ]]
fi

declare resourceGroupName="${teamName}rg"
declare registryName="${teamName}acr"

#DEBUG
echo $resourceGroupName
echo $tripFrequency
echo $teamName
echo $registryName
echo $imageTag
echo $dnsUrl

#get the acr repository id to tag image with.
ACR_ID=`az acr list -g $resourceGroupName --query "[].{acrLoginServer:loginServer}" --output json | jq .[].acrLoginServer | sed 's/\"//g'`

echo "ACR ID: "$ACR_ID

#Get the acr admin password and login to the registry
acrPassword=$(az acr credential show -n $registryName -o json | jq -r '[.passwords[0].value] | .[]')

docker login $ACR_ID -u $registryName -p $acrPassword
echo "Authenticated to ACR with username and password"

IMAGE=$ACR_ID"/devopsoh/simulator"
TAG=$IMAGE':'$imageTag

echo "TAG: "$TAG

pushd ../simulator/

docker build . -t $TAG

docker push $TAG

echo -e "\nSuccessfully pushed image: "$TAG

BASE_URI='http://'$dnsUrl
echo "Base URI: $BASE_URI"

echo "deploying simulator chart"
helm install ./helm --name simulator --set repository.image=$IMAGE,repository.tag=$imageTag,simulator.tripFrequency=$tripFrequency,simulator.teamName=$teamName,simulator.apiEndPoint=$BASE_URI --namespace=simulator

popd