-- Step 1: Prompt the user to select the server directory
set selectedFolder to choose folder with prompt "Select Snap Camera Server directory"
if selectedFolder is equal to "" then
    display dialog "No server folder selected. Exiting the program." buttons {"OK"} default button "OK"
    error "No folder selected"
end if

-- Step 2: Duplicate "example.env" as ".env"
tell application "Finder"
    set exampleEnvPath to (selectedFolder as text) & "example.env"
    if exists file exampleEnvPath then
        duplicate file exampleEnvPath to folder selectedFolder with replacing
        set name of result to ".env"
    else
        display dialog "example.env not found in the selected directory. Exiting the program." buttons {"OK"} default button "OK"
        error "example.env not found"
    end if
end tell

-- Step 3: Execute "gencert.sh" script
do shell script "cd " & quoted form of (selectedFolder as text) & " && ./gencert.sh"

-- Step 4: Verify the presence of "studio-app.snapchat.com.crt" in the "ssl/" subfolder
set sslFolderPath to (selectedFolder as text) & "ssl/"
set certPath to sslFolderPath & "studio-app.snapchat.com.crt"
if not (exists folder sslFolderPath) then
    display dialog "The 'ssl/' folder does not exist in the selected directory. Exiting the program." buttons {"OK"} default button "OK"
    error "ssl/ folder not found"
else if not (exists file certPath) then
    display dialog "studio-app.snapchat.com.crt not found in the 'ssl/' folder. Exiting the program." buttons {"OK"} default button "OK"
    error "studio-app.snapchat.com.crt not found"
end if

-- Step 5: Add the certificate to the system Keychain and trust it
do shell script "security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain " & quoted form of certPath

-- Step 6: Edit the "/etc/hosts" file to redirect the domain
do shell script "echo '127.0.0.1 studio-app.snapchat.com' | sudo tee -a /etc/hosts"

-- Step 7: Execute "docker compose up" in the selected directory
do shell script "cd " & quoted form of (selectedFolder as text) & " && docker-compose up"
