;MIT License
;
;Copyright (c) 2023-2025 Patrick Trumpis
;
;Permission is hereby granted, free of charge, to any person obtaining a copy
;of this software and associated documentation files (the "Software"), to deal
;in the Software without restriction, including without limitation the rights
;to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;copies of the Software, and to permit persons to whom the Software is
;furnished to do so, subject to the following conditions:
;
;The above copyright notice and this permission notice shall be included in all
;copies or substantial portions of the Software.
;
;THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;SOFTWARE.

#include <Array.au3>
#include <File.au3>
#include <FileConstants.au3>
#include <InetConstants.au3>
#include <MsgBoxConstants.au3>
#include <TrayConstants.au3>
#include <WinAPIFiles.au3>
#RequireAdmin

;===============================================================
; Install Config - You may change these values
;===============================================================

; Installer meta
$appName = "Snap Camera Server Auto Config"
$version = "1.1.0"

; IP adress of local Snap Camera server (Docker container)
$ip = "127.0.0.1"

; Original Snap Camera server
$host = "studio-app.snapchat.com"
$subjectAltName = "*.snapchat.com"

; Application
$processName = "Snap Camera.exe"

; OpenSSL Path/CMD
$openSslPath = "openssl"
$openSsl64Path = @HomeDrive & "\Program Files\OpenSSL-Win64\bin\openssl.exe"
$openSsl32Path = @HomeDrive & "\Program Files (x86)\OpenSSL-Win32\bin\openssl.exe"

; OpenSSL output files
$sslCrtFile = "studio-app.snapchat.com.crt"
$sslKeyFile = "studio-app.snapchat.com.key"

; URL's for missing software
$serverRepoUrl = "https://github.com/ptrumpis/snap-camera-server"
$latestSourcerUrl = "https://github.com/ptrumpis/snap-camera-server/releases/latest"
$dockerUrl = "https://docker.com"
$openSslUrl = "https://slproweb.com/products/Win32OpenSSL.html"

;===============================================================
;  DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING
;===============================================================
$mbTitle = $appName & " v" & $version

;----------------------------- Admin rights required for /etc/hosts changes  -----------------------------

If Not IsAdmin() Then 
    MsgBox($MB_SYSTEMMODAL, $mbTitle, "Please run this file as Administrator")
    Exit
EndIf

;----------------------------- Pre Check Docker Installation -----------------------------

$pid = Run("docker -v", "", @SW_HIDE)
If $pid = 0 Then
    If IsApplicationInstalled("Docker Desktop", -1) = 0 Then
        MsgBox($MB_SYSTEMMODAL, $mbTitle, "Please download Docker from:" & @CRLF & $dockerUrl)
    Else
        MsgBox($MB_SYSTEMMODAL, $mbTitle, "Docker is installed but not inside your PATH")
    EndIf
    Exit
EndIf

;----------------------------- Pre Check Docker Running -----------------------------

$dockerPID = ProcessExists("Docker Desktop.exe")
If $dockerPID = 0 Then
    MsgBox($MB_SYSTEMMODAL, $mbTitle, "Please start Docker Desktop")
    $dockerPID = ProcessWait("Docker Desktop.exe")
EndIf

;----------------------------- Pre Check OpenSSL Installation -----------------------------

$pid = Run($openSslPath & " help", "", @SW_HIDE)
If $pid = 0 Then
    If IsApplicationInstalled("OpenSSL", -1) = 0 Then
        MsgBox($MB_SYSTEMMODAL, $mbTitle, "Please download OpenSSL from:" & @CRLF & $openSslUrl)
        Exit
    EndIf
    ; OpenSSL is present but not included in PATH (expected default behaviour)
    If FileExists($openSsl64Path) = 1 Then 
        $openSslPath = $openSsl64Path
    ElseIf FileExists($openSsl32Path) = 1 Then
        $openSslPath = $openSsl32Path
    Else
        $openSslPath = ""
    EndIf
EndIf

;----------------------------- Ask user for permission before we start  -----------------------------

