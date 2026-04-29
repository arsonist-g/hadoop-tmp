FROM bde2020/hadoop-base:2.0.0-hadoop3.1.3-java8

ENV HBASE_VERSION=2.2.2
ENV HBASE_HOME=/opt/hbase
ENV PATH=$HBASE_HOME/bin:$PATH

WORKDIR /opt

RUN apt-get update && apt-get install -y \
    wget \
    vim \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://archive.apache.org/dist/hbase/${HBASE_VERSION}/hbase-${HBASE_VERSION}-bin.tar.gz && \
    tar -xzf hbase-${HBASE_VERSION}-bin.tar.gz && \
    mv hbase-${HBASE_VERSION} hbase && \
    rm hbase-${HBASE_VERSION}-bin.tar.gz

RUN echo "export HBASE_MANAGES_ZK=true" >> ${HBASE_HOME}/conf/hbase-env.sh

RUN cat > ${HBASE_HOME}/conf/hbase-site.xml << 'EOF'
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>hbase.rootdir</name>
        <value>hdfs://namenode:9000/hbase</value>
    </property>
    <property>
        <name>hbase.cluster.distributed</name>
        <value>true</value>
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

CMD ["/bin/bash"]
