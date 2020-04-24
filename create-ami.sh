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
            --cc)
                _cc="$2"
                shift
            ;;
            --cc=*)
                _cc="${1#*=}"
            ;;
            --pythonversion)
                _pythonversion="$2"
                shift
            ;;
            --pythonversion=*)
                _pythonversion="${1#*=}"
            ;;
            *)
                fail "Unrecognized option '$1'"
            ;;
        esac
        shift
    done
}

check() {
    [[ -z "${_versions}" ]] && fail "Parameter --versions cannot be empty"
    IFS=',' read -r -a _versions_array <<< "${_versions}"

    [[ -z "${_regions}" ]] && fail "Parameter --regions cannot be empty"
    IFS=',' read -r -a _regions_array <<< "${_regions}"

    [[ -z "${_oss}" ]] && fail "Parameter --oss cannot be empty"
    IFS=',' read -r -a _oss_array <<< "${_oss}"

    [[ -z "${_cc}" ]] && log "Custom cookbook not provided"
    if [[ -n "${_cc}" ]]; then
        _custom_bookbook="-cc ${_cc}"
    fi

    [[ -z "${_pythonversion}" ]] && _pythonversion="3.7.4"

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
            case "$OS" in
                alinux)
                    base_ami=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn-ami-hvm-*.*.*.*-x86_64-gp2" --query 'reverse(sort_by(Images, &CreationDate))[:1].ImageId' --output text)
                ;;
                alinux2)
                    base_ami=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*.*.*.*-x86_64-gp2" --query 'reverse(sort_by(Images, &CreationDate))[:1].ImageId'  --output text)
                ;;
                centos6)
                    base_ami=$(aws ec2 describe-images --owners "247102896272" --filters "Name=name,Values=CentOS 6.x x86_64 - minimal with cloud-init - *" --query 'reverse(sort_by(Images, &CreationDate))[:1].ImageId' --output text)
                ;;
                cento7)
                    base_ami=$(aws ec2 describe-images --owners "410186602215" --filters "Name=name,Values=CentOS Linux 7 x86_64 HVM EBS ENA " --query 'reverse(sort_by(Images, &CreationDate))[:1].ImageId' --output text)
                ;;
                ubutu1604)
                    base_ami=$(aws ec2 describe-images --owners "099720109477" "513442679011" "837727238323" --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*" --query 'reverse(sort_by(Images, &CreationDate))[:1].ImageId' --output text)
                ;;
                ubuntu1804)
                    base_ami=$(aws ec2 describe-images --owners "099720109477" "513442679011" "837727238323" --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*" --query 'reverse(sort_by(Images, &CreationDate))[:1].ImageId' --output text)
                ;;
            esac

            pcluster createami -ai ${base_ami}  -os $OS -r ${REGION} ${_custom_bookbook} | tee log-files/createami.$OS.${REGION}.${base_ami}.log
            log

            if [ $? -ne 0 ]; then
                log_error "PCluster AMI not built"
            fi

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