#!/bin/bash

# --------------------------------------------------------------
# Copyright (C) 2018: Early Warning Services, LLC. - All Rights Reserved
#
# Licensing:
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Date:
# May 22, 2018
#
# Author:
# Tyler Oyler
#
# Email:
# tyler.oyler@earlywarning.com
#
# Repository:
# None, (yet).
#
# Dependency:
# client-tools.jar
#
# Description:
# Trigger AddPayment API call with client-tools.jar
#
# ChangeLog (Unix Timestamps):
# 1527016548-ajs: Updated to 'Best Practices' coding standards
# 1529020705-ajs: Updated to contain a check on data submitted
# 1529020718-ajs: Updated to automatically update SSL
# 1529437728-ajs: Updated to run from a getopts while loop
# 1531157084-ajs: Updated next.clearxchange.net port (9443 --> 10100)
# 1594670404-tgo: Added ability to handle standard payments and removed y/n prompt for each transaction
# 1616626696-tgo: Added the ability to handle IN vs OON payments properly, fixed outdated clear cache url
# 1650998142-rtp: Add locking to not clobber other users of CXC Admin Cert
# --------------------------------------------------------------

if [[ ! "$USER" = 'appuser' ]]; then
   echo -en "Running as a the APPUSER is REQUIRED!  Please sudo to the Appuser (sudo -sHu appuser).\n\n"
   exit 1
fi

if [[ ! -f '/ews/scripts/.globalFunctions' ]]; then
   echo "Could not source Global Functions!"
   exit 1
else
   source '/ews/scripts/.globalFunctions'
fi

if [[ "${DB_SCHEMA}" == 'clx_next' ]]; then
   ENV='next'
   APIPORT='443'
elif [[ "${DB_SCHEMA}" == 'sd_p2p' ]]; then
   ENV='prod'
   APIPORT='10100'
else
   printf "I don't know where I am; expecting CAT or PROD.  Aborting.\n" 1>&2
   exit 1
fi

lockfile="/tmp/sd_cert.lock"
function CheckLocking() {
	if [[ -f "$lockfile" ]]; then
		# Someone else is using the cert.  Back off.
		otherpid="$(cat "${lockfile}")"
		printf "Another script is apparently using the SD Org Cert we need.  Aborting.\n" 1>&2
		printf "The PID of the other script appears to be %s.\n" "${otherpid}" 1>&2
		exit 1
	else
		# Good to go, so stash our PID in the lockfile.
		echo $$ > "$lockfile"
		trap 'rm -f "$lockfile"' EXIT
	fi
}
function CheckSSL(){
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select org_id from ${DB_SCHEMA}.sd_organization_cert  where subject_dn = 'CN=admin.clearxchange.com';
exit;
SQL
}

function UpdateSSL(){
   if [[ "$1" =~ [A-Z0-9]{3} ]]; then
      ORGID="$1"
      SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off
update ${DB_SCHEMA}.sd_organization_cert set org_id='$ORGID' where subject_dn = 'CN=admin.clearxchange.com';
commit;
exit;
SQL
      UPDATED=$(CheckSSL)
      if [[ "$UPDATED" = "$ORGID" ]]; then
         echo -en "Updated SSL to $ORGID\n\n"
         curl -k https://${ENV}.clearxchange.net:10100/ZSP-payment-ws-no-cert-required/clear-cache --tlsv1.2 > /dev/null 2>&1
         return 0
      else
         echo "Could not update SSL!"
         return 1
      fi
   else
      echo "RegEx Filter not met, You entered ${1}, which is not allowed!"
      return 1
   fi
}

SCRIPT=$(basename $0 2>/dev/null)

