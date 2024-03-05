#!/bin/bash

# --------------------------------------------------------------
# Copyright (C) 2017: Early Warning Services, LLC. - All Rights Reserved
#
# Licensing:
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
#
# Author:
# Tyler Oyler
#
# Email:
# tyler.oyler@earlywarning.com
#
# Dependency:
# Access to Appuser, Connection to DCN\DCW database.
#
# Description:
# Holds/Release MQ for banks (can hold/release by notification type if needed)
# Can also turn can_handle_dup_payments on or off
#
# ChangeLog (Unix Timestamps):
# ####-tgo: Complete Revamp
# 

if [[ ! $USER = 'appuser' ]]
   then
      echo -en "\nRunning as a the APPUSER is REQUIRED!  Please sudo to the Appuser (sudo -sHu appuser).\n\n"
      exit 1
fi

if [[ ! -f '/ews/scripts/.globalFunctions' ]]
   then
      echo -en "\nCould not source Global Functions!\n\n"
      exit 1
   else
      source '/ews/scripts/.globalFunctions'
fi

# This identifies which orgs can_handle_dup_payments by default so people can only edit these orgs.
DUPORGS="('COFPREF' 'FHCPREF' 'CFRPREF' 'PNCPREF' 'BACPREF' 'PNBPREF' 'USBPREF' 'USAPREF' 'JPMPREF' 'CTIPREF' 'FTBPREF' 'FSVPREF' '1TNPREF' 'MNTPREF' 'JHAPREF')"

# This will need to be manually edited each time a new event type is introduced to SD_P2P_EVENTS
# You'll see that the SQL statements have unions. The first half looking for NOT IN $USINGSDE to update sd_p2p
# And the second half looking for IN $USINGSDE to update sd_p2p_events
# Updates just use a second Update statement
USINGSDE="( 'change-payment-status','change-token-status' )"

REPLICA_SCHEMA="sdrep"
CAT_SCHEMA="clx_next"
PROD_SCHEMA="sd_p2p"
PTE_SCHEMA="sd_p2p"
NEW_EVENT_SCHEMA="$sd_p2p_event"

function VerifyOrgID(){
SQLWallet <<EOF
set lines 100 heading off echo off pagesize 0 feedback off verify off
select coalesce(reseller_id, org_id)
from ${PTE_SCHEMA}.sd_organization
where (org_id = '$ORG' or reseller_id = '$ORG')
and status = 'ACTIVE';
exit;
EOF
}

function GetNotificationOrgPrefID(){
SQLWallet <<EOF
set lines 100 heading off echo off pagesize 0 feedback off verify off
select notification_org_preference_id
from ${PTE_SCHEMA}.sd_notification_org_preference
where (org_id = '$ORG' or reseller_id = '$ORG');
exit;
EOF
}

function GetMQTypes(){
unset MQTYPES
read -r -a MQTYPES <<< SQLWallet <<EOF
set lines 100 heading off echo off pagesize 0 feedback off verify off
select notification_type_id
from ${PTE_SCHEMA}.sd_notification_org_preference nop
inner join ${PTE_SCHEMA}.sd_event_notification en on coalesce(en.destination_reseller_id,en.destination_org_id) = nop.org_id
where nop.do_not_deliver = 0
and (nop.org_id = '$ORG' or nop.reseller_id = '$ORG')
and en.event_type NOT in $USINGSDE;

select notification_type_id
from ${NEW_EVENT_SCHEMA}.sde_notification_org_preference nop
inner join ${NEW_EVENT_SCHEMA}.sde_event_message e on e.destination_id = nop.org_id
where nop.do_not_deliver = 0
and (nop.org_id = '$ORG' or nop.reseller_id = '$ORG')
and e.event_type in $USINGSDE;
exit;
EOF
}

