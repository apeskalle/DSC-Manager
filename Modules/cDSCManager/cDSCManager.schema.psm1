#Creates the Certificate Store if missing.
function Install-DSCMCertStores
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][String]$FileName = "$env:PROGRAMFILES\WindowsPowershell\DscService\Management\dscnodes.csv",
        [Parameter(Mandatory=$false)][String]$CertStore = "$env:PROGRAMFILES\WindowsPowershell\DscService\NodeCertificates",
        [Parameter(Mandatory=$false)][String]$AgentRegistration = "$env:PROGRAMFILES\WindowsPowershell\DscService\AgentRegistration",
        [switch]$TestOnly
        )

    [bool]$IsValid=$true
    [string]$Domain=(gwmi Win32_NTDomain).DomainName
    $Domain = $Domain.Trim()


    If($CertStore -and !(Test-Path -Path ($CertStore)))
        {
        If ($TestOnly) {
            [bool]$isValid=$false
            }
        else {
            try {
                New-Item ($CertStore) -type directory -force -ErrorAction STOP | Out-Null
                New-SmbShare -Name "CertStore" -Path $CertStore -ChangeAccess Everyone | Out-Null
                $acl = get-acl $CertStore
                $inherit = [system.security.accesscontrol.InheritanceFlags]"ContainerInherit, ObjectInherit"
                $propagation = [system.security.accesscontrol.PropagationFlags]"None"
                $rule = new-object System.Security.AccessControl.FileSystemAccessRule("$Domain\Domain Computers","Modify",$inherit,$propagation,"Allow")
                $acl.SetAccessRule($rule)
                set-acl $CertStore $acl
                }
            catch {
                $E = $_.Exception.GetBaseException()
                $E.ErrorInformation.Description
                }
            }
        }

    If($FileName -and !(Test-Path -Path ($FileName)))
        {
        If ($TestOnly) {
            [bool]$IsValid=$false
            }
        else {
            try {
                New-Item ($FileName) -type file -force -ErrorAction STOP | Out-Null
                $NewLine = "NodeName,NodeGUID,Thumbprint"
                $NewLine | add-content -path $FileName -ErrorAction STOP
                }
            catch {
                $E = $_.Exception.GetBaseException()
                $E.ErrorInformation.Description
                }
            }
        }

    If($AgentRegistration -and !(Test-Path -Path ($AgentRegistration)))
        {
        If ($TestOnly) {
            [bool]$IsValid=$false
            }
        else {
            try {
                New-Item ($AgentRegistration) -type directory -force -ErrorAction STOP | Out-Null
                New-SmbShare -Name "AgentRegistration" -Path $AgentRegistration -ChangeAccess Everyone | Out-Null
                $acl = get-acl $AgentRegistration
                $inherit = [system.security.accesscontrol.InheritanceFlags]"ContainerInherit, ObjectInherit"
                $propagation = [system.security.accesscontrol.PropagationFlags]"None"
                $rule = new-object System.Security.AccessControl.FileSystemAccessRule("$Domain\Domain Computers","Modify",$inherit,$propagation,"Allow")
                $acl.SetAccessRule($rule)
                set-acl $AgentRegistration $acl
                }
            catch {
                $E = $_.Exception.GetBaseException()
                $E.ErrorInformation.Description
                }
            }
        }

    If ($TestOnly) {return $IsValid}
}

#This function is to update and maintain the Host-to-GUID mapping table
function Update-DSCMTable
{
    [CmdletBinding()]
    param(
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)][Alias("FileName")][String]$PullServerNodeCSV = "$env:PROGRAMFILES\WindowsPowershell\DscService\Management\dscnodes.csv",
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)][Alias("CertStore")][String]$PullServerCertStore = "$env:PROGRAMFILES\WindowsPowershell\DscService\NodeCertificates",
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][String]$ConfigurationDataFile,
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][String]$ConfigurationData,
    [Parameter(ValueFromRemainingArguments = $true)]$Splat
    )

    #Load ConfigurationData file found into memory and execute updates
    Try {
        . $ConfigurationDataFile
        Invoke-Expression "`$CompiledData =`$$ConfigurationData"
        }
    Catch {
        Throw "Cannot find configuration data file $ConfigurationDataFile"
        }

    #Update CSVTable By calling other functions
    IF ($CompiledData) {
        $CompiledData.AllNodes | where-object {$_.NodeName -ne "*"} | ForEach-Object -Process {
            $CurrNode = $_.NodeName
            Update-DSCMGUIDMapping -NodeName $CurrNode -FileName $PullServerNodeCSV -Silent
            Update-DSCMCertMapping -NodeName $CurrNode -FileName $PullServerNodeCSV -CertStore $PullServerCertStore -Silent
            }
        }
    Else {
        Throw "Cannot find the variable $ConfigurationData"
        }
}

