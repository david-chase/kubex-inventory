[CmdletBinding()]
param (
    [string]$instance_param,
    [string]$scheme_param,
    [string]$port_param,
    [string]$user_param,
    [string]$pass_param,
    [string]$baseurl_param,
    [switch]$csv
)

Clear-Host

# Clear host and output banners only if not outputting raw CSV data
if (-not $csv) {
    Write-Host ""
    Write-Host "::: Kubex Inventory - Identify software deployed in a customer environment :::" -ForegroundColor Cyan
    Write-Host ""
}

# Determine Script Directory
$ScriptDir = Split-Path -Parent -Path ${MyInvocation}.MyCommand.Definition
$IniPath = Join-Path -Path ${ScriptDir} -ChildPath "kubex-inventory.ini"
$CsvPath = Join-Path -Path ${ScriptDir} -ChildPath "software.csv"

# Initialize Settings Dictionary
$Settings = @{
    "instance"   = $null
    "scheme" = "https://"
    "port"   = ":8443"
    "user"   = $null
    "pass"   = $null
    "baseurl" = ".kubex.ai"
}

# 1. Read Settings Hierarchy: INI -> Command-Line -> Prompt Fallback
if (Test-Path -Path ${IniPath}) {
    Get-Content -Path ${IniPath} | ForEach-Object {
        if ($_ -match '^\s*([^=]+)\s*=\s*(.*)\s*$') {
            $Key = $Matches[1].Trim().ToLower()
            $Value = $Matches[2].Trim()
            if ($Settings.ContainsKey(${Key})) {
                $Settings[${Key}] = ${Value}
            }
        }
    }
}

# Apply Command-Line Overrides explicitly
if (-not [string]::IsNullOrEmpty(${instance_param}))   { $Settings["instance"]   = ${instance_param} }
if (-not [string]::IsNullOrEmpty(${scheme_param})) { $Settings["scheme"] = ${scheme_param} }
if (-not [string]::IsNullOrEmpty(${port_param}))   { $Settings["port"]   = ${port_param} }
if (-not [string]::IsNullOrEmpty(${user_param}))   { $Settings["user"]   = ${user_param} }
if (-not [string]::IsNullOrEmpty(${pass_param}))   { $Settings["pass"]   = ${pass_param} }
if (-not [string]::IsNullOrEmpty(${baseurl_param}))   { $Settings["baseurl"]   = ${basurl_param} }

# Prompt Interactively for completely empty configurations
if ([string]::IsNullOrEmpty($Settings["instance"])) { $Settings["instance"] = Read-Host -Prompt "Enter instance (e.g. cluster.kubex.ai)" }
if ([string]::IsNullOrEmpty($Settings["user"])) { $Settings["user"] = Read-Host -Prompt "Enter Username" }
if ([string]::IsNullOrEmpty($Settings["pass"])) { 
    if ($csv) {
        $Settings["pass"] = Read-Host -Prompt "Enter Password"
    } else {
        $Settings["pass"] = Read-Host -Prompt "Enter Password" -AsSecureString 
    }
}

# 2. Parse software.csv
if (-not (Test-Path -Path ${CsvPath})) {
    Write-Error "Required reference file software.csv not detected."
    exit 1
}

$SoftwareRules = @()
if (Test-Path -Path ${CsvPath}) {
    $CsvData = Import-Csv -Path ${CsvPath} -Header "Software", "Type", "RawRule"
    foreach ($Row in ${CsvData}) {
        if ([string]::IsNullOrEmpty($Row.RawRule)) { continue }
        
        # Dynamic CSV Splitting: Extract nested 3-part syntax (Element Operator Value)
        if ($Row.RawRule -match '^\s*(\S+)\s+(\S+)\s+(.+)\s*$') {
            $SoftwareRules += [PSCustomObject]@{
                Software = $Row.Software
                Type     = $Row.Type
                Element  = $Matches[1].Trim()
                Operator = $Matches[2].Trim()
                Value    = $Matches[3].Trim().Trim('"')
            }
        }
    }
}

if (-not $csv) {
    Write-Output "Connecting to $($Settings['instance']) instance."
}

# 3. Compose Base URL (Silent Step)
$CleanScheme = $Settings["scheme"]
if (-not ($CleanScheme -match '://$')) {
    $CleanScheme = "${CleanScheme}://"
}
$CleanHost = ( $Settings["instance"] -replace '^https?://', '' ) + $Settings["baseurl"]
$CleanPort = $Settings["port"]
if (-not ($CleanPort -match '^:')) {
    $CleanPort = ":${CleanPort}"
}
$BaseUrl = "${CleanScheme}${CleanHost}${CleanPort}"

