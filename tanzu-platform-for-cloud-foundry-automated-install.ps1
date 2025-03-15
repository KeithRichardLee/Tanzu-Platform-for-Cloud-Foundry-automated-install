# PowerShell script which results in the deployment of VMware Tanzu Platform for Cloud Foundry
# 
# Script will... 
# - Deploy VMware Tanzu Operations Manager
# - Configure authentication for VMware Tanzu Operations Manager
# - Configure and deploy BOSH Director
# - Configure and deploy VMware Tanzu Platform for Cloud Foundry (aka TPCF)
# - Optionally
#    - Configure and deploy VMware Postgres
#    - Configure and deploy GenAI on Tanzu Platform
#    - Configuer and deploy Tanzu Kubernetes Grid integrated edition (aka TKGi)
#
# Script based off the orginal work of William Lam's (Broadcom) nested vSphere 6 PKS with NSX lab https://github.com/lamw/vmware-pks-automated-lab-deployment/

# Full Path to Ops Manager OVA, TPCF tile, and OM CLI
$OpsManOVA = "C:\Users\Administrator\Downloads\TPCF\ops-manager-vsphere-3.0.37+LTS-T.ova"  #Download from https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware%20Tanzu%20Operations%20Manager
$TPCFTile  = "C:\Users\Administrator\Downloads\TPCF\srt-10.0.2-build.3.pivotal"            #Download from https://support.broadcom.com/group/ecx/productdownloads?subfamily=Tanzu%20Platform%20for%20Cloud%20Foundry
$OMCLI     = "C:\Windows\System32\om.exe"                                                  #Download from https://github.com/pivotal-cf/om

# vCenter Server
$VIServer = "FILL-ME-IN"
$VIUsername = "FILL-ME-IN"
$VIPassword = "FILL-ME-IN"

# General deployment configuration
$VirtualSwitchType = "VSS" #VSS or VDS
$VMNetwork = "FILL-ME-IN" #portgroup name
$VMNetworkCIDR = "FILL-ME-IN" # eg "10.0.70.0/24"
$VMNetmask = "FILL-ME-IN"
$VMGateway = "FILL-ME-IN"
$VMDNS = "FILL-ME-IN"
$VMNTP = "FILL-ME-IN"
$VMDatacenter = "FILL-ME-IN"
$VMCluster = "FILL-ME-IN"
$VMResourcePool = "FILL-ME-IN" #where Ops Manager and TPCF will be installed. Create manually.
$VMDatastore = "FILL-ME-IN"

# Ops Manager config
$OpsManagerDisplayName = "tanzu-ops-manager"
$OpsManagerHostname = "FILL-ME-IN"
$OpsManagerIPAddress = "FILL-ME-IN"
$OpsManagerNetmask = $VMNetmask
$OpsManagerGateway = $VMGateway
$OpsManagerPublicSshKey = "FILL-ME-IN"
$OpsManagerAdminUsername = "admin"
$OpsManagerAdminPassword = "FILL-ME-IN"
$OpsManagerDecryptionPassword = "FILL-ME-IN"

# BOSH Director configuration 
$BOSHvCenterUsername = $VIUsername
$BOSHvCenterPassword = $VIPassword
$BOSHvCenterDatacenter = $VMDatacenter
$BOSHvCenterPersistentDatastores = $VMDatastore
$BOSHvCenterEpemeralDatastores = $VMDatastore
$BOSHvCenterVMFolder = "tpcf_vms"
$BOSHvCenterTemplateFolder = "tpcf_templates"
$BOSHvCenterDiskFolder = "tpcf_disk"
$BOSHNetworkReservedRange = "FILL-ME-IN" #add IPs, either individual and/or ranges you don't want BOSH to use in the subnet eg gateway, Ops Man, DNS/NTP, jumpbox eg 10.0.70.0-10.0.70.2,10.0.70.10

# AZ Definitions
$BOSHAZ = @{
    "az1" = @{
        iaas_name = "vCenter"
        cluster = $VMCluster
        resource_pool = $VMResourcePool
    }
}

