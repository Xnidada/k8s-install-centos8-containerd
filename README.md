# Kubernetes安装脚本 - CentOS 8 + Containerd优化版

https://img.shields.io/badge/License-Apache%202.0-blue.svg](https://opensource.org/licenses/Apache-2.0)
!https://img.shields.io/badge/Platform-CentOS%208-lightgrey
https://img.shields.io/badge/Runtime-Containerd%201.6%2B-green](https://containerd.io)

专为CentOS 8环境设计的Kubernetes一键安装脚本，使用containerd作为容器运行时，针对中国大陆网络环境深度优化，支持最新稳定版Kubernetes快速部署。

## 核心优势

🚀 **中国环境极速安装**  
- 使用阿里云镜像仓库替代Google容器仓库
- 内置清华大学elrepo源加速
- 所有组件均通过国内CDN加速下载

🔧 **最新组件支持**  
- 支持Kubernetes v1.33+ 最新稳定版
- 预装containerd 1.6.39+ 高性能运行时
- 默认使用Calico v3.30网络插件

🔄 **简易两步安装**  
```bash
# 第一步：系统预配置
sudo ./kube-install-containerd.sh

# 重启后...
# 第二步：Kubernetes安装
sudo ./kube-install-containerd.sh step2
```

## 系统要求

| 组件 | 要求 |
|------|------|
| 操作系统 | CentOS 8.5 (建议全新安装) |
| 网络 | 可访问公网 (需要访问国内镜像源) |

## 快速开始

1. **下载安装脚本**
```bash
curl -LO https://raw.githubusercontent.com/Xnidada/k8s-install-centos8-containerd/main/kube-install-containerd.sh
chmod +x kube-install-containerd.sh
```

2. **(可选) 自定义配置**  
编辑脚本顶部的配置区域：
```bash
###############################
# 用户可配置区域（部署前修改！）
###############################

APISERVER_ADVERTISE_ADDRESS="192.168.100.110"  # 本机IP地址
POD_NETWORK_CIDR="10.244.0.0/16"               # Kubernetes Pod网段
KUBERNETES_VERSION="v1.33.3"                   # Kubernetes版本
CONTAINERD_VERSION="1.6.39"                   # containerd版本
CNI_PLUGINS_VERSION="v1.7.1"                   # CNI插件版本
CALICO_VERSION="v3.30.2"                       # Calico版本
```

3. **执行安装**
```bash
# 第一阶段：系统优化和内核升级
sudo ./kube-install-containerd.sh

# 重启后执行第二阶段
sudo ./kube-install-containerd.sh step2
```

## 安装流程说明

### Phase 1: 系统预配置
- ✅ 启用IPv4转发
- ✅ 永久关闭Swap和SELinux
- ✅ 配置阿里云yum源加速
- ✅ 安装最新稳定版Linux内核
- 💻 完成提示系统重启

### Phase 2: Kubernetes安装
- 🐳 安装配置containerd容器运行时
- 📦 部署Kubernetes三件套(kubelet/kubeadm/kubectl)
- ✨ 初始化Kubernetes控制平面
- 🌐 安装Calico网络插件
- 🔑 自动生成worker节点加入命令

## 中国优化亮点

```bash
# 使用国内镜像源
REGISTRY_MIRROR="registry.aliyuncs.com/google_containers"

# containerd中国配置
sandbox_image = "registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.10"

# yum源加速
baseurl=https://mirrors.aliyuncs.com/...
```

## 获取加入节点命令

在Master节点安装完成后，运行：
```bash
kubeadm token create --print-join-command
```

输出类似：
```bash
kubeadm join 192.168.100.110:6443 --token xyz123 \
    --discovery-token-ca-cert-hash sha256:abcdef123456
```

## 卸载说明

```bash
# 1. 清理Kubernetes
kubeadm reset -f
yum remove -y kubelet kubeadm kubectl

# 2. 清理containerd
systemctl stop containerd
rm -rf /etc/containerd/ /var/lib/containerd/

# 3. 恢复系统配置
# 参考脚本的相反操作...
```

## 贡献指南

欢迎提交PR！请确保：
1. 在CentOS 8.5+环境下测试通过
2. 保持向后兼容性
3. 更新文档中的对应说明

---

## 项目结构

```
k8s-centos8-containerd/
├── kube-install-containerd.sh   # 主安装脚本
├── README.md                    # 本文档
├── LICENSE                      # Apache 2.0许可证
```

此项目全面解决了中国大陆环境下安装Kubernetes的各种痛点，是CentOS 8用户快速搭建生产级Kubernetes集群的优选方案。
