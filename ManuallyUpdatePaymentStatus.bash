#!/bin/bash
 
# --------------------------------------------------------------
# Copyright (C) 2017: Early Warning Services, LLC. - All Rights Reserved
#
# Licensing:
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Date:
# November 14, 2017
#
# Author:
# Tyler Oyler
#
# Email:
# tyler.oyler@earlywarning.com
#
# Dependency:
# keystore.jks, cxc-client-tools.jar, Database connection
#
# Description:
# This script will manually update payment ids to the STATUS specfied.
#
# ChangeLog (Unix Timestamps):
# 1510692399-ajs: Initial Setup
# 1511286110-ajs: Updated to restrict operation to only s5583pnlv (PROD, ONS-App3).
# 1511287018-ajs: Updated to include a static db user/pass
# 1511287029-ajs: Updated better handling of an empty STATUS
# 1511805899-ajs: Updated to remove new lines in the -f / -i loop
# 1511805918-ajs: Updated to remove database connection info (now in .globalFunctions)
# 1512577405-ajs: Updated to include a commit statement after the SSL Update.
# 1513624417-ajs: Removed restriction to only fail MSC/VSA payments.
# 1519418527-ajs: Updated to include EXPIRED status
# 1519860285-ajs: Added 'FlushAppCache' to (hopefully) mitigate the failures after certificate update
# 1524594580-ajs: Removed FlushAppCache function and replaced it with a sleep statement.
# 1524599546-ajs: Updated to sort payments and limit the number of times the SSL is updated, and removed cache flushing
# 1525301907-ajs: Updated 'SQLConnection' --> 'SQLWallet', where appropriate.
# 1526064686-ajs: Updated actor to be "$SUDO_USER" instead of just "$USER" (which would always be 'appuser')
# 1528477681-ajs: Added a printed count of payment ids to process
# 1531157084-ajs: Updated prod.clearxchange.net port (9443 --> 10100)
# 1531420099-ajs: Added 'FlushAppCache' (again) to flush all 3 hosts and nodes locally (7443,8443,9443)
# 1610643601-tgo: Now checks all payment statuses at once, instead of looping one sql query per payment
# 1650998142-rtp: Add locking to not clobber other users of CXC Admin Cert
# --------------------------------------------------------------

if [[ ! "$USER" = 'appuser' ]]
    then
        echo -en "Running as a the APPUSER is REQUIRED!  Please sudo to the Appuser (sudo -sHu appuser).\n\n"
        exit 1
fi

# Source Global Functions
if [[ ! -f '/ews/scripts/.globalFunctions' ]]
    then
        echo "Could not source Global Functions!"
        exit 1
    else
        source '/ews/scripts/.globalFunctions'
fi

# Verify our tools exist
if [[ ! -f '/ews/utils/cxc-client-tools.jar' ]]
    then
        echo "Could not locate Client Tools JAR!"
        exit 1
fi
if [[ ! -f '/ews/utils/keystore.jks' ]]
    then
        echo "Could not locate Client Tools Keystore!"
        exit 1
fi