#This function returns an updated hashtable with GUID and cert information
function Update-DSCMConfigurationData
{
    [CmdletBinding()]
    param(
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)][Alias("PullServerNodeCSV")][String]$FileName = "$env:PROGRAMFILES\WindowsPowershell\DscService\Management\dscnodes.csv",
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)][Alias("PullServerCertStore")][String]$CertStore = "$env:PROGRAMFILES\WindowsPowershell\DscService\NodeCertificates",
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)][String]$PasswordData = "$env:PROGRAMFILES\WindowsPowershell\DscService\Management\passwords.xml",
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][String]$ConfigurationDataFile,
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][String]$ConfigurationData
    )

    #Load ConfigurationData file found into memory and execute updates
    $ReturnData = $null
    $Wildcardinjection = $null

    Try {
        . $ConfigurationDataFile
        $ReturnData = Invoke-Expression "`$$ConfigurationData"
        }
    Catch {
        Throw "Cannot find configuration data file $ConfigurationDataFile"
        }
    
    #Load Passwords into the wildcard object to merge into ConfigData
    IF ($ReturnData.AllNodes.Where({$_.NodeName -eq "*"})) {
         #$Wildcardinjection = $ReturnData.AllNodes.Where({$_.NodeName -eq "*"})
        $returndata.AllNodes | ForEach-Object { IF ($_.NodeName -eq "*") {$Wildcardinjection= $_}}
        $ReturnData.AllNodes = $ReturnData.AllNodes.Where{($_.NodeName -ne "*")}
        }
    Else {
        #Create Missing Wildcard
        $Wildcardinjection = @{}
        $Wildcardinjection.NodeName = "*"
        }
    
    #Merge Data
    $Wildcardinjection+=Import-PasswordXML -XMLFile $PasswordData
    $ReturnData.AllNodes+=$Wildcardinjection

    #import-csv to speed the scan
    $CSVFile = (import-csv $FileName)
        #Update ReturnData By calling other functions
        $ReturnData.AllNodes | ForEach-Object -Process {
            $CurrNode = $_.NodeName
            If (($CSVFile.NodeName -contains $CurrNode) -and ($CurrNode -ne "*")) {
                $_.NodeName = (Update-DSCMGUIDMapping -NodeName $CurrNode -FileName $FileName)
                If (Update-DSCMCertMapping -NodeName $CurrNode) {
                    $_.Thumbprint = (Update-DSCMCertMapping -NodeName $CurrNode)
                    $_.CertificateFile = $CertStore+'\'+$CurrNode+'.cer'
                    }
                }
            }#End Per-Object Crawl
    return $ReturnData
}

#This function is to update and maintain the Host-to-GUID mapping to ease management.
function Update-DSCMGUIDMapping
{
    [cmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][String]$FileName = "$env:PROGRAMFILES\WindowsPowershell\DscService\Management\dscnodes.csv",
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][String]$NodeName,
        [switch]$Silent
    )

    If (Test-Path -Path ($FileName)) {
        
        #import file for modification
        $CSVFile = (import-csv $FileName)
        If($CSVFile.NodeName -notcontains $NodeName) {
            $NodeGUID = [guid]::NewGuid()
            Write-Verbose -Message "Cannot Find Node $NodeName, writing new entry with GUID $NodeGUID"
            $NewLine = "{0},{1}" -f $NodeName,$NodeGUID
            $NewLine | add-content -path $FileName
            } #End If
        Else {
            If (($csvfile|where-object{$_.NodeName -eq $NodeName}).NodeGUID)  {
                Write-Verbose -Message "All Entries present"
                $NodeGUID = ($csvfile|where-object{$_.NodeName -eq $NodeName}).NodeGUID
                }
            Else {
                $NodeGUID = [guid]::NewGuid()
                Write-Verbose -Message "Node $NodeName was found, adding GUID $NodeGUID"
                ($csvfile|where-object{$_.NodeName -eq $NodeName}).NodeGUID = $NodeGUID
                }

            #Write Changes back to file
            If ($CSVFile -and !($CSVFile -eq (import-csv $Filename))) {
                $CSVFile | Export-CSV $FileName -Delimiter ','
                }
            } #End Else
        }#End File Exists

    Else {
        write-verbose "the file $FileName cannot be found so there is nothing to return"
        }#End File Missing
    if(!($Silent)) {
            return [String]$NodeGUID
            }
}

