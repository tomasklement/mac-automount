#!/bin/bash

# Loads main configuration
# Globals:
#   CUSTOM_CONFIG_FILE_NAME Name of custom config file
# Arguments:
#   None
# Returns:
#   None (globals from config file are set)
function mnt::load_main_config {
  source base_config.sh
  if [[ -n "${CUSTOM_CONFIG_FILE_NAME}" ]] && \
    [[ -f "${CUSTOM_CONFIG_FILE_NAME}" ]]; then
    source "${CUSTOM_CONFIG_FILE_NAME}"
  fi
}

# Normalizes MAC address to format in lowercase with ":" separator used by arp
# Globals:
#   None
# Arguments:
#   MAC address
# Returns:
#   Normalized MAC address
function mnt::normalize_mac_address {
  local reg_exp
  local result
  local i
  local reg_exp_left=()
  local reg_exp_right=()

   for i in {1..6}; do
    reg_exp_left+=( "([0-9a-z]{2})" )
    reg_exp_right+=( "\\${i}" )
   done

  reg_exp_left=$( arr::join ".?" "${reg_exp_left[@]}" )
  reg_exp_right=$( arr::join ":" "${reg_exp_right[@]}" )
  reg_exp="s/^${reg_exp_left}/${reg_exp_right}/i"

  echo "${1}" | sed -E "${reg_exp}" | tr '[:upper:]' '[:lower:]'
}