# Network Definitions
$BOSHNetwork = @{
    "tpcf-network" = @{
        portgroupname = $VMNetwork 
        cidr = $VMNetworkCIDR
        reserved_range = $BOSHNetworkReservedRange
        dns = $VMDNS
        gateway = $VMGateway
        az = "az1"
    }
}

$BOSHAZAssignment = "az1"
$BOSHNetworkAssignment = "tpcf-network"

#######################################
# Tanzu Platform for Cloud Foundry (TPCF) configuration
$TPCFGoRouter = "FILL-ME-IN"
$TPCFDomain = "FILL-ME-IN" # sys and apps subdomain will be added to this
$TPCFCredHubSecret = "FILL-ME-IN" # must be 20 or more characters
$TPCFAZ = $BOSHAZAssignment
$TPCFNetwork = $BOSHNetworkAssignment
$TPCFComputeInstances = "1" # default is 1. Increase if planning to run many large apps

#######################################
# Install Tanzu AI Solutions?
$InstallTanzuAI = $false 

# Full Path to Postgres and GenAI tiles (required for Tanzu AI Solutions)
$PostgresTile = "C:\Users\Administrator\Downloads\TPCF\postgres-10.0.0-build.31.pivotal"   #Download from https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Tanzu+for+Postgres+on+Cloud+Foundry
$GenAITile    = "C:\Users\Administrator\Downloads\TPCF\genai-10.0.2.pivotal"               #Download from https://support.broadcom.com/group/ecx/productdownloads?subfamily=GenAI%20on%20Tanzu%20Platform%20for%20Cloud%20Foundry

# Tanzu AI Solutions config 
$OllamaChatModel = "gemma2:2b"
$OllamaEmbedModel = "nomic-embed-text"

#######################################
# Install Tanzu Kubernetes Grid integrated edition (TKGi)?
$InstallTKGI = $false

# Full Path to TKGi tile
$TKGITile = "C:\Users\Administrator\Downloads\TPCF\pivotal-container-service-1.21.0-build.32.pivotal"   #Download from https://support.broadcom.com/group/ecx/productdownloads?subfamily=Tanzu%20Kubernetes%20Grid%20Integrated%20Edition%20(TKGi)%20-%20CLI%20%26%20Tile 

# TKGi config
$TKGIDomain = "FILL-ME-IN" # TKGi and TKGi API domain

#######################################
#### DO NOT EDIT BEYOND HERE ####

$debug = $false
$verboseLogFile = "tanzu-platform-for-cloud-foundry-deployment.log"

$preCheck = 1
$confirmDeployment = 1
$deployOpsManager = 1
$setupOpsManager = 1
$setupBOSHDirector = 1
$setupTPCF = 1
$setupPostgres = $InstallTanzuAI
$setupGenAI = $InstallTanzuAI
$setupTKGI = $InstallTKGI

$StartTime = Get-Date

Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )

    $timeStamp = Get-Date -Format "dd-MM-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}


if($preCheck -eq 1) {
    if(!(Test-Path $OMCLI)) {
        Write-Host -ForegroundColor Red "`nUnable to find $OMCLI ...`nexiting"
        exit
    }

    if(!(Test-Path $OpsManOVA)) {
        Write-Host -ForegroundColor Red "`nUnable to find $OpsManOVA ...`nexiting"
        exit
    }

    if(!(Test-Path $TPCFTile)) {
        Write-Host -ForegroundColor Red "`nUnable to find $TPCFTile ...`nexiting"
        exit
    }

    if(!(Test-Path $PostgresTile) -and $InstallTanzuAI -eq $true) {
        Write-Host -ForegroundColor Red "`nUnable to find $PostgresTile ...`nexiting"
        exit
    }

    if(!(Test-Path $GenAITile) -and $InstallTanzuAI -eq $true) {
        Write-Host -ForegroundColor Red "`nUnable to find $GenAITile ...`nexiting"
        exit
    }

    if(!(Test-Path $TKGITile) -and $InstallTKGI -eq $true) {
        Write-Host -ForegroundColor Red "`nUnable to find $TKGITile ...`nexiting"
        exit
    }
}

