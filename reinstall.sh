#!/bin/bash

clusters_count=3
user_home_dir="/home/zhangcd"
ob_bin_source_dir="/home/zhangcd/oceanbase_install"

#解析命令行参数
while getopts "c:u:b:h" name
do
  case "${name}" in
  "c")
    clusters_count=${OPTARG}
    ;;
  "u")
    user_home_dir=${OPTARG}
    ;;
  "b")
    ob_bin_source_dir=${OPTARG}
    ;;
  "h")
    echo "Usage: sh $1 [-c cluster_count] [-u user_home_dir] [-b ob_bin_source_dir]"
    exit 0;
    ;;
  *)
    exit -1;
    ;;
  esac
done

function write_log
{
  level=$1
  msg=$2
  case $level in
  debug)
    echo -e "\e[1;33m[DEBUG] [`date "+%Y-%m-%d %H:%M:%S"`]\e[0m $msg"
    ;;
  info)
    echo -e "\e[1;32m[INFO] [`date "+%Y-%m-%d %H:%M:%S"`]\e[0m $msg"
    ;;
  error)
    echo -e "\e[1;31m[ERROE] [`date "+%Y-%m-%d %H:%M:%S"`]\e[0m $msg"
    ;;
  *)
    echo "error......"
    ;;
  esac
}

function echo_execute
{
  if [ $# -ne 1 ]; then
    echo "param error!"
  else
    write_log info "$1"
    eval "$1"
  fi
}

function kill_process_by_name
{
  if [ $# -ne 1 ]; then
    echo "kill_process_by_name param error!"
  else
    process_name=$1
    pid_list=`ps ux | grep ${process_name} | grep -v "grep" | awk '{print $2}'`
    echo "kill ${process_name}"
    for pid in ${pid_list}
    do
      echo_execute "kill -9 ${pid}"
    done
  fi
}

#杀掉所有还在运行的server
echo_execute "kill_process_by_name rootserver"
echo_execute "kill_process_by_name updateserver"
echo_execute "kill_process_by_name mergeserver"
echo_execute "kill_process_by_name chunkserver"

#挨个地清理、启动每个集群
for((i=1; i<=clusters_count;i++))
do
  #删除各个machine目录下子目录内容
  echo_execute "rm -rf ${user_home_dir}/clusters/machine${i}/bin/*"
  echo_execute "rm -rf ${user_home_dir}/clusters/machine${i}/etc/*"
  echo_execute "rm -rf ${user_home_dir}/clusters/machine${i}/data/*"
  echo_execute "rm -rf ${user_home_dir}/clusters/machine${i}/log/*"
  #创建machine目录，代表各个分布式机器
  echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}"
  #创建各个machine目录下的子目录
  echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/bin"
  echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/etc"
  echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/data"
  echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/log"
  #拷贝可执行文件到各个machine的bin目录下
  echo_execute "cp ${ob_bin_source_dir}/bin/rootserver ${user_home_dir}/clusters/machine${i}/bin/"
  echo_execute "cp ${ob_bin_source_dir}/bin/updateserver ${user_home_dir}/clusters/machine${i}/bin/"
  echo_execute "cp ${ob_bin_source_dir}/bin/chunkserver ${user_home_dir}/clusters/machine${i}/bin/"
  echo_execute "cp ${ob_bin_source_dir}/bin/mergeserver ${user_home_dir}/clusters/machine${i}/bin/"
  echo_execute "cp ${ob_bin_source_dir}/bin/rs_admin ${user_home_dir}/clusters/machine${i}/bin/"
  echo_execute "cp ${ob_bin_source_dir}/bin/ups_admin ${user_home_dir}/clusters/machine${i}/bin/"
  #拷贝配置文件到各个machine的etc目录下
  echo_execute "cp -r ${ob_bin_source_dir}/etc/* ${user_home_dir}/clusters/machine${i}/etc/"
  #创建chunkserver需要的目录
  for j in {1..8}
  do
    echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/data/${j}"
    echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/data/${j}/obtest/sstable"
  done
  #创建rootserver需要的目录
  echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/data/rs"
  echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/data/rs_commitlog"
  echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/data/ups_commitpoint"
  echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/data/ups_wasmaster"
  #创建updateserver需要的目录
  echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/data/ups_commitlog"
  #创建updateserver需要的目录
  for j in {0..3}
  do
    echo_execute "mkdir -p ${user_home_dir}/clusters/machine${i}/data/ups_data/raid${j}"
  done
  #为updateserver创建软连接到1..8目录
  for j in {0..3}
  do
    diskno1=$((j*2+1))
    diskno2=$((j*2+2))
    echo_execute "ln -s ${user_home_dir}/clusters/machine${i}/data/${diskno1} ${user_home_dir}/clusters/machine${i}/data/ups_data/raid${j}/store0"
    echo_execute "ln -s ${user_home_dir}/clusters/machine${i}/data/${diskno2} ${user_home_dir}/clusters/machine${i}/data/ups_data/raid${j}/store1"
  done
done

#初始化各集群的ip地址,端口号, 网卡名称
for((i=1; i<=clusters_count; i++))
do
  ip[$i]="192.168.1.$i"
  eth[$i]="eth0:$i"
  start_port[$i]=$((i*6+10000))
done

#初始化主集群的ip, 端口信息
main_cluster_ip="${ip[1]}"
main_cluster_port="${start_port[1]}"
main_cluster_ip_port="${main_cluster_ip}:${main_cluster_port}"

#设置rs启动时的-s选项参数内容
for((i=1; i<=clusters_count; i++))
do
  if [ $i -eq 1 ]; then
    cluster_info="${ip[$i]}:${start_port[$i]}@$i"
  else
    cluster_info="${cluster_info}#${ip[$i]}:${start_port[$i]}@$i"
  fi
done

#依次启动各集群中的server
for((i=1; i<=clusters_count; i++))
do
  echo_execute "cd ${user_home_dir}/clusters/machine${i}"
  rs_ip_port="${ip[$i]}:${start_port[$i]}"
  echo_execute "bin/rootserver -r ${rs_ip_port} -R ${main_cluster_ip_port} -s ${cluster_info} -i ${eth[$i]} -C $i"
  echo_execute "bin/updateserver -r ${rs_ip_port} -p $((start_port[$i] + 1)) -m $((start_port[$i] + 2)) -i ${eth[$i]}"
  echo_execute "bin/mergeserver -r ${rs_ip_port} -p $((start_port[$i] + 3)) -z $((start_port[$i] + 4)) -i ${eth[$i]}"
  echo_execute "bin/chunkserver -r ${rs_ip_port} -p $((start_port[$i] + 5)) -n obtest -i ${eth[$i]}"
  echo_execute "sleep 3"
done

#手动设主
echo_execute "sleep 15"
echo_execute "cd ${user_home_dir}/clusters/machine1"
echo_execute "bin/rs_admin -r ${main_cluster_ip} -p ${main_cluster_port} set_obi_master_first"
echo_execute "sleep 15"

#手动bootstrap
echo_execute "bin/rs_admin -r ${main_cluster_ip} -p ${main_cluster_port} -t 600000000 boot_strap"
