#!/bin/bash
#
# File:     pbs_submit.sh
# Author:   David Rebatto (david.rebatto@mi.infn.it)
#
# Revision history:
#     8-Apr-2004: Original release
#    28-Apr-2004: Patched to handle arguments with spaces within (F. Prelz)
#                 -d debug option added (print the wrapper to stderr without submitting)
#    10-May-2004: Patched to handle environment with spaces, commas and equals
#    13-May-2004: Added cleanup of temporary file when successfully submitted
#    18-May-2004: Search job by name in log file (instead of searching by jobid)
#     8-Jul-2004: Try a chmod u+x on the file shipped as executable
#                 -w option added (cd into submission directory)
#    20-Sep-2004: -q option added (queue selection)
#    29-Sep-2004: -g option added (gianduiotto selection) and job_ID=job_ID_log
#    13-Jan-2005: -n option added (MPI job selection)
#     9-Mar-2005: Dgas(gianduia) removed. Proxy renewal stuff added (-r -p -l flags)
#     3-May-2005: Added support for Blah Log Parser daemon (using the pbs_BLParser flag)
#    25-Jul-2007: Restructured to use common shell functions.
# 
#
# Description:
#   Submission script for PBS, to be invoked by blahpd server.
#   Usage:
#     pbs_submit.sh -c <command> [-i <stdin>] [-o <stdout>] [-e <stderr>] [-w working dir] [-- command's arguments]
#
# Copyright (c) Members of the EGEE Collaboration. 2004. 
# See http://www.eu-egee.org/partners/ for details on the copyright
# holders.  
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#     http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License.
#

. `dirname $0`/blah_common_submit_functions.sh

logpath=${pbs_spoolpath}/server_logs
if [ ! -d $logpath -o ! -x $logpath ]; then
  if [ -x "${pbs_binpath}/tracejob" ]; then
    pbs_spoolpath=`${pbs_binpath}/tracejob | grep 'default prefix path'|awk -F" " '{ print $5 }'`
    logpath=${pbs_spoolpath}/server_logs
  else
    # EPEL defaults for torque
    pbs_spoolpath=/var/lib/torque/spool
    logpath=/var/lib/torque/server_logs
  fi
fi

bls_job_id_for_renewal=PBS_JOBID

srvfound=""

original_args="$@"
bls_parse_submit_options "$@"

if [ "x$pbs_nologaccess" != "xyes" -a "x$pbs_nochecksubmission" != "xyes" ]; then

#Try different logparser
 if [ ! -z $pbs_num_BLParser ] ; then
  for i in `seq 1 $pbs_num_BLParser` ; do
   s=`echo pbs_BLPserver${i}`
   p=`echo pbs_BLPport${i}`
   eval tsrv=\$$s
   eval tport=\$$p
   testres=`echo "TEST/"|$bls_BLClient -a $tsrv -p $tport`
   if [ "x$testres" == "xYPBS" ] ; then
    pbs_BLPserver=$tsrv
    pbs_BLPport=$tport
    srvfound=1
    break
   fi
  done
  if [ -z $srvfound ] ; then
   echo "1ERROR: not able to talk with no logparser listed"
   exit 0
  fi
 fi
fi

bls_setup_all_files

# Write wrapper preamble
cat > $bls_tmp_file << end_of_preamble
#!/bin/bash
# PBS job wrapper generated by `basename $0`
# on `/bin/date`
#
# stgcmd = $bls_opt_stgcmd
# proxy_string = $bls_opt_proxy_string
# proxy_local_file = $bls_proxy_local_file
#
# PBS directives:
#PBS -S /bin/bash
end_of_preamble

#storage of std files
if [ "x$pbs_std_storage" == "x" ]
then
  pbs_std_storage=/dev/null
fi
if [ "x$pbs_std_storage" != "x" ]
then
  echo "#PBS -o $pbs_std_storage" >> $bls_tmp_file
  echo "#PBS -e $pbs_std_storage" >> $bls_tmp_file
fi

#local batch system-specific file output must be added to the submit file
bls_local_submit_attributes_file=${blah_libexec_directory}/pbs_local_submit_attributes.sh

# Begin building the select statement: select=x where x is the number of 'chunks'
# to request. Chunk requests should precede any resource requests (resource
# requests are order independent). An example from the PBS Pro manual:
# #PBS -l  select=2:ncpus=8:mpiprocs=8:mem=6gb:interconnect=10g,walltime=16:00:00
# Only one chunk is required for OSG needs at this time.
pbs_select="#PBS -l select=1"

