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
# Repository:
# None, (yet).
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

# The difference between FailedbyRatios and FailedByTotal is in the Order By clause

ONEHOUR=$(date -u +"%m/%d/%Y:%H:%M:%S" -d '1 hour ago')
FIVEMINUTE=$(date -u +"%m/%d/%Y:%H:%M:%S" -d '5 minutes ago')

function FailedByRatio(){
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off colsep "|" wrap off
select
    sum(case when p.status in ( 'DENIED', 'FAILED' ) then 1 else 0 end) as "Failed",
    count(1) as "total",
    round(sum(case when p.status in ( 'DENIED', 'FAILED') then 1 else 0 end) * 100 / count(1), 2) as "Ratio",
        case when o.reseller_id is null then '----' || o.org_id else o.reseller_id || '-' || o.org_id end as "Receiving_FI",
        stats_mode(coalesce(p.fail_code, p.denied_code)) as "Fail_Deny_Code",
    stats_mode(coalesce(
            regexp_replace(p.fail_desc, 'Payment ([[:alnum:]]{12})', 'Payment XXX'),
            regexp_replace(p.denied_desc, 'Payment ([[:alnum:]]{12})', 'Payment XXX')
        )
    ) as "Fail_Deny_Desc"
from sdrep.sd_payment p
inner join sdrep.sd_organization o on p.receiving_fi = o.org_id
where
            expedited = 1
	and match_date < cast(sys_extract_utc(systimestamp-numtodsinterval(15,'MINUTE')) as date)
	and match_date > cast(sys_extract_utc(systimestamp-numtodsinterval(75,'MINUTE')) as date)
group by
    case when o.reseller_id is null then '----' || o.org_id else o.reseller_id || '-' || o.org_id end
having sum(case when fail_desc in ('recipient bin inactive','Recipient card expired') then 1 else 0 end) = 0
order by 3 desc;
exit;
SQL
}

function FailedByTotal() {
SQLWallet <<SQL
set lines 1000 heading off echo off pagesize 0 feedback off verify off colsep "|" wrap off
select
    sum(case when p.status in ( 'DENIED', 'FAILED' ) then 1 else 0 end) as "Failed",
    count(1) as "total",
    round(sum(case when p.status in ( 'DENIED', 'FAILED') then 1 else 0 end) * 100 / count(1), 2) as "Ratio",
        case when o.reseller_id is null then '----' || o.org_id else o.reseller_id || '-' || o.org_id end as "Receiving_FI",
        stats_mode(coalesce(p.fail_code, p.denied_code)) as "Fail_Deny_Code",
    stats_mode(coalesce(
            regexp_replace(p.fail_desc, 'Payment ([[:alnum:]]{12})', 'Payment XXX'),
            regexp_replace(p.denied_desc, 'Payment ([[:alnum:]]{12})', 'Payment XXX')
        )
    ) as "Fail_Deny_Desc"
from sdrep.sd_payment p
inner join sdrep.sd_organization o on p.receiving_fi = o.org_id
where
            expedited = 1
	and match_date < cast(sys_extract_utc(systimestamp-numtodsinterval(15,'MINUTE')) as date)
	and match_date > cast(sys_extract_utc(systimestamp-numtodsinterval(75,'MINUTE')) as date)
group by
    case when o.reseller_id is null then '----' || o.org_id else o.reseller_id || '-' || o.org_id end
having sum(case when fail_desc in ('recipient bin inactive','Recipient card expired') then 1 else 0 end) = 0
order by 1 desc;
exit;
SQL
}


CheckReportingLag
if [[ "${WALLET_ALIAS}" == "unset" ]]; then
   printf "Something went wrong setting the WALLET_ALIAS variable.  Aborting.\n" 1>&2
   exit 3
fi

GREEN='\033[0;32m'
NC='\033[0m'

function CleanUp1() {
tr '\t' -d
}
function CleanUp2() {
sed -e 's,account--,account  ,g'
}
function CleanUp3() {
sed -e 's,network--,network  ,g'
}
function CleanUp4() {
sed -e 's,action---,action   ,g'
}
function CleanUp5() {
sed -e 's,inactive---,inactive   ,g'
}

read -r TIME < <(date -u +"%Y/%m/%d:%H:%M:%S")
echo -en "\n\nCurrent GMT date and time: $TIME"
echo -en "\n${REPORTING_REGION} Reporting Server SD Event Latency: ${REPORTING_LAG}\n\n"
echo -en "${GREEN}There are 2 sections.${NC} One for failures by ratio and one for total failures. Please see both!!"
echo -en "\n\n${GREEN}Section 1:${NC} Top 25 FAILED/DENIED Ratios in the last hour by RATIO (minus the last 5 minutes):\n"
echo -en "Note that MODE is the MOST COMMON, not the ONLY, failure type.\n\n"
echo -en "|Failed| Total|  Ratio|Org ID |     Failure Code Mode      |Failure Description Mode\n"
FailedByRatio | awk -F '|' 'NR < 25 && $1 > 0 { printf( "|%6d|%6d|%6.2f%%|%-7.7s|%-28.28s|%s\n", $1, $2, $3, $4, $5, $6 ) } END { printf( "\n\n" ) }' | CleanUp1 | CleanUp2 | CleanUp3 | CleanUp4 | CleanUp5
echo -en "${GREEN}Section 2:${NC} Top 25 FAILED/DENIED Ratios in the last hour by TOTAL FAILURES (minus the last 5 minutes):\n"
echo -en "Note that MODE is the MOST COMMON, not the ONLY, failure type.\n\n"
echo -en "|Failed| Total|  Ratio|Org ID |     Failure Code Mode      |Failure Description Mode\n"
FailedByTotal | awk -F '|' 'NR < 25 && $1 > 0 { printf( "|%6d|%6d|%6.2f%%|%-7.7s|%-28.28s|%s\n", $1, $2, $3, $4, $5, $6 ) } END { printf( "\n\n" ) }' | CleanUp1 | CleanUp2 | CleanUp3 | CleanUp4 | CleanUp5

echo -en "${GREEN}Make sure you are reading and understanding both sections 1 and 2.${NC}\n"


