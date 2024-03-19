param($artifactname, $reponame, $domainname, $port)

# Use CultureInfo for culture-independent string conversion 
$invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

# Convert artifact names to lower case and clean them
$artifactname = $artifactname.Trim().ToLower([System.Globalization.CultureInfo]::InvariantCulture)
$reponame = $reponame.ToLower()

echo "Artifact name: $artifactname"
echo "Repo name: $reponame"
echo "Domain name: $domainname"

# Get Instance Id from meta-data
[string]$token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT -Uri http://169.254.169.254/latest/api/token

$instanceId = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-id
echo $instanceId

# Retrieve Load Balancer ARN
$loadBalancers = aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, '$reponame-lb')].[LoadBalancerArn]" --output json | ConvertFrom-Json
$loadBalancerArn = $loadBalancers[0]

# Retrieve the Listener ARN for port 443
$listeners = aws elbv2 describe-listeners --load-balancer-arn $loadBalancerArn --query 'Listeners[?Port==`443`].[ListenerArn]' --output json  | ConvertFrom-Json
$listenerArn = $listeners[0]

# Retrieve rule ARNs based on the domain name
$domainName = $domainname.ToLower()

$rules = aws elbv2 describe-rules --listener-arn $listenerArn --query "Rules[?Conditions[?Field=='host-header'&&Values[?contains(@, '$domainName')]]]" --output json | ConvertFrom-Json

$ruleArn = $null
foreach ($rule in $rules) {
    $ruleArn = $rule.RuleArn
    break # Take the ARN of the first matching rule and exit the loop
}

echo "Rule ARN: $ruleArn"

# List all target groups starting with reponame and their ARNs
$targetgroups = aws elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName, '$reponame')].[TargetGroupName, TargetGroupArn]" --output json | ConvertFrom-Json

$bluetargetgroup = $null
$greentargetgroup = $null

# Process listed target groups and their ARNs
foreach ($tg in $targetgroups) {
    $targetGroupName = $tg[0]
    $targetGroupArn = $tg[1]
    
    if ($targetGroupName -like "*main*") {
        $bluetargetgroup = $targetGroupArn # Assign this as the blue target group
    }
    elseif ($targetGroupName -like "*deploy*") {
        $greentargetgroup = $targetGroupArn # Assign this as the green target group
    }
}

echo "Blue Target Group ARN: $bluetargetgroup"
echo "Green Target Group ARN: $greentargetgroup"





# Function to modify and apply the JSON files
function Update-Rule($blueTarget, $blueWeight, $greenTarget, $greenWeight) {
    # Create copies of original files
    Copy-Item "C:\runner_work\devops\json\conditions.json" "C:\runner_work\devops\json\conditions_temp.json"
    Copy-Item "C:\runner_work\devops\json\actions.json" "C:\runner_work\devops\json\actions_temp.json"

    # Modify the copied JSON files
    (Get-Content -path "C:\runner_work\devops\json\conditions_temp.json" -Raw) -replace 'domain',"$domainname" | Set-Content "C:\runner_work\devops\json\conditions_temp.json"
    (Get-Content -path "C:\runner_work\devops\json\actions_temp.json" -Raw) -replace 'blue-target-group',"$blueTarget" | Set-Content "C:\runner_work\devops\json\actions_temp.json"
    (Get-Content -path "C:\runner_work\devops\json\actions_temp.json" -Raw) -replace 'blue-weight',"$blueWeight" | Set-Content "C:\runner_work\devops\json\actions_temp.json"
    (Get-Content -path "C:\runner_work\devops\json\actions_temp.json" -Raw) -replace 'green-target-group',"$greenTarget" | Set-Content "C:\runner_work\devops\json\actions_temp.json"
    (Get-Content -path "C:\runner_work\devops\json\actions_temp.json" -Raw) -replace 'green-weight',"$greenWeight" | Set-Content "C:\runner_work\devops\json\actions_temp.json"

     # Modify the rule using the temporary JSON files
    aws elbv2 modify-rule --rule-arn $rulearn --conditions file://"C:\runner_work\devops\json\conditions_temp.json" --actions file://"C:\runner_work\devops\json\actions_temp.json"

    # Delete temporary files
    Remove-Item "C:\runner_work\devops\json\conditions_temp.json"
    Remove-Item "C:\runner_work\devops\json\actions_temp.json"
}


