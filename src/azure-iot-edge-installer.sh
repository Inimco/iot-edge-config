#!/usr/bin/env bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

if [[ $EUID -ne 0 ]];
then
    echo "$(echo -en "\e[31m")ERROR: $(echo -en "\e[00m")$0 requires elevated privileges.. "
    exit 1
fi

VERSION_TAG="v0.0.1"

# where am i
TOPDIR=$(dirname $0)

######################################
# download_bash_script
#
#    downloads a single bash script from release according to VERSION_TAG
# ARGUMENTS:
#    file_name to be downloaded from release
# OUTPUTS:
#    Write output to stdout
# RETURN:
######################################

function download_bash_script() {
    if [[ $# == 1 ]];
    then
        local file_name=$1
        local url_text=https://github.com/Azure/iot-edge-config/releases/download/${VERSION_TAG}/$file_name
        local tmp_file=$(echo `mktemp -u`)

        printf "attempting to download '%s'.\n" $file_name

        # attempt to download to a temporary file.
        # use 'sudo LOCAL_E2E=1 ./azure-iot-edge-installer.sh {}' to validate local source...
        if [ "$LOCAL_E2E" == "1" ];
        then
            printf "Testing local file '%s'\n" "../$TOPDIR/$file_name"
            cp ../$TOPDIR/$file_name .
        else
            printf "wget '%s' -q -O '%s'\n" $url_text $tmp_file
            wget $url_text -q -O $tmp_file

            # validate request
            exit_code=$?
            if [[ $exit_code != 0 ]];
            then
                printf "ERROR: Failed to download '%s'; error: %d\n" $file_name $exit_code

                rm $tmp_file
                exit $exit_code
            else
                printf "downloaded '%s'\n" $file_name

                mv -f $tmp_file $file_name
                chmod +x $file_name
            fi
        fi
    fi
}

# script
printf "Welcome to azure-iot-edge-installer\n"
printf "\n%s\n" "-------------------------"
printf "Telemetry\n"
printf "%s\n" "---------"
printf "The azure-iot-edge-installer collects usage data in order to improve your experience.\n"
printf "The data is anonymous and does not include commandline argument values.\n"
printf "The data is collected by Microsoft.\n"
printf "You can change your telemetry settings by adding -nt or --telemetry-opt-out to the command line.\n"
printf "\n"

# if helper scripts dont exist, fetch via wget 
if [ -d "iot-edge-installer" ];
then
    printf "Directory iot-edge-installer already exists.\n" 
else
    printf "Preparing install directory.\n"
    mkdir iot-edge-installer
fi

cd iot-edge-installer

printf "Downloading helper files to temporary directory ./iot-edge-installer\n"
download_bash_script validate-tier1-os.sh
download_bash_script install-container-management.sh
download_bash_script install-edge-runtime.sh
download_bash_script validate-post-install.sh
download_bash_script utils.sh
printf "Downloaded helper files to temporary directory ./iot-edge-installer\n"

# import utils
source utils.sh
log_init

# add flag:variable_name dictionary entries
add_option_args "TELEMETRY_OPT_OUT" -nt --telemetry-opt-out
add_option_args "VERBOSE_LOGGING" -v --verbose
add_option_args "SCOPE_ID" -s --scope-id
add_option_args "REGISTRATION_ID" -r --registration-id
add_option_args "SYMMETRIC_KEY" -k --symmetric-key

# parse command line inputs and fetch output from parser
declare -A parsed_cmds="$(cmd_parser $@)"

set_opt_out_selection ${parsed_cmds["TELEMETRY_OPT_OUT"]}

# validate that all arguments are acceptable / known
if [[ ${#@} > 0 && ${#parsed_cmds[*]} == 0 ]];
then
    array=("$*")
    echo Unknown argument "${array[*]}"
    echo "Usage: sudo ./azure-iot-edge-installer.sh -s <IDScope> -r <RegistrationID> -k <Symmetric Key>"
    exit 1
fi

if [[ "${parsed_cmds["SCOPE_ID"]}" == "" || "${parsed_cmds["REGISTRATION_ID"]}" == "" || "${parsed_cmds["SYMMETRIC_KEY"]}" == "" ]];
then
    echo Missing argument
    echo     defined: "'"${!parsed_cmds[@]}"'"
    echo     given: "'"${parsed_cmds[@]}"'"
    echo "Usage: sudo ./azure-iot-edge-installer.sh -s <IDScope> -r <RegistrationID> -k <Symmetric Key>"
    exit 1
fi

# check if current OS is Tier 1
source /etc/os-release
source validate-tier1-os.sh
is_os_tier1
if [ "$?" != "0" ];
then 
    log_error "This OS is not supported. Please visit this link for more information https://docs.microsoft.com/en-us/azure/iot-edge/support?view=iotedge-2020-11#tier-1."
else
    # run scripts in order, can take parsed input from above
    platform=$(get_platform)
    prepare_apt $platform

    source install-container-management.sh
    install_container_management

    source install-edge-runtime.sh
    install_edge_runtime ${parsed_cmds["SCOPE_ID"]}  ${parsed_cmds["REGISTRATION_ID"]} ${parsed_cmds["SYMMETRIC_KEY"]}

    source validate-post-install.sh
    validate_post_install
fi

# cleanup, always
cd ..
if [ -d "iot-edge-installer" ] 
then
    log_info "Removing temporary directory files for iot-edge-installer."
    rm -rf iot-edge-installer
    log_info "Removed temporary directory files for iot-edge-installer."
fi

announce_my_log_file "All logs were appended to" $OUTPUT_FILE