if [ "x$bls_opt_req_mem" != "x" ]; then
    # Max amount of virtual memory allocated to a single process
    if [[ "x$pbs_set_pvmem" == "xyes" ]]; then
        echo "#PBS -l pvmem=${bls_opt_req_mem}mb" >> $bls_tmp_file
    fi
    # Max amount of physical memory allocated to a single process
    if [[ "$bls_opt_smpgranularity" == 1 ]]; then
        echo "#PBS -l pmem=${bls_opt_req_mem}mb" >> $bls_tmp_file
    fi
    # Total amount of memory allocated to the job
    pbs_select="$pbs_select:mem=${bls_opt_req_mem}mb"
    if [ "x$pbs_pro" != "xyes" ]; then
        echo "#PBS -l mem=${bls_opt_req_mem}mb" >> $bls_tmp_file
    fi
fi

bls_set_up_local_and_extra_args

# Write PBS directives according to command line options
# handle queue overriding
[ -z "$bls_opt_queue" ] || grep -q "^#PBS -q" $bls_tmp_file || echo "#PBS -q $bls_opt_queue" >> $bls_tmp_file

# Extended support for MPI attributes
if [ "x$pbs_pro" == "xyes" ]; then
    pbs_select="$pbs_select:ncpus=$bls_opt_smpgranularity"
else
    if [ "x$bls_opt_wholenodes" == "xyes" ]; then
        bls_opt_hostsmpsize=${bls_opt_hostsmpsize:-1}
        if [[ ! -z "$bls_opt_smpgranularity" ]] ; then
            if [[ -z "$bls_opt_hostnumber" ]] ; then
                echo "#PBS -l nodes=1:ppn=$bls_opt_hostsmpsize" >> $bls_tmp_file
            else
                echo "#PBS -l nodes=$bls_opt_hostnumber:ppn=$bls_opt_hostsmpsize" >> $bls_tmp_file
            fi
            echo "#PBS -W x=NACCESSPOLICY:SINGLEJOB" >> $bls_tmp_file
        else
            if [[ ! -z "$bls_opt_hostnumber" ]] ; then
                if [[ $bls_opt_mpinodes -gt 0 ]] ; then
                    r=$((bls_opt_mpinodes % bls_opt_hostnumber))
                    (( r )) && mpireminder="+$r:ppn=$bls_opt_hostsmpsize"
                    echo "#PBS -l nodes=$((bls_opt_hostnumber-r)):ppn=${bls_opt_hostsmpsize}${mpireminder}" >> $bls_tmp_file
                else
                    echo "#PBS -l nodes=$bls_opt_hostnumber:ppn=$bls_opt_hostsmpsize" >> $bls_tmp_file
                fi
                echo "#PBS -W x=NACCESSPOLICY:SINGLEJOB" >> $bls_tmp_file
            fi
        fi
    else
        if [[ ! -z "$bls_opt_smpgranularity" ]] ; then
            n=$((bls_opt_mpinodes / bls_opt_smpgranularity))
            r=$((bls_opt_mpinodes % bls_opt_smpgranularity))
            (( r )) && mpireminder="+1:ppn=$r"
            echo "#PBS -l nodes=$n:ppn=${bls_opt_smpgranularity}${mpireminder}" >> $bls_tmp_file
        else
            if [[ ! -z "$bls_opt_hostnumber" ]] ; then
                n=$((bls_opt_mpinodes / bls_opt_hostnumber))
                r=$((bls_opt_mpinodes % bls_opt_hostnumber))
                (( r )) && mpireminder="+$r:ppn=$((n+1))"
                echo "#PBS -l nodes=$((bls_opt_hostnumber-r)):ppn=$n$mpireminder" >> $bls_tmp_file
            elif [[ $bls_opt_mpinodes -gt 0 ]] ; then
                echo "#PBS -l nodes=$bls_opt_mpinodes" >> $bls_tmp_file
            fi
        fi
    fi
fi
# --- End of MPI directives

# Input and output sandbox setup.
if [ "x$blah_torque_multiple_staging_directive_bug" == "xyes" ]; then
  bls_fl_subst_and_accumulate inputsand "stagein=@@F_REMOTE@`hostname -f`:@@F_LOCAL" ","
  [ -z "$bls_fl_subst_and_accumulate_result" ] || echo "#PBS -W $bls_fl_subst_and_accumulate_result" >> $bls_tmp_file
  bls_fl_subst_and_accumulate outputsand "stageout=@@F_REMOTE@`hostname -f`:@@F_LOCAL" ","
  [ -z "$bls_fl_subst_and_accumulate_result" ] || echo "#PBS -W $bls_fl_subst_and_accumulate_result" >> $bls_tmp_file
elif [ "x$blah_torque_multiple_staging_directive_bug" == "xmultiline" ]; then
  bls_fl_subst_and_dump inputsand "#PBS -W stagein=@@F_REMOTE@`hostname -f`:@@F_LOCAL" >> $bls_tmp_file
  bls_fl_subst_and_dump outputsand "#PBS -W stageout=@@F_REMOTE@`hostname -f`:@@F_LOCAL" >> $bls_tmp_file