if($confirmDeployment -eq 1) {
    Write-Host -ForegroundColor Magenta "`nPlease confirm the following configuration will be deployed:`n"

    Write-Host -ForegroundColor Yellow "---- VMware Tanzu for Cloud Foundry required files ---- "
    Write-Host -NoNewline -ForegroundColor Green "Tanzu Ops Manager OVA path: "
    Write-Host -ForegroundColor White $OpsManOVA
    Write-Host -NoNewline -ForegroundColor Green "TPCF tile path: "
    Write-Host -ForegroundColor White $TPCFTile
    Write-Host -NoNewline -ForegroundColor Green "OM CLI path: "
    Write-Host -ForegroundColor White $OMCLI

    Write-Host -ForegroundColor Yellow "`n---- vCenter Configuration ----"
    Write-Host -NoNewline -ForegroundColor Green "vCenter Server: "
    Write-Host -ForegroundColor White $VIServer
    Write-Host -NoNewline -ForegroundColor Green "Datacenter: "
    Write-Host -ForegroundColor White $VMDatacenter
    Write-Host -NoNewline -ForegroundColor Green "Datastore: "
    Write-Host -ForegroundColor White $VMDatastore
    Write-Host -NoNewline -ForegroundColor Green "Disk Type: "
    Write-Host -ForegroundColor White "Thin"
    Write-Host -NoNewline -ForegroundColor Green "VMs folder: "
    Write-Host -ForegroundColor White $BOSHvCenterVMFolder
    Write-Host -NoNewline -ForegroundColor Green "Templates folder: "
    Write-Host -ForegroundColor White $BOSHvCenterTemplateFolder
    Write-Host -NoNewline -ForegroundColor Green "Disks folder: "
    Write-Host -ForegroundColor White $BOSHvCenterDiskFolder
	
    Write-Host -ForegroundColor Yellow "`n---- BOSH Director Configuration ----"
    Write-Host -ForegroundColor Green "AZ Config"
    Write-Host -NoNewline -ForegroundColor Green "AZ name: "
    Write-Host -ForegroundColor White $BOSHAZ.Keys
    Write-Host -NoNewline -ForegroundColor Green "AZ Cluster: "
    Write-Host -ForegroundColor White $($BOSHAZ[$BOSHAZAssignment].cluster)
    Write-Host -NoNewline -ForegroundColor Green "AZ Resource Pool: "
    Write-Host -ForegroundColor White $($BOSHAZ[$BOSHAZAssignment].resource_pool)
    
    Write-Host -ForegroundColor Green "`nNetwork Config"
    Write-Host -NoNewline -ForegroundColor Green "Network name: "
    Write-Host -ForegroundColor White $BOSHNetwork.Keys
    Write-Host -NoNewline -ForegroundColor Green "Network Portgroup: "
    Write-Host -ForegroundColor White $($BOSHNetwork[$BOSHNetworkAssignment].portgroupname)	
    Write-Host -NoNewline -ForegroundColor Green "Network CIDR: "
    Write-Host -ForegroundColor White $($BOSHNetwork[$BOSHNetworkAssignment].cidr)
    Write-Host -NoNewline -ForegroundColor Green "Network Gateway: "
    Write-Host -ForegroundColor White $($BOSHNetwork[$BOSHNetworkAssignment].gateway)
    Write-Host -NoNewline -ForegroundColor Green "Network DNS: "
    Write-Host -ForegroundColor White $($BOSHNetwork[$BOSHNetworkAssignment].dns)
    Write-Host -NoNewline -ForegroundColor Green "Reserved IP range: "
    Write-Host -ForegroundColor White $($BOSHNetwork[$BOSHNetworkAssignment].reserved_range)

    Write-Host -NoNewline -ForegroundColor Green "`nNTP: "
    Write-Host -ForegroundColor White $VMNTP
    Write-Host -NoNewline -ForegroundColor Green "Enable human readable names: "
    Write-Host -ForegroundColor White "True"
    Write-Host -NoNewline -ForegroundColor Green "ICMP checks enabled: "
    Write-Host -ForegroundColor White "True"
    Write-Host -NoNewline -ForegroundColor Green "Include Tanzu Ops Manager Root CA in Trusted Certs: "
    Write-Host -ForegroundColor White "True"

    Write-Host -ForegroundColor Yellow "`n---- TPCF Configuration ----"
    Write-Host -NoNewline -ForegroundColor Green "AZ: "
    Write-Host -ForegroundColor White $BOSHAZ.Keys
    Write-Host -NoNewline -ForegroundColor Green "Network: "
    Write-Host -ForegroundColor White $BOSHNetwork.Keys
    Write-Host -NoNewline -ForegroundColor Green "System Domain: "
    Write-Host -ForegroundColor White "sys.$TPCFDomain"
    Write-Host -NoNewline -ForegroundColor Green "Apps Domain: "
    Write-Host -ForegroundColor White "apps.$TPCFDomain"
    Write-Host -NoNewline -ForegroundColor Green "GoRouter IP: "
    Write-Host -ForegroundColor White $TPCFGoRouter
    Write-Host -NoNewline -ForegroundColor Green "GoRouter wildcard cert SAN: "
    $domainlist = "*.apps.$TPCFDomain,*.login.sys.$TPCFDomain,*.uaa.sys.$TPCFDomain,*.sys.$TPCFDomain,*.$TPCFDomain"    
    Write-Host -ForegroundColor White $domainlist

    Write-Host -NoNewline -ForegroundColor Green "`nInstall Tanzu AI Solutions: "
    if($InstallTanzuAI -eq 1) {
        Write-Host -ForegroundColor White "Yes"
        Write-Host -ForegroundColor Yellow "`n---- Tanzu AI Solutions Configuration ----"
        Write-Host -NoNewline -ForegroundColor Green "Postgres tile path: "
        Write-Host -ForegroundColor White $PostgresTile
        Write-Host -NoNewline -ForegroundColor Green "GenAI tile path: "
        Write-Host -ForegroundColor White $GenAITile
        Write-Host -NoNewline -ForegroundColor Green "Ollama Chat Model: "
        Write-Host -ForegroundColor White $OllamaChatModel
        Write-Host -NoNewline -ForegroundColor Green "Ollama embedding model: "
        Write-Host -ForegroundColor White $OllamaEmbedModel
    } else {
        Write-Host -ForegroundColor White "No"
    }

    Write-Host -NoNewline -ForegroundColor Green "`nInstall Tanzu Kubernetes Grid integrated edition: "
    if($InstallTKGI -eq 1) {
        Write-Host -ForegroundColor White "Yes"
        Write-Host -ForegroundColor Yellow "`n---- TKGi Configuration ----"
        Write-Host -NoNewline -ForegroundColor Green "TKGi tile path: "
        Write-Host -ForegroundColor White $TKGITile
        Write-Host -NoNewline -ForegroundColor Green "TKGi domain: "
        Write-Host -ForegroundColor White $TKGIDomain
    } else {
        Write-Host -ForegroundColor White "No"
    }

    Write-Host -ForegroundColor Magenta "`nWould you like to proceed with this deployment?`n"
    $answer = Read-Host -Prompt "Do you accept (Y or N)"
    if($answer -ne "Y" -or $answer -ne "y") {
        exit
    }
    Clear-Host
}

