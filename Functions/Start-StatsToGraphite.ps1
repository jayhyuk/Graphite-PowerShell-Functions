Function Start-StatsToGraphite
{
<#
    .Synopsis
        Starts the loop which sends Windows Performance Counters to Graphite.

    .Description
        Starts the loop which sends Windows Performance Counters to Graphite. Configuration is all done from the StatsToGraphiteConfig.xml file.

    .Parameter Verbose
        Provides Verbose output which is useful for troubleshooting

    .Parameter TestMode
        Metrics that would be sent to Graphite is shown, without sending the metric on to Graphite.

    .Parameter ExcludePerfCounters
        Excludes Performance counters defined in XML config

    .Parameter SqlMetrics
        Includes SQL Metrics defined in XML config

    .Example
        PS> Start-StatsToGraphite

        Will start the endless loop to send stats to Graphite

    .Example
        PS> Start-StatsToGraphite -Verbose

        Will start the endless loop to send stats to Graphite and provide Verbose output.

    .Example
        PS> Start-StatsToGraphite -SqlMetrics

        Sends perf counters & sql metrics

    .Example
        PS> Start-StatsToGraphite -SqlMetrics -ExcludePerfCounters

        Sends only sql metrics

    .Notes
        NAME:      Start-StatsToGraphite
        AUTHOR:    Matthew Hodgkins
        WEBSITE:   http://www.hodgkins.net.au
#>
    [CmdletBinding()]
    Param
    (
        # Enable Test Mode. Metrics will not be sent to Graphite
        [Parameter(Mandatory = $false)]
        [switch]$TestMode,
        [switch]$ExcludePerfCounters = $false,
        [switch]$SqlMetrics = $false
    )



    # Run The Load XML Config Function
    $Config = Import-XMLConfig -ConfigPath $configPath

    # Get Last Run Time
    $sleep = 0
    $oldsumOfelapsedtimerequest =0
    $oldsumOfelapsedtime = 0

    $configFileLastWrite = (Get-Item -Path $configPath).LastWriteTime

    if($ExcludePerfCounters -and -not $SqlMetrics) {
        throw "Parameter combination provided will prevent any metrics from being collected"
    }

    if($SqlMetrics) {
        if ($Config.MSSQLServers.Length -gt 0)
        {
            # Check for SQLPS Module
			$listofSQLModules = Get-Module -List SQLPS
			write-verbose($listofSQLModules)
            if ($listofSQLModules -ne $null)
            {
                # Load The SQL Module
                Import-Module SQLPS -DisableNameChecking
            }
            # Check for the PS SQL SnapIn
            elseif ((Test-Path ($env:ProgramFiles + '\Microsoft SQL Server\100\Tools\Binn\Microsoft.SqlServer.Management.PSProvider.dll')) `
                -or (Test-Path ($env:ProgramFiles + ' (x86)' + '\Microsoft SQL Server\100\Tools\Binn\Microsoft.SqlServer.Management.PSProvider.dll')))
            {
                # Load The SQL SnapIns
                Add-PSSnapin SqlServerCmdletSnapin100
                Add-PSSnapin SqlServerProviderSnapin100
            }
            # If No Snapin's Found end the function
            else
            {
                throw "Unable to find any SQL CmdLets. Please install them and try again."
            }
        }
        else
        {
            Write-Warning "There are no SQL Servers in your configuration file. No SQL metrics will be collected."
        }
    }

	$elapseTime =999999;
	
    # Start Endless Loop
    while ($true)
    {

     $iterationStopWatch = [System.Diagnostics.Stopwatch]::StartNew()

        $nowUtc = [datetime]::UtcNow

        $timeNext = (Get-Date).AddMinutes(1) 
        # Loop until enough time has passed to run the process again.
        if($sleep -gt 0) {
            Start-Sleep -Milliseconds $sleep
        }


        # Used to track execution time
       

        # Round Time to Nearest Time Period
       
        $metricsToSend = @{}
		$metricsTime = @{}
        

        if(-not $ExcludePerfCounters)
        {

            foreach($PerformanceCounter in  $Config.PerformanceCounter){
			if($PerformanceCounter.ElapseTime -gt $PerformanceCounter.MetricTimeSpan.TotalMilliseconds ){
            $perFormanceCounter.ElapseTime =0
            Write-Warning $PerformanceCounter.MetricTimeSpan.TotalMilliseconds;
            # Take the Sample of the Counter
            Write-Warning $PerformanceCounter.Counters.Length;
            $collections = Get-Counter -Counter $PerformanceCounter.Counters -SampleInterval 1 -MaxSamples 1
            # Filter the Output of the Counters
            $samples = $collections.CounterSamples

        

            # Verbose
            Write-Verbose "All Samples Collected"

            # Loop Through All The Counters
            foreach ($sample in $samples)
            {
                if ($Config.ShowOutput)
                {
                    Write-Verbose "Sample Name: $($sample.Path)"
                }
                # Create Stopwatch for Filter Time Period
                $filterStopWatch = [System.Diagnostics.Stopwatch]::StartNew()

                # Check if there are filters or not
                if ([string]::IsNullOrWhiteSpace($Config.Filters) -or $sample.Path -notmatch [regex]$Config.Filters)
                {
                    # Run the sample path through the ConvertTo-GraphiteMetric function
                    $cleanNameOfSample = ConvertTo-GraphiteMetric -MetricToClean $sample.Path -HostName $Config.NodeHostName -MetricReplacementHash $Config.MetricReplace
                    
                    # Build the full metric path
                    if( $cleanNameOfSample.indexOf('sql') -eq -1){
                    $metricPath = ($Config.MetricPath +'.' + ( $cleanNameOfSample  -replace $Config.NodeHostName,($Config.NodeHostName+'.os.'+$Config.MetricPath2))).ToLower()
                    }
                    else
                    {
                    $metricPath = ($Config.MetricPath +'.' + ( $cleanNameOfSample  -replace $Config.NodeHostName,($Config.NodeHostName+'.dbengine.sql'))).ToLower()
                    
                    }
                    
                    $metricsToSend[$metricPath] = $sample.Cookedvalue
                    echo  $metricPath;
                    $metricsTime[$metricPath] = $nowUtc
                }
                else
                {
                    Write-Verbose "Filtering out Sample Name: $($sample.Path) as it matches something in the filters."
                }

                $filterStopWatch.Stop()

                Write-Verbose "Job Execution Time To Get to Clean Metrics: $($filterStopWatch.Elapsed.TotalSeconds) seconds."
				
				
            }
            }
            
			}
        
             $sumOfelapsedtimerequest =0
             $sumOfelapsedtime = 0
             $addOnMetric =@{}

             $responseKey = ""
           foreach ($key in $metricsToSend.Keys)
           { 
	           if( $key.IndexOf("freemegabytes") -gt 0 )
                {
                     #$sumOfelapsedtime += $($metricsToSend[$key])
               
                    if($metricsToSend.ContainsKey(($key -replace "freemegabytes","freespace")) )
                    {
                    $freespace =  $metricsToSend[($key -replace "freemegabytes","freespace")]
                    $freesmeg =  $metricsToSend[$key]
                    $usedspace = $freesmeg* 100/$freespace - $freesmeg
                    Write-Warning $usedspace
                     
                     $addOnMetric[($key -replace "freemegabytes","usedmegabytes")] =  $usedspace
                     $metricsTime[($key -replace "freemegabytes","usedmegabytes")] = $nowUtc
                    }
                    else
                    {
                    Write-Warning  "Not found freespace"
                    Write-Warning ($key -replace "freemegabytes","freespace")
        
                    }

                }


                if( $key.IndexOf("batchrespstatistics.elapsedtime.requests") -gt 0 )
                {
                $sumOfelapsedtimerequest+= $metricsToSend[$key]
                }
                
                if( $key.IndexOf("batchrespstatistics.elapsedtime.total.ms") -gt 0 )
                {
                $sumOfelapsedtime+= $metricsToSend[$key]
                }
                
           }

           $metricsToSend += $addOnMetric
           
           if( $oldsumOfelapsedtimerequest -eq 0){
           
           
              $oldsumOfelapsedtime = $sumOfelapsedtime
               $oldsumOfelapsedtimerequest = $sumOfelapsedtimerequest
           Write-Warning $sumOfelapsedtimerequest
           Write-Warning $sumOfelapsedtime
           Write-Warning "================"

           }
           else
           {
                $difsumOfelapsedtime  = $sumOfelapsedtime - $oldsumOfelapsedtime 
                $difsumOfelapsedtimerequest =  $sumOfelapsedtimerequest -  $oldsumOfelapsedtimerequest
                if($difsumOfelapsedtime -lt 0 -or $difsumOfelapsedtimerequest -lt 0){}
                else{
              #  $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                $tempMetricName = $Config.MetricPath +'.' +$Config.NodeHostName.ToLower() +'.dbengine.sql.sqlserver.batchrespstatistics.responsetime' 
                 $metricsToSend[$tempMetricName]  =$difsumOfelapsedtime /$difsumOfelapsedtimerequest
                  $metricsTime[$tempMetricName] = $nowUtc

                          Write-Warning $difsumOfelapsedtime
           Write-Warning $difsumOfelapsedtimerequest
           Write-Warning "=================================================================="

               $oldsumOfelapsedtime = $sumOfelapsedtime
               $oldsumOfelapsedtimerequest = $sumOfelapsedtimerequest
             #    $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
         
           }
           }

    
            	
        }# end if ExcludePerfCounters

        if($SqlMetrics) {
            # Loop through each SQL Server
            foreach ($sqlServer in $Config.MSSQLServers)
            {
				if($sqlServer.ElapseTime -gt $sqlServer.MSSQLMetricTimeSpan.TotalMilliseconds)
				{
                Write-Verbose "Running through SQLServer $($sqlServer.ServerInstance)"
                # Loop through each query for the SQL server
                foreach ($query in $sqlServer.Queries)
                {
                    Write-Verbose "Current Query $($query.TSQL)"

                    $sqlCmdParams = @{
                        'ServerInstance' = $sqlServer.ServerInstance;
                        'Database' = $query.Database;
                        'Query' = $query.TSQL;
                        'ConnectionTimeout' = $Config.MSSQLConnectTimeout;
                        'QueryTimeout' = $Config.MSSQLQueryTimeout
                    }

                    # Run the Invoke-SqlCmd Cmdlet with a username and password only if they are present in the config file
                    if (-not [string]::IsNullOrWhitespace($sqlServer.Username) `
                        -and -not [string]::IsNullOrWhitespace($sqlServer.Password))
                    {
                        $sqlCmdParams['Username'] = $sqlServer.Username
                        $sqlCmdParams['Password'] = $sqlServer.Password
                    }

                    # Run the SQL Command
                    try
                    {
                        $commandMeasurement = Measure-Command -Expression {
                            $sqlresult = Invoke-SQLCmd @sqlCmdParams

                            # Build the MetricPath that will be used to send the metric to Graphite
                            $metricPath = $sqlServer.MSSQLMetricPath + '.' + $query.MetricName
                          
                            $metricsToSend[$metricPath] = $sqlresult[0]
                            $metricsTime[$metricPath] = $nowUtc
                        }

                        Write-Verbose ('SQL Metric Collection Execution Time: ' + $commandMeasurement.TotalSeconds + ' seconds')
                    }
                    catch
                    {
                        $exceptionText = GetPrettyProblem $_
                        throw "An error occurred with processing the SQL Query. $exceptionText"
                    }
                } #end foreach Query
				
				
				foreach ($StoreProcedure in $sqlServer.StoreProcedures)
                {
                    Write-Verbose "Current Query $($StoreProcedure.StoreName)"
					
					$sqlCmdParams = @{
                        'ServerInstance' = $sqlServer.ServerInstance;
                        'Database' = $StoreProcedure.Database;
                        'Query' = 'EXEC '+$StoreProcedure.StoreName;
                        'ConnectionTimeout' = 2;#$Config.MSSQLConnectTimeout;
                        'QueryTimeout' = 58;
                    }

					if (-not [string]::IsNullOrWhitespace($sqlServer.Username) `
                        -and -not [string]::IsNullOrWhitespace($sqlServer.Password))
                    {
                        $sqlCmdParams['Username'] = $sqlServer.Username
                        $sqlCmdParams['Password'] = $sqlServer.Password
                    }
					
					try
                    {
                        $commandMeasurement = Measure-Command -Expression {
                            $sqlresults = Invoke-SQLCmd @sqlCmdParams
							foreach ($result in $sqlresults){
							Write-Verbose ('metric name: '+$result[0] +' metric value: '+$result[1] +' time : '+$result[2] )
							$metricPath = $result[0] +'&'+$result[2]
                              if($metricPath.IndexOf("mssql{$}$sqlServer.ServerInstance") -gt 0)
                              {
                              $metricPath = $metricPath -replace "mssql{$}$sqlServer.ServerInstance","sqlserver"
                              }
                            $metricsToSend[$metricPath] = $result[1]
                            
                            $metricsTime[$metricPath] = $result[2]
                            
							
                            
							}
                            # Build the MetricPath that will be used to send the metric to Graphite
                            #$metricPath = $Config.MSSQLMetricPath + '.' + $query.MetricName

                            #$metricsToSend[$metricPath] = $sqlresult[0]
                        }

                        Write-Verbose ('SQL Store ' + $commandMeasurement.TotalSeconds + ' seconds')
                    }
                    catch
                    {
					    $exceptionText = GetPrettyProblem $_
						Write-Verbose ('Error ' + $exceptionText )
                     
                        throw "An error occurred with processing the SQL Query. $exceptionText"
                    }
					Write-Verbose ('Hello ' + $StoreProcedure.StoreName )
                   
                }
				$sqlServer.ElapseTime =0
				}
            } #end foreach SQL Server
        }#endif SqlMetrics

        # Send To Graphite Server

           $sendBulkGraphiteMetricsParams = @{
            "CarbonServer" = $Config.CarbonServer
            "CarbonServerPort" = $Config.CarbonServerPort
            "Metrics" = $metricsToSend
            "DateTime" = $metricsTime
            "UDP" = $Config.SendUsingUDP
            "Verbose" = $Config.ShowOutput
            "TestMode" = $TestMode
        }
        Send-BulkGraphiteMetrics @sendBulkGraphiteMetricsParams

        # Reloads The Configuration File After the Loop so new counters can be added on the fly
        if((Get-Item $configPath).LastWriteTime -gt (Get-Date -Date $configFileLastWrite)) {
            $Config = Import-XMLConfig -ConfigPath $configPath
        }

        $iterationStopWatch.Stop()
        $collectionTime = $iterationStopWatch.Elapsed
        
        $timeNow = Get-Date 
        $TimeDiff = New-TimeSpan  $timeNow $timeNext

        if($TimeDiff.TotalSeconds -gt 0)
        {
        $sleep = $TimeDiff.TotalMilliseconds 
        }
        else
        {
        $sleep = 0
        		write-Output("IT USE MORE THAN 1 MINUTES")
        }

		write-Output("Sleep" +$sleep)
		
		if($sleep -lt 0 )
		{$sleep =0}
		$elapseTime += $sleep+$collectionTime.TotalMilliseconds +10
		foreach ($sqlServer in $Config.MSSQLServers)
            {
			$sqlServer.ElapseTime += $sleep+$collectionTime.TotalMilliseconds+10
			}
            foreach($PerformanceCounter in  $Config.PerformanceCounter)
        {
        
        $PerformanceCounter.ElapseTime += $sleep+$collectionTime.TotalMilliseconds+10
        }
        
			
        if ($Config.ShowOutput)
        {
            # Write To Console How Long Execution Took
            $VerboseOutPut = 'PerfMon Job Execution Time: ' + $collectionTime.TotalSeconds + ' seconds'
            Write-Output $VerboseOutPut
			$LogTime = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"
			Write-Output "last Runtime :"+$LogTime
			
        }
    }
}


