#!/bin/bash

# IP address is passed as an argument to this script
user_name=$1
ip_address=$2

# Validate user name
if [[ -z $user_name ]]; then
    echo "User name not specified"
    exit 1
fi

# Validate IP address
if [[ ! $ip_address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid IP address"
    exit 1
fi

# Zip all files in project directory apart from the following:
# - .tmp
# - *.example
# - composes/*/certs/
zip -r project.zip . -x .tmp\* .git .env.example.\* composes/\*/certs\* > /dev/null

# Copy entire project directory to remote host using SCP
scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null project.zip $user_name@$ip_address:/home/$user_name > /dev/null && rm project.zip

if [[ $? -eq 0 ]]; then
    echo "[OK] Project copied to $ip_address in /home/$user_name"
else
    echo "Error copying project to remote host"
    exit 1
fi
cd ..

# Destroy variables
unset user_name
unset ip_address