#This function is to update and maintain the Certificate-to-host mapping to ease management
function Update-DSCMCertMapping
{
[cmdletBinding()]
param(
    [Parameter(Mandatory=$false)][String]$FileName = "$env:PROGRAMFILES\WindowsPowershell\DscService\Management\dscnodes.csv",
    [Parameter(Mandatory=$false)][String]$CertStore = "$env:PROGRAMFILES\WindowsPowershell\DscService\NodeCertificates",
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][String]$NodeName,
    [switch]$Silent
    )

    #ClearCriticalVariables
    $Thumbprint=$null
    $OldThumbprint=$null

    If (Install-DSCMCertStores -FileName $FileName -CertStore $CertStore -TestOnly) {
        $CSVFile = import-csv $FileName
        
        #Check for existence of Certificate file
        $certfullpath = $CertStore+'\'+$NodeName+'.cer'
        If(Test-Path -Path ($certfullpath)) {
            # X509Certificate2 object that will represent the certificate
            $CertPrint = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2    
            # Imports the certificate from file to x509Certificate object and grabs the goodies
            $certPrint.Import($Certfullpath)
            $Thumbprint = $CertPrint.Thumbprint
            }#End Found Cert

        If ($csvfile.NodeName -contains $NodeName) {
            $OldThumbprint = ($csvfile|where-object{$_.NodeName -eq $NodeName}).Thumbprint
            IF ($OldThumbprint -ne $Thumbprint) {($csvfile|where-object{$_.NodeName -eq $NodeName}).Thumbprint = $Thumbprint}
            }#End Node Found

        #If the table was updated in the previous process, save it
        If($OldThumbprint -ne $Thumbprint) {
            $CSVFile | Export-CSV $FileName -Delimiter ','
            }
        
        #Return Data
        if(!($Silent)) {
            return,$Thumbprint
            }
        }#End If Stores Exist

    Else {
        write-verbose "the file $FileName or $CertStore cannot be found so there is nothing to return"
        }#End No Stores
    }

#This function is automatically zip-up modules into the right format and place them into the DSC module folder
function Update-DSCMModules
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$false)][String]$SourceModules="$env:PROGRAMFILES\WindowsPowershell\Modules",
        [Parameter(Mandatory=$false)][String]$Name,
        [Parameter(Mandatory=$false)][String]$PullServerModules="$env:PROGRAMFILES\WindowsPowershell\DscService\Modules",
        [Parameter(ValueFromRemainingArguments = $true)]$Splat
    )
 
    # Read the module names & versions
    If ($Name -and (Test-Path $SourceModules\$Name)) {
        $SourceList = $Name
        }
    Else {
        $SourceList = (Get-ChildItem -Directory $SourceModules).Name
        }
    foreach ($SourceModule in $SourceList) {
        write-verbose "Check module $SourceModule"
        $module = Import-Module $SourceModules\$SourceModule -PassThru
        Write-Verbose $Module.Version
        $moduleName = $module.Name
        $version = $module.Version.ToString()
        Remove-Module $moduleName
        $zipFilename = ("{0}_{1}.zip" -f $moduleName, $version)
        $outputPath = Join-Path $PullServerModules $zipFilename
        if (!(Test-Path $outputPath)) {
            write-verbose "$outputPath is $zipFilename, creating zip"
            # Courtesy of: @Neptune443 (http://blog.cosmoskey.com/powershell/desired-state-configuration-in-pull-mode-over-smb/)
            [byte[]]$data = New-Object byte[] 22
            $data[0] = 80
            $data[1] = 75
            $data[2] = 5
            $data[3] = 6
            [System.IO.File]::WriteAllBytes($outputPath, $data)
            $acl = Get-Acl -Path $outputPath
 
            $shellObj = New-Object -ComObject "Shell.Application"
            $zipFileObj = $shellObj.NameSpace($outputPath)
            if ($zipFileObj -ne $null) {
                write-verbose "adding modules to zip $outputPath"
                $target = get-item $SourceModules\$SourceModule
                # CopyHere might be async and we might need to wait for the Zip file to have been created full before we continue
                # Added flags to minimize any UI & prompts etc.
                $zipFileObj.CopyHere($target.FullName, 0x14)      
                [Runtime.InteropServices.Marshal]::ReleaseComObject($zipFileObj) | Out-Null
                Set-Acl -Path $outputPath -AclObject $acl
                New-DSCCheckSum -ConfigurationPath $PullServerModules
                }
            else {
                Throw "Failed to create the zip file"
                }
            }
        else {
            write-verbose "file already exists, skipping $zipFilename"
            }
        }
    write-verbose "complete"
}

