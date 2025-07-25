# Kubernetes安装脚本 - CentOS 8 + Containerd优化版

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
![Platform](https://img.shields.io/badge/Platform-CentOS%208-lightgrey)
[![Containerd](https://img.shields.io/badge/Runtime-Containerd%201.6%2B-green)](https://containerd.io)

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

🔄 **智能安装流程**  
- Master节点：两步安装（系统预配置 + K8s组件安装）
- Worker节点：自动生成专用安装脚本
- 组件安装前自动检查，避免重复安装

## 系统要求

| 组件 | 要求 |
|------|------|
| 操作系统 | CentOS 8.5 (建议全新安装) |
| CPU | 2核+ |
| 内存 | 2GB+ (Master节点建议4GB+) |
| 网络 | 可访问公网 (需要访问国内镜像源) |
| 磁盘 | 20GB+ 可用空间 |

## 快速开始

### Master节点安装

1. **下载安装脚本**
```bash
curl -LO https://raw.githubusercontent.com/Xnidada/k8s-install-centos8-containerd/main/kube-install-containerd.sh
chmod +x kube-install-containerd.sh
```

2. **自定义配置**  
编辑脚本顶部的配置区域：
```bash
###############################
# 用户可配置区域（部署前修改！）
###############################

# Master节点网络配置
APISERVER_ADVERTISE_ADDRESS="192.168.100.110"  # Master节点IP
POD_NETWORK_CIDR="10.244.0.0/16"             # Pod网段
MASTER_HOSTNAME="k8s-master"                  # Master主机名
WORKER_HOSTNAME_PREFIX="k8s-worker"          # Worker主机名前缀

# 版本配置
KUBERNETES_VERSION="v1.33.3"                 # Kubernetes版本
CONTAINERD_VERSION="1.6.39"                  # containerd版本
CNI_PLUGINS_VERSION="v1.7.1"                  # CNI插件版本
CRICTL_VERSION="v3.30.2"                     # CRICTL版本（Calico版本）

# 镜像仓库
REGISTRY_MIRROR="registry.aliyuncs.com/google_containers"  # 国内镜像源
```

3. **执行安装**
```bash
# 第一阶段：系统优化和内核升级
sudo ./kube-install-containerd.sh

# 重启后执行第二阶段
sudo ./kube-install-containerd.sh step2
```

### Worker节点安装

1. **获取Worker安装脚本**  
Master节点安装完成后，会在当前目录生成`install-k8s-worker.sh`脚本

2. **复制脚本到Worker节点**
```bash
scp install-k8s-worker.sh user@worker-node:/path/
```

3. **在Worker节点执行**
```bash
# Step1: 系统预配置（需要重启）
sudo ./install-k8s-worker.sh

# 重启后执行Step2并加入集群
sudo ./install-k8s-worker.sh step2 "<JOIN_COMMAND>"
```
`<JOIN_COMMAND>`替换为Master安装完成后输出的kubeadm join命令

## 安装流程说明

### Master节点安装流程
#### Phase 1: 系统预配置
- ✅ 设置主机名和主机映射
- ✅ 启用IPv4转发和网桥过滤
- ✅ 永久关闭Swap和SELinux
- ✅ 禁用防火墙
- ✅ 配置阿里云yum源加速
- ✅ 安装最新稳定版Linux内核
- 💻 完成提示系统重启

#### Phase 2: Kubernetes安装
- 🐳 安装配置containerd容器运行时
- 📦 部署Kubernetes三件套(kubelet/kubeadm/kubectl)
- ✨ 初始化Kubernetes控制平面
- 🌐 安装Calico网络插件
- 📜 自动生成Worker节点安装脚本

### Worker节点安装流程
#### Phase 1: 系统预配置
- ✅ 自动生成Worker主机名（前缀+IP末位）
- ✅ 添加Master主机解析
- ✅ 网络优化与安全设置
- ✅ 内核升级与系统更新
- 💻 完成提示系统重启

#### Phase 2: 加入集群
- 🐳 安装容器运行时和CNI插件
- 📦 部署Kubernetes组件
- 🤝 使用join命令加入集群
- 🌐 拉取Calico网络镜像

## 中国优化亮点

```bash
# 使用国内镜像源
REGISTRY_MIRROR="registry.aliyuncs.com/google_containers"

# containerd中国配置
sandbox_image = "registry.aliyuncs.com/google_containers/pause:3.10"

# yum源加速
baseurl=https://mirrors.aliyun.com/...

# elrepo清华镜像源
https://mirrors.tuna.tsinghua.edu.cn/elrepo
```

## 卸载说明

```bash
# Master节点卸载
kubeadm reset -f
yum remove -y kubelet kubeadm kubectl
systemctl stop containerd
rm -rf /etc/containerd/ /var/lib/containerd/

# Worker节点卸载
kubeadm reset -f
yum remove -y kubelet kubeadm
systemctl stop containerd
rm -rf /etc/containerd/ /var/lib/containerd/

# 所有节点恢复
sed -i '/swap/s/^#//' /etc/fstab  # 恢复swap
swapoff -a && swapon -a
sed -i 's/^SELINUX=permissive$/SELINUX=enforcing/' /etc/selinux/config
setenforce 1
systemctl enable --now firewalld
```

## 贡献指南

欢迎提交PR！请确保：
1. 在CentOS 8.5+环境下测试通过
2. 保持向后兼容性
3. 更新文档中的对应说明
4. 遵循现有代码风格

## 项目结构

```
k8s-centos8-containerd/
├── kube-install-containerd.sh   # Master节点安装脚本
├── install-k8s-worker.sh        # Worker节点安装脚本（由Master安装后生成,无需手动设置）
├── README.md                    # 本文档
├── LICENSE                      # Apache 2.0许可证
```

## 注意事项

1. **主机名规则**：
   - Worker节点主机名自动生成：`<前缀>-<IP末位>`（如k8s-worker-110）
   - 确保所有节点主机名唯一
   - 主机名长度不超过63字符

2. **网络要求**：
   - Master节点需固定IP
   - Pod网段不能与主机网络重叠
   - 所有节点间网络互通（关闭防火墙）

3. **内核升级**：
   - 安装前建议备份重要数据
   - 如遇内核启动问题，可在GRUB选择旧内核启动

## 常见问题解答

**Q: 安装过程中下载失败怎么办？**  
A: 脚本会自动重试下载，如多次失败请检查：
- 网络连接是否正常
- 能否访问GitHub和阿里云镜像站
- 防火墙是否阻止了下载

**Q: Worker节点加入集群失败？**  
A: 检查：
1. Master节点6443端口是否开放
2. join命令中的token是否过期（默认24小时）
3. Worker节点与Master时间是否同步
4. 使用`journalctl -u kubelet`查看日志

**Q: 如何添加多个Worker节点？**  
A: 在每个Worker节点上重复执行：
1. 复制`install-k8s-worker.sh`脚本
2. 执行Step1和重启
3. 执行Step2并传入相同的join命令

**Q: 如何升级Kubernetes版本？**  
A: 建议重新安装：
1. 备份集群重要数据
2. 卸载当前集群
3. 修改脚本中的版本号后重新安装

---

<a href="https://star-history.com/#Xnidada/k8s-install-centos8-containerd&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Xnidada/k8s-install-centos8-containerd&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Xnidada/k8s-install-centos8-containerd&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Xnidada/k8s-install-centos8-containerd&type=Date" />
 </picture>
</a>

**如果这个项目帮助您节省了时间，请点击右上角的 ⭐ 支持项目发展！**