if($deployOpsManager -eq 1) {
    My-Logger "Connecting to vCenter Server: $VIServer ..."
    $viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

    $datastore = Get-Datastore -Server $viConnection -Name $VMDatastore | Select -First 1
    if($VirtualSwitchType -eq "VSS") {
        $network = Get-VirtualPortGroup -Server $viConnection -Name $VMNetwork | Select -First 1
    } else {
        $network = Get-VDPortgroup -Server $viConnection -Name $VMNetwork | Select -First 1
    }
    $cluster = Get-Cluster -Server $viConnection -Name $VMCluster
    $datacenter = $cluster | Get-Datacenter
    $vmhost = $cluster | Get-VMHost | Select -First 1
    $resourcepool = Get-ResourcePool -Server $viConnection -Name $VMResourcePool
	
    # future work, change below to use "om vm-lifecycle create-vm"
	
    # Deploy Ops Manager
    $opsMgrOvfCOnfig = Get-OvfConfiguration $OpsManOVA
    $opsMgrOvfCOnfig.Common.ip0.Value = $OpsManagerIPAddress
    $opsMgrOvfCOnfig.Common.netmask0.Value = $OpsManagerNetmask
    $opsMgrOvfCOnfig.Common.gateway.Value = $OpsManagerGateway
    $opsMgrOvfCOnfig.Common.DNS.Value = $VMDNS
    $opsMgrOvfCOnfig.Common.ntp_servers.Value = $VMNTP
    $opsMgrOvfCOnfig.Common.public_ssh_key.Value = $OpsManagerPublicSshKey
    $opsMgrOvfCOnfig.Common.custom_hostname.Value = $OpsManagerHostname
    $opsMgrOvfCOnfig.NetworkMapping.Network_1.Value = $VMNetwork

    My-Logger "Deploying Tanzu Ops Manager ..."
    $opsmgr_vm = Import-VApp -Source $OpsManOVA -OvfConfiguration $opsMgrOvfCOnfig -Name $OpsManagerDisplayName -Location $resourcepool -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

    My-Logger "Powering on Tanzu Ops Manager ..."
    $opsmgr_vm | Start-Vm -RunAsync | Out-Null
}