#This function is to import all certificates from the CertStore onto the local machine
function Update-DSCMImportallCerts
{
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)][String]$CertStore = "$env:PROGRAMFILES\WindowsPowershell\DscService\NodeCertificates",
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][String]$NodeName,
    [Parameter(ValueFromRemainingArguments = $true)]$Splat
    )

    If (Install-DSCMCertStores -CertStore $CertStore -TestOnly) {
        $CertList = Get-ChildItem $CertStore
        
        #Verify every cert in the CertStore has been imported to all locations
        foreach ($cert in $certList) {

            # X509Certificate2 object that will represent the certificate
            $CertPrint = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        
            # Imports the certificate from file to x509Certificate object
            $certPrint.Import($CertStore+'\'+$cert)
            if (!(Get-Childitem cert:\LocalMachine\MY | Where-Object {$_.Thumbprint -eq $certPrint.Thumbprint})) {
                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "MY", "LocalMachine"
                $store.Open("ReadWrite")
                $store.Add($certStore+'\'+$cert)
                $store.Close()
                }
            }
        }
    Else {
        write-verbose "the file $CertStore cannot be found so there is nothing to update"
        }
    }

#This function creates Variables storing credentials
Function Import-PasswordXML
{
[cmdletBinding()]
param(
    [Parameter(Mandatory=$false)][String]$XMLFile = "$env:PROGRAMFILES\WindowsPowershell\DscService\Management\passwords.xml",
    [Parameter(Mandatory=$false)][Switch]$ToSession
    )

    #Create sample XMLFile if it is missing
    Write-Verbose "Checking/Adding XMLFile $XMLFile"
    IF (!(Test-Path -Path $XMLFile)) {
        Write-Verbose "File not found, creating dummy file"
        Try {
            $xmlWriter = New-Object System.XMl.XmlTextWriter($XMLFile,$Null)
            #Set Format 
            $xmlWriter.Formatting = 'Indented'
            $xmlWriter.Indentation = 1
            $XmlWriter.IndentChar = "`t"
            #Create
            $xmlWriter.WriteStartDocument()
            #Start New Element array
            $xmlWriter.WriteStartElement('Credentials')
            #Add Stuff to it
            $xmlWriter.WriteStartElement('Variable')
            $xmlWriter.WriteAttributeString('Name', 'SCCMAdministratorCredential')
            $xmlWriter.WriteAttributeString('User','Contoso\Administrator')
            $xmlWriter.WriteAttributeString('Password','Password')
            #End specific Entry
            $xmlWriter.WriteEndElement()
            #End larger element
            $xmlWriter.WriteEndElement()
            #Write to disk and let it go
            $xmlWriter.Flush()
            $xmlWriter.Close()
            }
        Catch {
            Throw "Error creating sample xml File"
            }
        }#End Create XML If

    #Generate Password Variables from XMLData
    Write-Verbose -Message "Loading Passwords from xml..."
    $Passwords = @{}
    $Config = [XML](Get-Content $XMLFile)
    $Config.Credentials | ForEach-Object {$_.Variable} | Where-Object {$_.Name -ne $null} | ForEach-Object {
        $SecurePass = ConvertTo-SecureString $_.Password -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential $_.User, $SecurePass
        If ($ToSession) {    
            $PSCmdlet.SessionState.PSVariable.Set($_.Name, $cred)
            }
        Else {
            $Passwords.add($_.Name, $cred)
            }
        } #End ForEach Loop

    #Return Hashtable
    If (!$ToSession) {return $Passwords}
}

#This function is to create MOF files and copy them to the Pull Server from the specific working directory
function Update-DSCMPullServer
{
    [cmdletBinding()]
    param(
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][String]$Configuration,
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][HashTable]$ConfigurationData,
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)][String]$ConfigurationFile = "$env:HOMEDRIVE\DSC-Manager\Configuration\MasterConfig.ps1",
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)][String]$PullServerConfiguration = "$env:PROGRAMFILES\WindowsPowershell\DscService\Configuration",
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)][String]$WorkingPath = $env:TEMP
    )

    #Load DSC Configuration into script
    Write-Verbose -Message "Loading DSC Configuration..."
    Try {
        Invoke-Expression ". $ConfigurationFile"
        }
    Catch {
        Throw "error loading DSC Configuration $ConfigurationFile"
        }

    #generate MOF files using Configurationdata and output to the appropriate temporary path
    Write-Verbose -Message "Generating MOF using Configurationdata and output to $WorkingPath..."
    invoke-expression "$Configuration -ConfigurationData `$ConfigurationData -outputpath $WorkingPath"

    #create a checksum file for eah generated MOF
    Write-Verbose -Message "Generating checksum..."
    New-DSCCheckSum -ConfigurationPath $WorkingPath -OutPath $WorkingPath -Force
    
    #All Generation is complete, now we copy it all to the Pull Server
    Write-Verbose -Message "Moving all files to $PullServerConfiguration..."
    $SourceFiles = $WorkingPath + "\*.mof*"
    Move-Item $SourceFiles $PullServerConfiguration -Force
}