function GetHeldMQTypes(){
unset MQTYPES
read -r -a MQTYPES <<< SQLWallet <<EOF
set lines 100 heading off echo off pagesize 0 feedback off verify off
select nop.notification_type_id
from ${PTE_SCHEMA}.sd_notification_org_preference nop
inner join ${PTE_SCHEMA}.sd_notification_deliver_detail ndd on ndd.notification_org_preference_id = nop.notification_org_preference_id
inner join ${PTE_SCHEMA}.sd_event_notification en on coalesce(en.destination_reseller_id,en.destination_org_id) = nop.org_id
where nop.do_not_deliver = 0
and (nop.org_id = '$ORG' or nop.reseller_id = '$ORG')
and en.event_type NOT in $USINGSDE
and ndd.active = 0;

select nop.notification_type_id
from ${NEW_EVENT_SCHEMA}.sde_notification_org_preference nop
inner join ${NEW_EVENT_SCHEMA}.sde_notification_deliver_detail ndd on ndd.notification_org_preference_id = nop.notification_org_preference_id
inner join ${NEW_EVENT_SCHEMA}.sde_event_message e on e.destination_id = nop.org_id
where nop.do_not_deliver = 0
and (nop.org_id = '$ORG' or nop.reseller_id = '$ORG')
and e.event_type in $USINGSDE
and ndd.active = 0;
exit;
EOF
}

function DoTheRelease(){
SQLWallet <<EOF
update ${PTE_SCHEMA}.sd_notification_deliver_detail ndd
inner join ${PTE_SCHEMA}.sd_notification_org_preference nop on nop.notification_org_preference_id = ndd.notification_org_preference_id
inner join ${PTE_SCHEMA}.sd_event_notification en on coalesce(en.destination_reseller_id,en.destination_org_id) = nop.org_id
set ndd.active = 1
where nop.do_not_deliver = 0
and ndd.notification_org_preference_id = '$ORGPREFID'
and en.event_type NOT in $USINGSDE
and nop.notification_type_id = '$RELEASE';
commit;

update ${NEW_EVENT_SCHEMA}.sde_notification_deliver_detail ndd
inner join ${NEW_EVENT_SCHEMA}.sde_notification_org_preference nop on nop.notification_org_preference_id = ndd.notification_org_preference_id
inner join ${NEW_EVENT_SCHEMA}.sde_event_message e on e.destination_id = nop.org_id
set ndd.active = 1
where nop.do_not_deliver = 0
and ndd.notification_org_preference_id = '$ORGPREFID'
and e.event_type in $USINGSDE
and nop.notification_type_id = '$RELEASE';
commit;
exit;
EOF
}

function HoldMQ(){
SQLWallet <<EOF
update ${PTE_SCHEMA}.sd_notification_deliver_detail ndd
inner join ${PTE_SCHEMA}.sd_notification_org_preference nop on nop.notification_org_preference_id = ndd.notification_org_preference_id
inner join ${PTE_SCHEMA}.sd_event_notification en on coalesce(en.destination_reseller_id,en.destination_org_id) = nop.org_id
set ndd.active = '0'
where nop.do_not_deliver = 0
and ndd.notification_org_preference_id in ( '$ORGPREFID' )
and en.event_type NOT in $USINGSDE;
commit;

update ${NEW_EVENT_SCHEMA}.sde_notification_deliver_detail ndd
inner join ${NEW_EVENT_SCHEMA}.sde_notification_org_preference nop on nop.notification_org_preference_id = ndd.notification_org_preference_id
inner join ${NEW_EVENT_SCHEMA}.sde_event_message e on e.destination_id = nop.org_id
set ndd.active = '0'
where nop.do_not_deliver = 0
and ndd.notification_org_preference_id in ( '$ORGPREFID' )
and e.event_type in $USINGSDE;
commit;
exit;
EOF
}

