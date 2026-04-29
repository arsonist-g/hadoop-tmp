FROM bde2020/hadoop-base:2.0.0-hadoop3.1.3-java8

# 环境变量配置
ENV HBASE_VERSION=2.2.2
ENV HBASE_HOME=/opt/hbase
ENV HADOOP_HOME=/opt/hadoop-3.1.3
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
ENV PATH=$HBASE_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH

# HDFS 和 YARN 用户配置
ENV HDFS_NAMENODE_USER=root
ENV HDFS_DATANODE_USER=root
ENV HDFS_SECONDARYNAMENODE_USER=root
ENV YARN_RESOURCEMANAGER_USER=root
ENV YARN_NODEMANAGER_USER=root

WORKDIR /opt

# 安装必要软件包
RUN sed -i 's/deb.debian.org/archive.debian.org/g' /etc/apt/sources.list && \
    sed -i 's|security.debian.org|archive.debian.org|g' /etc/apt/sources.list && \
    sed -i '/stretch-updates/d' /etc/apt/sources.list && \
    apt-get update && apt-get install -y \
    wget \
    vim \
    openssh-server \
    openssh-client \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# 下载并安装 HBase
RUN wget https://archive.apache.org/dist/hbase/${HBASE_VERSION}/hbase-${HBASE_VERSION}-bin.tar.gz && \
    tar -xzf hbase-${HBASE_VERSION}-bin.tar.gz && \
    mv hbase-${HBASE_VERSION} hbase && \
    rm hbase-${HBASE_VERSION}-bin.tar.gz

# 配置 Hadoop 环境（JAVA_HOME）
RUN sed -i 's|# export JAVA_HOME=|export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64|g' ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh

# 配置 SSH 免密登录
RUN ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa && \
    cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh

# 配置 SSH 服务
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#StrictModes yes/StrictModes no/' /etc/ssh/sshd_config

# 配置 HBase 环境变量
RUN echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> ${HBASE_HOME}/conf/hbase-env.sh && \
    echo "export HBASE_MANAGES_ZK=true" >> ${HBASE_HOME}/conf/hbase-env.sh && \
    echo "export HBASE_DISABLE_HADOOP_CLASSPATH_LOOKUP=true" >> ${HBASE_HOME}/conf/hbase-env.sh

# ==================== 关键修改：HBase 配置 ====================
RUN cat > ${HBASE_HOME}/conf/hbase-site.xml << 'EOF'
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <!-- HBase 存储在 HDFS 的路径（关键！使用 8020 端口 + 容器 hostname） -->
    <property>
        <name>hbase.rootdir</name>
        <value>hdfs://hadoop-master:8020/hbase</value>
    </property>

    <property>
        <name>hbase.cluster.distributed</name>
        <value>true</value>
    </property>

    <!-- ZooKeeper 配置 -->
    <property>
        <name>hbase.zookeeper.quorum</name>
        <value>hadoop-master</value>
    </property>
    <property>
        <name>hbase.zookeeper.property.dataDir</name>
        <value>/opt/hbase/zookeeper</value>
    </property>

    <!-- Master 和 RegionServer 显式绑定 hostname（Docker 环境下强烈推荐） -->
    <property>
        <name>hbase.master.hostname</name>
        <value>hadoop-master</value>
    </property>
    <property>
        <name>hbase.regionserver.hostname</name>
        <value>hadoop-master</value>
    </property>

    <!-- 兼容性设置 -->
    <property>
        <name>hbase.unsafe.stream.capability.enforce</name>
        <value>false</value>
    </property>
</configuration>
EOF

# 可选：同时修正 Hadoop 的 core-site.xml（确保一致性）
RUN cat > ${HADOOP_HOME}/etc/hadoop/core-site.xml << 'EOF'
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://hadoop-master:8020</value>
    </property>
</configuration>
EOF

WORKDIR /root

# 创建启动脚本（推荐写法）
RUN cat > /root/start-hadoop.sh << 'EOF'
#!/bin/bash

# 启动 SSH 服务
service ssh start

# 添加 known_hosts
ssh-keyscan -H localhost hadoop-master 0.0.0.0 172.19.0.2 >> /root/.ssh/known_hosts 2>/dev/null

echo "=== Starting Hadoop ==="
start-dfs.sh
start-yarn.sh

echo "Waiting for NameNode to be ready..."
sleep 8

echo "=== Checking HDFS ==="
hdfs dfsadmin -safemode get
hdfs dfs -ls / || true

echo "=== Starting HBase ==="
start-hbase.sh

echo "=== All services started ==="
jps

# 保持容器运行并实时查看日志（教学方便）
tail -f /opt/hbase/logs/hbase-root-master-*.log /opt/hadoop/logs/hadoop-root-namenode-*.log
EOF

RUN chmod +x /root/start-hadoop.sh

# 推荐使用这个启动脚本
CMD ["/root/start-hadoop.sh"]