#!/bin/bash

# =============================================================
# Kubernetes Worker节点安装脚本
# =============================================================

set -e

# 配置参数（根据Master节点安装时设置）
APISERVER_ADVERTISE_ADDRESS="192.168.100.110" 
POD_NETWORK_CIDR="10.244.0.0/16"
KUBERNETES_VERSION="v1.33.3"
CONTAINERD_VERSION="1.6.39"
CNI_PLUGINS_VERSION="v1.7.1"
CRICTL_VERSION="v3.30.2"
REGISTRY_MIRROR="registry.aliyuncs.com/google_containers"
SANDBOX_IMAGE="${REGISTRY_MIRROR}/pause:3.10"
MASTER_HOSTNAME="k8s-master"
WORKER_HOSTNAME_PREFIX="k8s-worker"

# 生成worker主机名
worker_index=$(ip a | grep -Eo 'inet [0-9.]+/' | grep -v '127.0.0.1' | head -n 1 | cut -d ' ' -f 2 | cut -d '/' -f 1 | cut -d '.' -f 4)
WORKER_HOSTNAME="${WORKER_HOSTNAME_PREFIX}-${worker_index}"
hostnamectl set-hostname ${WORKER_HOSTNAME}

echo "============================================================="
echo "安装 Kubernetes Worker节点"
echo "主机名: \$(hostname)"
echo "K8s版本: \${KUBERNETES_VERSION}"
echo "连接Master: \${MASTER_IP} (\${MASTER_HOSTNAME})"
echo "============================================================="

# ==============================
# Step 1: 系统预配置（需要重启）
# ==============================
if [ "\$1" != "step2" ]; then
  echo "启动Worker安装流程 Step 1/2 (需重启)"
  sleep 2

  # 添加master主机解析
  if ! grep -q "\${MASTER_HOSTNAME}" /etc/hosts; then
    echo "\${MASTER_IP} \${MASTER_HOSTNAME}" >> /etc/hosts
  fi

  # 开启IPv4转发
  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
  sysctl --system >/dev/null

  # 关闭swap
  swapoff -a
  if grep -q swap /etc/fstab; then
    sed -i '/swap/s/^/#/' /etc/fstab
  fi

  # 禁用SELinux与防火墙
  setenforce 0
  if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
  fi
  systemctl disable --now firewalld

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
  echo "Worker Step 1 完成！请执行以下操作："
  echo "1. 手动重启: reboot"
  echo "2. 重启后使用以下命令加入集群:"
  echo "   $ ./$WORKER_SCRIPT step2 \"<JOIN_COMMAND>\""
  echo "  <JOIN_COMMAND> 替换为Master提供的kubeadm join命令"
  echo "==========================================================="
  
  exit 0
fi

# ==============================
# Step 2: K8s组件安装并加入集群
# ==============================

if [ -z "\$2" ]; then
  echo "错误：未提供kubeadm join命令!"
  echo "使用方法: ./$WORKER_SCRIPT step2 \"<kubeadm join命令>\""
  exit 1
fi

JOIN_COMMAND="\$2"

echo "启动Worker安装流程 Step 2/2"
sleep 2

# 验证内核版本
echo "[系统内核] 当前内核版本：\$(uname -r)"

# 安装 containerd
echo "[容器运行时] 安装containerd ${CONTAINERD_VERSION}"
CONTAINERD_TARBALL="containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz"
# 检查 containerd 是否已安装
if ! command -v /usr/local/bin/containerd &> /dev/null; then
  if [ ! -f "${CONTAINERD_TARBALL}" ]; then
    curl -sL -O https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/${CONTAINERD_TARBALL}
  fi
  tar Cxzvf /usr/local ${CONTAINERD_TARBALL} >/dev/null
else
  echo "containerd 已安装，跳过。"
fi

# 检查 systemd 配置是否已存在
if [ ! -f "/etc/systemd/system/containerd.service" ]; then
  curl -s -o /etc/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
fi

# 检查 runc 是否已安装
RUNC_BINARY="runc.amd64"
if ! command -v /usr/local/sbin/runc &> /dev/null; then
  if [ ! -f "${RUNC_BINARY}" ]; then
    curl -sL -O https://github.com/opencontainers/runc/releases/download/v1.3.0/${RUNC_BINARY}
  fi
  install -m 755 ${RUNC_BINARY} /usr/local/sbin/runc
else
  echo "runc 已安装，跳过。"
fi

# 安装 CNI 插件
echo "[网络插件] 安装CNI ${CNI_PLUGINS_VERSION}"
CNI_TARBALL="cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz"
if [ ! -d "/opt/cni/bin" ] || [ ! "$(ls -A /opt/cni/bin)" ]; then
  if [ ! -f "${CNI_TARBALL}" ]; then
    curl -sL -O https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/${CNI_TARBALL}
  fi
  mkdir -p /opt/cni/bin
  tar Cxzvf /opt/cni/bin ${CNI_TARBALL} >/dev/null
else
  echo "CNI 插件已安装，跳过。"
fi

# 配置containerd
if [ ! -d "/etc/containerd/" ] || [ ! -f "/etc/containerd/config.toml" ]; then
  mkdir -p /etc/containerd/
  containerd config default | tee /etc/containerd/config.toml >/dev/null
  sed -i "s/SystemdCgroup = false/SystemdCgroup = true/" /etc/containerd/config.toml
  sed -i "s|sandbox_image = \".*\"|sandbox_image = \"${SANDBOX_IMAGE}\"|" /etc/containerd/config.toml
  systemctl daemon-reload
  systemctl enable --now containerd
else
  echo "containerd 已配置，跳过。"
fi

# 安装Kubernetes
echo "[Kubernetes] 安装组件 ${KUBERNETES_VERSION}"
YUMKUBERNETES_VERSION=$(echo $KUBERNETES_VERSION | grep -o 'v[0-9]\+\.[0-9]\+')
cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${YUMKUBERNETES_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${YUMKUBERNETES_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
yum install -y kubelet kubeadm --disableexcludes=kubernetes
systemctl enable --now kubelet

# 加入集群
echo "[加入集群] 正在加入Kubernetes集群..."
eval \$JOIN_COMMAND

# calico镜像下载
ctr -n k8s.io image pull quay.io/calico/cni:${CRICTL_VERSION}
ctr -n k8s.io image pull quay.io/calico/node:${CRICTL_VERSION}
ctr -n k8s.io image pull quay.io/calico/kube-controllers:${CRICTL_VERSION}

# 配置crictl
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF

echo "==========================================================="
echo "Worker节点加入完成！"
echo "可在Master节点执行以下命令查看节点状态:"
echo "   kubectl get nodes --kubeconfig /etc/kubernetes/admin.conf"
echo "==========================================================="