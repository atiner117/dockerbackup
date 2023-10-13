#!/bin/bash

# Get the hostname
hostname=$(hostname)

# Set the source folder
source_folder="/home/user/"

# Set Docker Volumes Folder
if systemctl is-active snap.docker.dockerd.service > /dev/null; then
    docker_volumes_folder="/var/snap/docker/common/var-lib-docker/volumes/"
else
    docker_volumes_folder="/var/lib/docker/volumes/"
fi

# Define a temporary backup folder under /mnt/backup
temp_backup_folder="/tmp/${hostname}_backup_$(date +\%Y\%m\%d_\%H\%M\%S)"

# Define an array to store the names of running containers
declare -a running_containers

# NTFY webhook URL for notifications
ntfy_webhook_url="https://ntfy.url"

# Logging function
log() {
  local message="$1"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $message"
}

# Error handling function
handle_error() {
  local exit_code="$1"
  local message="$2"
  if [ "$exit_code" -ne 0 ]; then
    log "Error: $message"
    # Send an unsuccessful notification
    curl -X POST -d "$hostname backup was unsuccessful: $message" "$ntfy_webhook_url"
    exit "$exit_code"
  fi
}

# Function to stop Docker containers and copy data
stop_docker_containers() {
  log "Stopping running Docker containers..."
  # Get a list of all running containers and store their names
  mapfile -t running_containers < <(docker ps --format "{{.Names}}")

  # Stop only the running containers
  for container in "${running_containers[@]}"; do
    log "Stopping container: $container"
    docker stop "$container"
    handle_error $? "Failed to stop container: $container"
  done
}

# Function to copy data to tmp
perform_local_backup_copy(){
  # Copy the Docker Dir
  log "Copying source folder to backup location..."
  cp -r "$source_folder" "$temp_backup_folder"

  # Copy the Docker volumes (if any)
  if [ -d "$docker_volumes_folder" ]; then
    log "Copying Docker volumes to backup location..."
    cp -r "$docker_volumes_folder" "$temp_backup_folder/docker_volumes"
  fi
}

# Function to start Docker containers
start_docker_containers() {
  log "Starting Docker containers..."
  for container in "${running_containers[@]}"; do
    log "Starting container: $container"
    docker start "$container"
    handle_error $? "Failed to start container: $container"
  done
}

# Function to perform the backup to local backup
# set your own location to have zip crated to
perform_local_backup_zip() {
  log "Zipping the temporary backup folder..."
  zip -r "/mnt/backup/${hostname}_backup_$(date +\%Y\%m\%d_\%H\%M\%S).zip" "$temp_backup_folder" >/dev/null
}

# Cleanup function
cleanup() {
  log "Cleaning up temporary files..."
  rm -rf "$temp_backup_folder"
}

# Main backup process
log "Starting backup process..."

# Ensure the temporary backup folder doesn't exist
if [ -d "$temp_backup_folder" ]; then
  log "Error: Temporary backup folder already exists. Aborting."
  exit 1
fi

# Call the function to manage containers
stop_docker_containers

# Perform the local backup
perform_local_backup_copy

# Start the containers that were stopped
start_docker_containers

# Perform the local backup
perform_local_backup_zip

# Clean up the temporary files
cleanup

log "Backup process completed successfully."
# Send a successful notification
curl -X POST -d "$hostname backup was successful" "$ntfy_webhook_url"