# Setup our functions
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
function VerifyPaymentID(){
SQLWallet <<EOF
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select payment_id from ${DB_SCHEMA}.sd_payment where payment_id in ( $SQL_PAYMENTS ) order by receiving_fi;
exit;
EOF
}
function CountPaymentsDB(){
SQLWallet <<EOF
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select count(1) from ${DB_SCHEMA}.sd_payment where payment_id in ( $SQL_PAYMENTS );
exit;
EOF
}
function CountPaymentsFile(){
wc -l ${OPTARG} | awk '{print $1}' | tr -d "[:blank:]"
}
function CountStatus(){
SQLWallet <<EOF
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select count(1), status from ${DB_SCHEMA}.sd_payment where payment_id in ( $SQL_PAYMENTS ) group by status;
exit;
EOF
}
function SQLfy(){
awk 'BEGIN { ORS="" } { print p"\047"$0"\047"; p=",\r\n" } END { print "\n" }' ${OPTARG}
}
function GetReceivingOrgID(){
SQLWallet <<EOF
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select receiving_fi from ${DB_SCHEMA}.sd_payment where payment_id='$PAYMENTID';
exit;
EOF
}
function GetSendingOrgID(){
SQLWallet <<EOF
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select sending_fi from ${DB_SCHEMA}.sd_payment where payment_id='$PAYMENTID';
exit;
EOF
}
function GetProfileID(){
SQLWallet <<EOF
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select profile_id from ${DB_SCHEMA}.sd_payment where payment_id='$PAYMENTID';
exit;
EOF
}
function CheckSSL(){
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select org_id from ${DB_SCHEMA}.sd_organization_cert where subject_dn = 'CN=admin.clearxchange.com';
exit;
SQL
}
function UpdateSSL(){
if [[ "$1" =~ [A-Z0-9]{3} ]]
    then
        ORGID="$1"
        SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off
update ${DB_SCHEMA}.sd_organization_cert set org_id='$ORGID' where subject_dn = 'CN=admin.clearxchange.com';
commit;
exit;
SQL
        UPDATED=$(CheckSSL)
        if [[ "$UPDATED" = "$ORGID" ]]
            then
                echo -en "Updated SSL to $ORGID\n\n"
                FlushAppCachePayment > /dev/null 2>&1
                sleep 5
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
function DoUpdate(){
"$JVMPATH" -Djavax.net.ssl.keyStore='/ews/utils/keystore.jks' -Djavax.net.ssl.keyStorePassword=KjP0Mv1HuHJFvb0h4AoF -jar '/ews/utils/cxc-client-tools.jar' -url 'https://prod.clearxchange.net:10100/P2P-ws/' -org "$ORGID" -actor "${SUDO_USER}-ManuallyUpdatePaymentStatus.bash" $DETERMINATOR -paymentid "$PAYMENTID" -verbose
}
SCRIPT=$(basename $0 2>/dev/null)
function usage(){
echo -en "\nProper Usage:\n"
echo -en "\n\t${SCRIPT} [-s STATUS {-f FILENAME OR -i PAYMENTID} | -h ]\n\n"
echo -en "\n\t${SCRIPT} -s ::: (This option is REQUIRED and must be set FIRST! { -s DELIVERED | -s DENIED | -s EXPIRED | -s FAILED | -s SENT })"
echo -en "\n\t${SCRIPT} -f ::: (1 Single file that contains payments ids. 1 Payment ID per line.)"
echo -en "\n\t${SCRIPT} -i ::: (1 Single payment id per option { -i PAYMENTID -i PAYMENTID -i PAYMENTID })"
echo -en "\n\t${SCRIPT} -h ::: (Display this help)"
echo -en "\n\n"
}

# Declare the indexed arrays for later.
declare -a SANITIZED_PAYMENTIDS
declare -a PAYMENTIDS

# Do Work
CheckLocking
if [[ "$#" -eq '0' ]]
    then
        echo "No options specified!"
        usage
        exit 1
    else
        while getopts :hs:f:i: opt
            do
                case "$opt" in
                    s)
                        STATUS=$(echo "${OPTARG}" | tr '[:lower:]' '[:upper:]')
                        if [[ "$STATUS" =~ ^(DELIVERED)$ ]]
                            then
                                STATUS="DELIVERED"
                                echo -en "\n\nUpdating all payment statuses to: $STATUS\n\n"
                                DETERMINATOR="-deliveredpayment"
                        elif [[ "$STATUS" =~ ^(DENIED)$ ]] #new as of schema 3.8
                            then
                                STATUS="DENIED"
                                echo -en "\n\nUpdating all payment statuses to: $STATUS\n\n"
                                DETERMINATOR="-denypayment -denialcode issue-with-credit-account"
                        elif [[ "$STATUS" =~ ^(FAILED)$ ]]
                            then
                                STATUS="FAILED"
                                echo -en "\n\nUpdating all payment statuses to: $STATUS\n\n"
                                DETERMINATOR="-failpayment"
                        elif [[ "$STATUS" =~ ^(EXPIRED)$ ]]
                            then
                                STATUS="EXPIRED"
                                echo -en "\n\nUpdating all payment statuses to: $STATUS\n\n"
                                DETERMINATOR="-expirepayment"
                        elif [[ "$STATUS" =~ ^(SENT)$ ]]
                            then
                                STATUS="SENT"
                                echo -en "\n\nUpdating all payment statuses to: $STATUS\n\n"
                        else
                            echo -en "\n\nSTATUS was not specified correctly! {DELIVERED|DENIED|FAILED|SENT|EXPIRED}\n\n"
                            exit 1
                        fi
                        ;;
                    f)
                        if [[ ! -z "$STATUS" ]] && [[ -s "${OPTARG}" ]]; then
                          COUNT_PAYMENTS_FILE=$(CountPaymentsFile)
                           if ! [[ "$COUNT_PAYMENTS_FILE" -le 1000 ]]; then
                              echo -en "${OPTARG} has more than 1000 payments/rows.\n\n"
                              exit 1
                           fi
                          SQL_PAYMENTS=$(SQLfy)
                          COUNT_PAYMENTS_DB=$(CountPaymentsDB)
                        if ! [[ "$COUNT_PAYMENTS_DB" -eq "$COUNT_PAYMENTS_FILE" ]] ; then
                             echo -en "The file ${OPTARG} has ${COUNT_PAYMENTS_FILE} rows and doesn't match number of payments found in the DB which was ${COUNT_PAYMENTS_DB}.\n\n"
                             exit 1
                          fi
                          IFS=$'\n'
                          for x in ${OPTARG} ; do 
                              CHECK=$(VerifyPaymentID)
                              SANITIZED_PAYMENTIDS+=($CHECK)
                          done
                          IFS=$' \t\n'
                       else     
                           echo -en "\n\nEither the STATUS was not specified or ${OPTARG} is not valid.\n\n"
                           usage
                           exit 1
                        fi
                        OPT_CHECK1="1"
                        ;;
                    i)
                        if [[ ! -z "$STATUS" ]] && [[ "${OPTARG}" =~ ^([a-zA-Z0-9]{12})$ ]]
                            then
                                SQL_PAYMENTS="'${OPTARG}'"
                                CHECK=$(VerifyPaymentID)
                                if [[ -z "$CHECK" ]]
                                    then
                                        echo -en "Payment ${OPTARG} not found.\n"
                                        exit 1
                                    else
                                        SANITIZED_PAYMENTIDS+=($CHECK)
                                fi
                            else
                                echo -en "Either STATUS was not specified, or the payment id syntax is wrong (12 alphanumeric characters).\n\n"
                                usage
                                exit 1
                        fi
                        OPT_CHECK2="1"
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
fi

