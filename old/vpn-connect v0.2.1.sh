#!/bin/bash

####################
# Variables
####################
## How many seconds to wait for the ppp to come up each try
TIMEOUT=20
## LAC name in config file
L2TPD_LAC=zjuvpn

## auto-generated file, don't need to care about.
L2TPD_CONTROL_FILE=/var/run/xl2tpd/l2tp-control
L2TPD_INIT_FILE=/usr/sbin/xl2tpd
L2TPD_CFG_FILE=/etc/xl2tpd/xl2tpd.conf
L2TPD_PID_FILE=/var/run/xl2tpd.pid
# PPPD files
PPP_OPT_FILE=/etc/ppp/peers/zjuvpn
PPP_LOG_FILE=/var/log/zjuvpn


## lns.zju.edu.cn must use ip!
VPN_SERVER="10.5.1.9"
#VPN_SERVER=$(dig +short lns.zju.edu.cn)

####################
# Commands
####################
function myl2tp
{
case "$1" in
  start)
    if ! [ -e $L2TPD_PID_FILE ]; then
        $L2TPD_INIT_FILE
    else
        echo 'Already exists other xl2tp process.'
    fi
	;;
  stop)
    # must kill pppd first
    if ! [ -e $L2TPD_PID_FILE ]; then
        echo 'No live l2tp connection!'
        return
    fi
    # then kill xl2tpd
    kill `sed -n '1p' $L2TPD_PID_FILE`
	;;
esac

}

function usage
{
    cat <<EOF
$0: A utility for ZJU school L2TP VPN.
Usage: $0 [ACTION]

Actions: 
      Default             Connect.
      -d                  Disconnect.
      -r                  Reconnect.
      -c                  Configure.
      -s                  Only setup static route.
      -h                  Show this information.

EOF
}

function connect
{
    if ppp_alive ; then
        echo "[MSG] VPN already connected."
    else
        bring_up_ppp && setup_route
    fi
}

function disconnect
{
    echo "[MSG] Disconnecting VPN ... "
    # write disconnect command to l2tp server
    # wait 1s, for the server to response
    # if the server response in 1s, then pppd will be end, otherwise, pppd still exists
    # actually directly kill xl2tpd will also cause connection terminate automatically.
    # so this sentence isn't necessary.
    [ -e $L2TPD_CONTROL_FILE ] && echo "d $L2TPD_LAC" > $L2TPD_CONTROL_FILE && sleep 1
    # kill the pid
    myl2tp stop
    echo "Done!"
    tail $PPP_LOG_FILE | sed -u 's/^/[LOG] pppd: /'
    echo -n > $PPP_LOG_FILE
    return 0
}

function reconnect
{
    disconnect && connect
}

function configure
{
    echo "Configure L2TP VPN for ZJU.";
    read_param && write_settings
    echo "[MSG] Configuration saved. You can use 'vpn-connect' to connect."
}

####################
# Internal utility functions
####################
function super_user
{
    if [ "$UID" = "0" ]; then
        return 0         # Yes, super user
    else
        return 1
    fi
}

function read_param
{
    read -p "Username: " username
    if [ "${username/@/}" = "$username" ]; then
        echo -e "WARNING: If you are connecting to ZJU VPN, you\e[01;31;1m must\e[0m append your domain name (e.g. @a / @c / @d) after your username."
    fi
    read -s -p "Password: " password
    echo
}

function ppp_alive
{
    # this won't work well when you reboot without disconnect,
    # because in this case, both xl2tpd.pid and ppp-zjuvpn.pid still exists
    # if [ -e /var/run/ppp-$L2TPD_LAC.pid ] && ip addr show | grep 'inet.*ppp' > /dev/null; then
    pid=`ps -ef | grep $L2TPD_LAC | grep -v grep`
    # if ! ps -ef | grep $L2TPD_LAC | grep -v grep; then
    if [ -n "$pid" ]; then
        return 0         # Yes, connected
    else
        return 1
    fi
}

