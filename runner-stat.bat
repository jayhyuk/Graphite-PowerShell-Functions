@ECHO off
SET COMMAND= Import-Module -Name Graphite-PowerShell;^
Start-statsToGraphite

Powershell.exe -noexit -Command %COMMAND%

