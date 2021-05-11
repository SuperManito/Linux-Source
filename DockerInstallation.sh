#!/bin/env bash
## Author: SuperManito
## License: GPL-2.0
## Modified: 2021-5-12

## 定义目录和文件
RedHatRelease=/etc/redhat-release
DebianSourceList=/etc/apt/sources.list
DebianSourceListBackup=/etc/apt/sources.list.bak
DebianExtendListDirectory=/etc/apt/sources.list.d
DebianExtendListDirectoryBackup=/etc/apt/sources.list.d.bak
RedHatReposDirectory=/etc/yum.repos.d
RedHatReposDirectoryBackup=/etc/yum.repos.d.bak

DockerSourceList=${DebianExtendListDirectory}/docker.list
DockerRepo=${RedHatReposDirectory}/docker-ce.repo
DockerDirectory=/etc/docker
DockerConfig=${DockerDirectory}/daemon.json
DockerConfigBackup=${DockerDirectory}/daemon.json.bak
DockerCompose=/usr/local/bin/docker-compose

## 定义变量
DebianRelease=lsb_release
Architecture=$(uname -m)
SYSTEM_DEBIAN=Debian
SYSTEM_UBUNTU=Ubuntu
SYSTEM_KALI=Kali
SYSTEM_REDHAT=RedHat
SYSTEM_CENTOS=CentOS
SYSTEM_FEDORA=Fedora
PROXY_URL=https://mirror.ghproxy.com/
DOCKER_COMPOSE_URL=https://github.com/docker/compose/releases/download/1.29.1/docker-compose-$(uname -s)-$(uname -m)

## 判定当前系统基于 Debian or RedHat
if [ -f ${RedHatRelease} ]; then
    SYSTEM=${SYSTEM_REDHAT}
else
    SYSTEM=${SYSTEM_DEBIAN}
fi

## 系统判定变量（名称、版本、版本号、使用架构）
if [ ${SYSTEM} = ${SYSTEM_DEBIAN} ]; then
    SYSTEM_NAME=$(${DebianRelease} -is)
    SYSTEM_VERSION=$(${DebianRelease} -cs)
    SYSTEM_VERSION_NUMBER=$(${DebianRelease} -rs)
elif [ ${SYSTEM} = ${SYSTEM_REDHAT} ]; then
    SYSTEM_NAME=$(cat ${RedHatRelease} | cut -c1-6)
    if [ ${SYSTEM_NAME} = ${SYSTEM_CENTOS} ]; then
        SYSTEM_VERSION_NUMBER=$(cat ${RedHatRelease} | cut -c22-24)
        CENTOS_VERSION=$(cat ${RedHatRelease} | cut -c22)
    elif [ ${SYSTEM_NAME} = ${SYSTEM_FEDORA} ]; then
        SYSTEM_VERSION_NUMBER=$(cat ${RedHatRelease} | cut -c16-18)
    fi
fi

if [ $Architecture = "x86_64" ]; then
    SYSTEM_ARCH=x86_64
    SOURCE_ARCH=amd64
elif [ $Architecture = "aarch64" ]; then
    SYSTEM_ARCH=arm64
    SOURCE_ARCH=arm64
elif [ ${Architecture} = "armv7l*" ]; then
    SYSTEM_ARCH=armv7
    SOURCE_ARCH=armhf
elif [ $Architecture = "armv*" ]; then
    SYSTEM_ARCH=armhf
    SOURCE_ARCH=armhf
elif [ $Architecture = "*i?86*" ]; then
    SYSTEM_ARCH=x86_32
    echo -e '\n\033[31m---------- Docker Engine 不支持安装在 x86_32 架构的环境上 ---------- \033[0m'
    exit 1
fi

## 定义更新源分支名称
SOURCE_BRANCH=${SYSTEM_NAME,,}

## 组合各个函数模块
function CombinationFunction() {
    EnvJudgment
    clear
    ChooseMirrors
    RemoveOldVersion
    DockerEngine
    [ ${DOCKER_COMPOSE} = "True" ] && DockerCompose
    ShowVersion
}

