# Tanzu Platform for Cloud-Foundry automated install

A powershell script that automates the install of Tanzu Platform for Cloud Foundry (including Tanzu Operations Manager and BOSH Director) on vSphere with minimum resources. The script uses what is known as the Small Footprint Tanzu Platform for Cloud Foundry which is a repackaging of Tanzu Platform for Cloud Foundry into a smaller deployment with fewer VMs which is perfect for POC and sandbox work. Note, there are some limitations with small footprint which can be found [here](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/10-0/tpcf/toc-tas-install-index.html#limits)

For a much more comprehensive automated install of Tanzu Platform for Cloud Foundry, which uses [Concourse](https://concourse-ci.org/), check out the [Platform Automation Toolkit for Tanzu](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/platform-automation-toolkit-for-tanzu/5-2/vmware-automation-toolkit/docs-index.html)

**Update**: The script now has an option to install Tanzu AI Solutions after Tanzu Platform for Cloud Foundry

## High-level flow
- Prepare env
- Download bits
- Add the required data to the powershell script
- Run the script!
  - The script will...
    - Deploy VMware Tanzu Operations Manager (aka Ops Man)
    - Deploy BOSH Director 
    - Deploy Small Footprint Tanzu Platform for Cloud Foundry (aka TPCF)
    - If enabled, will install Tanzu AI Solutions...
      - Deploy VMware Postgres
      - Deploy GenAI for Tanzu Platform

## Prepare env
ESXi host/cluster (ESXi v7.x or v8.x) with the following spare capacity...
- Tanzu Platform for Cloud Foundry
  - Compute: ~18 vCPU, although only uses approx 4 GHz
  - Memory: ~60 GB
  - Storage: ~300GB
- Tanzu Platform for Cloud Foundry & Tanzu AI Solutions
  - Compute: ~40 vCPU, although only uses approx 5 GHz
  - Memory: ~90 GB
  - Storage: ~400GB

Networking
- IP addresses
  - Tanzu Platform for Cloud Foundry
    - A subnet with approximately 10 free IP addresses
      - 1x Ops Man
      - 1x BOSH Director
      - 5x TPCF (gorouter, blobstore, compute, control, database)
      - x various errands, compilations, workers
  - Tanzu Platform for Cloud Foundry & Tanzu AI Solutions
    - A subnet with approximately 20 free IP addresses (and has internet access so can download models from ollama. Airgapped is supported but not covered in this guide. Please see [here](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform-services/genai-on-tanzu-platform-for-cloud-foundry/10-0/ai-cf/tutorials-offline-model-support.html) for offline model support)
      - 1x Ops Man
      - 1x BOSH Director
      - 5x TPCF (gorouter, blobstore, compute, control, database)
      - 3x Postgres (broker, instances)
      - 4x GeAI (controller, workers)
      - x various errands, compilations, workers
  
- DNS
  - 3 records created
    - 1x Tanzu Operations Manager eg opsman.tanzu.lab
    - 1x TPCF system wildcard eg *.sys.tpcf.tanzu.lab which will resolve to the gorouter IP
    - 1x TPCF apps wildcard eg *.apps.tpcf.tanzu.lab which will resolve to the gorouter IP
- NTP service

Workstation/jump-host
- [Powershell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows) or later installed
- [VMware PowerCLI](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/power-cli/latest/powercli/installing-vmware-vsphere-powercli/install-powercli.html) installed eg `Install-Module VMware.PowerCLI -Scope CurrentUser`
- This repo cloned eg `git clone https://github.com/KeithRichardLee/Tanzu-Platform-for-Cloud-Foundry-automated-install.git`

## Download bits
- VMware Tanzu Operations Manager 
	- https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware%20Tanzu%20Operations%20Manager 
- Small Footprint Tanzu Platform for Cloud Foundry 
	- https://support.broadcom.com/group/ecx/productdownloads?subfamily=Tanzu%20Platform%20for%20Cloud%20Foundry
- OM CLI
  - https://github.com/pivotal-cf/om
- VMware Postgres (if installing Tanzu AI Solutions)
  - https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Tanzu+for+Postgres+on+Cloud+Foundry
- GenAI for Tanzu Platform (if installing Tanzu AI Solutions)
  - https://support.broadcom.com/group/ecx/productdownloads?subfamily=GenAI%20on%20Tanzu%20Platform%20for%20Cloud%20Foundry

## Fill out required data in the script
Update each instance of "FILL-ME-IN" in the script. See below for a worked example...

Update the path to the Tanzu Operations Manager OVA, Tanzu Platform for Cloud Foundry Tile, and OM CLI
```bash
# Full Path to Ops Manager OVA, TPCF tile, and OM CLI
$OpsManOVA = "C:\Users\Administrator\Downloads\TPCF\ops-manager-vsphere-3.0.37+LTS-T.ova" 
$TPCFTile = "C:\Users\Administrator\Downloads\TPCF\srt-10.0.2-build.3.pivotal"            
$OMCLI = "C:\Windows\System32\om.exe"
```

Update vSphere env details
```bash
# vCenter Server
$VIServer = "vcsa.tanzu.lab"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "my-super-safe-password!"

# General deployment configuration
$VirtualSwitchType = "VSS" #VSS or VDS
$VMNetwork = "tpcf-network-70" #portgroup name
$VMNetworkCIDR = "10.0.70.0/24"
$VMNetmask = "255.255.255.0"
$VMGateway = "10.0.70.1"
$VMDNS = "10.0.70.1"
$VMNTP = "10.0.70.1"
$VMDatacenter = "Tanzu-DC"
$VMCluster = "Tanzu-Cluster"
$VMResourcePool = "TPCF" #where Ops Manager, Bosh Director, and TPCF will be installed. Create manually.
$VMDatastore = "vsanDatastore"
```

Update Tanzu Operations Manager config
```bash
$OpsManagerDisplayName = "tanzu-ops-manager"
$OpsManagerHostname = "ops-man.tanzu.lab"
$OpsManagerIPAddress = "10.0.70.10"
$OpsManagerPublicSshKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQ.....etc"
$OpsManagerAdminUsername = "admin"
$OpsManagerAdminPassword = "my-super-safe-password!"
$OpsManagerDecryptionPassword = "my-super-safe-password!"
```

Update BOSH Director config
```bash
# BOSH Director configuration 
$BOSHvCenterVMFolder = "tpcf_vms"
$BOSHvCenterTemplateFolder = "tpcf_templates"
$BOSHvCenterDiskFolder = "tpcf_disk"
$BOSHNetworkReservedRange = "10.0.70.0-10.0.70.5,10.0.70.10" # add IPs, either individual and/or ranges you don't want BOSH to use in the subnet eg gateway, Ops Man, DNS/NTP, jumpbox eg 10.0.70.0-10.0.70.2,10.0.70.10
```

Update Tanzu Platform for Cloud Foundry config
```bash
# TPCF configuration
$TPCFGoRouter = "10.0.70.100"
$TPCFDomain = "tpcf.tanzu.lab" # sys and apps subdomain will be added to this
$TPCFCredHubSecret = "my-super-safe-password!" # must be 20 or more characters
$TPCFComputeInstances = "1" # default is 1. Increase if planning to run many large apps
```

If wish to install Tanzu AI Solutions, change the flag to $true and update the following parameters where required
```bash
# Install Tanzu AI Solutions?
$InstallTanzuAI = $false 

# Full Path to Postgres and GenAI tiles (required for Tanzu AI Solutions)
$PostgresTile = "C:\Users\Administrator\Downloads\TPCF\postgres-10.0.0-build.31.pivotal"   #Download from https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Tanzu+for+Postgres+on+Cloud+Foundry
$GenAITile    = "C:\Users\Administrator\Downloads\TPCF\genai-10.0.2.pivotal"               #Download from https://support.broadcom.com/group/ecx/productdownloads?subfamily=GenAI%20on%20Tanzu%20Platform%20for%20Cloud%20Foundry

# Tanzu AI Solutions config 
$OllamaChatModel = "gemma2:2b"
$OllamaEmbedModel = "nomic-embed-text"
```

## Run the script
```bash
.\tanzu-platform-for-cloud-foundry-automated-install.ps1
```

Installation can take up to 1.5 hours (or up to 2.5 hours if installing Tanzu AI Solutions also). Install time depends on the performance of your underlying infrastructure. 

Congratulations you now have installed and configured Tanzu Platform for Cloud Foundry. Let's go see it in action!


## Deploy a sample app
- Retrieve UAA admin credentials
  - Tanzu Operations Manager > Small Footprint Tanzu Platform for Cloud Foundry > Credentials > UAA > Admin Credentials
- Create an Org and a Space using either Apps Manager or cf CLI for where we can deploy a sample app
  - Apps Manager
    - See docs [here](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/10-0/tpcf/console-login.html) on how to access and use Apps Manager 
  - cf CLI
    - [Install cf CLI](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/10-0/tpcf/install-go-cli.html)
    - [Login](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/10-0/tpcf/getting-started.html) eg
      - `cf login -a api.sys.tpcf.tanzu.lab --skip-ssl-validation`
    - Create an Org eg
      - `cf create-org tanzu-demos-org`
    - Create a Space eg
      - `cf create-space demos-space -o tanzu-demos-org`
    - Target an Org and Space eg
      - `cf target -o tanzu-demos-org -s demos-space`
- Deploy a sample app
  - Download spring-music
    - `git clone https://github.com/cloudfoundry-samples/spring-music.git`
  - Build jar file
    - ```
      cd spring-music
      ./gradlew clean assemble
      ```
  - Run app
    - `cf push`
  - Verify app is running, retrieve route, and open app
    - `cf apps` 

## Tanzu AI Solutions
If you opted to install Tanzu AI Solutions, check out these guides [here](https://github.com/KeithRichardLee/VMware-Tanzu-Guides) to learn more about it and deploy sample apps
