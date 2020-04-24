#!/bin/bash
fail() {
    echo "ERROR: $1" >&2
    exit 1
}

log() {
    echo "INFO : $1"
}

log_error() {
    echo "ERROR : $1"
}

parse_options() {
    if [ $# -eq 0 ]; then
        echo "No options specified"
        exit 0
    fi

    while [ $# -gt 0 ] ; do
        case "$1" in
            --versions)
                _versions="$2"
                shift
            ;;
            --versions=*)
                _versions="${1#*=}"
            ;;
            --regions)
                _regions="$2"
                shift
            ;;
            --regions=*)
                _regions="${1#*=}"
            ;;
            --oss)
                _oss="$2"
                shift
            ;;
            --oss=*)
                _oss="${1#*=}"
            ;;
            --pythonversion)
                _pythonversion="$2"
                shift
            ;;
            --pythonversion=*)
                _pythonversion="${1#*=}"
            ;;
            *)
                syntax
                fail "Unrecognized option '$1'"
            ;;
        esac
        shift
    done
}

check() {
    [ -z "${_versions}" ] && fail "Parameter --versions cannot be empty"
    IFS=',' read -r -a _versions_array <<< "${_versions}"

    [ -z "${_regions}" ] && fail "Parameter --regions cannot be empty"
    IFS=',' read -r -a _regions_array <<< "${_regions}"

    [ -z "${_oss}" ] && fail "Parameter --oss cannot be empty"
    IFS=',' read -r -a _oss_array <<< "${_oss}"

    [ -z "${_pythonversion}" ] && _pythonversion="3.7.4"

}

test() {
for VERSION in "${_versions_array[@]}"
do
    _virtual_env="pcluster-virtual-env-${VERSION}-$$"
    _python_version="${_pythonversion}"

    echo "Create virtualenv (${_virtual_env})"
    [[ ":$PATH:" != *":/usr/local/bin/.pyenv/bin:"* ]] && PATH="/usr/local/bin/.pyenv/bin:${PATH}"
    eval "$(pyenv init -)" && eval "$(pyenv virtualenv-init -)"

    if [ $(pyenv virtualenvs | egrep -c -e "^ *${_virtual_env} ") -eq 1 ]; then
        pyenv virtualenv-delete -f ${_virtual_env}
    fi
    pyenv virtualenv ${_python_version} ${_virtual_env}
    pyenv activate ${_virtual_env}

    pip install aws-parallelcluster==${VERSION}
    pip install Jinja2

    for REGION in "${_regions_array[@]}"
    do
        for OS in "${_oss_array[@]}"
        do
            # Create the cluster config file
            cluster_config=$(python scripts/make-pcluster-config.py --version ${VERSION} --region ${REGION} --os ${OS})
            cluster_name="${VERSION//.}-${REGION}-${OS}"

            # Create the cluster
            pcluster create -c $cluster_config $cluster_name -nr

            # Sleep for 5 seconds to make sure cluster is ready to go
            sleep 5

            # Get the cluster's status. Ensure it was created successfully. Extract
            # the public IP address of its master node.
            cluster_status_output="$(pcluster status ${cluster_name})"
            if ! echo $cluster_status_output| grep 'Status:' | grep &> /dev/null 'CREATE_COMPLETE' ; then
                log_error 'Cluster creation failed'
            fi
            master_ip=$(echo "$cluster_status_output"| grep 'MasterPublicIP' | egrep -o '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

            case "$OS" in
                alinux|alinux2)
                    cluster_user="ec2-user"
                ;;
                centos6|cento7)
                    cluster_user="centos"
                ;;
                ubutu1604|ubuntu1804)
                    cluster_user="ubuntu"
                ;;
            esac

            disable_host_check="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

            # Copy the log file back over
            scp ${disable_host_check} $cluster_user@$master_ip:/var/log/cfn-init.log log-files/${cluster_name}-cfn-init.log
            scp ${disable_host_check} $cluster_user@$master_ip:/var/log/cfn-init-cmd.log log-files/${cluster_name}-cfn-init-cmd.log
            scp ${disable_host_check} $cluster_user@$master_ip:/var/log/cloud-init.log log-files/${cluster_name}-cloud-init.log
            scp ${disable_host_check} $cluster_user@$master_ip:/var/log/cloud-init-output.log log-files/${cluster_name}-cloud-init-output.log

            # Verify chef.io is not called to download chef installer script or client
            grep -ir "chef-install.sh" log-files/${cluster_name}-cloud-init-output.log | grep "chef.io"
            if [ $? -eq 0 ]; then
                log_error "Chef installer downloaded from chef.io"
            fi
            grep -ir "packages.chef.io" log-files/${cluster_name}-cloud-init-output.log
            if [ $? -eq 0 ]; then
                log_error "Chef package downloaded from chef.io"
            fi

            # Delete the cluster
            echo "Deleting cluster"
            pcluster delete $cluster_name -nw
        done
    done

    echo "Delete virtualenv (${_virtual_env})"
    pyenv deactivate
    pyenv virtualenv-delete -f ${_virtual_env}
done
}

main() {
    parse_options "$@"
    check
    test
}

main "$@"