#!/ffp/bin/sh

#
#  Description: Script to get fan control working with DNS-320
#  Written by Johny Mnemonic
#  @see http://forum.dsmg600.info/viewtopic.php?id=6522
#
#  Modified by: http://seb.flippence.net to provide support for 2x Samsung F4 EcoGreen 2TB 32MB 5400RPM 3.5 Inch SATA-II Internal Hard Drives (HD204UI)
#  with longer cool down period and details command
#

# PROVIDE: fancontrol
# REQUIRE: LOGIN

. /ffp/etc/ffp.subr

name="fancontrol"
start_cmd="fancontrol_start"
stop_cmd="fancontrol_stop"
status_cmd="fancontrol_status"

extra_commands="details"
details_cmd="fancontrol_details"

PERIOD=30
LOGFILE=/var/log/fan.log

# SysHigh=55
# SysLow=50
# HddHigh=50
# HddLow=45
# Hyst=2

SysHigh=55
SysLow=50
HddHigh=43
HddLow=40
Hyst=3

SH=$((SysHigh-Hyst))
DH=$((HddHigh-Hyst))
SL=$((SysLow-Hyst))
DL=$((HddLow-Hyst))

logcommand()
   { 
   echo "`/bin/date '+%b %e %H:%M:%S'`:" $1 >> $LOGFILE
   }

disk1_temp()
    {
	smartctl -d marvell --attributes /dev/sda | grep 194 | tail -c 28 | head -c 2
    }

disk2_temp()
    {
    	smartctl -d marvell --attributes /dev/sdb | grep 194 | tail -c 28 | head -c 2
    }
    
system_temp()
    {
    	FT_testing -T | tail -c 3 | head -c 2
    }

Fancontrol() {
	#!/bin/sh
    
	logcommand "  Starting DNS-320 Fancontrol script"
	logcommand "  Current temperatures: Sys: `system_temp`°C, HDD1: `disk1_temp`°C, HDD2: `disk2_temp`°C "

	FAN=`fanspeed g`
	
	COUNT=0

	while /ffp/bin/true; do
        /bin/sleep $PERIOD

	SYSTEM_TEMP=`system_temp`
	DISK1_TEMP=`disk1_temp`
	DISK2_TEMP=`disk2_temp`
        LOG_TEMP="Sys: $SYSTEM_TEMP°C, HDD1: $DISK1_TEMP°C, HDD2: $DISK2_TEMP°C"

	if [ $FAN == 'low' -o $FAN == 'high' -o $FAN == 'stop' ]; then
		# Do nothing
		FAN="$FAN"
	else
		logcommand "Fan speed not set, setting to low (was $FAN)"
		fanspeed l
		FAN=low
	fi

        if [ $SYSTEM_TEMP -ge $SysHigh -o $DISK1_TEMP -ge $HddHigh -o $DISK2_TEMP -ge $HddHigh ]; then
            # logcommand "Fan speed $FAN"
            if [ $FAN != high ]; then
                logcommand "Running fan on high, temperature too high: $LOG_TEMP "
                fanspeed h
                FAN=high
            fi
        else
	    # Ternary https://developmentality.wordpress.com/2010/10/20/ternary-operator-in-bash/
	    # Temp is low
	    [ $SYSTEM_TEMP -ge $SysLow -o $DISK1_TEMP -ge $HddLow -o $DISK2_TEMP -ge $HddLow ] && if_fan_low=1 || if_fan_low=0
            # If temp has gone over the high limit but if its now less than our high cool down period
	    [ $SYSTEM_TEMP -le $SH -a $DISK1_TEMP -le $DH -a $DISK2_TEMP -le $DH ] && if_fan_hyst=1 || if_fan_hyst=0

            if [ $if_fan_low = 1 -a $if_fan_hyst = 1 ]; then
		# logcommand "Fan speed $FAN"
                if [ $FAN != low ]; then
                    logcommand "Running fan on low, temperature high: $LOG_TEMP "
                    fanspeed l
                    FAN=low
                fi
            else
                if [ $SYSTEM_TEMP -le $SL -a $DISK1_TEMP -le $DL -a $DISK2_TEMP -le $DL ]; then
		    # logcommand "Fan speed $FAN"
                    if [ $FAN != 'stop' ]; then
                        logcommand "Stopping fan, temperature low: $LOG_TEMP "
                        fanspeed s
                        FAN=stop
                    fi
                fi
            fi
        fi
        
        let COUNT=COUNT+1
        if [ $COUNT = 4 ]; then
        	logcommand "Fan speed $FAN: $LOG_TEMP "
        	COUNT=0
        fi
        
    done
}
   
fancontrol_start() {
    if [ ! -e /var/run/fancontrol.pid ] ; then
        logcommand "Starting DNS-320 Fancontrol daemon"
        killall fan_control >/dev/null 2>/dev/null &
        Fancontrol & 
        echo $! >> /var/run/fancontrol.pid
    else
        logcommand "Fancontrol daemon already running"
    fi
}

fancontrol_stop() {
    logcommand "Stopping DNS-320 Fancontrol daemon"
    kill -9 `cat /var/run/fancontrol.pid`
    rm /var/run/fancontrol.pid
}
    
fancontrol_restart() {
    fancontrol_stop
    fancontrol_start
}

fancontrol_status() {
    if [ -e /var/run/fancontrol.pid ]; then
        echo " Fancontrol daemon is running"
    else
        echo " Fancontrol daemon is not running"
    fi
}

fancontrol_details() {
	fancontrol_status
        echo " SysHigh=$SysHigh, SysLow=$SysLow "
        echo " HddHigh=$HddHigh, HddLow=$HddLow "
	echo " Hyst=$Hyst "
	echo " SH=$SH, DH=$DH (high cool down) "
	echo " SL=$SL, DL=$DL (low cool down) "
        echo " Current temperatures: Sys: `system_temp`°C, HDD1: `disk1_temp`°C, HDD2: `disk2_temp`°C "
}

run_rc_command "$1"