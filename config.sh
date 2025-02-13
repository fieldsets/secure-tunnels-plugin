#!/usr/bin/env pwsh

$plugin_path = (Get-Location).Path
$ssh_key_path = [System.Environment]::GetEnvironmentVariable('SSH_KEY_PATH')
$home_path = [System.Environment]::GetEnvironmentVariable('HOME')

if ($ssh_key_path -eq $null) {
    $ssh_key_path = [System.IO.Path]::GetFullPath((Join-Path -Path $home_path -ChildPath './.ssh/'))
} elseif ($ssh_key_path.StartsWith('~')) {
    $ssh_key_path = $ssh_key_path.Replace('~', "$($home_path)")
}

Write-Output "## Secure Tunnels Plugin Config Script ##"
Write-Output "$($plugin_path)"

if (Test-Path -Path "$($plugin_path)/config.json") {
    $config = Get-Content -Raw -Path "$($plugin_path)/config.json" | ConvertFrom-Json

    $retries = $config.retries
    $auto_ssh_port = 40000
    foreach ($forward in $config.forwards) {
        $tunnel_type = ''
        $forward_cmd = ''
        # Check our connections to make sure they are active. Otherwise throw an error
        try {
            $ssh_active =  Test-Connection -TargetName $forward.ssh_host -Ipv4 -TcpPort $forward.ssh_port
            if ($ssh_active) {
                switch ($forward.tunnel_type) {
                    "remote" {
                        $check_host = $forward.local_host
                        if ($check_host -eq "0.0.0.0") {
                            $check_host = "localhost"
                        }
                        $is_active = Test-Connection -TargetName $check_host -Ipv4  -Quiet -Count $retries
                        if ($is_active) {
                            $tunnel_type = '-R'
                            $forward_cmd = "$($forward.remote_port):$($forward.local_host):$($forward.local_port)"
                        } else {
                            Throw "Inactive Host"
                        }
                    }
                    "dynamic" {
                        $tunnel_type = '-D'
                        $forward_cmd = "$($forward.local_port)"
                    }
                    "local" {
                        $check_host = $forward.remote_host
                        if ($check_host -eq "0.0.0.0") {
                            $check_host = "localhost"
                        }
                        $is_active = Test-Connection -TargetName $forward.remote_host -Ipv4  -Quiet -Count $retries
                        if ($is_active) {
                            $tunnel_type = '-L'
                            $forward_cmd = "$($forward.local_port):$($forward.remote_host):$($forward.remote_port)"
                        } else {
                            Throw "Inactive Host"
                        }
                    }
                    default {
                        $check_host = $forward.local_host
                        if ($check_host -eq "0.0.0.0") {
                            $check_host = "localhost"
                        }
                        $is_active = Test-Connection -TargetName $check_host -Ipv4  -Quiet -Count $retries
                        if ($is_active) {
                            $tunnel_type = '-R'
                            $forward_cmd = "$($forward.remote_port):$($forward.local_host):$($forward.local_port)"
                        } else {
                            Throw "Inactive Host"
                        }
                    }
                }

                $key = [System.IO.Path]::GetFullPath((Join-Path -Path $ssh_key_path -ChildPath $forward.ssh_key))
                $log_path = '/data/logs/plugins/secure-tunnels/'
                # Build our autossh command
                [Environment]::SetEnvironmentVariable('AUTOSSH_POLL', 600)
                [Environment]::SetEnvironmentVariable('AUTOSSH_PORT', $auto_ssh_port)
                [Environment]::SetEnvironmentVariable('AUTOSSH_GATETIME', 30)
                [Environment]::SetEnvironmentVariable('AUTOSSH_DEBUG', 'yes')
                [Environment]::SetEnvironmentVariable('AUTOSSH_LOG_PATH', "$($log_path)")
                [Environment]::SetEnvironmentVariable('AUTOSSH_LOGFILE', "$($log_path)secure_tunnels.log")
                mkdir -p "$($log_path)"

                Write-Output "Setting up SSH tunnel."
                $ssh_cmd = "bash -c `"autossh -2 -fN -M $($auto_ssh_port) -o 'ServerAliveInterval=60' -o 'ServerAliveCountMax=2' -o 'StrictHostKeyChecking=no' -4 -o 'IdentitiesOnly=yes' -i $($key) $($tunnel_type) $($forward_cmd) -tt $($forward.ssh_user)@$($forward.ssh_host) -p $($forward.ssh_port)`""
                $processOptions = @{
                    Filepath ="nohup"
                    ArgumentList = "$($ssh_cmd)"
                    RedirectStandardInput = "/dev/null"
                    RedirectStandardOutput = "$($log_path)/config.log"
                    RedirectStandardError = "$($log_path)/config_error.log"
                }
                Start-Process @processOptions
                $auto_ssh_port = $auto_ssh_port + 1
            } else {
                Write-Error "The following tunnel has inactive ssh host connections. If on a slow connection, increase the number of retries. Skipping."
                Write-Error $forward
            }
        } catch {
            Write-Error "An error occurred:"
            Write-Error $_
            Write-Error $_.ScriptStackTrace
        }
    }
} else {
    Write-Output "Missing config.json file. No tunnels created."
}

Exit
Exit-PSHostProcess