function monitor_ppp_log
{
    sleep $TIMEOUT >/dev/null 2>&1 &
    WAITPID=$!
    disown %1
    trap "kill $WAITPID >/dev/null 2>&1" SIGINT
    tail -f --pid $WAITPID $PPP_LOG_FILE 2>/dev/null | awk '
    {
        print "[LOG] pppd:", $0;
        if (index($0, "remote IP address") != 0 || index($0, "terminated") != 0) {
            close(0);
            system("echo >> '$PPP_LOG_FILE'");
            exit 0;
        }
    }
'
    kill $WAITPID >/dev/null 2>&1
    echo -n > $PPP_LOG_FILE
    trap SIGINT
    return 0
}

function test_connection
{
    if ping -c 1 -q $VPN_SERVER > /dev/null 2>&1 ; then
        return 0
    else
        cat <<EOF
[ERR] The network connection between your computer and the VPN server
[ERR] was interrupted. This can be caused by:
[ERR]     1) VPN server temporarily got down.
[ERR]     2) Route table of your computer got corrupted. Restart your
[ERR]        computer and try again.
[ERR]     3) You have not logged into campus network. If you are in
[ERR]        Students' Dormitory of Zijingang Campus, make sure that
[ERR]        you have passed authentication via '201 card' or 'Shan
[ERR]        Xun'.
[ERR]
EOF
        return 1
    fi
}

function bring_up_ppp
{

    echo "[MSG] Trying to bring up vpn..."
    # ! return true if the following command execute failed,
    # i.e. return nonzero value
    # however, this usage is tricky.
    if ! test_connection; then
        return 1
    fi
    #no need to stop first
    #myl2tp stop
    echo -n > $PPP_LOG_FILE
    myl2tp start
    monitor_ppp_log
    if ppp_alive; then
        echo "[LOG] Done!"
        return 0     # Yes, brought up!
    fi
    myl2tp stop
    echo "[ERR] Failed to bring up vpn!"
    return 1
}

function setup_route
{
    GW=$(ip route get $VPN_SERVER 2>/dev/null | grep via | awk '{print $3}')
    PPP=$(ip addr show | grep ppp[0-9]: | cut "-d " -f2 | cut -d: -f1)
    echo "[MSG] Detected gateway: $GW, PPP device: $PPP ."
    echo -n "[MSG] Setting up route table...  "

    ip route add 10.0.0.0/8 via $GW 2>/dev/null
    ip route add 210.32.0.0/20 via $GW 2>/dev/null
    ip route add 210.32.128.0/18 via $GW 2>/dev/null
    ip route add 222.205.0.0/16 via $GW 2>/dev/null
    ip route add 58.206.192.0/19 via $GW 2>/dev/null

    ip route add 0.0.0.0/1 dev $PPP 2>/dev/null
    ip route add 128.0.0.0/1 dev $PPP 2>/dev/null
    echo "Done!"
}

function write_settings
{
    cat > $L2TPD_CFG_FILE <<EOF
[global]
access control = no
auth file = /etc/ppp/chap-secrets
debug avp = no
debug network = no
debug packet = no
debug state = no
debug tunnel = no

[lac zjuvpn]
lns = 10.5.1.9
redial = no
redial timeout = 5
require chap = yes
require authentication = no
ppp debug = no
pppoptfile = /etc/ppp/peers/zjuvpn
require pap = no
autodial = yes
EOF

    cat > $PPP_OPT_FILE <<EOF
noauth
lcp-echo-interval 0
lcp-echo-failure 0
linkname $L2TPD_LAC
logfile $PPP_LOG_FILE
name $username
password $password
EOF
    chmod 600 $PPP_OPT_FILE

    return 0
}


####################
# Main
####################
if ! super_user ; then
    echo "[ERR] You must be super user to run this utility!"
    exit 1
fi

if [ $# -lt 1 ]; then
    connect
elif [ "$1" = "-d" ]; then
    disconnect
elif [ "$1" = "-r" ]; then
    reconnect
elif [ "$1" = "-c" ]; then
    configure
elif [ "$1" = "-s" ]; then
    setup_route
elif [ "$1" = "-h" ]; then
    usage
else
    echo "[ERR] Unknown parameter.";
    usage
fi