else
  bls_fl_subst_and_accumulate inputsand "@@F_REMOTE@`hostname -f`:@@F_LOCAL" ","
  [ -z "$bls_fl_subst_and_accumulate_result" ] || echo "#PBS -W stagein=\\'$bls_fl_subst_and_accumulate_result\\'" >> $bls_tmp_file
  bls_fl_subst_and_accumulate outputsand "@@F_REMOTE@`hostname -f`:@@F_LOCAL" ","
  [ -z "$bls_fl_subst_and_accumulate_result" ] || echo "#PBS -W stageout=\\'$bls_fl_subst_and_accumulate_result\\'" >> $bls_tmp_file
fi

if [ "x$pbs_pro" == "xyes" ]; then
    echo $pbs_select >> $bls_tmp_file
fi

echo "#PBS -m n"  >> $bls_tmp_file

bls_add_job_wrapper
bls_save_submit

# Let the wrap script be at least 1 second older than logfile
# for subsequent "find -newer" command to work
sleep 1


###############################################################
# Submit the script
###############################################################

datenow=`date +%Y%m%d`
jobID=`${pbs_binpath}/qsub $bls_tmp_file` # actual submission
retcode=$?
if [ "$retcode" != "0" ] ; then
	rm -f $bls_tmp_file
	# Echo the output from qsub onto stderr, which is captured by HTCondor
	echo "Error from qsub: $jobID" >&2
	exit 1
fi

# The job id is actually the first numbers in the string (slurm support)
jobID=`echo $jobID | awk 'match($0,/[0-9]+/){print substr($0, RSTART, RLENGTH)}'`
if [ "X$jobID" == "X" ]; then
	rm -f $bls_tmp_file
	echo "Error from qsub: $jobID" >&2
	echo Error # for the sake of waiting fgets in blahpd
	exit 1
fi

if [ "x$pbs_nologaccess" != "xyes" -a "x$pbs_nochecksubmission" != "xyes" ]; then

# Don't trust qsub retcode, it could have crashed
# between submission and id output, and we would
# loose track of the job

# Search for the job in the logfile using job name

# Sleep for a while to allow job enter the queue
sleep 5


# find the correct logfile (it must have been modified
# *more* recently than the wrapper script)

logfile=""
jobID_log=""
log_check_retry_count=0
while [ "x$logfile" == "x" -a "x$jobID_log" == "x" ]; do

 cliretcode=0
 if [ "x$pbs_BLParser" == "xyes" ] ; then
     jobID_log=`echo BLAHJOB/$bls_tmp_name| $bls_BLClient -a $pbs_BLPserver -p $pbs_BLPport`
     cliretcode=$?
     if [ "x$jobID_log" != "x" ] ; then
        logfile=$datenow
     fi
 fi
 
 if [ "$cliretcode" == "1" -a "x$pbs_fallback" == "xno" ] ; then
  ${pbs_binpath}/qdel $jobID
  echo "Error: not able to talk with logparser on ${pbs_BLPserver}:${pbs_BLPport}" >&2
  echo Error # for the sake of waiting fgets in blahpd
  rm -f $bls_tmp_file
  exit 1
 fi

 if [ "$cliretcode" == "1" -o "x$pbs_BLParser" != "xyes" ] ; then

     logfile=`find $logpath -type f -newer $bls_tmp_file -exec grep -l "job name = $bls_tmp_name" {} \;`
     if [ "x$logfile" != "x" ] ; then

       jobID_log=`grep "job name = $bls_tmp_name" $logfile | awk -F";" '{ print $5 }'`
     fi
 fi

 if (( log_check_retry_count++ >= 12 )); then
     ${pbs_binpath}/qdel $jobID
     echo "Error: job not found in logs" >&2
     echo Error # for the sake of waiting fgets in blahpd
     rm -f $bls_tmp_file
     exit 1
 fi

 let "bsleep = 2**log_check_retry_count"
 sleep $bsleep

done

if [ "$jobID_log" != "$jobID"  -a "x$jobID_log" != "x" ]; then
    echo "WARNING: JobID in log file is different from the one returned by qsub!" >&2
    echo "($jobID_log != $jobID)" >&2
    echo "I'll be using the one in the log ($jobID_log)..." >&2
    jobID=$jobID_log
fi

fi #end of if on $pbs_nologaccess

if [ "x$pbs_nologaccess" == "xyes" -o "x$pbs_nochecksubmission" == "xyes" ]; then
 logfile=$datenow
fi
  
# Compose the blahp jobID ("pbs/" + logfile + pbs jobid)
blahp_jobID="pbs/`basename $logfile`/$jobID"

if [ "x$job_registry" != "x" ]; then
  now=`date +%s`
  let now=$now-1
  ${blah_sbin_directory}/blah_job_registry_add "$blahp_jobID" "$jobID" 1 $now "$bls_opt_creamjobid" "$bls_proxy_local_file" "$bls_opt_proxyrenew_numeric" "$bls_opt_proxy_subject"
fi

echo "BLAHP_JOBID_PREFIX$blahp_jobID"
  
bls_wrap_up_submit

exit $retcode
