#!/bin/bash
set -e

# ==============================
# 可自定义变量区域（部署前务必修改！）
# ==============================

# 网络配置
APISERVER_ADVERTISE_ADDRESS="192.168.100.110"  # Master节点IP
POD_NETWORK_CIDR="10.244.0.0/16"             # Pod网段

# 版本配置
KUBERNETES_VERSION="v1.33.3"                 # Kubernetes版本
CONTAINERD_VERSION="1.6.39"                   # containerd版本
CNI_PLUGINS_VERSION="v1.7.1"                 # CNI插件版本

# 镜像仓库
REGISTRY_MIRROR="registry.aliyuncs.com/google_containers"  # 国内镜像源
SANDBOX_IMAGE="${REGISTRY_MIRROR}/pause:3.10" # Pause镜像地址

# ==============================
# Step 1: 系统预配置（需要重启）
# ==============================

echo "启动安装流程 Step 1/2 (需重启)"
sleep 2

# 开启IPv4转发
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
sysctl --system >/dev/null

# 关闭swap
swapoff -a
if grep -q swap /etc/fstab; then
  sed -i '/swap/s/^/#/' /etc/fstab
fi

# 禁用SELinux
setenforce 0
if [ -f /etc/selinux/config ]; then
  sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
fi

# 配置yum源
mkdir -p /bak && mv /etc/yum.repos.d/* /bak 2>/dev/null
curl -s -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo

# 安装新内核
yum update -y --nobest
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
yum install -y https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm
sed -i -e 's/^mirrorlist=/#mirrorlist=/' \
       -e 's|http://elrepo.org/linux|https://mirrors.tuna.tsinghua.edu.cn/elrepo|g' \
       /etc/yum.repos.d/elrepo.repo
yum --enablerepo=elrepo-kernel install kernel-lt-devel kernel-lt -y
grub2-set-default 0

echo "==========================================================="
echo "Step 1 完成！请执行以下操作："
echo "1. 手动重启: reboot"
echo "2. 重启后使用以下命令继续安装:"
echo "   $ bash install-k8s.sh step2"
echo "==========================================================="

# ==============================
# Step 2: K8s组件安装（重启后执行）
# ==============================

if [ "$1" != "step2" ]; then
  exit 0
fi

echo "启动安装流程 Step 2/2"
sleep 2

# 验证内核版本
echo "[系统内核] 当前内核版本：$(uname -r)"

# 安装containerd
echo "[容器运行时] 安装containerd ${CONTAINERD_VERSION}"
curl -sL -O https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz >/dev/null
curl -s -o /etc/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service

# 安装runc
curl -sL -O https://github.com/opencontainers/runc/releases/download/v1.3.0/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc

# 安装CNI插件
echo "[网络插件] 安装CNI ${CNI_PLUGINS_VERSION}"
curl -sL -O https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz >/dev/null

# 配置containerd
mkdir -p /etc/containerd/
containerd config default | tee /etc/containerd/config.toml >/dev/null
sed -i "s/SystemdCgroup = false/SystemdCgroup = true/" /etc/containerd/config.toml
sed -i "s|sandbox_image = \".*\"|sandbox_image = \"${SANDBOX_IMAGE}\"|" /etc/containerd/config.toml
systemctl daemon-reload
systemctl enable --now containerd

# 安装Kubernetes
echo "[Kubernetes] 安装组件 v${KUBERNETES_VERSION}"
cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VERSION:1}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VERSION:1}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

yum install -y kubelet-$(echo $KUBERNETES_VERSION | tr -d v) \
               kubeadm-$(echo $KUBERNETES_VERSION | tr -d v) \
               kubectl-$(echo $KUBERNETES_VERSION | tr -d v) \
               --disableexcludes=kubernetes
systemctl enable --now kubelet

# 初始化集群
echo "[集群初始化] 启动K8s集群"
kubeadm config images pull \
  --image-repository=${REGISTRY_MIRROR} \
  --kubernetes-version=${KUBERNETES_VERSION}
  
kubeadm init \
  --apiserver-advertise-address=${APISERVER_ADVERTISE_ADDRESS} \
  --image-repository=${REGISTRY_MIRROR} \
  --kubernetes-version=${KUBERNETES_VERSION} \
  --pod-network-cidr=${POD_NETWORK_CIDR} \
  --cri-socket=unix:///var/run/containerd/containerd.sock \
  --ignore-preflight-errors=NumCPU

# 配置kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# 配置crictl
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# 安装Calico
echo "[网络插件] 安装Calico CNI"
curl -sL -O https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/calico.yaml
sed -i "s|docker.io|quay.io|g" calico.yaml
kubectl apply -f calico.yaml >/dev/null

# 输出完成信息
echo "==========================================================="
echo "Kubernetes 安装完成！"
echo "控制平面IP: ${APISERVER_ADVERTISE_ADDRESS}"
echo "K8s版本: ${KUBERNETES_VERSION}"
echo "Pod网段: ${POD_NETWORK_CIDR}"
echo ""
echo "请记录以下加入命令(worker节点执行):"
kubeadm token create --print-join-command
echo "==========================================================="