if($setupOpsManager -eq 1) {
    My-Logger "Waiting for Tanzu Ops Manager to come online ..."
	while (1) {
		try {
			$results = Invoke-WebRequest -Uri https://$OpsManagerHostname -SkipCertificateCheck -Method GET
			if ($results.StatusCode -eq 200) {
				break
			}
		} catch {
			My-Logger "Tanzu Ops Manager is not ready yet, sleeping 30 seconds ..."
			Start-Sleep 30
		}
	}	
	
    My-Logger "Setting up Tanzu Ops Manager authentication ..."
      
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword configure-authentication --username $OpsManagerAdminUsername --password $OpsManagerAdminPassword --decryption-passphrase $OpsManagerDecryptionPassword"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile
}


if($setupBOSHDirector -eq 1) {
    My-Logger "Creating BOSH Director configuration ..."

    # Create BOSH config yaml 
    $boshPayloadStart = @"
---
az-configuration:

"@
    # Process AZ
    $singleAZString = ""
	$BOSHAZ.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
		$singleAZString += "- name: "+$_.Name+"`n"
		$singleAZString += "  iaas_configuration_name: "+$_.Value['iaas_name']+"`n"
		$singleAZString += "  clusters:`n"
		$singleAZString += "  - cluster: "+$_.Value['cluster']+"`n"
		$singleAZString += "    resource_pool: "+$_.Value['resource_pool']+"`n"
    }

    # Process Networks
    $boshPayloadNetwork = @"
networks-configuration:
  icmp_checks_enabled: true
  networks:

"@
    $singleNetworkString = ""
    $BOSHNetwork.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
        $singleNetworkString += "  - name: "+$_.Name+"`n"
        $singleNetworkString += "    subnets:`n"
        $singleNetworkString += "    - iaas_identifier: "+$_.Value['portgroupname']+"`n"
        $singleNetworkString += "      cidr: "+$_.Value['cidr']+"`n"
        $singleNetworkString += "      gateway: "+$_.Value['gateway']+"`n"
        $singleNetworkString += "      dns: "+$_.Value['dns']+"`n"
        $singleNetworkString += "      cidr: "+$_.Value['cidr']+"`n"
        $singleNetworkString += "      reserved_ip_ranges: "+$_.Value['reserved_range']+"`n"
        $singleNetworkString += "      availability_zone_names:`n"
        $singleNetworkString += "      - "+$_.Value['az']+"`n"
    }

    # Concat Network config
    $boshPayloadNetwork += $singleNetworkString

    # Process remainder configs
    $boshPayloadEnd = @"
network-assignment:
  network:
    name: $BOSHNetworkAssignment
  singleton_availability_zone:
    name: $BOSHAZAssignment
