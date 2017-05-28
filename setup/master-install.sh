#!/bin/bash

virt-install --virt-type kvm --name centos-master --vcpus 1 --cpu host --ram 1024 --disk path=/data/hdd/kubernetes/centos-master.qcow2 --network network:kubenet --graphics vnc --os-type linux --os-variant rhel7 --boot hd --location /data/iso/CentOS-7-x86_64-DVD-1611.iso --initrd-inject /tmp/master-ks.cfg --extra-args "inst.ks=file:/master-ks.cfg"
