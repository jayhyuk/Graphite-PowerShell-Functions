Function Import-XMLConfig
{
<#
    .Synopsis
        Loads the XML Config File for Send-StatsToGraphite.

    .Description
        Loads the XML Config File for Send-StatsToGraphite.

    .Parameter ConfigPath
        Full path to the configuration XML file.

    .Example
        Import-XMLConfig -ConfigPath C:\Stats\Send-PowerShellGraphite.ps1

    .Notes
        NAME:      Convert-TimeZone
        AUTHOR:    Matthew Hodgkins
        WEBSITE:   http://www.hodgkins.net.au

#>
    [CmdletBinding()]
    Param
    (
        # Configuration File Path
        [Parameter(Mandatory = $true)]
        $ConfigPath
    )

    [hashtable]$Config = @{ }

    # Load Configuration File
    $xmlfile = [xml]([System.IO.File]::ReadAllText($configPath))

    # Set the Graphite carbon server location and port number
    $Config.CarbonServer = $xmlfile.Configuration.Graphite.CarbonServer
    $Config.CarbonServerPort = $xmlfile.Configuration.Graphite.CarbonServerPort

    # Get the HostName to use for the metrics from the config file
    $Config.NodeHostName = $xmlfile.Configuration.Graphite.NodeHostName
    
    # Set the NodeHostName to ComputerName
    if($Config.NodeHostName -eq '$env:COMPUTERNAME')
    {
        $Config.NodeHostName = $env:COMPUTERNAME
    }

    
    # Convert Value in Configuration File to Bool for Sending via UDP
    [bool]$Config.SendUsingUDP = [System.Convert]::ToBoolean($xmlfile.Configuration.Graphite.SendUsingUDP)


    # What is the metric path

    $Config.MetricPath = $xmlfile.Configuration.Graphite.MetricPath
    $Config.MetricPath2 = $xmlfile.Configuration.Graphite.MetricPath2
    # Convert Value in Configuration File to Bool for showing Verbose Output
    [bool]$Config.ShowOutput = [System.Convert]::ToBoolean($xmlfile.Configuration.Logging.VerboseOutput)

    # Create the Performance Counters Array
    $Config.Counters = @()


    $Config.PerformanceCounter = @()     

    foreach($PerformanceCounter in $xmlfile.Configuration.PerformancesMetrics.PerformanceCounter){
    # Get Metric Send Interval From Config
  
    # Convert Interval into TimeSpan
  
    $Counters = @()
    [int]$time = $PerformanceCounter.PerformanceCounters.MetricSendIntervalSecond
    $timespan = [timespan]::FromSeconds($time)

       
    # Load each row from the configuration file into the counter array
    foreach ($Counter in $PerformanceCounter.PerformanceCounters.Counter)
    {
        $Counters += $Counter.Name
        Write-Warning $Counter.Name
    }
   
 
    
    $Config.PerformanceCounter += [pscustomobject]@{
                Counters  = $Counters 
                MetricTimeSpan = $timespan
				ElapseTime =99999999999
				}
    }


    # Create the Metric Cleanup Hashtable
    $Config.MetricReplace = New-Object System.Collections.Specialized.OrderedDictionary

    # Load metric cleanup config
    ForEach ($metricreplace in $xmlfile.Configuration.MetricCleaning.MetricReplace)
    {
        # Load each MetricReplace into an array
        $Config.MetricReplace.Add($metricreplace.This,$metricreplace.With)
    }

    $Config.Filters = [string]::Empty;
    # Load each row from the configuration file into the counter array
    foreach ($MetricFilter in $xmlfile.Configuration.Filtering.MetricFilter)
    {
        $Config.Filters += $MetricFilter.Name + '|'
    }

    if($Config.Filters.Length -gt 0) {
        # Trim trailing and leading white spaces
        $Config.Filters = $Config.Filters.Trim()

        # Strip the Last Pipe From the filters string so regex can work against the string.
        $Config.Filters = $Config.Filters.TrimEnd("|")
    }
    else
    {
        $Config.Filters = $null
    }

    # Doesn't throw errors if users decide to delete the SQL section from the XML file. Issue #32.
    try
    {
        # Below is for SQL Metrics
       

        # Create the Performance Counters Array
        $Config.MSSQLServers = @()     
     
      foreach ($msMetics in $xmlfile.Configuration.MSSQLMetics){
       
       [int]$Config.MSSQLMetricSendIntervalSeconds = $msMetics.MetricSendIntervalSeconds
        $Config.MSSQLMetricTimeSpan = [timespan]::FromSeconds($Config.MSSQLMetricSendIntervalSeconds)
        [int]$Config.MSSQLConnectTimeout = $msMetics.SQLConnectionTimeoutSeconds
        [int]$Config.MSSQLQueryTimeout = $msMetics.SQLQueryTimeoutSeconds
        foreach ($sqlServer in $msMetics.SQLServers.sqlServer)
        {
            # Load each SQL Server into an array
			
			if ( $sqlServer.PSObject.Properties.Match('Query').Count -gt 0){
                $Queries = $sqlServer.Query
				}
				else{
				$Queries = @()
				}
			if ( $sqlServer.PSObject.Properties.Match('StoreProcedure').Count -gt 0){
				$StoreProcedures = $sqlServer.StoreProcedure
				}	
				else{
				$StoreProcedures =@()
				}
            $Config.MSSQLServers += [pscustomobject]@{
                ServerInstance = $sqlServer.ServerInstance
                Username = $sqlServer.Username
                Password = $sqlServer.Password
				Queries = $Queries
				StoreProcedures = $StoreProcedures
				MSSQLMetricPath = $msMetics.MetricPath
				MSSQLMetricTimeSpan = [timespan]::FromSeconds($Config.MSSQLMetricSendIntervalSeconds)
				ElapseTime =999999
				}
        }
        }
    }
    catch
    {
        Write-Verbose "SQL configuration has been left out, skipping."
		 $exceptionText = GetPrettyProblem $_
						Write-Verbose ('Error ' + $exceptionText )
    }

    Return $Config
}