iaas-configurations:
- name: vCenter
  vcenter_host: $VIServer
  vcenter_username: $BOSHvCenterUsername
  vcenter_password: $BOSHvCenterPassword
  datacenter: $BOSHvCenterDatacenter
  disk_type: thin
  ephemeral_datastores_string: $BOSHvCenterEpemeralDatastores
  persistent_datastores_string: $BOSHvCenterPersistentDatastores
  nsx_networking_enabled: false
  avi_load_balancer_enabled: false
  bosh_vm_folder: $BOSHvCenterVMFolder
  bosh_template_folder: $BOSHvCenterTemplateFolder
  bosh_disk_path: $BOSHvCenterDiskFolder
  enable_human_readable_name: true
properties-configuration:
  director_configuration:
    ntp_servers_string: $VMNTP
    post_deploy_enabled: true
  security_configuration:
    generate_vm_passwords: true
    opsmanager_root_ca_trusted_certs: true
"@

    # Concat configuration to form final YAML
    $boshPayload = $boshPayloadStart + $singleAZString + $boshPayloadNetwork + $boshPayloadEnd

    $boshYaml = "bosh-director-config.yaml"
    $boshPayload > $boshYaml

    My-Logger "Applying BOSH Director configuration ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword configure-director --config $boshYaml"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile

    My-Logger "Installing BOSH Director (can take up to 15 minutes) ..."
    $installArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword apply-changes"
    if($debug) { My-Logger "${OMCLI} $installArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $installArgs -Wait -RedirectStandardOutput $verboseLogFile
	
}