function SetAndDoWork(){
   ORGID=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $1}' | tr '[:lower:]' '[:upper:]')
   PROFILEID=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $2}')
   RECORGID=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $3}')
   SENDERNAME=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $4}')
   MEMO=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $5}')
   AMOUNT=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $6}')
   PAYMENTID=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $7}')
   PRODUCTTYPE=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $8}')
   ADDRESSLINE1=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $9}')
   ADDRESSLINE2=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $10}')
   ADDRESSSTATE=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $11}')
   ADDRESSCITY=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $12}')
   ADDRESSZIP=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $13}')
   ADDRESSCOUNTRY=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $14}')
   DEBITCARDISSUINGBANKNAME=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $15}')
   DEBITCARDISSUINGORGID=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $16}')
   DEBITCARDLAST4DIGITS=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $17}')
   EXPEDITED=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $18}')
   SENDERUUID=$(echo "${ADDPAYMENT}" | awk -F'^' '{print $19}')

   OLDORG=$(CheckSSL)

   if [[ "$OLDORG" = "$ORGID" ]]; then
      DoUpdate
   fi
   if [[ ! "$OLDORG" = "$ORGID" ]]; then
      if UpdateSSL "$ORGID"; then
         DoUpdate
      else
         exit 1 # probably should output some sort of error message here rather than silently dying
      fi
   fi
}

function DoUpdate(){
if [[ "$EXPEDITED" = 1 ]] && [[ -n "$DEBITCARDISSUINGBANKNAME" ]]; then
    "$JVMPATH" -Djavax.net.ssl.keyStore='/ews/utils/keystore.jks' -Djavax.net.ssl.keyStorePassword=KjP0Mv1HuHJFvb0h4AoF -jar '/ews/utils/cxc-client-tools.jar' -url "https://${ENV}.clearxchange.net:${APIPORT}/P2P-ws/" -org "$ORGID" -actor "${SENDERUUID}" -addpaymenttoprofile -profileid "$PROFILEID" -receivingorg "$RECORGID" -sent -sendername "$SENDERNAME" -memo "$MEMO" -amount "$AMOUNT" -paymentid "$PAYMENTID" -expeditedpayment -producttype "$PRODUCTTYPE" -addressline1 "$ADDRESSLINE1" -addressline2 "$ADDRESSLINE2" -addressstate "$ADDRESSSTATE" -addresscity "$ADDRESSCITY" -addresszip "$ADDRESSZIP" -addresscountry "$ADDRESSCOUNTRY" -debitcardissuingbankname "$DEBITCARDISSUINGBANKNAME" -debitcardlast4digits "$DEBITCARDLAST4DIGITS" -sendertype "person" -verbose
elif [[ "$EXPEDITED" = 0 ]] && [[ -n "$DEBITCARDISSUINGBANKNAME" ]]; then
    "$JVMPATH" -Djavax.net.ssl.keyStore='/ews/utils/keystore.jks' -Djavax.net.ssl.keyStorePassword=KjP0Mv1HuHJFvb0h4AoF -jar '/ews/utils/cxc-client-tools.jar' -url "https://${ENV}.clearxchange.net:${APIPORT}/P2P-ws/" -org "$ORGID" -actor "${SENDERUUID}" -addpaymenttoprofile -profileid "$PROFILEID" -receivingorg "$RECORGID" -sent -sendername "$SENDERNAME" -memo "$MEMO" -amount "$AMOUNT" -paymentid "$PAYMENTID" -producttype "$PRODUCTTYPE" -addressline1 "$ADDRESSLINE1" -addressline2 "$ADDRESSLINE2" -addressstate "$ADDRESSSTATE" -addresscity "$ADDRESSCITY" -addresszip "$ADDRESSZIP" -addresscountry "$ADDRESSCOUNTRY" -debitcardissuingbankname "$DEBITCARDISSUINGBANKNAME" -debitcardlast4digits "$DEBITCARDLAST4DIGITS" -sendertype "person" -verbose
elif [[ "$EXPEDITED" = 1 ]] && [[ -n "$DEBITCARDISSUINGORGID" ]] ; then
      "$JVMPATH" -Djavax.net.ssl.keyStore='/ews/utils/keystore.jks' -Djavax.net.ssl.keyStorePassword=KjP0Mv1HuHJFvb0h4AoF -jar '/ews/utils/cxc-client-tools.jar' -url "https://${ENV}.clearxchange.net:${APIPORT}/P2P-ws/" -org "$ORGID" -actor "${SENDERUUID}" -addpaymenttoprofile -profileid "$PROFILEID" -receivingorg "$RECORGID" -sent -sendername "$SENDERNAME" -memo "$MEMO" -amount "$AMOUNT" -paymentid "$PAYMENTID" -expeditedpayment -producttype "$PRODUCTTYPE" -addressline1 "$ADDRESSLINE1" -addressline2 "$ADDRESSLINE2" -addressstate "$ADDRESSSTATE" -addresscity "$ADDRESSCITY" -addresszip "$ADDRESSZIP" -addresscountry "$ADDRESSCOUNTRY" -debitcardissuingorgid "$DEBITCARDISSUINGORGID" -debitcardlast4digits "$DEBITCARDLAST4DIGITS" -sendertype "person" -verbose
elif [[ "$EXPEDITED" = 0 ]] && [[ -n "$DEBITCARDISSUINGORGID" ]]; then
      "$JVMPATH" -Djavax.net.ssl.keyStore='/ews/utils/keystore.jks' -Djavax.net.ssl.keyStorePassword=KjP0Mv1HuHJFvb0h4AoF -jar '/ews/utils/cxc-client-tools.jar' -url "https://${ENV}.clearxchange.net:${APIPORT}/P2P-ws/" -org "$ORGID" -actor "${SENDERUUID}" -addpaymenttoprofile -profileid "$PROFILEID" -receivingorg "$RECORGID" -sent -sendername "$SENDERNAME" -memo "$MEMO" -amount "$AMOUNT" -paymentid "$PAYMENTID" -producttype "$PRODUCTTYPE" -addressline1 "$ADDRESSLINE1" -addressline2 "$ADDRESSLINE2" -addressstate "$ADDRESSSTATE" -addresscity "$ADDRESSCITY" -addresszip "$ADDRESSZIP" -addresscountry "$ADDRESSCOUNTRY" -debitcardissuingorgid "$DEBITCARDISSUINGORGID" -debitcardlast4digits "$DEBITCARDLAST4DIGITS" -sendertype "person" -verbose
else
  echo -en "\nThis receiving profile is in an unexpected state for $PAYMENTID.\n\n"
fi
}

