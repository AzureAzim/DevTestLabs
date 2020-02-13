#The resource group information, the source and destination
resourceGroupName="<Source Resource Group Name>"
newResourceGroupName="<Destination Resource Group Name>"

#The name of the VM you wish to migrate
vmName="<VM Name>"
newVmName="<New vm name after migration>"

#The OS image of the VM
imageName="Windows Server 2016 Datacenter"
osType="Windows"

#The size of hte VM
vmsize="<VM Size>"
#The location of the VM
location="<vm location>"
#The admin username for the newly created vm
adminusername="<admin user name>"

#The suffix to add to the end of the VM
osDiskSuffix="_lab.vhd"
#The type of storage for the data disks
storageType="Premium_LRS"

#The VNET information for the VM that is being migrated
vnet="<vnet name>"
subnet="<subnet name>"

#The name of the lab to be migrated to
labName="<lab name>"

#The information about the storage account associated with the lab
newstorageAccountName="<lab storage account name>"
storageAccountKey="<lab storage account primary key>"
diskcontainer="<lab container for 'uploads'>"

echo "Set to Government Cloud"
sudo az cloud set --name AzureUSGovernment

echo "Login to Azure"
sudo az login

echo "Create new Resource Group"
az group create -l $location -n $newResourceGroupName

echo "Deallocate current machine"
az vm deallocate --resource-group $resourceGroupName --name $vmName

echo "Create container"
az storage container create -n $diskcontainer --account-name $newstorageAccountName --account-key $storageAccountKey

osDisks=$(az vm show -d -g $resourceGroupName -n $vmName --query "storageProfile.osDisk.name") 
echo ""
echo "Copy OS Disks"
echo "--------------"
echo "Get OS Disk List"

osDisks=$(echo "$osDisks" | tr -d '"')

for osDisk in $(echo $osDisks | tr "[" "\n" | tr "," "\n" | tr "]" "\n" )
do
   echo "Copying OS Disk $osDisk"

   echo "Get url with token"
   sas=$(az disk grant-access --resource-group $resourceGroupName --name $osDisk --duration-in-seconds 3600 --query [accessSas] -o tsv)

   newOsDisk="$osDisk$osDiskSuffix"
   echo "New OS Disk Name = $newOsDisk"

   echo "Start copying $newOsDisk disk to blob storage"
   az storage blob copy start --destination-blob $newOsDisk --destination-container $diskcontainer --account-name $newstorageAccountName --account-key $storageAccountKey --source-uri $sas

   echo "Get $newOsDisk copy status"
   while [ "$status"=="pending" ]
   do
      status=$(az storage blob show --container-name $diskcontainer --name $newOsDisk --account-name $newstorageAccountName --account-key $storageAccountKey --output json | jq '.properties.copy.status')
      status=$(echo "$status" | tr -d '"')
      echo "$newOsDisk Disk - Current Status = $status"

      progress=$(az storage blob show --container-name $diskcontainer --name $newOsDisk --account-name $newstorageAccountName --account-key $storageAccountKey --output json | jq '.properties.copy.progress')
      echo "$newOsDisk Disk - Current Progress = $progress"
      sleep 10s
      echo ""

      if [ "$status" != "pending" ]; then
      echo "$newOsDisk Disk Copy Complete"
      break
      fi
   done

   echo "Get blob url"
   blobSas=$(az storage blob generate-sas --account-name $newstorageAccountName --account-key $storageAccountKey -c $diskcontainer -n $newOsDisk --permissions r --expiry "2019-02-26" --https-only)
   blobSas=$(echo "$blobSas" | tr -d '"')
   blobUri=$(az storage blob url -c $diskcontainer -n $newOsDisk --account-name $newstorageAccountName --account-key $storageAccountKey)
   blobUri=$(echo "$blobUri" | tr -d '"')

   echo $blobUri

   blobUrl=$(echo "$blobUri")

   echo "Create image from $newOsDisk vhd in blob storage"
   az group deployment create --name "LabMigrationv1" --resource-group $newResourceGroupName --template-file customImage.json --parameters existingVhdUri=$blobUrl --verbose

   echo "Create Lab VM - $newVmName"
   az lab vm create --lab-name $labName -g $newResourceGroupName --name $newVmName --image "$imageName" --image-type gallery --size $vmsize --admin-username $adminusername --vnet-name $vnet --subnet $subnet
done 

echo "Script Completed"