if($setupTPCF -eq 1) {
    
    # Get product name and version
    $TPCFProductName = & "$OMCLI" product-metadata --product-path $TPCFTile --product-name
    $TPCFVersion = & "$OMCLI" product-metadata --product-path $TPCFTile --product-version

    # Upload tile
    My-Logger "Uploading TPCF tile to Tanzu Ops Manager (can take up to 15 mins) ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword upload-product --product $TPCFTile"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile

    # Stage tile
    My-Logger "Adding TPCF tile to Tanzu Ops Manager ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword stage-product --product-name $TPCFProductName --product-version $TPCFVersion"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile
	
	
    # Generate wildcard cert and key
    $domainlist = "*.apps.$TPCFDomain,*.login.sys.$TPCFDomain,*.uaa.sys.$TPCFDomain,*.sys.$TPCFDomain,*.$TPCFDomain"
    $TPCFcert_and_key = & "$OMCLI" -k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword generate-certificate -d $domainlist
	
    $pattern = "-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\\n"
    $TPCFcert = [regex]::Match($TPCFcert_and_key, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
	
    $pattern = "-----BEGIN RSA PRIVATE KEY-----.*?-----END RSA PRIVATE KEY-----\\n"
    $TPCFkey = [regex]::Match($TPCFcert_and_key, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    
    # Create TPCF config yaml
    $TPCFPayload = @"
---
product-name: cf
network-properties:
  singleton_availability_zone:
    name: $TPCFAZ
  other_availability_zones:
  - name: $TPCFAZ
  network:
    name: $TPCFNetwork
product-properties:
  .cloud_controller.system_domain:
    value: sys.$TPCFDomain
  .cloud_controller.apps_domain:
    value: apps.$TPCFDomain
  .router.static_ips:
    value: $TPCFGoRouter
  .properties.networking_poe_ssl_certs:
    value:
    - name: gorouter-cert
      certificate:
        cert_pem: "$TPCFcert"
        private_key_pem: "$TPCFkey"
  .properties.routing_tls_termination:
    value: router
  .properties.security_acknowledgement:
    value: X
  .uaa.service_provider_key_credentials:
    value:
      cert_pem: "$TPCFcert"
      private_key_pem: "$TPCFkey"
  .properties.credhub_internal_provider_keys:
    value:
    - name: Internal-encryption-provider-key
      key:
        secret: $TPCFCredHubSecret
      primary: true
resource-config:
  backup_restore:
    instances: 0
  mysql_monitor:
    instances: 0
  compute:
    instances: $TPCFComputeInstances
"@	

    $TPCFyaml = "tpcf-config.yaml"
    $TPCFPayload > $TPCFyaml	
	
    My-Logger "Applying TPCF configuration ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword configure-product --config $TPCFyaml"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile

    # To improve install time, don't install TPCF just yet if postgres and GenAI tiles are to be installed also
    if($InstallTanzuAI -eq 0) {
        My-Logger "Installing TPCF (can take up to 60 minutes) ..."
        $installArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword apply-changes"
        if($debug) { My-Logger "${OMCLI} $installArgs"}
        $output = Start-Process -FilePath $OMCLI -ArgumentList $installArgs -Wait -RedirectStandardOutput $verboseLogFile
    } 

}

if($setupPostgres -eq 1) {

   # Get product name and version
   $PostgresProductName = & "$OMCLI" product-metadata --product-path $PostgresTile --product-name
   $PostgresVersion = & "$OMCLI" product-metadata --product-path $PostgresTile --product-version

    # Upload tile
    My-Logger "Uploading Postgres tile to Tanzu Ops Manager ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword upload-product --product $PostgresTile"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile

    # Stage tile
    My-Logger "Adding Postgres tile to Tanzu Ops Manager ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword stage-product --product-name $PostgresProductName --product-version $PostgresVersion"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile	
	
    # Create Postgres config yaml
    $PostgresPayload = @"
---
product-name: postgres
product-properties:
  .properties.plan_collection:
    value:
    - az_multi_select:
      - $BOSHAZAssignment
      cf_service_access: enable
      name: on-demand-postgres-db
network-properties:
  network:
    name: $BOSHNetworkAssignment
  other_availability_zones:
  - name: $BOSHAZAssignment
  service_network:
    name: $BOSHNetworkAssignment
  singleton_availability_zone:
    name: $BOSHAZAssignment
"@	


    $Postgresyaml = "postgres-config.yaml"
    $PostgresPayload > $Postgresyaml	
	
    My-Logger "Applying Postgres configuration ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword configure-product --config $Postgresyaml"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile

    My-Logger "Installing TPCF and Postgres (can take up to 75 minutes) ..."
    $installArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword apply-changes"
    if($debug) { My-Logger "${OMCLI} $installArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $installArgs -Wait -RedirectStandardOutput $verboseLogFile
}

if($setupGenAI -eq 1) {

    # Get product name and version
    $GenAIProductName = & "$OMCLI" product-metadata --product-path $GenAITile --product-name
    $GenAIVersion = & "$OMCLI" product-metadata --product-path $genAITile --product-version

    # Upload tile
    My-Logger "Uploading GenAI tile to Tanzu Ops Manager ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword upload-product --product $GenAITile"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile

    # Stage tile
    My-Logger "Adding GenAI tile to Tanzu Ops Manager ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword stage-product --product-name $GenAIProductName --product-version $GenAIVersion"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile	
	
    # Create GenAI config yaml
    $GenAIPayload = @"
---
product-name: genai
product-properties:
  .errands.ollama_models:
    value:
    - azs:
      - $BOSHAZAssignment
      model_capabilities:
      - chat
      model_name: $OllamaChatModel
      vm_type: cpu
    - azs:
      - $BOSHAZAssignment
      model_capabilities:
      - embedding
      model_name: $OllamaEmbedModel
      vm_type: cpu
  .properties.database_source.service_broker.name:
    value: postgres
  .properties.database_source.service_broker.plan_name:
    value: on-demand-postgres-db
network-properties:
  network:
    name: $BOSHNetworkAssignment
  other_availability_zones:
  - name: $BOSHAZAssignment
  service_network:
    name: $BOSHNetworkAssignment
  singleton_availability_zone:
    name: $BOSHAZAssignment

"@	

    $GenAIyaml = "genai-config.yaml"
    $GenAIPayload > $GenAIyaml	
	
    My-Logger "Applying GenAI configuration ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword configure-product --config $GenAIyaml"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile

    My-Logger "Installing GenAI (can take up to 40 minutes) ..."
    $installArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword apply-changes --product-name $GenAIProductName"
    if($debug) { My-Logger "${OMCLI} $installArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $installArgs -Wait -RedirectStandardOutput $verboseLogFile

}


if($setupTKGI -eq 1) {
	
    # Get product name and version
    $TKGIProductName = & "$OMCLI" product-metadata --product-path $TKGITile --product-name
    $TKGIVersion = & "$OMCLI" product-metadata --product-path $TKGITile --product-version

    # Upload tile 
    My-Logger "Uploading TKGi tile to Tanzu Ops Manager ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword upload-product --product $TKGITile"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile
    
    # Stage tile
    My-Logger "Adding TKGi tile to Tanzu Ops Manager ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword stage-product --product-name $TKGIProductName --product-version $TKGIVersion"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile
	
	
   # Generate wildcard cert and key
    $domainlist = "*.$TKGIDomain"
    $TKGIcert_and_key = & "$OMCLI" -k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword generate-certificate -d $domainlist
	
    $pattern = "-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\\n"
    $TKGIcert = [regex]::Match($TKGIcert_and_key, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
	
    $pattern = "-----BEGIN RSA PRIVATE KEY-----.*?-----END RSA PRIVATE KEY-----\\n"
    $TKGIkey = [regex]::Match($TKGIcert_and_key, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    
    # Create TKGI config yaml
    $TKGIPayload = @"
---
product-name: pivotal-container-service
product-properties:
  .pivotal-container-service.pks_tls:
    value:
      cert_pem: "$TKGIcert"
      private_key_pem: "$TKGIkey"
  .properties.pks_api_hostname:
    value: api.$TKGIDomain
  .properties.cloud_provider:
    value: vSphere
  .properties.cloud_provider.vsphere.vcenter_ip:
    value: $VIServer
  .properties.cloud_provider.vsphere.vcenter_master_creds:
    value:
      identity: $BOSHvCenterUsername 
      password: $BOSHvCenterPassword
  .properties.cloud_provider.vsphere.vcenter_dc:
    value: $BOSHvCenterDatacenter
  .properties.cloud_provider.vsphere.vcenter_ds:
    value: $BOSHvCenterPersistentDatastores
  .properties.cloud_provider.vsphere.vcenter_vms:
    value: $BOSHvCenterVMFolder
  .properties.plan1_selector:
    selected_option: active
    value: Plan Active
  .properties.plan1_selector.active.master_az_placement:
    value:
    - $BOSHAZAssignment
  .properties.plan1_selector.active.worker_az_placement:
    value:
    - $BOSHAZAssignment
  .properties.telemetry_installation_purpose_selector:
    value: not_provided
network-properties:
  network:
    name: $BOSHNetworkAssignment
  other_availability_zones:
  - name: $BOSHAZAssignment
  service_network:
    name: $BOSHNetworkAssignment
  singleton_availability_zone:
    name: $BOSHAZAssignment
errand-config:
  smoke-tests:
    post-deploy-state: true
"@

    $TKGIyaml = "tkgi-config.yaml"
    $TKGIPayload > $TKGIyaml	
	
    My-Logger "Applying TKGi configuration ..."
    $configArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword configure-product --config $TKGIyaml"
    if($debug) { My-Logger "${OMCLI} $configArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $configArgs -Wait -RedirectStandardOutput $verboseLogFile

    My-Logger "Installing TKGi (can take up to 40 minutes) ..."
    $installArgs = "-k -t $OpsManagerHostname -u $OpsManagerAdminUsername -p $OpsManagerAdminPassword apply-changes --product-name $TKGIProductName"
    if($debug) { My-Logger "${OMCLI} $installArgs"}
    $output = Start-Process -FilePath $OMCLI -ArgumentList $installArgs -Wait -RedirectStandardOutput $verboseLogFile

}

$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "Tanzu Platform for Cloud Foundry deployment complete!"
My-Logger "StartTime: $StartTime"
My-Logger "  EndTime: $EndTime"
My-Logger " Duration: $duration minutes"
