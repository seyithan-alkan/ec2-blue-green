<powershell>
[string]$awstoken = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT -Uri http://169.254.169.254/latest/api/token
$instanceId = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $awstoken} -Method GET  -Uri http://169.254.169.254/latest/meta-data/instance-id
$tagName = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $awstoken} -Method GET  -Uri "http://169.254.169.254/latest/meta-data/tags/instance/Name").Trim()
$computerInfo = Get-WmiObject Win32_ComputerSystem
$computerInfo.Rename($tagName)

#AWS CLI SETUP
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
[Environment]::SetEnvironmentVariable("Path", "$($env:Path);C:\ProgramData\chocolatey\bin", [System.EnvironmentVariableTarget]::Machine)
$env:Path += ";C:\ProgramData\chocolatey\bin"
choco install awscli --force -y

[Environment]::SetEnvironmentVariable("Path", "$($env:Path);C:\Program Files\Amazon\AWSCLIV2\", [System.EnvironmentVariableTarget]::Machine)
$env:Path += ";C:\Program Files\Amazon\AWSCLIV2\"

Install-WindowsFeature -Name Web-Server
Install-WindowsFeature -Name Web-Mgmt-Console

Import-Module WebAdministration
Remove-WebSite -Name 'Default Web Site'

$port = 8080 
$repoNames = @("ec2-blue-green", "test-repo")
mkdir c:\temp
foreach ($reponame in $repoNames) {
    New-WebAppPool -Name $reponame

    $websitePath = "C:\inetpub\wwwroot\$reponame"
    if (!(Test-Path $websitePath)) {
        New-Item -ItemType Directory -Path $websitePath -Force
    }

    # HTML content
    $htmlContent = @"
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Instance ID and Repo Name</title>
    </head>
    <body>
        <h1>Instance ID: $instanceId</h1>
        <h2>Repo Name: $tagName</h2>
    </body>
    </html>
"@
    $htmlContent | Out-File -FilePath "$websitePath\index.html" -Encoding UTF8

    # Create Web site and binding
    $website = New-Website -Name $reponame -ApplicationPool $reponame -PhysicalPath $websitePath -Port $port -IPAddress '*' -Force

    # Update Windows Firewall
    New-NetFirewallRule -DisplayName "Allow Port $port" -Direction Inbound -LocalPort $port -Protocol TCP -Action Allow

    $port++ 

    $secretName = "iis-demo-$reponame"
    $secrets = Get-SECSecretList | Where-Object { $_.Name -eq $secretName } 

    try {
        $secret = $secrets | Select-Object -First 1 # $secrets'in ilk elemanını seç
        $secretID = $secret.ARN # Secret ID'yi al

        $secretValue = Get-SECSecretValue -SecretId $secretID 
        $secretObject = $secretValue.SecretString | ConvertFrom-Json

        $pfxContent = [System.Convert]::FromBase64String($secretObject.'seyithan_pfx')
        [System.IO.File]::WriteAllBytes("C:\temp\$reponame.pfx", $pfxContent)

        $pfxPassword = ConvertTo-SecureString -String $secretObject.'seyithan_pfx_secret' -Force -AsPlainText 

        Import-PfxCertificate -FilePath "C:\temp\$reponame.pfx" -CertStoreLocation Cert:\LocalMachine\My -Password $pfxPassword

        $thumbprint = (Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Subject -eq "CN=*.seyithanalkan.com"}).Thumbprint
        New-WebBinding -Name $reponame -IPAddress "*" -Port 443 -Protocol https -HostHeader "$reponame.seyithanalkan.com" -SSLFlags 1
        New-Item -Path "IIS:\\SslBindings\*!443!$reponame.seyithanalkan.com" -Thumbprint $thumbprint -SSLFlags 1
 
    } catch {
        Write-Host "An error occurred for $($reponame): $_"
    }
}




# GitHub Actions Runner Setup
try {
    $githubActionToken = $secretObject.'gh_action_token'
    $token = Invoke-RestMethod -Uri "https://api.github.com/orgs/seyithan-alkan/actions/runners/registration-token" -Method POST -Headers @{
        "Accept" = "application/vnd.github+json"
        "Authorization" = "Bearer $githubActionToken"
        "X-GitHub-Api-Version" = "2022-11-28"
    } | Select-Object -ExpandProperty token
    
    $runnerName = "${tagName}-runner"
    $runnerWorkDir = "C:\runner_work"
    mkdir C:\runner
    Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.314.1/actions-runner-win-x64-2.314.1.zip -OutFile "C:\runner\actions-runner-win-x64-2.314.1.zip"
    Expand-Archive -Path "C:\runner\actions-runner-win-x64-2.314.1.zip" -DestinationPath "C:\runner"
    Set-Location -Path "C:\runner"
    ./config.cmd --url https://github.com/seyithan-alkan --token $token --runnergroup default --labels self-hosted,Windows,$tagName --name $runnerName  --work  $runnerWorkDir --unattended 
    Start-Process -FilePath "powershell" -ArgumentList "-Command", 'Start-Process -FilePath ".\run.cmd" -Verb RunAs'

} catch {
    Write-Host "GitHub Actions Runner setup failed: $_"
}


</powershell>