# http://support-hq.blogspot.com/2011/07/using-clause-for-powershell.html
function PSUsing
{
    param (
        [System.IDisposable] $inputObject = $(throw "The parameter -inputObject is required."),
        [ScriptBlock] $scriptBlock = $(throw "The parameter -scriptBlock is required.")
    )

    Try
    {
        &$scriptBlock
    }
    Finally
    {
        if ($inputObject -ne $null)
        {
            if ($inputObject.psbase -eq $null)
            {
                $inputObject.Dispose()
            }
            else
            {
                $inputObject.psbase.Dispose()
            }
        }
    }
}

function SendMetrics
{
    param (
        [string]$CarbonServer,
        [int]$CarbonServerPort,
        [string[]]$Metrics,
        [switch]$IsUdp = $false,
        [switch]$TestMode = $false
    )

    if (!($TestMode))
    {
        try
        {
            if ($isUdp)
            {
                PSUsing ($udpobject = new-Object system.Net.Sockets.Udpclient($CarbonServer, $CarbonServerPort)) -ScriptBlock {
                    $enc = new-object system.text.asciiencoding
                    foreach ($metricString in $Metrics)
                    {
                        $Message += "$($metricString)`r"
                    }
                    $byte = $enc.GetBytes($Message)
                    $Sent = $udpobject.Send($byte,$byte.Length)
                }

                Write-Verbose "Sent via UDP to $($CarbonServer) on port $($CarbonServerPort)."
            }
            else
            {
			$sendCount = 1;
                PSUsing ($socket = New-Object System.Net.Sockets.TCPClient) -ScriptBlock {
                    $socket.connect($CarbonServer, $CarbonServerPort)
                    PSUsing ($stream = $socket.GetStream()) {
                        PSUSing($writer = new-object System.IO.StreamWriter($stream)) {
                            foreach ($metricString in $Metrics)
                            {
							$sendCount++;
							Write-Verbose $sendCount+""+$metricString;
                                $writer.WriteLine($metricString)
                            }
                            $writer.Flush()
                            Write-Verbose "Sent via TCP to $($CarbonServer) on port $($CarbonServerPort)."
                        }
                    }
                }
            }
        }
        catch
        {
            $exceptionText = GetPrettyProblem $_
            Write-Error "Error sending metrics to the Graphite Server. Please check your configuration file. `n$exceptionText"
        }
    }
}

function GetPrettyProblem {
    param (
        $Problem
    )

    $prettyString = (Out-String -InputObject (format-list -inputobject $Problem -Property * -force)).Trim()
    return $prettyString
}
