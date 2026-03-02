#!/bin/bash

# Check if we are inside the canuto-framework repository
# Update the detection logic
if [ ! -d ".git" ]; then
    echo "Error: This script must be run inside a Git repository."
    exit 1
fi

repo_name=$(basename `git rev-parse --show-toplevel`)
if [ "$repo_name" != "canuto-framework" ]; then
    echo "Error: This script must be run inside the canuto-framework repository."
    exit 1
fi

# Detect modes
if [ "\$1" == "--update" ]; then
    mode="update"
elif [ "\$1" == "--install" ]; then
    mode="install"
else
    mode="auto"
fi

# Check if called via pipe and read arguments
if [ "\$-" == *i* ]; then
    # If not interactive, treat input as arguments
    set -- "$(cat)"
fi

# Pass arguments to the script
case "$mode" in
    update)
        echo "Updating..."
        # Add update logic here
        ;;  
    install)
        echo "Installing..."
        # Add install logic here
        ;;  
    *)
        echo "Running in auto mode..."
        ;;  
esac

exit 0