function ReleaseMQ(){
SQLWallet <<EOF
update ${PTE_SCHEMA}.sd_notification_deliver_detail ndd
inner join ${PTE_SCHEMA}.sd_notification_org_preference nop on nop.notification_org_preference_id = ndd.notification_org_preference_id
inner join ${PTE_SCHEMA}.sd_event_notification en on coalesce(en.destination_reseller_id,en.destination_org_id) = nop.org_id
set ndd.active = '1'
where nop.do_not_deliver = 0
and ndd.notification_org_preference_id in ( '$ORGPREFID' )
and en.event_type NOT in $USINGSDE;
commit;

update ${NEW_EVENT_SCHEMA}.sde_notification_deliver_detail ndd
inner join ${NEW_EVENT_SCHEMA}.sde_notification_org_preference nop on nop.notification_org_preference_id = ndd.notification_org_preference_id
inner join ${NEW_EVENT_SCHEMA}.sde_event_message e on e.destination_id = nop.org_id
set ndd.active = '1'
where nop.do_not_deliver = 0
and ndd.notification_org_preference_id in ( '$ORGPREFID' )
and e.event_type in $USINGSDE;
commit;
exit;
EOF
}

function ReloadAllBatch(){
SQLWallet <<EOF
update ${PTE_SCHEMA}.sd_processing_engine set reload='1' where processing_engine_id in ('zsd-lp-default','zsp-lp-default','zsp-default','zsd-default');
commit;

update ${NEW_EVENT_SCHEMA}.sde_processing_engine set reload='1' where processing_engine_id in ('zsd-lp-default','zsp-lp-default','zsp-default','zsd-default');
commit;
exit;
EOF
}

function ExcludeFromReport(){
SQLWallet <<EOF
update ${PTE_SCHEMA}.sd_event_notification en
inner join sde_notification_deliver_detail nop on nop.org_id = en.destination_id
set en.exclude_from_report='1'
where en.status = 'SENT'
and en.exclude_from_report='0'
and en.sent_dt between to_date('$START', 'yyyy/mm/dd:hh24:mi:ss') and to_date('$END','yyyy/mm/dd:hh24:mi:ss')
and en.coalesce(destination_reseller_id,destination_org_id) = '$ORG'
and en.event_type NOT in $USINGSDE
and en.rownum < 1000;
commit;

update ${NEW_EVENT_SCHEMA}.sd_event_message e
inner join sde_notification_deliver_detail nop on nop.org_id = e.destination_id
set e.exclude_from_report='1'
where e.status = 'SENT'
and e.exclude_from_report='0'
and e.sent_dt between to_date('$START', 'yyyy/mm/dd:hh24:mi:ss') and to_date('$END','yyyy/mm/dd:hh24:mi:ss')
and e.destination_id = '$ORG'
and e.event_type in $USINGSDE
and e.rownum < 1000;
commit;
exit;
EOF
}

function ExcludeFromReportCheck(){
SQLWallet <<EOF
set lines 100 heading off echo off pagesize 0 feedback off verify off
Select ltrim(count(1))
from ${PTE_SCHEMA}.sd_event_notification
where status = 'SENT'
and exclude_from_report='0'
and sent_dt between to_date ('$START', 'yyyy/mm/dd:hh24:mi:ss') and to_date ('$END','yyyy/mm/dd:hh24:mi:ss')
and coalesce(destination_reseller_id,destination_org_id) = '$ORG';
exit;
EOF
}

function ExcludeFromReportCheckSDE(){
SQLWallet <<EOF
set lines 100 heading off echo off pagesize 0 feedback off verify off
Select ltrim(count(1))
from ${NEW_EVENT_SCHEMA}.sd_event_message
where status = 'SENT'
and exclude_from_report='0'
and sent_dt between to_date ('$START', 'yyyy/mm/dd:hh24:mi:ss') and to_date ('$END','yyyy/mm/dd:hh24:mi:ss')
and destination_id = '$ORG';
exit;
EOF
}

