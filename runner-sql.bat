@ECHO off
SET COMMAND= Import-Module -Name Graphite-PowerShell;^
Start-SQLStatsToGraphite -verbose

Powershell.exe -noexit -Command %COMMAND%

