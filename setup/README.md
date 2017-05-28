# CentOS7 の仮想マシン上に Kubernetes をインストールする

[Installing Kubernetes on Linux with kubeadm]([https://kubernetes.io/docs/getting-started-guides/kubeadm/) を参考にして CentOS 7.3 に kubernetes をインストールします。複数マシンでクラスタ構成を試してみたいので、CentOS7 をインストールした仮想マシンに Kubernetes をインストールします。  
仮想マシンは [古いインストール手順](https://kubernetes.io/docs/getting-started-guides/centos/centos_manual_config/) と同じように構成します。master を 1 台、minion を 3 台 の仮想マシンを用意します。

```
centos-master = 192.168.121.9
centos-minion-1 = 192.168.121.65
centos-minion-2 = 192.168.121.66
centos-minion-3 = 192.168.121.67
```

設定ファイルなどは github に置いてあるので参照してください。
* [https://github.com/syunasin/kubernetes/tree/master/setup](https://github.com/syunasin/kubernetes/tree/master/setup)


# 環境

ホスト
* Core i3-4020U(1.9GHz)
* メモリ16GB
* CentOS7.3

仮想マシン x4
* メモリ1GB
* HDD 10GB
* CentOS7.3

# 仮想マシンの作成

KVM 環境は作成済みであることは前提とします。  
以下の操作はホストマシン上の root ユーザーで実行します。

## CentOS7 の DVD イメージを取得

```
# mkdir -p /data/iso
# cd /data/iso
# wget http://ftp.iij.ad.jp/pub/linux/centos/7/isos/x86_64/CentOS-7-x86_64-DVD-1611.iso
```

## 仮想 HDD の作成

```
# mkdir -p /data/hdd/kubernetes
# cd /data/hdd/kubernetes
# qemu-img create -f qcow2 centos-master.qcow2 10G
# qemu-img create -f qcow2 centos-minion-1.qcow2 10G
# qemu-img create -f qcow2 centos-minion-2.qcow2 10G
# qemu-img create -f qcow2 centos-minion-3.qcow2 10G
```

## 仮想ネットワークの作成

例えば以下の xml を作成してネットワークを作成します。

```xml:/tmp/kubenet.xml
<network>
  <name>kubenet</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr1' stp='off' delay='0'/>
  <ip address='192.168.121.1' netmask='255.255.255.0'/>
</network>
```

以下の操作で 192.168.121.* の kubenet が作成されます。

```
# virsh net-define /tmp/kubenet.xml
# virsh net-start kubenet
# virsh net-autostart kubenet
# virsh net-list
```

## 仮想マシンの作成

CentOS を自動インストールために kickstart ファイルを用意します。以下は master 用の kickstart ファイルです。ip アドレス、ホスト名を変更して minion 用に同様のファイルを作成します。

```xml:/tmp/master-ks.cfg
#version=DEVEL
# System authorization information
auth --enableshadow --passalgo=sha512
# Use CDROM installation media
cdrom
# Use graphical install
graphical
# Run the Setup Agent on first boot
firstboot --enable
ignoredisk --only-use=vda
# Keyboard layouts
keyboard --vckeymap=jp --xlayouts='jp'
# System language
lang ja_JP.UTF-8

# Network information
network  --bootproto=static --device=eth0 --onboot=on --activate --gateway=192.168.122.1 --ip=192.168.122.9 --nameserver=192.168.122.1 --netmask=255.255.255.0 --noipv6
network  --hostname=centos-master

# Root password
rootpw --plaintext root
# System services
#services --enabled="chronyd"
# System timezone
timezone Asia/Tokyo --isUtc
user --groups=wheel --name=kube --password=kube --plaintext --gecos="kube"
# System bootloader configuration
bootloader --location=mbr --boot-drive=vda
autopart --type=lvm

# Partition clearing information
clearpart --all --initlabel --drives=vda

install
reboot
zerombr
text

%packages
@core
@base
%end

%post --log=/root/postinstall.log
yum update -y
%end
```

以下のコマンドを実行して、master 用の仮想マシンを起動します。同様に minion 用の仮想マシンを 3 つ起動します。
変更するパラメータは以下のとおりです。
* --name
* --disk
* --initrd-inject
* --extra-args

```
# virt-install \
    --virt-type kvm \
    --name centos-master \
    --vcpus 1 \
    --cpu host \
    --ram 1024 \
    --disk path=/data/hdd/kubernetes/master.qcow2 \
    --network network:kubenet \
    --graphics vnc \
    --os-type linux \
    --os-variant rhel7 \
    --boot hd \
    --location /data/iso/CentOS-7-x86_64-DVD-1611.iso \
    --initrd-inject /tmp/master-ks.cfg \
    --extra-args "inst.ks=file:/master-ks.cfg" \
```

インストールが終ったときに再起動しない場合があります。その場合は virt-manager から起動してください。

```
# virt-manager
virt-manager が起動したら、仮想マシンを右クリックして起動を選択します。
```

# master の設定

master に kubernet をインストールします。

## master にログイン

ホストマシンから master にログインします。
ユーザーは kube、パスワードは kube です。
kube のインストールは master 上の root ユーザーで実行します。

```
$ ssh kube@192.168.122.9
kube@192.168.122.9's password: kube
$ sudo su -
[sudo] password for kube: kube
#
```

## kubernet のリポジトリの設定

kubernet の yum のリポジトリを作成します。
以下の内容を /etc/yum.repos.d/kubernetes.repo に保存します。

```
# vi /etc/yum.repos.d/kubernetes.repo
```

```/etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
```

## /etc/sysctl.d/k8s.conf の設定

/etc/sysctl.d/k8s.conf に以下の設定します。

```
# vi /etc/sysctl.d/k8s.conf
```

```/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
```

## /etc/hosts の設定

/etc/hosts に以下を追加します。

```
centos-master   192.168.121.9
centos-minion-1 192.168.121.65
centos-minion-2 192.168.121.66
centos-minion-3 192.168.121.67
```

## ファイアウォールの無効化

ファイアウォールを無効化します。

```
# systemctl stop firewalld
# systemctl disable firewalld
```

## SELinux の無効化

kubernetes はまだ SELinux をサポートしていないようなので無効化します。
/etc/sysconfig/selinux の SELINUX=enforcing を SELINUX=disabled に変更します。
編集が完了したら、いったんリブートします。
リブート完了したら、再度にログインして root ユーザーになってください。

```
# vi /etc/sysconfig/selinux
# reboot
```

```
$ ssh kube@192.168.122.9
kube@192.168.122.9's password: kube
$ sudo su -
[sudo] password for kube: kube
#
```


## kubernetes のインストール

```
# setenforce 0
# yum install -y docker kubelet kubeadm kubectl kubernetes-cni
# systemctl enable docker && systemctl start docker
# systemctl enable kubelet && systemctl start kubelet
```

## kubernetes の初期化

kubeadm init を実行します。インストールに成功すると

 Your Kubernetes master has initialized successfully!

と表示されます。失敗したときは kubeadm reset すれば init する前の状態に戻ります。

```
# kubeadm init
[root@centos-master kube]# kubeadm init
[kubeadm] WARNING: kubeadm is in beta, please do not use it for production clusters.
[init] Using Kubernetes version: v1.6.4
[init] Using Authorization mode: RBAC
[preflight] Running pre-flight checks
[preflight] WARNING: hostname "centos-master" could not be reached
[preflight] WARNING: hostname "centos-master" lookup centos-master on 192.168.121.1:53: no such host
[certificates] Generated CA certificate and key.
[certificates] Generated API server certificate and key.
[certificates] API Server serving cert is signed for DNS names [centos-master kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 192.168.121.9]
[certificates] Generated API server kubelet client certificate and key.
[certificates] Generated service account token signing key and public key.
[certificates] Generated front-proxy CA certificate and key.
[certificates] Generated front-proxy client certificate and key.
[certificates] Valid certificates and keys now exist in "/etc/kubernetes/pki"
[kubeconfig] Wrote KubeConfig file to disk: "/etc/kubernetes/admin.conf"
[kubeconfig] Wrote KubeConfig file to disk: "/etc/kubernetes/kubelet.conf"
[kubeconfig] Wrote KubeConfig file to disk: "/etc/kubernetes/controller-manager.conf"
[kubeconfig] Wrote KubeConfig file to disk: "/etc/kubernetes/scheduler.conf"
[apiclient] Created API client, waiting for the control plane to become ready
[apiclient] All control plane components are healthy after 69.402003 seconds
[apiclient] Waiting for at least one node to register
[apiclient] First node has registered after 2.624214 seconds
[token] Using token: 4b0978.d0855f49cbe81a34
[apiconfig] Created RBAC rules
[addons] Created essential addon: kube-proxy
[addons] Created essential addon: kube-dns

Your Kubernetes master has initialized successfully!

To start using your cluster, you need to run (as a regular user):

  sudo cp /etc/kubernetes/admin.conf $HOME/
  sudo chown $(id -u):$(id -g) $HOME/admin.conf
  export KUBECONFIG=$HOME/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  http://kubernetes.io/docs/admin/addons/

You can now join any number of machines by running the following on each node
as root:

  kubeadm join --token 4b0978.d0855f49cbe81a34 192.168.121.9:6443
# 
```

環境変数 KUBECONFIG を設定します。/root/.bash_profile にも環境変数の設定を追加しておきます。

```
# export KUBECONFIG=/etc/kubernetes/admin.conf
# vi /root/.bash_profile
```

あとで minion を join するときに使用するので、以下をメモっておきます。token は環境によって異なります。

```
  kubeadm join --token 4b0978.d0855f49cbe81a34 192.168.121.9:6443
```


## pod network のインストール

[アドオン](https://kubernetes.io/docs/concepts/cluster-administration/addons/) の Networking and Network Policy の中からネットワークを選んでインストールします。ここでは Weave Net をインストールしてみます。

```
# kubectl apply -f https://git.io/weave-kube-1.6
```

## 動作確認

master が動作しているかどうか確認しておきます。

```
# kubectl get nodes
NAME            STATUS    AGE       VERSION
centos-master   Ready     1m       v1.6.4
```

pod が動作しているかどうかも確認しておきます。すべて Running 状態になるまでには少し時間がかります。

```
# kubectl get pods --all-namespaces
NAMESPACE     NAME                                    READY     STATUS    RESTARTS   AGE
kube-system   etcd-centos-master                      1/1       Running   0          3m
kube-system   kube-apiserver-centos-master            1/1       Running   0          2m
kube-system   kube-controller-manager-centos-master   1/1       Running   0          2m
kube-system   kube-dns-3913472980-6qlgm               3/3       Running   0          3m
kube-system   kube-proxy-7qwjg                        1/1       Running   0          3m
kube-system   kube-scheduler-centos-master            1/1       Running   0          2m
kube-system   weave-net-wdpbh                         2/2       Running   0          1m
```

# minion の設定

minion の設定をします。以下は minion-1 の設定です。同様に minion-2, minion-3 を設定してください。

## minion にログイン

ホストマシンから minion-1 にログインします。
ユーザーは kube、パスワードは kube です。
kube のインストールは minion-1 上の root ユーザーで実行します。

```
$ ssh kube@192.168.122.65
kube@192.168.122.65's password: kube
$ sudo su -
[sudo] password for kube: kube
#
```

## kubernetes のインストール

master の設定で実施した以下の手順を、同様に minion でも実施します。master の手順を参照してください。

* kubernet のリポジトリの設定
* /etc/sysctl.d/k8s.conf の設定
* /etc/hosts の設定
* ファイアウォールの無効化
* SELinux の無効化
* kubernetes のインストール

## minion の追加

kubernetes の初期化のときにメモっておいた join を実行します。

```
# kubeadm join --token 4b0978.d0855f49cbe81a34 192.168.121.9:6443
```

master にログインして minion-1 が追加されていることを確認します。Ready, Running になるまで、しばらく時間がかかります。

```
# ssh kube@192.168.122.9
kube@192.168.122.9's password: kube
# sudo su -
[sudo] password for kube: kube
# kubectl get nodes
NAME              STATUS    AGE       VERSION
centos-master     Ready     1h        v1.6.4
centos-minion-1   Ready     1m        v1.6.4
# kubectl get pods --all-namespaces
NAMESPACE     NAME                                    READY     STATUS    RESTARTS   AGE
kube-system   etcd-centos-master                      1/1       Running   1          12m
kube-system   kube-apiserver-centos-master            1/1       Running   1          12m
kube-system   kube-controller-manager-centos-master   1/1       Running   1          12m
kube-system   kube-dns-3913472980-6qlgm               3/3       Running   0          17m
kube-system   kube-proxy-27c8w                        1/1       Running   0          59s
kube-system   kube-proxy-7qwjg                        1/1       Running   1          17m
kube-system   kube-scheduler-centos-master            1/1       Running   1          12m
kube-system   weave-net-pvqf3                         2/2       Running   0          59s
kube-system   weave-net-wdpbh                         2/2       Running   0          6m
```

# クラスタ構成の確認

master, minion をインストールすると最終的には以下の構成になります。master で実行します。

```
# kubectl get nodes
NAME              STATUS    AGE       VERSION
centos-master     Ready     38m       v1.6.4
centos-minion-1   Ready     22m       v1.6.4
centos-minion-2   Ready     10m       v1.6.4
centos-minion-3   Ready     1m        v1.6.4
# kubectl get pods --all-namespaces
NAMESPACE     NAME                                    READY     STATUS    RESTARTS   AGE
kube-system   etcd-centos-master                      1/1       Running   1          33m
kube-system   kube-apiserver-centos-master            1/1       Running   1          33m
kube-system   kube-controller-manager-centos-master   1/1       Running   1          33m
kube-system   kube-dns-3913472980-6qlgm               3/3       Running   0          38m
kube-system   kube-proxy-1g22c                        1/1       Running   0          10m
kube-system   kube-proxy-27c8w                        1/1       Running   0          22m
kube-system   kube-proxy-29q4c                        1/1       Running   0          1m
kube-system   kube-proxy-7qwjg                        1/1       Running   1          38m
kube-system   kube-scheduler-centos-master            1/1       Running   1          33m
kube-system   weave-net-0dvs3                         2/2       Running   1          10m
kube-system   weave-net-kjlj5                         2/2       Running   1          1m
kube-system   weave-net-pvqf3                         2/2       Running   1          22m
kube-system   weave-net-wdpbh                         2/2       Running   0          28m
```

# dashboard のインストール

Podの一覧などを表示する dashboard をインストールします。
以下の操作はすべて master 上で行います。

## dashboard のインストール

```
# kubectl create -f https://git.io/kube-dashboard
```

## nginx のインストール

ホストマシンから dashboard にアクセスできるように nginx をインストールします。
kubernet の認証を設定すれば master の api serve に直接接続して dashboard を表示できると思うのですが、
設定方法がわかりませんでした。

/etc/yum.repo.d/nginx.repo に nginx のリポジトリを設定します。

```
# vi /etc/yum.repo.d/nginx.repo
```

```/etc/yum.repos.d/nginx.repo
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/7/$basearch/
gpgcheck=0
enabled=1
```

nginx をインストール。

```
# yum install -y nginx
```

nginx の設定にリバースプロキシの設定を追加します。
/etc/nginx/nginx.conf の http の設定の中に以下を追加します。

```
    server {
        listen 18001;
        location / {
            proxy_pass http://localhost:8001;
        }
    }
```

nginx を起動します。

```
# systemctl start nginx
# systemctl enable nginx
```

kubernetes の proxy を起動します。フォアグランドで動作します。
この状態で ホストマシンのブラウザから http://192.168.121.9:18001/ui にアクセスすると dashboard を表示します。

```
# kube proxy
Starting to serve on 127.0.0.1:8001
```

# 参考

* [https://kubernetes.io/docs/getting-started-guides/kubeadm/](https://kubernetes.io/docs/getting-started-guides/kubeadm/)
* [https://kubernetes.io/docs/getting-started-guides/centos/centos_manual_config/](https://kubernetes.io/docs/getting-started-guides/centos/centos_manual_config/)
* [https://github.com/kubernetes/dashboard](https://github.com/kubernetes/dashboard)