$result = MsgBox($MB_OKCANCEL + $MB_ICONINFORMATION, $mbTitle, $mbTitle & @CRLF & _
"by github.com/ptrumpis" & @CRLF & @CRLF & _
"This tool will automatically handle the configuration steps of:" & @CRLF & _
$serverRepoUrl & @CRLF & @CRLF & _
"Do you want to continue?")
If $result = $IDCANCEL Then Exit

;----------------------------- Check Server installation location  -----------------------------

$serverInstallDir = @WorkingDir
If isServerDir($serverInstallDir) = 0 Then
    $serverInstallDir = ""
EndIf

;----------------------------- Resolve unknown Server installation location  -----------------------------

If $serverInstallDir = "" Then
    $result = MsgBox($MB_YESNO + $MB_ICONQUESTION, $mbTitle, "Did you already download 'Snap Camera Server' from:" & @CRLF & @CRLF & $serverRepoUrl)
    If $result = $IDNO Then
        MsgBox($MB_SYSTEMMODAL, $mbTitle, "Please download the latest source files from:" & @CRLF & @CRLF & $latestSourcerUrl)
        Exit
    EndIf

    MsgBox($MB_SYSTEMMODAL + $MB_ICONINFORMATION, $mbTitle, "Ok great!" & @CRLF & _
    "Please select the location of your 'Snap Camera Server' directory in the next step.")
    $serverInstallDir = FileSelectFolder("Snap Camera Server' directory", "", @WorkingDir)
    If $serverInstallDir = "" Then
        MsgBox($MB_SYSTEMMODAL, $mbTitle, "Auto configuration canceled")
        Exit
    EndIf
EndIf

;----------------------------- Resolve unknown OpenSSL installation location  -----------------------------

If $openSslPath = "" Then
    MsgBox($MB_SYSTEMMODAL + $MB_ICONINFORMATION, $mbTitle, _
    "OpenSSL has been found on your Computer but the exact installation path could not be determined." & @CRLF & @CRLF & _
    "Please select the location of your 'openssl.exe' inside your OpenSSL installation directory in the next step.")

    $openSslPath = FileOpenDialog("Please select the path to your openssl.exe file", @WorkingDir, "OpenSSL (*.exe)", $FD_FILEMUSTEXIST + $FD_PATHMUSTEXIST, "openssl.exe")
    If $openSslPath = "" Then
        MsgBox($MB_SYSTEMMODAL, $mbTitle, "Auto configuration canceled")
        Exit
    EndIf
EndIf

;----------------------------- 1. Create a default .env configuration file -----------------------------

FileCopy($serverInstallDir & "\example.env", $serverInstallDir & "\.env", $FC_NOOVERWRITE)

;----------------------------- 2. Generate self signed certificate with OpenSSL -----------------------------

$certFilePath = $serverInstallDir & "\ssl\" & $sslCrtFile
If FileExists($certFilePath) = 0 Then
    GenerateSelfSignedCertificate($openSslPath, $serverInstallDir & "\ssl", "Snap Inc.", $host, $subjectAltName)
EndIf

;----------------------------- 3. Install Snap Camera Server Root certificate -----------------------------

InstallRootCertificate($sslCrtFile, $serverInstallDir & "\ssl")

;----------------------------- 4. Patch Windows hosts file with local Docker IP -----------------------------

If CheckHostsFile($ip, $host) = 0 Then
    If PatchHostsFile($ip, $host) = 0 Then
        MsgBox($MB_SYSTEMMODAL, "Error", "Hosts file could not be accessed")
        Exit
    EndIf
EndIf

;----------------------------- 5. Close running Snap Camera application  -----------------------------

KillProcess($processName)

;----------------------------- 6. Initialize Docker container for the first time  -----------------------------

RunDocker($serverInstallDir)

;----------------------------- Custom helper functions - magic happens here -----------------------------

Func isServerDir($dir)
    Local $serverFiles[6] = ["server.js", "package.json", "docker-compose.yml", "Dockerfile", "ssl", "src"]
    For $i = 0 To 5
        $checkFile = $dir & "\" & $serverFiles[$i]
        If FileExists($checkFile) = 0 Then
            Return 0
            ExitLoop
        EndIf
    Next
    Return 1
