-- Step 1: Prompt the user to select the server directory
set selectedFolder to choose folder with prompt "Select Snap Camera Server directory"
if selectedFolder is equal to "" then
	display dialog "No server folder selected. Exiting the program." buttons {"OK"} default button "OK"
	error "No folder selected"
end if

-- Step 2: Duplicate "example.env" as ".env"
set exampleEnvPath to POSIX path of selectedFolder & "example.env"
set envFiles to (do shell script "find " & quoted form of (POSIX path of selectedFolder) & " -name '*.env' -maxdepth 1")'s paragraphs
if (count of envFiles) is greater than 0 then
	set firstEnvFile to item 1 of envFiles
	display dialog "Found .env file at: " & firstEnvFile & ". Proceeding with the copy operation." buttons {"OK"} default button "OK"
	-- Rest of your script follows...
end if

if (count of envFiles) is greater than 0 then
	set firstEnvFile to item 1 of envFiles
	try
		do shell script "cp " & quoted form of firstEnvFile & " " & quoted form of (POSIX path of selectedFolder & ".env")
	on error
		display dialog "Failed to copy .env file from: " & firstEnvFile & " to the selected directory: " & (selectedFolder as text) & ". Exiting the program." buttons {"OK"} default button "OK"
		error "Failed to copy .env file"
	end try
else
	display dialog "No .env file found in the selected directory: " & (selectedFolder as text) & ". Exiting the program." buttons {"OK"} default button "OK"
	error "No .env file found in: " & (selectedFolder as text)
end if


-- Step 3: Ensure gencert.sh has execution permissions and execute it
do shell script "chmod +x " & quoted form of (POSIX path of selectedFolder & "gencert.sh")

if not (do shell script "test -f " & quoted form of (POSIX path of selectedFolder & "gencert.sh") & "; echo $?") is "0" then
	display dialog "gencert.sh not found in the selected directory: " & (selectedFolder as text) & ". Exiting the program." buttons {"OK"} default button "OK"
	error "gencert.sh not found in: " & (selectedFolder as text)
end if

try
	do shell script "cd " & quoted form of (POSIX path of selectedFolder) & " && ./gencert.sh"
on error errorMessage
	display dialog "Failed to execute gencert.sh. Error: " & errorMessage buttons {"OK"} default button "OK"
	error "Failed to execute gencert.sh. Detailed error: " & errorMessage
end try

-- Step 4: Verify the presence of "studio-app.snapchat.com.crt" in the "ssl/" subfolder
set sslFolderPath to POSIX path of selectedFolder & "ssl/"
set certPath to sslFolderPath & "studio-app.snapchat.com.crt"
if (do shell script "test -d " & quoted form of sslFolderPath & "; echo $?") is not "0" then
	display dialog "The 'ssl/' folder does not exist in the selected directory: " & (selectedFolder as text) & ". Exiting the program." buttons {"OK"} default button "OK"
	error "ssl/ folder not found in: " & (selectedFolder as text)
else if (do shell script "test -f " & quoted form of certPath & "; echo $?") is not "0" then
	display dialog "studio-app.snapchat.com.crt not found in the 'ssl/' folder of the selected directory: " & (selectedFolder as text) & ". Exiting the program." buttons {"OK"} default button "OK"
	error "studio-app.snapchat.com.crt not found in: " & (selectedFolder as text)
end if

-- Step 5: Add the certificate to the system Keychain and trust it
set certExists to false
try
	set certInfo to do shell script "security find-certificate -c 'studio-app.snapchat.com' /Library/Keychains/System.keychain"
	if certInfo contains "labl" then
		set certExists to true
	end if
on error
	set certExists to false
end try


if not certExists then
	try
		do shell script "sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain " & quoted form of certPath with administrator privileges
	on error errorMessage
		display dialog "Failed to add the certificate automatically. Please ensure it's manually added and trusted in the Keychain Access app. Error details: " & errorMessage buttons {"OK"} default button "OK"
		error "Failed to add the certificate. Detailed error: " & errorMessage
	end try
end if


-- Step 6: Edit the "/etc/hosts" file to redirect the domain
try
	do shell script "echo '127.0.0.1 studio-app.snapchat.com' | sudo tee -a /etc/hosts" with administrator privileges
on error
	display dialog "Failed to edit /etc/hosts. Exiting the program." buttons {"OK"} default button "OK"
	error "Failed to edit /etc/hosts"
end try

-- Step 7: Execute "docker compose up" in the selected directory
set dockerSuccess to false
set errorMsg to ""

-- Try the basic docker-compose command
try
	do shell script "cd " & quoted form of (POSIX path of selectedFolder) & " && docker-compose up"
	set dockerSuccess to true
on error e
	set errorMsg to e
end try

-- If the first attempt fails, try using the full path
if not dockerSuccess then
	try
		do shell script "cd " & quoted form of (POSIX path of selectedFolder) & " && /usr/local/bin/docker-compose up"
		set dockerSuccess to true
	on error e
		set errorMsg to e
	end try
end if

-- If the second attempt fails, try updating $PATH
if not dockerSuccess then
	try
		do shell script "export PATH=/usr/local/bin:$PATH; cd " & quoted form of (POSIX path of selectedFolder) & " && docker-compose up"
		set dockerSuccess to true
	on error e
		set errorMsg to e
	end try
end if

-- If all attempts fail, display the last error message
if not dockerSuccess then
	display dialog "Failed to execute docker-compose up. Error: " & errorMsg buttons {"OK"} default button "OK"
	error "Failed to run docker-compose. Detailed error: " & errorMsg
end if