# 4. Authenticate and Generate JWT Web Token
$AuthUrl = "${BaseUrl}/CIRBA/api/v2/authorize"
$RawPass = if ($Settings["pass"] -is [System.Security.SecureString]) {
    [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Settings["pass"]))
} else { 
    $Settings["pass"] 
}

$AuthBody = @{
    userName = $Settings["user"]
    pwd      = $RawPass
} | ConvertTo-Json

$JwtToken = $null
try {
    $AuthResponse = Invoke-RestMethod -Uri ${AuthUrl} -Method Post -Body ${AuthBody} -ContentType "application/json; charset=utf-8"
    
    if ($AuthResponse -ne $null) {
        if ($AuthResponse.PSObject.Properties.Name -contains 'apiToken') { 
            $JwtToken = $AuthResponse.apiToken 
        } elseif ($AuthResponse.PSObject.Properties.Name -contains 'token') { 
            $JwtToken = $AuthResponse.token 
        } elseif ($AuthResponse -is [string]) { 
            $JwtToken = $AuthResponse 
        }
    }
} catch [System.Net.WebException] {
    $Exception = $_.Exception
    if ($Exception.Response -and $Exception.Response.StatusCode -eq 401) {
        Write-Error "Invalid credentials provided. Authentication failed."
    } elseif ($Exception.Response -and $Exception.Response.StatusCode -eq 404) {
        Write-Error "Target URL path configuration was invalid. Tested Endpoint: ${AuthUrl}"
    } else {
        Write-Error "Connection error during login sequence: $($_.Exception.Message)"
    }
    exit 1
}

if (-not $JwtToken) {
    Write-Error "Authorization failed or token not found."
    exit 1
}

# 5. Query GraphQL API
$GraphUrl = "${BaseUrl}/api/graphql/containers"
$Headers = [System.Collections.Generic.Dictionary[string,string]]::new()
$Headers.Add("Authorization", "Bearer ${JwtToken}".Trim())
$Headers.Add("Accept", "application/json")

$QueryPayload = @"
{
  "query": "query K8sData_ALL { getContainerDetailsByViewAndFilter ( viewId: \"a2823ef2-5c59-41b0-bcc7-abfb2a9e1c0e\", filterId: \"cf1e8b62-a5b7-46fb-824a-df30cd30da2e\", treeviewPath: \"Containers\") { cluster namespace controllerType podService containerName } }",
  "variables": {}
}
"@

try {
    $GraphResponse = Invoke-RestMethod -Uri ${GraphUrl} -Method Post -Headers ${Headers} -Body ${QueryPayload} -ContentType "application/json; charset=utf-8"
} catch {
    Write-Error "Failed to retrieve or parse container records via GraphQL endpoint: $($_.Exception.Message)"
    exit 1
}

$RawContainers = $GraphResponse.data.getContainerDetailsByViewAndFilter

# 6. Setup Tracking Entities & Sorting Hierarchy (Broad-to-Narrow Sequence)
$Containers = $RawContainers | ForEach-Object {
    [PSCustomObject]@{
        cluster        = $_.cluster
        namespace      = $_.namespace
        controllerType = $_.controllerType
        pod            = $_.podService
        container      = $_.containerName
    }
}

# Sort-Order Precedence logic: Cluster -> Namespace -> Container
$SortedContainers = $Containers | Sort-Object -Property cluster, namespace, container

# Global Tracking Aggregations
$ClusterSoftwareMapping = @{}
$GlobalClusters         = @{}
$GlobalNamespaces       = @{}
$GlobalMatchesCount     = 0
$CurrentCluster         = $null

# Console Output Method for Standard Text UI (Fires only if -csv switch is omitted)
function Flush-ClusterSoftware {
    param([string]$TargetCluster)
    if ([string]::IsNullOrEmpty(${TargetCluster}) -or -not $ClusterSoftwareMapping.ContainsKey(${TargetCluster})) { return }
    
    $GlobalClusters[${TargetCluster}] = $true
    Write-Output "`n## ${TargetCluster}" 
    
    # Sort software names alphabetically
    $SoftwareKeys = @($ClusterSoftwareMapping[${TargetCluster}].Keys) | Sort-Object
    foreach ($SoftwareName in $SoftwareKeys) {
        $SoftwareData = $ClusterSoftwareMapping[${TargetCluster}][$SoftwareName]
        $Category = $SoftwareData.Type
        $DistinctNamespaces = @($SoftwareData.Namespaces.Keys)
        $NamespaceCount = $DistinctNamespaces.Count
        
        $NamespaceString = ""
        if ($NamespaceCount -gt 3) {
            $NamespaceString = "(${NamespaceCount} namespaces)"
        } else {
            $NamespaceString = "(" + ($DistinctNamespaces -join ", ") + ")"
        }
        
        # Write the software name to the host
        Write-Output "  - ${SoftwareName}, ${Category} ${NamespaceString} " 
        
        # NOTE: Removed local scope counter from here to avoid scope corruption
    }
}

