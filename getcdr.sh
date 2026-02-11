#!/bin/bash

##################################################################
#                                                                #
# - a.loiseau - 20/02/2014 ------------------------------------- #
#                                                                #
# This script is used to retrieve cdrs from each platform of     #
# each site.                                                     #
# Rsync is used to make sure src is the same as dest even if     #
# the dom is unreachable for a long period.                      #
#                                                                #
##################################################################


# Fonctions ######################################################
#
# echo usage
#
function usage {
        cat << EOF
usage: $(basename $0) options

This script synchronise CDR from a specific place to this server ($(hostname))

OPTIONS:
   -h      Show this message
   -c      Configuration file

EXAMPLE of config file:

SITE="REU MTQ MAY"			# mandatory
PFS="SMSC USSD SMSFW"			# mandatory
DST_DIR="/home/cdr/mctel/"		# mandatory, {hostname}, {pfs}, {site}, {id} can be use as variable, "!" for upper case
SRC_DIR="/home/cdr/"			# optional, default: /home/cdr/
PURGE=31				# optional, default: 31 days, 0 => no purge
DEL_SOURCE=0				# optional, remove source file after copy 1=>yes, 0=no, default: 0
LOGIN="cdr"				# optional, default: cdr
PASSWD="mypassword"			# optional
FILTER=xxxxx				# optional
KEY="/path/to/private/key"		# optional, \$KEY override \$PASSWD
LOCK="/var/lock/cdr/.mctel/cdr.xlock"	# optional, default: /var/tmp/.cdr.xlock 
LOG="/var/log/cdr/getcdr.log"		# optional, default: /var/tmp/getcdr.log 
SKIP_SECOND_SERVER=0			# optional, default: 0
GZIPPED=1				# optional, default: 0
NO_RSYNC=1				# optional, if client does not support rsync, default: 0

EOF
}

#
# echo ouput in a specific format and send to log file if needed
#
function log {
	if [ -t 1 ]
	then
        	echo "$(date '+%Y %b %d %H:%M:%S') $(hostname) $(basename $0)[$PID]: $1"
	else
		echo "$(date '+%Y %b %d %H:%M:%S') $(hostname) $(basename $0)[$PID]: $1" 2>&1 >> $LOG
	fi
}

#
# Purge file up to 31 days for a specific directory
#
function purge {
	if [ -z $1 ]
        then
                log "[ERROR] not enough argument provided"
                exit 2
        else
		_data=$1
		find "$_data" -type f -mtime +$PURGE -exec rm -f {} \;
	fi
}

function getind {
	case $1 in
		gpe) return 1
		     ;;
		mtq) return 2
                     ;;
		guy) return 3
		     ;;
		reu) return 4
                     ;;
		mad) return 5
		     ;;
		cry) return 15
                     ;;
		mau) return 6
                     ;;
		plh) return 116
                     ;;
		may) return 7
		     ;;
		*)   return 99
		     ;;
	esac
}

#
# Translate {xxx} variables into values
#
function forge_dst_dir {
	YMD=$(date +%Y%m%d)
        getind ${_dom,,}
        ind=$?
	dst_rdir=$DST_DIR
	dst_rdir=$(echo $dst_rdir|sed s/\{hostname\}/${serv,,}/)
	dst_rdir=$(echo $dst_rdir|sed s/\{!hostname\}/${serv^^}/)
	dst_rdir=$(echo $dst_rdir|sed s/\{pfs\}/${_msc,,}/)
	dst_rdir=$(echo $dst_rdir|sed s/\{!pfs\}/${_msc^^}/)
	dst_rdir=$(echo $dst_rdir|sed s/\{site\}/${_dom,,}/)
	dst_rdir=$(echo $dst_rdir|sed s/\{!site\}/${_dom^^}/)
	dst_rdir=$(echo $dst_rdir|sed s/\{id\}/${i,,}/)
	dst_rdir=$(echo $dst_rdir|sed s/\{!id\}/${i^^}/)
	dst_rdir=$(echo $dst_rdir|sed s/\{YMD\}/$YMD/)
	dst_rdir=$(echo $dst_rdir|sed s/\{ind\}/$ind/)
}

