#!/bin/bash

# Framework installation script

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -r, --repo REPO    Specify the repository of the framework to install"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;  
        -r|--repo)
            FRAMEWORK_REPO="$2"
            shift 2
            ;;  
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;  
    esac
done

# Detect framework repository if not specified
if [ -z "$FRAMEWORK_REPO" ]; then
    FRAMEWORK_REPO="https://github.com/example/framework"
fi

# Clone the framework repository
if ! git clone "$FRAMEWORK_REPO"; then
    echo "Failed to clone repository: $FRAMEWORK_REPO"
    exit 1
fi

# Navigate to the cloned repository
cd framework || { echo 'Failed to enter framework directory'; exit 1; }

# Install dependencies
if [ -f requirements.txt ]; then
    echo "Installing dependencies..."
    pip install -r requirements.txt
fi

# Build the framework
echo "Building the framework..."
make

# Finish
echo "Framework installed successfully!"