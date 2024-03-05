#!/bin/bash

# --------------------------------------------------------------
# Copyright (C) 2018: Early Warning Services, LLC. - All Rights Reserved
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
# Access to the Reporting Database
#
# Description:
# Showing the number of transactions stuck in SENT
#
# --------------------------------------------------------------

if [[ ! "$USER" = 'appuser' ]]
    then
        echo -en "Running as a the APPUSER is REQUIRED!  Please sudo to the Appuser (sudo -sHu appuser).\n\n"
        exit 1
fi

if [[ ! -f '/ews/scripts/.globalFunctions' ]]
    then        echo "Could not source Global Functions!"
        exit 1
    else
        source '/ews/scripts/.globalFunctions'
fi

#WALLET_ALIAS="cxcrwp_automation"
#WALLET_ALIAS="cxcrwp_automation"
WALLET_ALIAS="unset"
REPORTING_LAG="unset"
REPORTING_REGION="unset"

function CheckReportingLag(){
   canaryfile=/home/appuser/.best_report_server
   if ! [[ -r "${canaryfile}" ]]; then
      printf "Unable to read %s; aborting." "${canaryfile}" 1>%2
      exit 2
   fi
   #alias | actual lag
   WALLET_ALIAS=$(awk -F'|' '{ print $1 }' "${canaryfile}")
   REPORTING_LAG=$(awk -F'|' '{ print $2 }' "${canaryfile}")
   REPORTING_REGION=$(awk -F'|' '{ print $3 }' "${canaryfile}")

}
function StuckInSentSD1d(){
TODAY=$(date -u +"%m/%d/%Y:%H:%M:%S" --date='-1 day')
FIVEMINSAGO=$(date -u +"%m/%d/%Y:%H:%M:%S" --date='-5 minute')
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off colsep "|"
select
    count(*) as "Total",
    p.receiving_fi as "Recipient FI", COALESCE(b.reseller_id,'N/A') as "Reseller", SUBSTR(b.name,1,15) as "Bank Name"
from
    sdrep.sd_payment p,
    sdrep.sd_organization b
where
    p.receiving_fi=b.org_id
        and
    p.match_date
        between
            to_date('$TODAY','mm/dd/yyyy:hh24:mi:ss')
        and
            to_date('$FIVEMINSAGO','mm/dd/yyyy:hh24:mi:ss')
and
    p.expedited = '1'
and
    p.status = 'SENT'
group by
    p.receiving_fi, b.reseller_id, b.name
order by
    1 DESC;
exit;
SQL
}
function StuckInSentCore1d(){
TODAY=$(date -u +"%m/%d/%Y:%H:%M:%S" --date='-1 day')
FIVEMINSAGO=$(date -u +"%m/%d/%Y:%H:%M:%S" --date='-5 minute')
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off colsep "|"
select
    count(*) as "Total",
    p.recipient_org_id as "Recipient FI", COALESCE(b.reseller_id, 'N/A'), substr(b.name,1,15) as "Bank Name"
from
    payment.payments p,
    sdrep.sd_organization b
where
    p.recipient_org_id=b.org_id
        and
    p.date_created
        between
            to_date('$TODAY','mm/dd/yyyy:hh24:mi:ss')
        and
            to_date('$FIVEMINSAGO','mm/dd/yyyy:hh24:mi:ss')
and
    p.expedited = '1'
and
    p.status = 'SENT'
group by
    p.recipient_org_id, b.reseller_id, b.name
order by
    1 DESC;
exit;
SQL
}
function StuckInSentSD1h(){
TODAY=$(date -u +"%m/%d/%Y:%H:%M:%S" --date='-1 hour')
FIVEMINSAGO=$(date -u +"%m/%d/%Y:%H:%M:%S" --date='-5 minute')
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off colsep "|"
select
    count(*) as "Total",
    p.receiving_fi as "Recipient FI", COALESCE(b.reseller_id,'N/A') as "Reseller", SUBSTR(b.name,1,15) as "Bank Name"
from
    sdrep.sd_payment p,
    sdrep.sd_organization b
where
    p.receiving_fi=b.org_id
        and
    p.match_date
        between
            to_date('$TODAY','mm/dd/yyyy:hh24:mi:ss')
        and
            to_date('$FIVEMINSAGO','mm/dd/yyyy:hh24:mi:ss')
and
    p.expedited = '1'
and
    p.status = 'SENT'
group by
    p.receiving_fi, b.reseller_id, b.name
order by
    1 DESC;
exit;
SQL
}
function StuckInSentCore1h(){
TODAY=$(date -u +"%m/%d/%Y:%H:%M:%S" --date='-1 hour')
FIVEMINSAGO=$(date -u +"%m/%d/%Y:%H:%M:%S" --date='-5 minute')
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off colsep "|"
select
    count(*) as "Total",
    p.recipient_org_id as "Recipient FI", COALESCE(b.reseller_id, 'N/A'), substr(b.name,1,15) as "Bank Name"
from
    payment.payments p,
    sdrep.sd_organization b
where
    p.recipient_org_id=b.org_id
        and
    p.date_created
        between
            to_date('$TODAY','mm/dd/yyyy:hh24:mi:ss')
        and
            to_date('$FIVEMINSAGO','mm/dd/yyyy:hh24:mi:ss')
and
    p.expedited = '1'
and
    p.status = 'SENT'
group by
    p.recipient_org_id, b.reseller_id, b.name
order by
    1 DESC;
exit;
SQL
}




CheckReportingLag
if [[ "${WALLET_ALIAS}" == "unset" ]]; then
   printf "Something went wrong setting the WALLET_ALIAS variable.  Aborting.\n" 1>&2
   exit 3
fi

oneday=$(mktemp)
onehour=$(mktemp)
read -r TIME < <(date -u +"%m/%d/%Y:%H:%M:%S")
echo -en "Current GMT date and time: $TIME.  Counts below exclude the most recent five minutes."
#echo -en "\n${REPORTING_REGION} Reporting Server SD Event Latency: ${REPORTING_LAG}"
{
echo -en "\nItems stuck in SENT in the past day:\n\n"
echo -en "|==============SD==================|\n"
echo -en "|Count|ORG|Reseller|Bank Name      |\n"
StuckInSentSD1d | awk -F '|' '{ printf( "|%5d|%3s|%6s  |%-15s|\n", $1, $2, $3, $4 ) } END { printf( "\n\n" ) }'
echo -en "|=============CORE=================|\n"
echo -en "|Count|ORG|Reseller|Bank Name      |\n"
StuckInSentCore1d | awk -F '|' '{ printf( "|%5d|%3s|%6s  |%-15s|\n", $1, $2, $3, $4 ) } END { printf( "\n\n" ) }'
} > $oneday
{
echo -en "\nItems stuck in SENT in the past hour:\n\n"
echo -en "|==============SD==================|\n"
echo -en "|Count|ORG|Reseller|Bank Name      |\n"
StuckInSentSD1h | awk -F '|' '{ printf( "|%5d|%3s|%6s  |%-15s|\n", $1, $2, $3, $4 ) } END { printf( "\n\n" ) }'
echo -en "|=============CORE=================|\n"
echo -en "|Count|ORG|Reseller|Bank Name      |\n"
StuckInSentCore1h | awk -F '|' '{ printf( "|%5d|%3s|%6s  |%-15s|\n", $1, $2, $3, $4 ) } END { printf( "\n\n" ) }'
}  > $onehour
paste "$oneday" "$onehour"

rm -f "$oneday" "$onehour"