function forge_src_dir {
	YMD=$(date +%Y%m%d)
        getind ${_dom,,}
        ind=$?
        src_rdir=$SRC_DIR
        src_rdir=$(echo $src_rdir|sed s/\{hostname\}/${serv,,}/)
        src_rdir=$(echo $src_rdir|sed s/\{!hostname\}/${serv^^}/)
        src_rdir=$(echo $src_rdir|sed s/\{pfs\}/${_msc,,}/)
        src_rdir=$(echo $src_rdir|sed s/\{!pfs\}/${_msc^^}/)
        src_rdir=$(echo $src_rdir|sed s/\{site\}/${_dom,,}/)
        src_rdir=$(echo $src_rdir|sed s/\{!site\}/${_dom^^}/)
        src_rdir=$(echo $src_rdir|sed s/\{id\}/${i,,}/)
        src_rdir=$(echo $src_rdir|sed s/\{!id\}/${i^^}/)
        src_rdir=$(echo $src_rdir|sed s/\{YMD\}/$YMD/)
	src_rdir=$(echo $src_rdir|sed s/\{ind\}/$ind/)
}

function forge_filter {
	year=$(date +%y)
	allyear=$(date +%Y)
	tfilter=$FILTER
	#echo "forge, tfilter: $tfilter"
        tfilter=$(echo $tfilter|sed s/%Y/${allyear}/)
	#echo "forge, tfilter: $tfilter"
}

#
# Get files from msc by pair (SITE-PFS-01 // SITE-PFS-02), purge if success
#
function synccdrs {
	if [ -z $1 ] || [ -z $2 ]
	then
		log "[ERROR] not enough argument provided"
		exit 2
	else
		_dom=${1^^}
		_msc=${2^^}
		mscdir="$_dom/$_msc"
	fi

	if [ -z "$FILTER" ]
	then
		FILTER="$_dom"
	else if [ "$FILTER" != "*" ]
		then
			forge_filter
			#echo "tfilter: $tfilter"
			FILTER="$tfilter"
			#echo "FILTER: $FILTER"
		fi
	fi
	
	fails=0				# clear global errors counter
	purge_dirs=""			# init directories to purge

	end_loop="02"	
	if [ $SKIP_SECOND_SERVER -eq 1 ]
	then
		end_loop="01"
	fi

	for i in `eval echo {01..$end_loop}`
	do      
		fail=0 			# clear error counter
        	serv="$_dom-$_msc-$i" 	# generate serveur name
		pre=$(date +%s)		# init timer

		# Forge $DST_DIR in case of templating
		forge_dst_dir
		purge_dirs="$purge_dirs $dst_rdir"

		# Forge $SRC_DIR
		forge_src_dir
                #echo "src_dir: $src_rdir"

		log "Syncing $serv files"
		if [ $NO_RSYNC -eq 1 ]
		then
			$SFTP $SFTP_OPTIONS --use-pget-n=8 $LOGIN@$serv << EOF > /dev/null
cd $src_rdir
lcd $dst_rdir
mget $FILTER
bye
EOF
		fail=$?
		else
			if [ $GZIPPED -eq 0 ]
			then
				$RSYNC $RSYNC_OPTS -e "$SSH $SSH_OPTIONS -l $LOGIN" --exclude='*.curr' --exclude='*.gz' --include=$FILTER'*' --exclude='*' $serv:$src_rdir/ $dst_rdir/ 2>> $LOG
			else
		 		$RSYNC $RSYNC_OPTS -e "$SSH $SSH_OPTIONS -l $LOGIN" --exclude='*.curr' --include=$FILTER'*' --exclude='*' $serv:$src_rdir/ $dst_rdir/ 2>> $LOG
			fi
			fail=$?
		fi

		aft=$(date +%s)		# stop timer
		let fails=$fails+$fail  # count errors
                if [ $fail -eq 0 ]	# manage return code of rsync
                then    
                        let dif=$aft-$pre
                        log "$serv Sync finished in $dif seconds"
		else
			log "/!\ $serv Sync terminates with errors"
                fi
	done

	if [[ $fails -eq 0 ]] && [[ "$PURGE" != "0" ]]
	then
		log "nodes $_msc on $_dom are synced, removing files older than $PURGE days"
		#purge "$dst_rdir"
		for i in $purge_dirs
		do
			purge $i
		done
	else
		log "no purge for nodes $_msc on $_dom"
	fi

        if [[ "$UNTAR" != "0" ]]
        then
            if [[ "$GZIPPED" == "0" ]]
            then
                find $dst_rdir -type f -name "*.tar" ! -path "$dst_rdir/archives/*" -exec tar xvf {} --directory $dst_rdir --no-same-owner \;
            else
                find $dst_rdir -type f \( -name "*.tgz" -o -name "*.tar.gz" \) ! -path "$dst_rdir/archives/*" -exec tar xvfz {} --directory $dst_rdir --no-same-owner \;
            fi
            find $dst_rdir -name "$UNTAR" -exec mv {} $dst_rdir \;
            find $dst_rdir -type f \( -name "*.tgz" -o -name "*.tar.gz" -o -name "*.tar" \) ! -path "$dst_rdir/archives/*" -exec mv {} $dst_rdir/archives/  \;
            find $dst_rdir -type d -empty -delete
        fi

	exit $fails
}

