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

# 安装必要软件包（包括 SSH）
RUN sed -i 's/deb.debian.org/archive.debian.org/g' /etc/apt/sources.list && \
    sed -i 's|security.debian.org|archive.debian.org|g' /etc/apt/sources.list && \
    sed -i '/stretch-updates/d' /etc/apt/sources.list && \
    apt-get update && apt-get install -y \
    wget \
    vim \
    openssh-server \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://archive.apache.org/dist/hbase/${HBASE_VERSION}/hbase-${HBASE_VERSION}-bin.tar.gz && \
    tar -xzf hbase-${HBASE_VERSION}-bin.tar.gz && \
    mv hbase-${HBASE_VERSION} hbase && \
    rm hbase-${HBASE_VERSION}-bin.tar.gz

# 配置 Hadoop 环境
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

RUN cat > ${HBASE_HOME}/conf/hbase-site.xml << 'EOF'
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>hbase.rootdir</name>
        <value>hdfs://localhost:9000/hbase</value>
    </property>
    <property>
        <name>hbase.cluster.distributed</name>
        <value>true</value>
    </property>
    <property>
        <name>hbase.zookeeper.quorum</name>
        <value>localhost</value>
    </property>
    <property>
        <name>hbase.zookeeper.property.dataDir</name>
        <value>/opt/hbase/zookeeper</value>
    </property>
    <property>
        <name>hbase.unsafe.stream.capability.enforce</name>
        <value>false</value>
    </property>
</configuration>
EOF

WORKDIR /root

# 创建启动脚本
RUN cat > /root/start-hadoop.sh << 'EOF'
#!/bin/bash

# 启动 SSH 服务
service ssh start

# 添加 localhost 到 known_hosts
ssh-keyscan -H localhost >> /root/.ssh/known_hosts 2>/dev/null
ssh-keyscan -H 0.0.0.0 >> /root/.ssh/known_hosts 2>/dev/null
ssh-keyscan -H hadoop-master >> /root/.ssh/known_hosts 2>/dev/null

# 检查 HDFS 是否已格式化
if [ ! -d "/tmp/hadoop-root/dfs/name/current" ]; then
    echo "Formatting HDFS NameNode..."
    $HADOOP_HOME/bin/hdfs namenode -format -force
fi

# 启动 Hadoop 服务
echo "Starting Hadoop services..."
$HADOOP_HOME/sbin/start-all.sh

# 等待 HDFS 完全启动
echo "Waiting for HDFS to be ready..."
sleep 10

# 启动 HBase
echo "Starting HBase..."
$HBASE_HOME/bin/start-hbase.sh

# 保持容器运行
tail -f /dev/null
EOF

RUN chmod +x /root/start-hadoop.sh

CMD ["/bin/bash"]
