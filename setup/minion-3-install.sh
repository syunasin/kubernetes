#!/bin/bash

virt-install --virt-type kvm --name centos-minion-3 --vcpus 1 --cpu host --ram 1024 --disk path=/data/hdd/kubernetes/centos-minion-3.qcow2 --network network:kubenet --graphics vnc --os-type linux --os-variant rhel7 --boot hd --location /data/iso/CentOS-7-x86_64-DVD-1611.iso --initrd-inject /tmp/minion-3-ks.cfg --extra-args "inst.ks=file:/minion-3-ks.cfg"
