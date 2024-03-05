#!/bin/bash

# --------------------------------------------------------------
# Copyright (C) 2017: Early Warning Services, LLC. - All Rights Reserved
#
# Licensing:
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Author:
# Tyler Oyler
#
# Email:
# tyler.oyler@earlywarning.com
#
# Dependency:
# Database Connection with GRANT select, update
#
# Description:
# Script to Retrigger MQ Notifications upon bank request
#
# ChangeLog (Unix Timestamps):
# 1655136392-tgo Complete revamp
#
# --------------------------------------------------------------

if [[ ! "$USER" = 'appuser' ]]
    then
        echo -en "Running as a the APPUSER is REQUIRED!  Please sudo to the Appuser (sudo -sHu appuser).\n\n"
        exit 1
fi

if [[ ! -f '/ews/scripts/.globalFunctions' ]]
    then
        echo "Could not source Global Functions!"
        exit 1
    else
        source '/ews/scripts/.globalFunctions'
fi

function Usage(){
echo -en "\nProper Usage:"
echo -en "\n\n\t$0 [-s STATUS {-f FILENAME OR -i PAYMENTID} | -h ]\n\n"
echo -en "\n\t${SCRIPT} -s ::: (This option is REQUIRED and must be set FIRST! { -s SENT | -s DELIVERED | -s FAILED | -s PENDING_ACCEPTANCE | -s SETTLED | -s ACCEPT_WITHOUT_POSTING | -s ACCEPTED })"
echo -en "\n\t${SCRIPT} -f ::: (1 Single file that contains payments ids. 1 Payment ID per line. Max 1000.)"
echo -en "\n\t${SCRIPT} -i ::: (1 Single payment id per option { -i PAYMENTID })"
echo -en "\n\t${SCRIPT} -d ::: (The destination ORG or destination reseller for all notification retriggers)"
echo -en "\n\t${SCRIPT} -h ::: (Display this help)"
echo -en "\n\n"
}

function CountPaymentsDB(){
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select count(1) from ${DB_SCHEMA}.sd_payment where payment_id in ( $SQL_PAYMENTS ) and status = '$STATUS';
exit;
SQL
}

function CountPaymentsFile(){
wc -l ${OPTARG} | awk '{print $1}' | tr -d "[:blank:]"
}

function CheckOrg() {
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select count(1) from ${DB_SCHEMA}.sd_organization where coalesce(org_id,reseller_id) = '$DORG' and status = 'ACTIVE';
exit;
SQL
}

function DoWork(){
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off
update ${DB_SCHEMA}.sd_event_notification set status = 'READY', exclude_from_report = '1' where event_id in (select event_id from ${DB_SCHEMA}.sd_payment_history where payment_id in ( $SQL_PAYMENTS ) and status = '$STATUS') and coalesce(destination_org_id,destination_reseller_id) = '$DORG';
commit;
SQL
}

function Ready() {
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select count(1) from ${DB_SCHEMA}.sd_event_notification where status = 'READY' and event_id in (select event_id from ${DB_SCHEMA}.sd_payment_history where payment_id in ( $SQL_PAYMENTS ) and status = '$STATUS') and coalesce(destination_org_id,destination_reseller_id) = '$DORG';
exit;
SQL
}

function PaymentStatusNotifyDual() {
echo -en "Status|Notify_count|Occurrences: \n\n"
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off
select ph.status || '|' || en.notify_count || '|' || count(en.event_id) from ${DB_SCHEMA}.sd_payment p inner join ${DB_SCHEMA}.sd_payment_history ph on ph.payment_id = p.payment_id inner join ${DB_SCHEMA}.sd_event_notification en on en.event_id = ph.event_id where ph.payment_id in ( $SQL_PAYMENTS ) and ph.status = '$STATUS' and coalesce(destination_org_id,destination_reseller_id) = '$DORG' group by ph.status || '|' || en.notify_count;
exit;
SQL
}

function SQLfy(){
awk 'BEGIN { ORS="" } { print p"\047"$0"\047"; p=",\r\n" } END { print "\n" }' ${OPTARG}
}


