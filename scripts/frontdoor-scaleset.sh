# Text colors
red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

# Variables
rgName="rg-frontdoor-eus-wus-demo"
prefix="alemor"
vmssnameE=vmsseus
vmssnameW=vmsswus
fdname="${prefix}-frontend"
vnetNameE="fd-eus-vnet"
#vnetEPrefixE="10.50.0.0/16"
#vnetEDefaultPrefix="10.50.0.0/24"
#vnetESubnetPrefixE="10.50.1.0/24"
vnetNameW="fd-wus-vnet"
subnetName="vmssSubnet"

echo "${green}Create Groups${reset}"

#az group delete -g $rgName
az group create -g $rgName --location eastus

echo "${green}Create VNets and Subnets${reset}"

az network vnet create -g $rgName \
  --name $vnetNameE \
  --location eastus \
  --address-prefix 10.50.0.0/16 \
  --subnet-name default \
  --subnet-prefix 10.50.0.0/24

az network vnet subnet create --resource-group $rgName --vnet-name $vnetNameE --name $subnetName --address-prefixes 10.50.1.0/24

az network vnet create -g $rgName \
  --name $vnetNameW \
  --location westus \
  --address-prefix 10.51.0.0/16 \
  --subnet-name default \
  --subnet-prefix 10.51.0.0/24

az network vnet subnet create --resource-group $rgName --vnet-name $vnetNameW --name $subnetName --address-prefixes 10.51.1.0/24

echo "${green}Get the subnet IDs'${reset}"

subnetIDE=$(az network vnet subnet list -g $rgName --vnet-name $vnetNameE --query "[?name=='${subnetName}'].id" --output tsv)
subnetIDW=$(az network vnet subnet list -g $rgName --vnet-name $vnetNameW --query "[?name=='${subnetName}'].id" --output tsv)

if [ -z "$subnetIDE" ] || [ -z "$subnetIDW" ]
then
  echo "One of the subnet IDs was not found and it is required."
  exit 1
fi

echo "${green}Creating Scale Sets${reset}"

az vmss create \
  --resource-group $rgName \
  --name $vmssnameE \
  --image UbuntuLTS \
  --upgrade-policy-mode automatic \
  --subnet $subnetIDE \
  --custom-data cloud-init.txt \
  --admin-username azureuser \
  --generate-ssh-keys

az vmss create \
  --resource-group $rgName \
  --name $vmssnameW \
  --image UbuntuLTS \
  --upgrade-policy-mode automatic \
  --subnet $subnetIDW \
  --custom-data cloud-init.txt \
  --admin-username azureuser \
  --location westus \
  --generate-ssh-keys  

echo "${green}Creating LB rules${reset}"

az network lb rule create \
  --resource-group $rgName \
  --name myLoadBalancerRuleWeb \
  --lb-name "${vmssnameE}LB" \
  --backend-pool-name "${vmssnameE}LBBEPool" \
  --backend-port 80 \
  --frontend-ip-name loadBalancerFrontEnd \
  --frontend-port 80 \
  --protocol tcp

az network lb rule create \
  --resource-group $rgName \
  --name myLoadBalancerRuleWeb \
  --lb-name "${vmssnameW}LB" \
  --backend-pool-name "${vmssnameW}LBBEPool" \
  --backend-port 80 \
  --frontend-ip-name loadBalancerFrontEnd \
  --frontend-port 80 \
  --protocol tcp \

echo "${green}Assigning DNS names to public IPs${reset}"

az network public-ip update -g $rgName -n vmsseusLBPublicIP --dns-name "${prefix}fdeus" 
az network public-ip update -g $rgName -n vmsswusLBPublicIP --dns-name "${prefix}fdwus"

echo "${green}Creating the front-door${reset}"

az network front-door create \
--resource-group $rgName \
--name $fdname \
--backend-address "${prefix}fdeus.eastus.cloudapp.azure.com" 

az network front-door backend-pool backend add \
--resource-group $rgName \
--address "${prefix}fdwus.eastus.cloudapp.azure.com" \
--front-door-name $fdname \
--pool-name "DefaultBackendPool" \