## 环境判定：
function EnvJudgment() {
    ## 权限判定：
    if [ $UID -ne 0 ]; then
        echo -e '\033[31m ------------ Permission no enough, please use user ROOT! ------------ \033[0m'
        exit
    fi
    ## 网络环境判定：
    ping -c 1 www.baidu.com >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\033[31m ----- Network connection error.Please check the network environment and try again later! ----- \033[0m"
        exit
    fi
}

## 删除旧版本
function RemoveOldVersion() {
    ## 删除旧的 Docker CE 源
    if [ $SYSTEM = ${SYSTEM_DEBIAN} ]; then
        sed -i '/docker-ce/d' ${DebianSourceList}
        rm -rf ${DockerSourceList}
    elif [ $SYSTEM = ${SYSTEM_REDHAT} ]; then
        rm -rf ${DockerRepo}
    fi
    ## 卸载旧版本
    systemctl disable --now docker >/dev/null 2>&1
    if [ $SYSTEM = ${SYSTEM_DEBIAN} ]; then
        apt-get remove -y docker* runc >/dev/null 2>&1
    elif [ $SYSTEM = ${SYSTEM_REDHAT} ]; then
        yum remove -y docker* >/dev/null 2>&1
    fi
}

## 安装 Docker Engine
function DockerEngine() {
    ## 安装前环境检测
    if [ $SYSTEM = ${SYSTEM_DEBIAN} ]; then
        apt-get update
    elif [ $SYSTEM = ${SYSTEM_REDHAT} ]; then
        yum makecache
    fi
    VERIFICATION_SOURCESYNC=$?
    if [ ${VERIFICATION_SOURCESYNC} -ne 0 ]; then
        echo -e '\033[31m ------------ 软件源同步出错，请先确保软件包管理工具可用！ ------------ \033[0m'
        exit
    fi

    ## 安装环境软件包
    if [ $SYSTEM = ${SYSTEM_DEBIAN} ]; then
        apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
    elif [ $SYSTEM = ${SYSTEM_REDHAT} ]; then
        yum install -y yum-utils device-mapper-persistent-data lvm2
    fi

    ## 配置 Docker CE 源
    if [ $SYSTEM = ${SYSTEM_DEBIAN} ]; then
        if [ $SYSTEM_NAME = ${SYSTEM_KALI} ]; then
            curl -fsSL https://${SOURCE}/linux/debian/gpg | apt-key add -
        else
            curl -fsSL https://${SOURCE}/linux/${SOURCE_BRANCH}/gpg | apt-key add -
        fi

        echo "deb [arch=${SOURCE_ARCH}] https://${SOURCE}/linux/${SOURCE_BRANCH} $SYSTEM_VERSION stable" | tee ${DockerSourceList} >/dev/null 2>&1

        if [ $SYSTEM_NAME = ${SYSTEM_KALI} ]; then
            sed -i "s/${SYSTEM_VERSION}/buster/g" ${DockerSourceList}
            sed -i "s/${SOURCE_BRANCH}/debian/g" ${DockerSourceList}
        fi
    elif [ $SYSTEM = ${SYSTEM_REDHAT} ]; then
        yum-config-manager -y --add-repo https://${SOURCE}/linux/${SOURCE_BRANCH}/docker-ce.repo
    fi

    ## 安装 Docker Engine 软件包
    if [ $SYSTEM = ${SYSTEM_DEBIAN} ]; then
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
    elif [ $SYSTEM = ${SYSTEM_REDHAT} ]; then
        yum makecache
        yum install -y docker-ce docker-ce-cli containerd.io
    fi

    ## 配置镜像加速器
    [ $REGISTRY_SOURCE_OFFICIAL == "True" ] || ImageAccelerator

    ## 启动 Docker Engine 服务
    systemctl stop docker >/dev/null 2>&1
    systemctl enable --now docker
}

## 镜像加速器
function ImageAccelerator() {
    ## 创建目录和文件
    if [ -d ${DockerDirectory} ] && [ -e ${DockerConfig} ]; then
        if [ -e ${DockerConfigBackup} ]; then
            echo -e "\n\033[32m└ 检测到已备份的 Docker 配置文件，跳过备份操作 ...... \033[0m\n"
        else
            cp -rf ${DockerConfig} ${DockerConfigBackup}
            echo -e "\n\033[32m└ 已备份原有 Docker 配置文件至 ${DockerConfigBackup} ...... \033[0m\n"
        fi
        sleep 2s
    else
        mkdir -p ${DockerDirectory} >/dev/null 2>&1
        touch ${DockerConfig}
    fi

    ## 配置镜像加速器
    echo -e '{\n  "registry-mirrors": ["https://SOURCE"]\n}' >${DockerConfig}
    sed -i "s/SOURCE/$REGISTRY_SOURCE/g" ${DockerConfig}
    systemctl daemon-reload
}

## 安装 Docker Compose
function DockerCompose() {
    echo -e ''
    ## 卸载旧版本
    [ -e ${DockerCompose} ] && rm -rf ${DockerCompose}
    if [ ${DOCKER_COMPOSE_PROXY} = "True" ]; then
        curl -L ${PROXY_URL}${DOCKER_COMPOSE_URL} -o ${DockerCompose}
    else
        curl -L ${DOCKER_COMPOSE_URL} -o ${DockerCompose}
    fi
    chmod +x ${DockerCompose}
    echo -e ''
}

## 查看版本信息
function ShowVersion() {
    docker info
    [ -x ${DockerCompose} ] && docker-compose -v
    echo -e '\n\033[32m---------- 安装完成 ---------- \033[0m\n'
}

## 选择 Docker CE & Docker Hub 源：
function ChooseMirrors() {
    echo -e '+---------------------------------------------------+'
    echo -e '|                                                   |'
    echo -e '|   =============================================   |'
    echo -e '|                                                   |'
    echo -e '|            欢迎使用 Docker 一键安装脚本           |'
    echo -e '|                                                   |'
    echo -e '|   =============================================   |'
    echo -e '|                                                   |'
    echo -e '+---------------------------------------------------+'
    echo -e ''
    echo -e '#####################################################'
    echo -e ''
    echo -e '    提供以下 Docker CE 和 Docker Hub 源可供选择：'
    echo -e ''
    echo -e '#####################################################'
    echo -e ''
    echo -e ' Docker CE'
    echo -e ''
    echo -e ' *  1)    阿里云'
    echo -e ' *  2)    腾讯云'
    echo -e ' *  3)    华为云'
    echo -e ' *  4)    微软 Azure'
    echo -e ' *  5)    网易'
    echo -e ' *  6)    清华大学'
    echo -e ' *  7)    浙江大学'
    echo -e ' *  8)    中国科学技术大学'
    echo -e ' *  9)    官方（国际）'
    echo -e ''
    echo -e ' Docker Hub'
    echo -e ''
    echo -e ' *  1)    阿里云'
    echo -e ' *  2)    腾讯云'
    echo -e ' *  3)    华为云'
    echo -e ' *  4)    微软 Azure'
    echo -e ' *  5)    DaoCloud'
    echo -e ' *  6)    网易'
    echo -e ' *  7)    中国科学技术大学'
    echo -e ' *  8)    谷歌云（国际）'
    echo -e ' *  9)    官方（国际）'
    echo -e ''
    echo -e '#####################################################'
    echo -e ''
    echo -e "            运行环境  ${SYSTEM_NAME} ${SYSTEM_VERSION_NUMBER} ${SYSTEM_ARCH}"
    echo -e "            系统时间  $(date "+%Y-%m-%d %H:%M:%S")"
    echo -e ''
    echo -e '#####################################################'
    CHOICE_A=$(echo -e '\n\033[32m└ 请选择并输入您想使用的 Docker CE 源 [ 1~9 ]：\033[0m')
    read -p "${CHOICE_A}" INPUT
    case $INPUT in
    1)
        SOURCE="mirrors.aliyun.com/docker-ce"
        ;;
    2)
        SOURCE="mirrors.cloud.tencent.com/docker-ce"
        ;;
    3)
        SOURCE="mirrors.huaweicloud.com/docker-ce"
        ;;
    4)
        SOURCE="mirror.azure.cn/docker-ce"
        ;;
    5)
        SOURCE="mirrors.163.com/docker-ce"
        ;;
    6)
        SOURCE="mirrors.tuna.tsinghua.edu.cn/docker-ce"
        ;;
    7)
        SOURCE="mirrors.zju.edu.cn/docker-ce"
        ;;
    8)
        SOURCE="mirrors.ustc.edu.cn/docker-ce"
        ;;
    9)
        SOURCE="download.docker.com"
        ;;
    *)
        SOURCE="mirrors.aliyun.com/docker-ce"
        echo -e '\n\033[33m---------- 输入错误，Docker CE 源将默认使用阿里云 ---------- \033[0m'
        sleep 2s
        ;;
    esac
    echo -e ''

    ## 定义镜像加速器
    CHOICE_B=$(echo -e '\033[32m└ 请选择并输入您想使用的 Docker Hub 源 [ 1~9 ]：\033[0m')
    read -p "${CHOICE_B}" INPUT
    case $INPUT in
    1)
        REGISTRY_SOURCE="registry.cn-hangzhou.aliyuncs.com"
        REGISTRY_SOURCE_OFFICIAL="False"
        ;;
    2)
        REGISTRY_SOURCE="mirror.ccs.tencentyun.com"
        REGISTRY_SOURCE_OFFICIAL="False"
        ;;
    3)
        REGISTRY_SOURCE="0bab0ef02500f24b0f31c00db79ffa00.mirror.swr.myhuaweicloud.com"
        REGISTRY_SOURCE_OFFICIAL="False"
        ;;
    4)
        REGISTRY_SOURCE="dockerhub.azk8s.com"
        REGISTRY_SOURCE_OFFICIAL="False"
        ;;
    5)
        REGISTRY_SOURCE="f1361db2.m.daocloud.io"
        REGISTRY_SOURCE_OFFICIAL="False"
        ;;
    6)
        REGISTRY_SOURCE="hub-mirror.c.163.com"
        REGISTRY_SOURCE_OFFICIAL="False"
        ;;
    7)
        REGISTRY_SOURCE="docker.mirrors.ustc.edu.cn"
        REGISTRY_SOURCE_OFFICIAL="False"
        ;;
    8)
        REGISTRY_SOURCE="gcr.io"
        REGISTRY_SOURCE_OFFICIAL="False"
        ;;
    9)
        REGISTRY_SOURCE="registry.docker-cn.com"
        REGISTRY_SOURCE_OFFICIAL="True"
        ;;
    *)
        REGISTRY_SOURCE="registry.cn-hangzhou.aliyuncs.com"
        echo -e '\033[33m---------- 输入错误，将默认使用阿里云镜像加速器 ---------- \033[0m'
        sleep 3s
        ;;
    esac

    ## 选择是否安装 Docker Compose
    if [ -x ${DockerCompose} ]; then
        CHOICE_C=$(echo -e '\n\033[32m└ 检测到已安装 Docker Compose ，是否覆盖安装 [ Y/n ]：\033[0m')
    else
        CHOICE_C=$(echo -e '\n\033[32m└ 是否安装 Docker Compose [ Y/n ]：\033[0m')
    fi
    read -p "${CHOICE_C}" INPUT
    [ -z ${INPUT} ] && INPUT=Y
    case $INPUT in
    [Yy]*)
        DOCKER_COMPOSE="True"
        ## 选择下载方式
        CHOICE_C1=$(echo -e '\n\033[32m  └ 是否使用国内代理进行下载 [ Y/n ]：\033[0m')
        read -p "${CHOICE_C1}" INPUT
        [ -z ${INPUT} ] && INPUT=Y
        case $INPUT in
        [Yy]*)
            DOCKER_COMPOSE_PROXY="True"
            ;;
        [Nn]*)
            DOCKER_COMPOSE_PROXY="False"
            ;;
        *)
            DOCKER_COMPOSE_PROXY="False"
            echo -e '\n\033[33m---------- 输入错误，默认不使用代理 ---------- \033[0m\n'
            ;;
        esac
        ;;
    [Nn]*)
        DOCKER_COMPOSE="False"
        ;;
    *)
        DOCKER_COMPOSE="False"
        echo -e '\n\033[33m---------- 输入错误，默认不安装 Docker Compose ---------- \033[0m\n'
        ;;
    esac
    echo -e ''
}

CombinationFunction
