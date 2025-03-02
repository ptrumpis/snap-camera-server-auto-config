#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "🔑 This script requires administrator rights. Please enter your password:"
    exec sudo "$0" "$@"
    exit 1
fi

echo "......................................."
echo "macOS auto config v1.2.0 with ($SHELL)"
[ -n "$BASH_VERSION" ] && echo "bash version $BASH_VERSION"
[ -n "$ZSH_VERSION" ] && echo "zsh version $ZSH_VERSION"
OS_version=$(sw_vers | awk '/ProductVersion/ {print $2}') || true
[ -z "$OS_version" ] && OS_version="(Unknown)"
architecture=$(uname -m)
echo "OS Version: $OS_version"
echo "Architecture: $architecture"
echo "......................................."

echo "🔍 Checking if Docker is installed."
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker command not found. Please install Docker and try again."
    exit 1
else
    echo "✅ Docker is installed."
fi

echo "🔍 Checking if jq is installed."
if ! command -v jq &>/dev/null; then
    if command -v brew &>/dev/null; then
        echo "🛠️ Installing jq..."
        brew install jq >/dev/null
    else
        echo "⚠️ jq is not installed." 
    fi
else
    echo "✅ jq is installed."
fi

server_ip="127.0.0.1"
hostname="studio-app.snapchat.com"
server_url="https://$hostname"
cert_file="$hostname.crt"

if pgrep -x "Snap Camera" > /dev/null; then
    echo "⚠️ Snap Camera is running. Terminating application."
    pkill -x "Snap Camera"
fi

function to_posix_path() {
    local path="$1"
    local resolved_path=""
    if command -v greadlink >/dev/null 2>&1; then
        resolved_path=$(greadlink -f "$path")
    elif command -v perl >/dev/null 2>&1; then
        resolved_path=$(perl -MCwd=realpath -e 'print realpath($ARGV[0])' "$path")
    elif [[ -d "$path" ]]; then
        resolved_path=$(cd "$path" && pwd -P)
    elif [[ -f "$path" ]]; then
        resolved_path="$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
    fi
    echo "${resolved_path%/}"
}

function verify_directory() {
    local dir
    dir=$(to_posix_path "$1")
    if [[ -d "$dir" && -f "$dir/server.js" && -d "$dir/ssl" ]]; then
        return 0
    else
        return 1
    fi
}

function is_container_running() {
    local container_id
    container_id=$(docker ps -q --filter "name=snap" --filter "name=webapp" | head -n 1)
    if [[ -n "$container_id" ]]; then
        local running
        running=$(docker inspect --format '{{.State.Running}}' "$container_id" 2>/dev/null)
        [[ "$running" == "true" ]] && return 0
    fi
    return 1
}