# If CSV generation parameter is verified, emit the clean, space-free header row instantly
if ($csv) {
    Write-Output "Software,Category,Namespace,Pod Name,Container Name"
}

# 7. Main Core Control Process Loop Evaluation
foreach ($Pod in $SortedContainers) {
    if ([string]::IsNullOrEmpty($Pod.cluster)) { continue }
    
    $GlobalNamespaces[$Pod.namespace] = $true
    
    # Cluster Boundaries Tracking Evaluation change
    if ($null -eq $CurrentCluster) {
        $CurrentCluster = $Pod.cluster
    } elseif ($CurrentCluster -ne $Pod.cluster) {
        if (-not $csv) {
            Flush-ClusterSoftware -TargetCluster $CurrentCluster
        }
        $CurrentCluster = $Pod.cluster
    }
    
    # Evaluate checking rules sequentially against target fields
    foreach ($Rule in $SoftwareRules) {
        $TargetValue = $null
        if ($Rule.Element -ieq "namespace") { $TargetValue = $Pod.namespace }
        if ($Rule.Element -ieq "pod")       { $TargetValue = $Pod.pod }
        if ($Rule.Element -ieq "container") { $TargetValue = $Pod.container }
        
        if ($null -eq $TargetValue) { continue }
        
        $IsMatch = $false
        switch ($Rule.Operator) {
            "Equals"           { if ($TargetValue -ieq $Rule.Value) { $IsMatch = $true } }
            "Contains"         { if ($TargetValue -ilike "*$($Rule.Value)*") { $IsMatch = $true } }
            "StartsWith"       { if ($TargetValue -ilike "$($Rule.Value)*") { $IsMatch = $true } }
            "EndsWith"         { if ($TargetValue -ilike "*$($Rule.Value)") { $IsMatch = $true } }
            "DoesntContain"    { if ($TargetValue -notlike "*$($Rule.Value)*") { $IsMatch = $true } }
            "DoesntEqual"      { if ($TargetValue -ne $Rule.Value) { $IsMatch = $true } }
            "DoesntStartWith"  { if ($TargetValue -notlike "$($Rule.Value)*") { $IsMatch = $true } }
            "DoesntEndWith"    { if ($TargetValue -notlike "*$($Rule.Value)") { $IsMatch = $true } }
        }
        
        if ($IsMatch) {
            if ($csv) {
                # Immediate inline CSV record row delivery streaming to StdOut with no spaces after commas
                Write-Output "$($Rule.Software),$($Rule.Type),$($Pod.namespace),$($Pod.pod),$($Pod.container)"
                $GlobalClusters[$Pod.cluster] = $true
                
                # FIXED: Count match during CSV generation stream
                $GlobalMatchesCount++
            } else {
                if (-not $ClusterSoftwareMapping.ContainsKey($Pod.cluster)) {
                    $ClusterSoftwareMapping[$Pod.cluster] = @{}
                }
                if (-not $ClusterSoftwareMapping[$Pod.cluster].ContainsKey($Rule.Software)) {
                    $ClusterSoftwareMapping[$Pod.cluster][$Rule.Software] = @{
                        Type       = $Rule.Type
                        Namespaces = @{}
                    }
                    # FIXED: In Standard UI view, count a unique match per piece of software per cluster 
                    $GlobalMatchesCount++
                }
                $ClusterSoftwareMapping[$Pod.cluster][$Rule.Software].Namespaces[$Pod.namespace] = $true
            }
        }
    }
}

# Flush trailing edge item record tracking context block remaining
if ($null -ne $CurrentCluster -and -not $csv) {
    Flush-ClusterSoftware -TargetCluster $CurrentCluster
}

# 8. Report Summary Analytics (Suppressed entirely if running in -csv streaming mode)
if (-not $csv) {
    Write-Output ""
    Write-Output "Total clusters: $($GlobalClusters.Count)"
    Write-Output "Total namespaces: $($GlobalNamespaces.Count)"
    Write-Output "Total pieces of software identified: ${GlobalMatchesCount}"
}

exit 0