EndFunc

Func CheckHostsFile($ip, $host)
    $filePath = @WindowsDir & "\System32\drivers\etc\hosts"
    $arrLines = FileReadToArray ($filePath)
    $nLines = Ubound($arrLines)

    For $i = 0 To ($nLines-1)
        If StringRegExp($arrLines[$i], "^" & $ip & "\s*" & $host) Then
            Return 1
        EndIf
    Next
    Return 0
EndFunc

Func PatchHostsFile($ip, $host)
    $filePath = @WindowsDir & "\System32\drivers\etc\hosts"
    $newLine = $ip & "       " & $host & @CRLF

    $fileContent = FileRead($filePath)
    If @error Then Return 0

    FileCopy($filePath, $filePath & ".bak", $FC_OVERWRITE)

    $hFile = FileOpen($filePath, $FO_WRITE)
    If $hFile = -1 Then
        ConsoleWrite("Failed to open " & $filePath & @CRLF)
        Return 0
    EndIf

    TrayTip("Patching Windows Hosts File", "File " & $filePath, 10, $TIP_NOSOUND)

    FileWrite($hFile, $fileContent & @CRLF)
    FileWriteLine($hFile, "");
    FileWriteLine($hFile,  "# Added by " & $appName)
    FileWriteLine($hFile, $newLine)
    FileWriteLine($hFile,  "# End of section")

    FileClose($hFile)
    Return 1
EndFunc

Func GenerateSelfSignedCertificate($openSslPath, $outputDir, $owner, $domain, $altName, $daysExpire = 3650)
    TrayTip("Generating SSL Certificate", "Domain " & $domain, 10, $TIP_NOSOUND)
    ShellExecuteWait($openSslPath, 'req -x509 -nodes -days ' & $daysExpire & ' -subj "/C=CA/ST=QC/O=' & $owner & '/CN=' & $domain & '" -addext "subjectAltName=DNS:' & $altName & '" -newkey rsa:2048 -keyout ' & $domain & '.key -out ' & $domain & '.crt', $outputDir)
EndFunc

Func InstallRootCertificate($certFile, $workingDir)
    TrayTip("Installing Root Certificate", "Certificate " & $certFile, 10, $TIP_NOSOUND)
    ShellExecuteWait("certutil", "-addstore -enterprise Root " & $certFile, $workingDir)
EndFunc

Func RunDocker($workingDir)
    TrayTip("Running Docker", "docker compose up", 10, $TIP_NOSOUND)
    ShellExecuteWait("docker", "compose up", $workingDir)
EndFunc

Func IsApplicationInstalled($appName, $is64bit = -1)
    If $is64bit = -1 Then
        If IsApplicationInstalled($appName, 0) = 1 Then Return 1
        $is64bit = 1
    EndIf
    $regList = GetRegUninstallList($is64bit)
    If $regList = -1 Then Return -1
    For $key in $regList
        If StringLen($key) > StringLen($appName) Then
            If StringInStr($key, $appName) <> 0 Then Return 1
        Else
            If StringCompare($key, $appName, 0) = 0 Then Return 1
        EndIf
    Next
    Return 0
EndFunc

Func GetRegUninstallList($use64bit = 0)
    $sRegHive = "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    If $use64bit = 1 Then
        $sRegHive = "HKLM64\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    EndIf
    Local $aUninstall[0]
    $i = 1
    While 1
        $sRegKey = RegEnumKey($sRegHive, $i)
        If @error Then ExitLoop
        $sDisplayName = RegRead($sRegHive & "\" & $sRegKey, "DisplayName")
        If @error Then ContinueLoop
        _ArrayAdd($aUninstall, $sDisplayName)
        $i += 1
    WEnd
    Return _ArrayUnique($aUninstall)
EndFunc

Func KillProcess($processName)
    $pid = ProcessExists($processName)
    If $pid Then
        Return ProcessClose($pid)
    Else
        Return 0
    EndIf
EndFunc