# Returns relative paths to mounts configurations
# Globals:
#   MOUNTS_CONFIG_DIR Relative path to mounts configurations directory
# Arguments:
#   None
# Returns:
#   Array of relative paths to particular configuration files
function mnt::get_mounts_configs {
  local directories

  for file_path in $MOUNTS_CONFIG_DIR/*; do
    # Ignore sample file
    if [[ "${file_path}" == "${MOUNTS_CONFIG_DIR}/sample.conf" ]]; then
      continue
    fi

    # Ignore files which doesn't end ".conf"
    if ! [[ "${file_path}" =~ .conf$ ]]; then
      continue
    fi

    directories+=( "${file_path}" )
  done

  echo "${directories[@]}"
}

# Resets all configuration variables
# Globals:
#   Config vars: HOST, PORT, HOST_MAC, USERNAME, SHARE_NAME, MOUNT_POINT
# Arguments:
#   None
# Returns:
#   None
function mnt::unset_config_vars {
  HOST=""
  PORT=""
  HOST_MAC=""
  USERNAME=""
  SHARE_NAME=""
  MOUNT_POINT=""
}

# Validates configuration variables
# Globals:
#   Config vars: HOST, USERNAME, SHARE_NAME, MOUNT_POINT
# Arguments:
#   None
# Returns:
#   None
function mnt::validate_config {
  local empty_variables
  local error_text

  empty_variables=(
    $( val::filter_empty_variable_names "HOST" "USERNAME" \
      "SHARE_NAME" "MOUNT_POINT" )
  )

  if [[ "${#empty_variables[@]}" -gt 0 ]]; then
    error_text=$( arr::join ", " "${empty_variables[@]}" )
    error_text="Missing configuration variables: \"${error_text}\" in \"${1}\""
    err::throw 134 "${error_text}"
  fi

  if [[ ! -w "${MOUNT_POINT}" ]]; then
    err::throw 134 "Mount dir \"${MOUNT_POINT}\" is not writable or not exist"
  fi
}

# Process all configured mounts (connect/disconnect)
# Globals:
#   MOUNTS_CONFIG_DIR Relative path to mounts configurations directory
# Arguments:
#   None
# Returns:
#   None
function mnt::validate_all_configs {
  local config

  for config in $( mnt::get_mounts_configs )
  do
    mnt::load_mount_config "${config}"
    # Validate configured variables
    mnt::validate_config
    # Unset configuration vars for next round
    mnt::unset_config_vars
  done
}

# Creates share url
# Globals:
#   Config vars: HOST, PORT, USERNAME, SHARE_NAME
# Arguments:
#   None
# Returns:
#   True or false
function mnt::create_share_url {
  echo "//${USERNAME}@${HOST}:${PORT}/${SHARE_NAME}"
}

# Unmounts network disk
# Globals:
#   Config vars: MOUNT_POINT
# Arguments:
#   None
# Returns:
#   True or false
function mnt::unmount {
  echo "Unmounting \"${MOUNT_POINT}\""
  umount -f "${MOUNT_POINT}" &
}

# Mounts network disk
# Globals:
#   Config vars: HOST, PORT, USERNAME, SHARE_NAME, MOUNT_POINT
# Arguments:
#   None
# Returns:
#   True or false
function mnt::mount {
  local password
  local share_url
  local result

  share_url="//${USERNAME}@${HOST}:${PORT}/${SHARE_NAME}"

  echo "Mounting \"${share_url}\" to \"${MOUNT_POINT}\""
  password=$(security find-internet-password -a ${USERNAME} -s ${HOST} -w \
    2> /dev/null)

  echo "Fetching password for \"${share_url}\" from keychain"
  if [[ "$?" -eq 0 ]]; then
    echo "Password for \"${share_url}\" was found in keychain"
    password=":${password}"
  else
    echo "Password for \"${share_url}\" was not found in keychain"
  fi

  echo "Mounting \"${share_url}\""
  result=$(mount_smbfs \
    "//${USERNAME}${password}@${HOST}:${PORT}/${SHARE_NAME}" "${MOUNT_POINT}" \
    2>&1
  )

  if [[  "$?" -gt 0 ]]; then
    err::throw "$?" "Mount failed: ${result}"
  fi

  echo -e "${GREEN}Successfully mounted \"${share_url}\"${NC}"
}

# Checks if given share is available
# Globals:
#   Config vars: HOST, PORT, HOST_MAC, USERNAME, SHARE_NAME, MOUNT_POINT
# Arguments:
#   Result of "arp -a" to check MAC address
# Returns:
#   True or false
function mnt::is_online {
  local host_port="\"${HOST}:${PORT}\""
  # Error output must be redirected - netcat puts success messages to it
  if ! nc -z -G 3 "${HOST}" "${PORT}" &> /dev/null; then
    echo "Port \"${HOST}:${PORT}\" is not open"
    false
    return
  fi

  echo "Port \"${HOST}:${PORT}\" is open"

  if [[ ! -z "${HOST_MAC}" ]]; then
    if ! echo "${1}" | grep -q "${HOST_MAC}"; then
      echo "Host \"${HOST}\" has not correct MAC \"${HOST_MAC}\""
      false
      return
    fi

    echo "Host \"${HOST}\" has correct MAC \"${HOST_MAC}\""
  fi

  true
  return
}

# Check if given share is already mounted
# Globals:
#   None
# Arguments:
#   Local mount point
# Returns:
#   True or false
function mnt::is_mounted {
  if mount | grep "on ${1}" > /dev/null; then
    echo "Mount point \"${1}\" is mounted"
    true
    return
  fi

  echo "Mount point \"${1}\" is not mounted"
  false
  return
}

# Loads global configuration variables from configuration file
# Globals:
#   Config vars: HOST, PORT, HOST_MAC, USERNAME, SHARE_NAME, MOUNT_POINT
# Arguments:
#   Configuration file path
# Returns:
#   None
function mnt::load_mount_config {
  # Declare default values
  PORT="139"

  source "${1}"

  if [[ ! -z "$HOST_MAC" ]]; then
      HOST_MAC=$( mnt::normalize_mac_address "${HOST_MAC}" )
  fi
}

# Process all configured mounts (connect/disconnect)
# Globals:
#   MOUNTS_CONFIG_DIR Relative path to mounts configurations directory
# Arguments:
#   None
# Returns:
#   None
function mnt::process {
  local config
  local mac_addresses
  local is_mounted
  local is_online

  for config in $( mnt::get_mounts_configs )
  do
    is_mounted=false
    is_online=false

    echo -e "${BLUE}Start processing of \""${config}"\"${NC}"

    mnt::load_mount_config "${config}"

    # In case MAC address check is reqired, load all MAC addresses in local net
    # and use that for next iterations (to save time)
    if [[ ! -z "$HOST_MAC" ]] && [[ -z "${mac_addresses}" ]]; then
        mac_addresses=$( arp -a )
    fi

    if mnt::is_mounted "${MOUNT_POINT}"; then
      is_mounted=true
    fi

    if mnt::is_online "${mac_addresses}"; then
      is_online=true
    fi

    if "${is_mounted}" && ! "${is_online}"; then
      mnt::unmount
    fi

    if "${is_online}" && ! "${is_mounted}"; then
      mnt::mount
    fi

    # Unset configuration vars for next round
    mnt::unset_config_vars
  done
}

# Saves passwords for configured shares to keychain. Compatible with records
# added by Finder, so they are available for use by Finder
# Globals:
#   None
# Arguments:
#   Configuration file path
# Returns:
#   None
function mnt::save_passwords {
  local config
  local share_url
  local password
  local current_path

  current_path=$( pwd )

  for config in $( mnt::get_mounts_configs )
  do
    mnt::load_mount_config "${config}"

    share_url=$( mnt::create_share_url )

    read -s -p \
      "Enter password for \"${share_url}\" (leave blank for no password): "\
      password

    echo

    if [[ ! -z "${password}" ]]; then
      security add-internet-password\
        -a "${USERNAME}"\
        -s "${HOST}"\
        -p "${SHARE_NAME}"\
        -D "network password"\
        -w "${password}"\
        -T "${current_path}/mount"\
        -P "${PORT}"\
        -r "smb "\
        -j "Added by Mac automount"\
        -U
    fi

    # Unset configuration vars for next round
    mnt::unset_config_vars
  done
}

# Return name of the job file
# Globals:
#   APP_NAME App name used for job
# Arguments:
#   None
# Returns:
#   None
function mnt::get_job_filename {
  echo "${APP_NAME}.plist"
}

# Return path to job file
# Globals:
#   APP_NAME App name used for job
#   HOME User home directory path
# Arguments:
#   None
# Returns:
#   None
function mnt::get_job_path {
  local job_filename
  local job_path
  local working_dir
  local automount_path

  working_dir=$( pwd )
  automount_path="${working_dir}/automount"
  job_filename=$( mnt::get_job_filename )
  job_path="${HOME}/Library/LaunchAgents/${job_filename}"

  echo "${job_path}"
}

# Create job file content
# Globals:
#   APP_NAME App name used for job
#   HOME User home directory path
# Arguments:
#   None
# Returns:
#   None
function mnt::create_job_content {
  local job_xml
  local working_dir
  local automount_path

  working_dir=$( pwd )
  automount_path="${working_dir}/automount"
  job_xml=$( cat launch_agent_template.plist )
  printf "${job_xml}"\
    "${APP_NAME}" "${automount_path}" "${working_dir}"
}

# Creates job
# Globals:
#   APP_NAME App name used for job
#   HOME User home directory path
# Arguments:
#   None
# Returns:
#   None
function mnt::create_job {
  local job_xml
  local job_path

  if mnt::is_automount_running; then
    echo "Removing previously started automount job"
    mnt::remove_job
  fi

  job_path=$( mnt::get_job_path )
  job_xml=$( mnt::create_job_content )

  echo "${job_xml}" > "${job_path}"

  echo "Loading job \"${job_path}\""

  mnt::start_job
}

# Starts job
# Globals:
#   APP_NAME App name used for job
#   HOME User home directory path
# Arguments:
#   None
# Returns:
#   None
function mnt::start_job {
  local job_path

  job_path=$( mnt::get_job_path )

  if [[ ! -r "${job_path}" ]]; then
    err::throw 5 "Job file \"${job_path}\" doesn't exist"
  fi

  launchctl load -w "${job_path}"
}

# Stops job
# Globals:
#   APP_NAME App name used for job
#   HOME User home directory path
# Arguments:
#   None
# Returns:
#   None
function mnt::stop_job {
  local job_path

  job_path=$( mnt::get_job_path )

  if ! mnt::is_automount_running; then
    echo "Stop skipped - automount is not running"
    return
  fi

  launchctl unload -w "${job_path}"
  launchctl remove "${APP_NAME}"
}

# Removes job
# Globals:
#   APP_NAME App name used for job
#   HOME User home directory path
# Arguments:
#   None
# Returns:
#   None
function mnt::remove_job {
  local job_path

  job_path=$( mnt::get_job_path )

  mnt::stop_job

  if [[ -e "${job_path}" ]]; then
    rm "${job_path}"
  else
    echo "Job file \"${job_path}\" not found"
  fi
}

# Checks if automount job is running
# Globals:
#   APP_NAME App name used for job
# Arguments:
#   None
# Returns:
#   True when running, False otherwise
function mnt::is_automount_running {
  # Check if the automount is already running
  if launchctl list | grep -q "${APP_NAME}"; then
    true
    return
  fi

  false
  return
}