##################################################################


# Init ###########################################################
if [ "$UID" -eq 0 ]
  then echo "Please don't run $0 as root" >&2
  exit
fi

LOGIN="cdr"
ACK="/tmp/cdr.out"
PID=$$
PURGE=31
SSH=/usr/bin/ssh
SFTP=/usr/bin/sftp
SSH_OPTIONS="-q -oStrictHostKeychecking=no -oUserKnownHostsFile=/dev/null"
SFTP_OPTIONS="-oStrictHostKeychecking=no -oUserKnownHostsFile=/dev/null"
RSYNC=/usr/bin/rsync
DEL_SOURCE=0
#RSYNC_OPTS="--remove-source-files -rlptcz"
RSYNC_OPTS="-rlptcz"
SKIP_SECOND_SERVER=0
GZIPPED=0
UNTAR=0
NO_RSYNC=0

while getopts “hc:” OPTION
do
     case $OPTION in
         h)  usage
             exit 1
             ;;
         c)  OPT_FILE=$OPTARG
             shift 2
             ;;
     esac
done

if [ -z $OPT_FILE ]
then   
        OPT_FILE=/etc/getcdr.conf
fi

if [ -f $OPT_FILE ]
then
. $OPT_FILE
else   
        log "[ERROR] config file $OPT_FILE does not exists"
        exit 3
fi

# Check if mandatory pamater exists
if [[ -z "$SITE" ]] || [[ -z "$PFS" ]] || [[ -z $DST_DIR ]]
then   
        log "[ERROR] mandatory parameter is not present"
        exit 4
fi

# Set non-mandatory parameters to default value
if [ ! -z $KEY ]
then
	SSH_OPTIONS="$SSH_OPTIONS -oIdentityFile=$KEY"
else if [ ! -z $PASSWD ]
	then
		SSH="sshpass -p $PASSWD $SSH"
		SFTP="sshpass -p $PASSWD $SFTP"
	else
		log "[ERROR] no password or private key has been provide, check your configuration file"
                exit 5	
	fi
fi

if [ -z $SRC_DIR ]
then
	SRC_DIR="/home/cdr/"
fi

if [ -z $LOCK ]
then   
        LOCK="/var/tmp/.cdr.xlock"
fi

if [ -z $LOG ]
then   
        LOG="/var/tmp/getcdr.log"
fi

if [ $DEL_SOURCE -eq 1 ]
then
	RSYNC_OPTS="$RSYNC_OPTS --remove-source-files"
fi

if [ -z $UNTAR ]
then
	UNTAR=0
fi

##################################################################


# BEGIN ##########################################################
(
  # Wait for lock on /var/lock/.cdr.xlock (fd 200) for 10 seconds
  flock -x -w 10 200 || exit 1		# create semaphore

  # Just a loop
  for i in $PFS				# process plateforms one by one
  do
	for j in $SITE			# process all DOMs
	do
		synccdrs $j $i &	# launch syncing in background for paralleling
	done
	wait				# wait for the msc to finish before going futher
  done

#  if [ "$UNTAR" == "1" ]; then
 #     for i in $(ls $); do
 #         echo $i
 #     done
 # fi

  #echo "dst: $DST_DIR"	                # Remove ~/.ssh directory

) 200>$LOCK				# free lock

# END ############################################################

The script uses the configuration as show below:
SITE="GPE"
PFS="CIRPACKT_IMS"
DST_DIR="/home/cdr/cirpack_ims/{!site}/{hostname}"
SRC_DIR="/home/omni/tickets"
PURGE=60
DEL_SOURCE=0
LOGIN="omni"
KEY="/etc/ssh/generated_keys/cirpack_ims/cirpack_ims_id_rsa"
FILTER="grnti*0"
LOCK="/var/lock/cdr/.cirpack_ims/getcdr-cirpack_ims.xlock"
LOG="/var/log/cdr/cirpack_ims/getcdr-cirpack_ims.log"
SKIP_SECOND_SERVER=1

Please explain each line of the script and what it does? How the data in the configuration file is used?