# Ensure that both -f and -i arguments aren't used

if [[ -n "$OPT_CHECK1" ]] && [[ -n "$OPT_CHECK2" ]]; then
   echo -en "You can't use -f and -i at the same time.\n\n"
   exit 1
fi
    
# Get the current count, status and confirmation to proceed with the update
echo -en "Current status count: \n\n $(CountStatus) \n"
read -r -p $'\n\nPlease review the results above, and confirm if you\'d like to continue: [y/n] ' PROCEED
case "$PROCEED" in
Y|y)
   echo -e "\n\n"
   ;;
N|n)
   exit 1
   ;;
esac

for PAYMENTID in "${SANITIZED_PAYMENTIDS[@]}"
   do
      # Check the ssl being used in sd_organization_cert for admin.clearxchange.net
      # And update it to the receiving_fi
      # Unless the payment is being updated to EXPIRED
      # Or it's a pending payment to an unknown recipient and we're updating to FAILED
      OLDORG=$(CheckSSL)
      ORGID=$(GetReceivingOrgID)
      PAYMENTID=$(echo "$PAYMENTID" )
         if [[ "$OLDORG" = "$ORGID" ]]; then
            if [[ "$STATUS" = "SENT" ]]; then
               PROFILE_ID=$(GetProfileID)
               DETERMINATOR="-completepayment -profileid '$PROFILE_ID' -receivingorgid '$ORGID'"
            elif [[ "$STATUS" = "EXPIRED" ]]; then
               ORGID=$(GetSendingOrgID)
            elif
	       [[ "$STATUS" = "FAILED" ]] && [[ -z "$ORGID" ]]; then
	       ORGID=$(GetSendingOrgID)
	    fi
            DoUpdate
         fi
         if [[ ! "$OLDORG" = "$ORGID" ]]; then
            if [[ "$STATUS" = "SENT" ]]; then
               PROFILE_ID=$(GetProfileID)
               DETERMINATOR="-completepayment -profileid '$PROFILE_ID' -receivingorgid '$ORGID'"
            elif [[ "$STATUS" = "EXPIRED" ]]; then
               ORGID=$(GetSendingOrgID)
            elif
               [[ "$STATUS" = "FAILED" ]] && [[ -z "$ORGID" ]]; then
               ORGID=$(GetSendingOrgID)
	    fi
            if UpdateSSL "$ORGID"; then
               DoUpdate
            else
               exit 1
            fi
         fi
      echo -en "\n\n"
   done