if [[ "$#" -eq '0' ]]
    then
        echo "No options specified!"
        Usage
        exit 1
    else
        while getopts :hs:f:i:d: opt
            do
                case "$opt" in
                    s)
                        STATUS=$(echo "${OPTARG}" | tr '[:lower:]' '[:upper:]')
                        if [[ "$STATUS" =~ ^(DELIVERED)$ ]]
                            then
                                STATUS="DELIVERED"
                                echo -en "\n\nPreparing to retrigger the $STATUS status ...\n\n"
                        elif [[ "$STATUS" =~ ^(DENIED)$ ]] 
                            then
                                STATUS="DENIED"
                                echo -en "\n\nPreparing to retrigger the $STATUS status ...\n\n"
                        elif [[ "$STATUS" =~ ^(FAILED)$ ]]
                            then
                                STATUS="FAILED"
                                echo -en "\n\nPreparing to retrigger the $STATUS status ...\n\n"
                        elif [[ "$STATUS" =~ ^(SENT)$ ]]
                            then
                                STATUS="SENT"
                                echo -en "\n\nPreparing to retrigger the $STATUS status ...\n\n"
                        elif [[ "$STATUS" =~ ^(PENDING_ACCEPTANCE)$ ]]
                            then
                                STATUS="PENDING_ACCEPTANCE"
                                echo -en "\n\nPreparing to retrigger the $STATUS status ...\n\n"
                        elif [[ "$STATUS" =~ ^(SETTLED)$ ]]
                            then
                                STATUS="SETTLED"
                                echo -en "\n\nPreparing to retrigger the $STATUS status ...\n\n"
                        elif [[ "$STATUS" =~ ^(ACCEPT_WITHOUT_POSTING)$ ]]
                            then
                                STATUS="ACCEPT_WITHOUT_POSTING"
                                echo -en "\n\nPreparing to retrigger the $STATUS status ...\n\n"
                        elif [[ "$STATUS" =~ ^(ACCEPTED)$ ]]
                            then
                                STATUS="ACCEPTED"
                                echo -en "\n\nPreparing to retrigger the $STATUS status ...\n\n"
                        else
                            echo -en "\n\nSTATUS was not specified correctly!\n\n"
                            exit 1
                        fi
                  OPT_CHECK_1="1"
                        ;;
                    f)
                        if [[ ! -z "$STATUS" ]] && [[ ! -z "${OPTARG}" ]]; then
                          COUNT_PAYMENTS_FILE=$(CountPaymentsFile)
                           if ! [[ "$COUNT_PAYMENTS_FILE" -le 1000 ]]; then
                              echo -en "${OPTARG} has more than 1000 payments/rows.\n\n"
                              exit 1
                           fi
                          SQL_PAYMENTS=$(SQLfy)
                          COUNT_PAYMENTS_DB=$(CountPaymentsDB)
							if ! [[ "$COUNT_PAYMENTS_DB" -eq "$COUNT_PAYMENTS_FILE" ]] ; then
								echo -en "The file ${OPTARG} has ${COUNT_PAYMENTS_FILE} rows and doesn't match number of payments found in the DB under status $STATUS which was ${COUNT_PAYMENTS_DB}.\n\n"
								exit 1
							fi
						else
							echo -en "\nEither the Status (-s) or File (-f) argument was not set properly.\n"
							Usage
							exit 1
						fi
						OPT_CHECK_2="1"
                        ;;
                    i)
                        if [[ ! -z "$STATUS" ]] && [[ ! -z "${OPTARG}" ]]; then
                                SQL_PAYMENTS="'${OPTARG}'"
                        COUNT_PAYMENTS_DB=$(CountPaymentsDB)
                           if [[ -z "$COUNT_PAYMENTS_DB" ]]; then
                                 echo -en "Payment ${OPTARG} not found.\n"
                                 exit 1
                           fi
						else
							echo -en "\nEither the Status (-s) or Payment (-i) argument was not set properly.\n"
							Usage
							exit 1
						fi
						OPT_CHECK_3="1"
                        ;;
					d) 
						if [[ ! -z "$STATUS" ]] && [[ ! -z "${OPTARG}" ]]; then
							DORG="${OPTARG}"
							CHECK_ORG=$(CheckOrg)
							if [[ -z "$CHECK_ORG" ]]; then
								echo -en "This Org or reseller does not exist or is INACTIVE.\n"
								Usage
								exit 1
							fi
						else
							echo -en "\nEither the Status (-s) or Destination Org (-d) argument was not set properly.\n"
							Usage
							exit 1
						fi
						OPT_CHECK_4="1"
						;;
                    h)
                        echo -en "\n\nHelp Details:\n\n"
                        Usage
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

# Double down on ensuring that the Status and Destination ORG is set
if [[ -z "$OPT_CHECK_1" ]] || [[ -z "$OPT_CHECK_4" ]]; then
   echo -en "You must set the status and destination ORG.\n\n"
   exit 1
fi

# Ensure the -f and -i options are not both used
if [[ -z "$OPT_CHECK_2" ]] && [[ -z "$OPT_CHECK_3" ]]; then
   echo -en "You can't use -f and -i at the same time.\n\n"
   exit 1
fi

# Check current state
echo -en "\n\nHere is the current state of the retriggers: \n$(PaymentStatusNotifyDual)\n"
read -r -p $'\n\nPlease review the results above, and confirm if you\'d like to continue: [y/n] ' PROCEED
case "$PROCEED" in
Y|y)
   echo -e "\n\n"
   ;;
N|n)
   exit 1
   ;;
esac

# Perform the update
DoWork

# Ensure the work is done
until [[ "$COUNT" -eq "0" ]]
    do
        unset -v COUNT
        COUNT=$(Ready)
                echo -en "."
                sleep 3
    done
echo -e "All set!\n\n"