# Deregister instance from blue target group
aws elbv2 deregister-targets --target-group-arn $bluetargetgroup --targets Id=$instanceId,Port=$port

# Wait for unused state
do {
    Start-Sleep -Seconds 30 # Target health kontrolü için bir süre bekle
    $targetHealth = aws elbv2 describe-target-health --target-group-arn $bluetargetgroup --targets Id=$instanceId,Port=$port | ConvertFrom-Json
    $targetState = $targetHealth.TargetHealthDescriptions.TargetHealth.State
    Write-Output "Current target state: $targetState"
} while ($targetState -ne 'unused')

Write-Output "Deregistration completed."



###### DEPLOYMENT PROCESS    ############

$reponame_S3 = $reponame.ToLower($invariantCulture)

# Get the artifact from S3 bucket
$S3Bucket = "seyithan-" + $reponame_S3 + "-deploy"
echo $S3Bucket

# Read the artifact from S3 bucket
Read-S3Object -BucketName $S3Bucket -Key "$artifactname.zip" -File "C:\runner_work\devops\$reponame.zip"

# Temporary directory for unzipping
$unzipTempDirectory = "C:\runner_work\devops\$reponame-temp"

# Unzip the artifact
powershell -command  "Expand-Archive -Path C:\runner_work\devops\$reponame.zip -DestinationPath $unzipTempDirectory -Force"

# Get Physical path for the IIS site
Import-Module WebAdministration
$site = Get-Item IIS:\Sites\$($reponame)
echo $site.physicalPath

# IIS backup
$date = Get-Date -Format "yyyyMMdd-hhmmss"
$backupPath = "C:\runner_work\devops\backup\$reponame\$($site.Name)-backup-$date"
echo $site.Name
echo $backupPath
Copy-Item $site.physicalPath $backupPath -Recurse



# Stop Application Pool
$appPool = Get-WebAppPoolState -Name $site.Name -ErrorAction SilentlyContinue
if ($appPool -ne $null -and $appPool.Value -eq 'Started') {
    Stop-WebAppPool -Name $site.Name
    Write-Host "Application Pool '$site.Name' has been stopped."
}

do {
    echo "stopping..."
    # Wait for a while
    Start-Sleep -Seconds 5

} while ($appPool.Value -ne 'Stopped')

# Stop Website
$website = Get-Website -Name $site.Name -ErrorAction SilentlyContinue
if ($website -ne $null -and $website.State -eq 'Started') {
    Stop-Website -Name $site.Name
    Write-Host "Website '$site.Name' has been stopped."
}

# Remove old files
Remove-Item "$($site.physicalPath)\*" -Recurse -Force

# Copy new release to Website path
Copy-Item "$unzipTempDirectory\build\*" $site.physicalPath -Recurse -Force

echo $site.physicalPath






# Start Application Pool
if ($appPool -ne $null -and $appPool.Value -eq 'Stopped') {
    Start-WebAppPool -Name $site.Name
    Write-Host "Application Pool '$site.Name' has been started."
}

# Start Website
if ($website -ne $null -and $website.State -eq 'Stopped') {
    Start-Website -Name $site.Name
    Write-Host "Website '$site.Name' has been started."
}

# Remove zip file
Remove-Item -Path "C:\runner_work\devops\$reponame.zip" -Force

# Remove temporary directory
Remove-Item -Path "$unzipTempDirectory" -Recurse -Force




aws elbv2 register-targets --target-group-arn $greentargetgroup --targets Id=$instanceId,Port=$port 


#check heath status

do {
    $targetHealth = aws elbv2 describe-target-health --target-group-arn $greentargetgroup --targets Id=$instanceId,Port=$port | ConvertFrom-Json
    $targetState = $targetHealth.TargetHealthDescriptions.TargetHealth.State
    Write-Output "Current target state: $targetState"

    if ($targetState -ne 'healthy') {
        Start-Sleep -Seconds 30
    }
} while ($targetState -ne 'healthy')

# Switch traffic back to blue

Start-Sleep -Seconds 15


Update-Rule $bluetargetgroup "0" $greentargetgroup "100"

#remove old backups
$folders = Get-ChildItem -Directory -Path 'C:\runner_work\devops\Backup\*\*' | Where-Object {$_.CreationTime -lt (Get-Date).AddDays(-20)}

$folders | ForEach-Object {
    Remove-Item -Path $_.FullName -Recurse -Force
}