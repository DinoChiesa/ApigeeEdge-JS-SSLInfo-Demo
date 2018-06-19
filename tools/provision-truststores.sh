#!/bin/bash
# -*- mode:shell-script; coding:utf-8; -*-
#
# Created: <Thu Jun 14 18:51:47 2018>
# Last Updated: <2018-June-19 12:09:17>
#

scriptname=${0##*/}
verbosity=2
defaultmgmtserver="https://api.enterprise.apigee.com"
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
version="20180618-1815"
credentials="-n"
key_file=""
cert_file=""
keystore_name=""
keyalias=""
client_cert_file=""
truststore_name=""
vhost_name="api-vhost-2way"
vhost_alias=""
way=""
asset_prefix="js-sslinfo-demo"
reset_wanted=0
check_org_message=""

usage() {
  local CMD=`basename $0`
  echo "$CMD:"
  echo "  Provisions truststores for a demonstration of b/110380889"
  echo "  Uses the curl utility."
  echo "version: ${version}"
  echo "usage:"
  echo "  $CMD [options]"
  echo "options: "
  echo "  -M url      optional. the base url for the Admin APIs. (export mgmtserver=xxx) default: ${mgmtserver:-${defaultmgmtserver}}"
  echo "  -o org      optional. the Apigee Edge organization to use. (export ORG=xxx) default: ${ORG:?-none-}"
  echo "  -e env      optional. the Apigee Edge environment to use. (export ENV=xxx) default: ${ENV:?-none-}"
  echo "  -u creds    optional. http basic authn credentials for the Apigee Edge Admin API  calls. default: use .netrc"
  echo "  -n          optional. use .netrc for credentials for the Apigee Edge Admin API calls"
  echo "  -P prefix   optional. name prefix for assets. default: ${Asset_prefix}."
  echo "  -r          optional. Reset everything. Delete vhost, references, keystore, and truststore."
  exit 1
}

## function MYCURL
## Print the curl command, omitting sensitive parameters, then run it.
## There are side effects:
## 1. puts curl output into file named ${CURL_OUT}. If the CURL_OUT
##    env var is not set prior to calling this function, it is created
##    and the name of a tmp file in /tmp is placed there.
## 2. puts curl http_status into variable CURL_RC
MYCURL() {
  [[ -z "${CURL_OUT}" ]] && CURL_OUT=`mktemp /tmp/apigee-${scriptname}.curl.out.XXXXXX`
  [[ -f "${CURL_OUT}" ]] && rm ${CURL_OUT}
  [[ $verbosity -gt 0 ]] && echo "curl $@"

  # run the curl command
  CURL_RC=`curl $credentials -s -w "%{http_code}" -o "${CURL_OUT}" "$@"`
  [[ $verbosity -gt 0 ]] && printf "==> ${CURL_RC}\n"
}

CleanUp() {
    [[ -f ${CURL_OUT} ]] && rm -rf ${CURL_OUT}
}

check_rc() {
    local rc=$1
    if [[ ${CURL_RC} -ne $rc ]]; then
        printf "failed\n\n"
        cat "$CURL_OUT"
        CleanUp
        exit 1
    fi
}

check_org() {
    local orgType
    [[ $verbosity -gt 0 ]] && echo "checking org ${ORG}..."
    MYCURL -X GET ${mgmtserver}/v1/o/${ORG}
    if [[ ${CURL_RC} -eq 200 ]]; then
        orgType=$(cat ${CURL_OUT} | grep \"type\" | tr '\r\n' ' ' | sed -E 's/"type"|[:, "]//g')
        if [[ "${orgType}" == "paid" ]]; then
            check_org=0
        else
            check_org=1
            check_org_message="That organization does not support user-defined vhosts (org type = ${orgType})"
        fi 
    else
        check_org=1
        check_org_message="That organization cannot be accessed"
    fi
}

check_env() {
  echo "  checking environment ${ENV}..."
  MYCURL -X GET  ${mgmtserver}/v1/o/${ORG}/e/${ENV}
  if [[ ${CURL_RC} -eq 200 ]]; then
    check_env=0
  else
    check_env=1
  fi
}

while getopts "M:o:e:u:nP:rh" opt; do
  case $opt in
    M) mgmtserver=$OPTARG ;;
    o) ORG=$OPTARG ;;
    e) ENV=$OPTARG ;;
    u) credentials="-u $OPTARG" ;;
    n) credentials="-n" ;;
    P) asset_prefix="$OPTARG" ;;
    r) reset_wanted=1 ;;
    h) usage ;;
    *) echo "unknown arg" && usage ;;
  esac
done

[[ -z "$mgmtserver" ]] && { printf "using ${defaultmgmtserver}\n" ; mgmtserver="${defaultmgmtserver}" ; }

[[ "$mgmtserver" =~ ^http ]] || mgmtserver="https://${mgmtserver}" 

[[ -z "$ORG" ]] && { echo "Need to export ORG=xxxx" && usage ; }
check_org
if [[ ${check_org} -ne 0 ]]; then
    printf "\n%s\nExiting.\n\n" "${check_org_message}"
    CleanUp
    exit 1
fi

[[ -z "$ENV" ]] && { echo "Specify environment" && usage ; }
check_env
if [[ ${check_env} -ne 0 ]]; then
    printf "\nCannot access environment ${ENV}.\nExiting.\n\n"
    CleanUp
    exit 1
fi


for fullfile in ${scriptdir}/../certs/*.pem ; do

    pemfile="${fullfile##*/}"
    pemfile_sans_extension="${pemfile%.*}"
    
    truststore_name="${asset_prefix}-${pemfile_sans_extension}"
    if [[ $reset_wanted -eq 0 ]]; then
        printf "\ncreate truststore %s\n" "${truststore_name}"
        MYCURL -X POST $mgmtserver/v1/o/$ORG/e/$ENV/keystores \
               -H Content-Type:text/xml \
               -d '<KeyStore name="'${truststore_name}'"/>'
        check_rc 201

        printf "\nupload certificate\n"
        MYCURL -X POST -H "Content-Type: multipart/form-data" \
               -F certFile="@${scriptdir}/../certs/${pemfile}" \
               "$mgmtserver/v1/o/$ORG/e/$ENV/keystores/${truststore_name}/aliases?alias=${pemfile_sans_extension}&format=keycertfile"
        check_rc 201

        printf "\ncreate a reference %s\n" "${truststore_name}-ref"
        MYCURL -X POST -H "Content-Type:application/xml" \
               $mgmtserver/v1/o/$ORG/e/$ENV/references \
               -d '
    <ResourceReference name="'${truststore_name}'-ref">
        <Refers>'${truststore_name}'</Refers>
        <ResourceType>KeyStore</ResourceType>
    </ResourceReference>'
        check_rc 201
    else

        printf "\ndelete truststore ref %s\n" "${truststore_name}-ref"
        MYCURL -X DELETE $mgmtserver/v1/o/$ORG/e/$ENV/references/${truststore_name}-ref
        printf "\ndelete truststore %s\n" "${truststore_name}"
        MYCURL -X DELETE $mgmtserver/v1/o/$ORG/e/$ENV/keystores/${truststore_name}
    fi
done
