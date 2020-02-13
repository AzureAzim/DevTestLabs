<#
.SYNOPSIS
    This is an EXAMPLE script to collect information on disks in Azure, and move them to Azure Dev Test Labs. It is not inteded to be executied in a production enviuronment as-is
.DESCRIPTION
    
.PARAMETER 
    
.PARAMETER 
    
.PARAMETER 
    
.EXAMPLE
    
.NOTES

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
#>


#PARAMS

#The resource group information, the source and destination
resourceGroupName="<Original Resource Group>"
newResourceGroupName="<Destination Resource Group>"
 
#The name of the VM you wish to migrate
vmName="<VM Name>"
newVmName="<New VM Name>"
 
#The OS image of the VM
imageName="Windows Server 2016 Datacenter"
osType="Windows"
 
#The size of the VM
vmsize="<vm size>"
#The location of the VM
location="<location>"
#The admin username for the newly created vm
adminusername="<username>"
 
#The suffix to add to the end of the VM
osDiskSuffix="_lab.vhd"
#The type of storage for the data disks
storageType="Premium_LRS"
 
#The VNET information for the VM that is being migrated
vnet="<vnet name>"
subnet="<Subnet name>"
 
#The name of the lab to be migrated to
labName="<Lab Name>"
 
#The information about the storage account associated with the lab
newstorageAccountName="<Lab account name>"
storageAccountKey="<Storage account key>"
diskcontainer="uploads"

#for gov (from original script
#echo "Set to Government Cloud"
#sudo az cloud set --name AzureCommerical


echo "Set to Commercial Cloud"
sudo az cloud set --name AzureCommerical

 
#echo "Login to Azure"
#sudo az login
 
echo "Get updated access token"
sudo az account get-access-token
 
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
 
dataDisks=$(az vm show -d -g $resourceGroupName -n $vmName --query "storageProfile.dataDisks[].name")
echo ""
echo "Copy Data Disks"
echo "--------------"
echo "Get Data Disk List"
 
dataDisks=$(echo "$dataDisks" | tr -d '"')
 
for dataDisk in $(echo $dataDisks | tr "[" "\n" | tr "," "\n" | tr "]" "\n" )
do
   echo "Copying Data Disk $dataDisk"
 
   echo "Get url with token"
   sas=$(az disk grant-access --resource-group $resourceGroupName --name $dataDisk --duration-in-seconds 3600 --query [accessSas] -o tsv)
 
   newDataDisk="$dataDisk$osDiskSuffix"
   echo "New OS Disk Name = $newDataDisk"
 
   echo "Start copying disk to blob storage"
   az storage blob copy start --destination-blob $newDataDisk --destination-container $diskcontainer --account-name $newstorageAccountName --account-key $storageAccountKey --source-uri $sas
 
   echo "Get copy status"
   while [ "$status"=="pending" ]
   do
      status=$(az storage blob show --container-name $diskcontainer --name $newDataDisk --account-name $newstorageAccountName --account-key $storageAccountKey --output json | jq '.properties.copy.status')
      status=$(echo "$status" | tr -d '"')
      echo "Current Status = $status"
 
      progress=$(az storage blob show --container-name $diskcontainer --name $newDataDisk --account-name $newstorageAccountName --account-key $storageAccountKey --output json | jq '.properties.copy.progress')
      echo "Current Progress = $progress"
      sleep 10s
      echo ""
 
      if [ "$status" != "pending" ]; then
      echo "Disk Copy Complete"
      break
      fi
   done
done
 
echo "Script Completed"

}
