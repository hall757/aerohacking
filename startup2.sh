#!/bin/sh
umask 077
mkdir -p /tmp/root/.ssh
cp /f/authorized_keys /tmp/root/.ssh/authorized_keys
mkdir -p /tmp/home/admin/.ssh
ln /tmp/root/.ssh/authorized_keys /tmp/home/admin/.ssh/authorized_keys
# create beacon folder
mkdir /tmp/BLE
# bind mount a ro folder over working folders
mount -o bind /info /tmp/BLE
mount -o bind /info /etc2/BLE
mount -o bind /info /etc/BLE
# mark ble as in upgrade status so script skips startup
touch /tmp/ble_upgrade_in_progress
# kill anything that is currently running
kill $(ps | egrep '(ibeacon|bsa_server)' | grep -v grep | awk '{ print $1 }')
# reset the bt chip
ble_test reset
