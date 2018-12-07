# zju_l2tp
a refined l2tp vpn client for zju university. fork from original work.

## dependencies
xl2tpd

On ubuntu,  
sudo apt install xl2tpd

On opensuse,  
sudo zypper in xl2tpd

On centos,  
sudo yum install xl2tpd

## usage
just use vpn-connect.sh is okay. vpn-connect_comment.sh contains comments, vpn-connect_old.sh shouldn't be used any more.

1, configure your zju vpn account: sudo vpn-connect -c

2, then connect: sudo vpn-connect

3, disconnect: sudo vpn-connect -d

## CHANGELOG

v0.1

rewrite.

v0.2

1. remove the dependency of script /etc/init.d/xl2tpd. This script file only exists in ubuntu, thus cause problems under opensuse and centos.

2. replace the connection judge condition from PID file existence to pid grep existence. since the pid exists --> pid file exists but pid file exists !--> pid exists especially after reboot and suspend operation.

v0.3 current version

fix the inconsistent detection of live ppp connection in v0.2.1.

## Test

tested on ubuntu, centos, opensuse.