function CountHeldMQ(){
SQLWallet <<EOF
set lines 100 heading off echo off pagesize 0 feedback off verify off
select ltrim(count(1)), coalesce(destination_reseller_id,destination_org_id), event_type
from ${PTE_SCHEMA}.sd_event_notification
where status = 'READY'
and event_type NOT in $USINGSDE
and coalesce(destination_reseller_id, destination_org_id) = '$ORG'
and event_dt between to_date('$START', 'yyyy/mm/dd:hh24:mi:ss') and to_date('$END', 'yyyy/mm/dd:hh24:mi:ss');

select ltrim(count(1)), destination_id, event_type
from ${NEW_EVENT_SCHEMA}.sd_event_message
where e.status = 'READY'
and event_type in $USINGSDE
and destination_id = '$ORG'
and event_dt between to_date('$START', 'yyyy/mm/dd:hh24:mi:ss') and to_date('$END', 'yyyy/mm/dd:hh24:mi:ss');
exit;
EOF
}

function CheckProcessingEngine(){
SQLWallet <<EOF
set lines 100 heading off echo off pagesize 0 feedback off verify off
select distinct ltrim(reload) from ${PTE_SCHEMA}.sd_processing_engine;
exit;
EOF
}

function CheckProcessingEngineSDE(){
SQLWallet <<EOF
set lines 100 heading off echo off pagesize 0 feedback off verify off
select distinct ltrim(reload) from ${NEW_EVENT_SCHEMA}.sd_processing_engine;
exit;
EOF
}

function ValidateDups(){
if [[ ! "${DUPORGS[@]}" =~ "${OPTARG}" ]]; then
	echo -en "This Org doesn't have Duplicate payments turned on by default. No action taken.\n"
    exit 1
fi
}

function TurnDupsOn(){
SQLWallet <<EOF
update ${PTE_SCHEMA}.sd_org_preference
set can_handle_dup_payments = 1 
where notification_org_preference_id = '$NOTIFORGPREFID'
and org_pref_id = ${DUPORGS[@]};
commit;
exit;
EOF
}

function TurnDupsOff(){
SQLWallet <<EOF
update ${PTE_SCHEMA}.sd_org_preference
set can_handle_dup_payments = 0 
where notification_org_preference_id = '$NOTIFORGPREFID'
and org_pref_id = ${DUPORGS[@]};
commit;
exit;
EOF
}

function Usage(){
SCRIPT=$(basename $0 2>/dev/null)
printf '\n%s' "Proper Usage:"
printf '\n\n\t%s\n\n' "${SCRIPT} [{-o ORGID} | {-r RESELLERID} | -d | -e | -c | -h ]"
printf '\n\t%s' "${SCRIPT} -o ::: This option is REQUIRED and must be set FIRST.  This is the Org ID OOORRR the Reseller ID of the Participant doing maintenance"
printf '\n\t%s' "${SCRIPT} -d ::: Declare this option to hold (Disable) ~~~ALL~~~ the MQ for the Participant or Reseller"
printf '\n\t%s' "${SCRIPT} -e ::: Declare this option to release (Enable) ~~~ALL~~~ the MQ for the Participant or Reseller"
printf '\n\t%s' "${SCRIPT} -x ::: Turns duplicate messages off. You do not have to hold/release MQ to use this option."
printf '\n\t%s' "${SCRIPT} -z ::: Turns duplicate messages on. You do not have to hold/release MQ to use this option."
printf '\n\t%s' "${SCRIPT} -n ::: Show available MQ Types by org/Show Held MQ Types by org/Release MQ Types by org."
printf '\n\t%s' "${SCRIPT} -n ::: ^^^ If you use the -n option YOU MUST STILL use the -e option when you're done. ^^^"
printf '\n\t%s' "${SCRIPT} -c ::: Declare this option to show the number of messages currently held in a READY status for the Participant or Reseller"
printf '\n\t%s\n\n' "${SCRIPT} -h ::: (Display this help)"
}