echo "🔍 Trying to determine server directory."
project_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if [[ -z "$project_dir" || ! -d "$project_dir" || ! verify_directory "$project_dir" ]]; then
    while true; do
        user_input=$(osascript -e 'tell app "Finder" to set folderPath to POSIX path of (choose folder with prompt "Please select the Snap Camera Server directory:")' 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            echo "❌ User canceled directory selection."
            exit 1
        fi
        user_input=$(echo "$user_input" | sed 's/^ *//g' | sed 's/ *$//g')
        if verify_directory "$user_input"; then
            project_dir="${user_input%/}"
            break
        else
            echo "⚠️ Invalid directory: '$user_input'!"
        fi
    done
fi
echo "✅ Snap Camera Server directory: $project_dir"

echo "🔍 Checking if an .env file exists."
env_path="$project_dir/.env"
example_env_path="$project_dir/example.env"
if [[ ! -f "$env_path" ]]; then
    if [[ -f "$example_env_path" ]]; then
        cp "$example_env_path" "$env_path"
        echo "✅ An .env file was created from example.env."
    else
        echo "❌ Error: Neither .env nor example.env found."
        exit 1
    fi
else
    echo "✅ An .env file exists."
fi

echo "🔍 Checking if a '/etc/hosts' entry exists."
if grep -E -q "^$server_ip[[:space:]]+$hostname" /etc/hosts; then
    echo "✅ '/etc/hosts' entry $server_ip $hostname exists."
else
    echo "$server_ip $hostname" | sudo tee -a /etc/hosts
    if grep -E -q "^$server_ip[[:space:]]+$hostname" /etc/hosts; then
        echo "✅ '/etc/hosts' entry $server_ip $hostname was created."
    else
        echo "❌ Error: Failed to create '/etc/hosts' entry."
        exit 1
    fi
fi

echo "🔍 Checking if an SSL certificate is present."
cert_path="$project_dir/ssl/$cert_file"
gen_cert_script="$project_dir/gencert.sh"
if [[ ! -f "$cert_path" ]]; then
    chmod +x "$gen_cert_script"
    if [[ -x "$gen_cert_script" ]]; then
        echo "🔄 Generating new SSL certificate..."
        (cd "$project_dir" && ./gencert.sh)
    else
        echo "❌ Error: SSL certificate missing and gencert.sh is not executable or does not exist."
        exit 1
    fi
else
    echo "✅ SSL certificate found."
fi

echo "🛠️ Setting SSL certificate file ownership."
sudo chown -R $(id -un):$(id -gn) "$project_dir/ssl/*"

echo "🛠️ Adding SSL certificate to Keychain."
cert_hash=$(openssl x509 -in "$cert_path" -noout -fingerprint -sha1 | sed 's/^.*=//')
if [[ -z "$cert_hash" ]]; then
    echo "❌ Error: Failed to read certificate fingerprint! Please check the certificate file."
    exit 1
else
    sudo security delete-certificate -c "$hostname" ~/Library/Keychains/login.keychain-db 2>/dev/null && echo "🗑️ Removed old '$hostname' certificate from Login Keychain."
    sudo security delete-certificate -Z "$cert_hash" ~/Library/Keychains/login.keychain-db 2>/dev/null && echo "🗑️ Removed old certificate from Login Keychain."
    sudo security delete-certificate -c "$hostname" /Library/Keychains/System.keychain 2>/dev/null && echo "🗑️ Removed old '$hostname' certificate from System Keychain."
    sudo security delete-certificate -Z "$cert_hash" /Library/Keychains/System.keychain 2>/dev/null && echo "🗑️ Removed old certificate from System Keychain."
fi
if sudo security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db "$cert_path"; then
    echo "✅ Imported and trusted certificate in Login Keychain."
else
    echo "❌ Error: Failed to mark certificate as trusted in Login Keychain!"
    exit 1
fi
if sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$cert_path"; then
    echo "✅ Imported and trusted certificate in System Keychain."
else
    # Login Keychain should be sufficient
    echo "⚠️ Warning: Failed to mark certificate as trusted in System Keychain!"
fi

echo "🔍 Checking pf-rules."
tmp_rules="/tmp/pf_rules.conf"
sudo pfctl -sr 2>/dev/null > "$tmp_rules"
if [ ! -s "$tmp_rules" ]; then
    echo "✅ No pf rules found. Skipping pf check."
else
    if grep -q "$hostname" "$tmp_rules"; then
        echo "⚠️ Host $hostname is blocked by pf. Unblocking..."
        grep -v "$hostname" "$tmp_rules" | sudo tee "$tmp_rules.filtered" > /dev/null
        sudo pfctl -f "$tmp_rules.filtered"
        sudo pfctl -e
        echo "✅ Host $hostname was unblocked."
    else
        echo "✅ Host $hostname is not blocked by pf."
    fi
fi

echo "🔍 Checking Docker file sharing directories."
docker_restart_required="false"
if ! command -v jq &>/dev/null; then
    echo "⚠️ jq is not installed. Skipping Docker file sharing check."
else
    docker_settings="$HOME/Library/Group Containers/group.com.docker/settings.json"
    if [[ -f "$docker_settings" ]]; then
        if jq -e --arg folder "$project_dir" '.filesharingDirectories | index($folder) != null' "$docker_settings" &>/dev/null; then
            echo "✅ '$project_dir' is already in the Docker whitelist."
        else
            echo "🛠️ Adding '$project_dir' to Docker whitelist."
            cp "$docker_settings" "$docker_settings.bak"
            temp_settings=$(mktemp) && mv "$temp_settings" "${temp_settings}.json" && temp_settings="${temp_settings}.json"
            jq --arg folder "$project_dir" '.filesharingDirectories += [$folder]' "$docker_settings" > "$temp_settings"
            if jq empty "$temp_settings" &>/dev/null; then
                mv "$temp_settings" "$docker_settings"
                echo "✅ Server directory added successfully."
                docker_restart_required="true"
            else
                echo "⚠️ JSON validation failed! Changes were not applied."
            fi
            rm -f "$temp_settings"
        fi
    else
        echo "⚠️ Docker settings.json not found!"
    fi
fi

if pgrep -x "Docker" > /dev/null && [ "$docker_restart_required" == "true" ]; then
    echo "🔄 Restarting Docker..."
    osascript -e 'quit app "Docker"' & disown
    echo "⏳ Waiting for Docker to close..."
    timeout=60
    while docker system info &>/dev/null; do
        sleep 1
        ((timeout--))
        if [ $timeout -le 0 ]; then
            echo "❌ Timeout reached. Docker did not close successfully."
            exit 1
        fi
    done
    echo "✅ Docker closed successfully."
fi

if ! pgrep -x "Docker" > /dev/null; then
    echo "🚀 Starting Docker in the background..."
    open -a Docker & disown
    echo "⏳ Waiting for Docker to start..."
    timeout=60
    while ! docker system info &>/dev/null; do
        sleep 1
        ((timeout--))
        if [ $timeout -le 0 ]; then
            echo "❌ Timeout reached. Docker did not start successfully."
            exit 1
        fi
    done
    echo "✅ Docker started successfully."
fi

if ! is_container_running; then
    echo "🚀 Starting the server with 'docker compose up'."
    (cd "$project_dir" && docker compose up -d)
    max_retries=10
    retries=0
    echo "⏳ Waiting for the server to start... "
    while [[ $retries -lt $max_retries ]]; do
        if is_container_running; then
            echo "✅ Snap Camera Server is now running."
            break
        fi
        ((retries++))
        sleep 6
    done
    if ! is_container_running; then
        echo "❌ Error: Snap Camera Server did not start within the expected time."
        exit 1
    fi
fi

echo "🔍 Sending ping to host $hostname."
if ping -c 1 -W 2000 "$hostname" > /dev/null 2>&1; then
    echo "✅ Ping to host $hostname succesful."
else
    echo "⚠️ Ping to host $hostname failed."
fi

echo "🔍 Sending request to host $server_url."
if command -v curl > /dev/null; then
    server_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$server_url" 2>&1)
    if [[ "$server_response" == "000" ]]; then
        echo "❌ Error: The server $server_url cannot be reached. Checking details..."
        echo "🔍 Running: curl -v --connect-timeout 5 $server_url"
        curl -v --connect-timeout 5 "$server_url"
        echo "🔍 Running: curl -v --insecure --connect-timeout 5 $server_url"
        curl -v --insecure --connect-timeout 5 "$server_url"
        exit 1
    elif [[ "$server_response" =~ ^[0-9]{3}$ ]]; then
        if [[ "$server_response" != "200" ]]; then
            echo "❌ Error: The server $server_url responded with status: $server_response"
            exit 1
        else
            echo "✅ The server $server_url is reachable."
        fi
    else
        echo "❌ Error: The server $server_url cannot be reached:"
        echo "$server_response"
        exit 1
    fi
else
    echo "⚠️ Warning: The 'curl' command is not available. Please check in your browser that the URL $server_url is accessible."
fi

echo "🆗 Snap Camera Server is working!"