#This function approves pending agents for use by DSC
Function Add-DSCMAgent
{
    [cmdletBinding()]
    param (
    [Parameter(Mandatory=$false)][String]$FileName = "$env:PROGRAMFILES\WindowsPowershell\DscService\Management\dscnodes.csv",
    [Parameter(Mandatory=$false)][String]$CertStore = "$env:PROGRAMFILES\WindowsPowershell\DscService\NodeCertificates",
    [Parameter(Mandatory=$false)][String]$AgentReg = "$env:PROGRAMFILES\WindowsPowershell\DscService\AgentRegistration",
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][String]$NodeName,
    [switch]$Silent
    )

    #Generate Request and check file
    $Request = "$AgentReg\$NodeName.txt"
    
    If (Test-Path $request) {
        Try {
            write-verbose "replying with GUID for use by agent"
            $newguid = Update-DSCMGUIDMapping -NodeName $NodeName -FileName $FileName
            Update-DSCMCertMapping -NodeName $NodeName -CertStore $CertStore -FileName $FileName -Silent
            $newguid | Out-File -FilePath $request
            }
        Catch {
            Throw "Error trying to genrate the request file!"
            exit
            }
        }
    Else {
        Write-Output "Cannot find a request for $NodeName, exiting"
        exit
        }
    If (!$Silent) {Write-Output "Node $NodeName has been approved for use.  Run Install-Node script again."}
    }

#This function pulls node information back from the pull server
function Request-NodeInformation
{
    [cmdletBinding()]
    Param (
        [Parameter(Mandatory=$false)][string]$URL = "http://localhost:9080/PSDSCComplianceServer.svc/Status",                         
        [Parameter(Mandatory=$false)][string]$ContentType = "application/json",
        [Parameter(ValueFromRemainingArguments = $true)]$Splat
        )

    #Feedback
    Write-Verbose "Querying node information from pull server URL  = $URL"
    Write-Verbose "Querying node status in content type  = $ContentType "

    #Gather data from reporting server
    $response = Invoke-WebRequest -Uri $URL -Method Get -ContentType $ContentType -UseDefaultCredentials -Headers @{Accept = $ContentType}

    #Report on Nulldata
    if($response.StatusCode -ne 200) {
        Write-Verbose "node information was not retrieved."
        }

    #Inject information from the repo    
    $ReturnData = ConvertFrom-Json $response.Content
    $CompiledData = $null
    $ReturnData.value | ForEach-Object -Process {
        $Object = New-Object -TypeName PSObject
		$Object | Add-Member -Name "Node Name" -MemberType NoteProperty -Value (Request-DSCMGUIDMapping -GUIDName $_.ConfigurationID)
		$Object | Add-Member -Name "Target Name" -MemberType NoteProperty -Value $_.TargetName
		$Object | Add-Member -Name "GUID" -MemberType NoteProperty -Value $_.ConfigurationId
        $Object | Add-Member -Name "Checksum" -MemberType NoteProperty -Value $_.ServerChecksum
        $Object | Add-Member -Name "Node Compliant" -MemberType NoteProperty -Value $_.NodeCompliant
        $Object | Add-Member -Name "Last Compliance" -MemberType NoteProperty -Value $_.LastComplianceTime
        $Object | Add-Member -Name "Status Code" -MemberType NoteProperty -Value $_.StatusCode
        [Array]$CompiledData+=$Object
        }

    #Spit out the report
    return $CompiledData | Format-Table
}

#reporting function to translate GUID to name
function Request-DSCMGUIDMapping
{
    [cmdletBinding()]
    param(
    [Parameter(Mandatory=$false)][String]$FileName = "$env:PROGRAMFILES\WindowsPowershell\DscService\Management\dscnodes.csv",
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][String]$GUIDName
    )

    If (Test-Path $FileName) {
        $CSVFile = (import-csv $FileName)
        $CSVFile | ForEach-Object { if ($_.NodeGUID -eq $GUIDName) {$returnname  = $_.NodeName}}
        }
    Else {
        write-verbose "the file $FileName cannot be found so there is nothing to return"
        exit
        }
 
    if ($returnname) {return $returnname}
}