function usage(){
echo -en "\nProper Usage:\n"
echo -en "\n\t${SCRIPT} -f ::: (1 Single file that contains AddPayment strings. 1 AddPayment string per line. DO NOT PUT STRINGS IN DOUBLE QUOTES!)"
echo -en "\n\t${SCRIPT} -i ::: (1 Single AddPayment string per option { -i \"AddPayment\" -i \"AddPayment\" -i \"AddPayment\" } string must be enclosed in double-quotes)"
echo -en "\n\t${SCRIPT} -h ::: (Display this help)"
echo -en "\n\n"
}
CheckLocking
IFS=$'\n'
while getopts :f:i:h OPT
    do
        case "$OPT" in
            f)
                if [[ -s "${OPTARG}" ]]
                    then
                        for ADDPAYMENT in $(cat "${OPTARG}")
                            do
                               if [[ $(echo "$ADDPAYMENT" | awk -F'^' '{print NF}') -eq '19' ]]
                                  then
                                     SetAndDoWork
                                  else
                                     echo "The number of fields (^) is not correct."
                                     exit 1
                               fi
                            done
                    else
                       echo "This file is empty"
                fi
                ;;
            i)
                ADDPAYMENT="${OPTARG}"
                    if [[ $(echo "$ADDPAYMENT" | awk -F'^' '{print NF}') -eq '19' ]]
                       then
                          SetAndDoWork
                    else
                       echo "The number of fields (^) is not correct."
                       exit 1
                    fi
                ;;
            h)
                echo -en "\n\nHelp Details:\n\n"
                usage
                exit 1
                ;;
            \?)
                echo "Invalid option: -$OPTARG"
                exit 1
                ;;
            \:)
                echo "Option -$OPTAGR requires an argument"
                exit 1
                ;;
        esac
    done
IFS=$' \t\n'