# Do Work
if [[ "$#" -eq '0' ]]
   then
      echo -en "\nNo options specified!\n"
      usage
      exit 1
   else
      while getopts :o:hrnch opt
         do
            case "$opt" in
               o)
                  ORG=$(echo "${OPTARG}" | tr '[:lower:]' '[:upper:]')
                  if [[ "$ORG" =~ [A-Z0-9]{3} ]]; then
                    ORG=$(VerifyOrgID)
                    if [[ ! -z "$ORG" ]]; then
                       NOTIFORGPREFID=$(GetNotificationOrgPrefID)
                    else
                       echo -en "\nCould not verify Org/Reseller id! You didn't have a typo or try to hold a child bank did you? Please try again!\n"
                       exit 1
                    fi
                  else
                     echo -en "\nOrg/Reseller ID syntax is wrong! Quitting ...\n"
                     exit 1
                  fi
                  ;;
               d)   
                  if [[ ! "$ACTION" = '2' ]]; then
                     if [[ ! -z "$ORG" ]]; then
                        if [[ ! -f "$HOME"/.disable_mq_start_"$ORGID" ]]; then
                           date -u +"%Y/%m/%d:%H:%M:%S" > "$HOME"/.disable_mq_start_"$ORGID"
                        else
                           echo -en "\nYou've already disabled $ORGID Notifications. Exiting...\n"
                           exit 1
                        fi
                        
                        echo -en "\nHolding MQ and reloading Processing Engines now...\n"
                        HoldMQ
                        ReloadAllBatch
                        
                        # Verify processing engines restarted successfully
                        COUNT=1
                        until [[ "$COUNT" = "0" ]]; do
                           unset -v COUNT
                           COUNT=$(CheckProcessingEngine)
                           echo -en "."
                           sleep 2
                           continue
                        done
						
						# Doing this again for the new event queues
						COUNT=1
						until [[ "$COUNT" = "0" ]]; do
                           unset -v COUNT
                           COUNT=$(CheckProcessingEngineSDE)
                           echo -en "."
                           sleep 2
                           continue
                        done
						
                        echo -en "\nMQ is now being held for $ORGID\n"
                        echo -en "Don't forget to run reconmaintenance.bash\n"
                     else
                        echo "You must specify the Organization /or/ Reseller FIRST!"
                        exit 1
                     fi
                  else
                     echo -en "\nYou can't specify Hold AND Release at the same time. Exiting..."
                     Usage
                     exit 1
                  ACTION=1
                  fi
                  ;;
               e)
                  if [[ ! "$ACTION" = '1' ]]; then
                     read -r START < <(cat "$HOME"/.disable_mq_start_"$ORGID")
                     rm -f "$HOME"/.disable_mq_start_"$ORGID"
                     echo -en "Maintenance summary for $ORGID: $(date +"%Y%m%d")\n\n"
                     echo -en "Start Time $START (GMT)\n"
                  
                     CountHeldMQ
                  
                     echo -en "Releasing MQ and reloading Processing Engines now...\n"
                     ReleaseMQ
                     ReloadAllBatch
                     
                     # Verify processing engines restarted successfully
                     COUNT=1
                     until [[ "$COUNT" = "0" ]]; do
                        unset -v COUNT
                        COUNT=$(CheckProcessingEngine)
                        echo -en "."
                        sleep 2
                        continue
                     done
                     
					 # Doing this again for the new event queues
					 COUNT=1
                     until [[ "$COUNT" = "0" ]]; do
                        unset -v COUNT
                        COUNT=$(CheckProcessingEngineSDE)
                        echo -en "."
                        sleep 2
                        continue
                     done
					 
                     echo -en "\n"
                     read -r END < <(date -u +"%Y/%m/%d:%H:%M:%S")
                     echo -en "End Time $END (GMT)\n\n"
                     
                  
                        
                     # Exclude From Report
                     echo -en "\nExcluding from $START to $END\n"
                     echo -en "Waiting for Exclude from Report to complete..."
                     COUNT=1
                     until [[ "$COUNT" -eq "0" ]]
                        do
                           COUNT=$(ExcludeFromReportCheck)
                           echo -en "\n\n\t Count is $COUNT"
                           if [[ ! "$COUNT" -eq "0" ]]; then
                              if ExcludeFromReport
                                 then
                                    echo -en "\n\t Count is now $COUNT"
                                    sleep 3
                                    continue
                                 else
                                    echo "exclude from report was not successful"
                              fi
                           else
                              echo -en " Exclusion Complete!\n"
                              echo -en ""
                              break
                           fi
                        done
					# Doing this again for the new event queues
					COUNT=1
                     until [[ "$COUNT" -eq "0" ]]
                        do
                           COUNT=$(ExcludeFromReportCheckSDE)
                           echo -en "\n\n\t Count is $COUNT"
                           if [[ ! "$COUNT" -eq "0" ]]; then
                              if ExcludeFromReportSDE
                                 then
                                    echo -en "\n\t Count is now $COUNT"
                                    sleep 3
                                    continue
                                 else
                                    echo "exclude from report was not successful"
                              fi
                           else
                              echo -en " Exclusion Complete!\n"
                              echo -en ""
                              break
                           fi
                        done
                  else
                     echo -en "\nYou can't specify Hold AND Release at the same time. Exiting..."
                     Usage
                     exit 1
                  fi
                  ACTION=2
                  ;;
               c)
                  echo -en "Notifications in a READY status for $ORGID\n\n"
                  CountHeldMQ
                  ;;
               x)
                  ValidateDups
                  TurnDupsOff
				  ReloadAllBatch
                  echo -en "Duplicate payments are now turned off.\n"
                  ;;
               z)
                  ValidateDups
                  TurnDupsOn
				  ReloadAllBatch
                  echo -en "Duplicate payments are now turned on.\n"
                  ;;
               n)
                  while true
                     do
                        clear
                        PS3=$'\n\nPlease make a selection [1-4]: '
                        printf '\n'
                        select opt in 'Show MQ Types' 'Show Held MQ Types' 'Release MQ Types' 'Exit'
                           do
                              case "$REPLY" in
                                 1)
                                    GetMQTypes   
                                    ;;
                                 2)
                                    GetHeldMQTypes
                                    ;;
                                 3)
                                    if GetMQTypes
                                       then
                                          PS3=$'\n\nWhich MQ Type Would you like to release? '
                                          printf '\n'
                                          GetMQTypes
                                          select ALIAS in "${MQTYPES[@]}"
                                             do
						# The read statement is picking up user input and assigning it to the variable RELEASE which is used in the "DoTheRelease" function
                                                printf '\n\n%s' "Would you like to release the \"$ALIAS\" MQ Type? [y/n] "
                                                read -r RELEASE
                                                case "$RELEASE" in
                                                   Y|y)
                                                      DoTheRelease
                                                      ReloadAllBatch
                                                      read -r -p $'Press any key to continue ...' GO
                                                      case "$GO" in
                                                         *)
                                                            break 2
                                                            ;;
                                                      esac
                                                      ;;
                                                   N|n)
                                                      printf '%s\n\n' "Okay, peace out!"
                                                      break 2
                                                      ;;
                                                   *)
                                                      echo "Invalid Option!"
                                                      continue
                                                      ;;
                                                esac
                                             done
                                          continue
                                       else
                                          break 2
                                    fi
                                    ;;
                                 4)
                                    clear
                                    printf '\n\n\n%s\n\n\n' "Peace out!"
                                    sleep 1
                                    break 2
                                    break 2
                                    ;;
                                 *)
                                    echo "Invalid Option"
                                    continue
                                    ;;
                              esac
                           done
                     done
                  exit 1
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
                  echo "Option -$OPTARG requires an argument"
                  exit 1
                  ;;
            esac
         done
fi


