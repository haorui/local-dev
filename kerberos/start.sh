#!/bin/bash

FQDN="test.com"
REALM="TEST.COM"
ADMIN="admin"
PASS="Admin12!"
KRB5_KTNAME=/etc/admin.keytab
KEYTAB_DIR=/keytabs

cat /etc/hosts
echo "hostname: ${FQDN}"

function init_user() {
    echo "begin init user"

    # 1. 初始化 KDC 数据库（仅第一次）
    if [ ! -f /var/lib/krb5kdc/principal ]; then
        echo -e "${PASS}\n${PASS}" | kdb5_util create -s
    fi

    # 2. 管理员账号（幂等）
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey ${ADMIN}/admin@${REALM}" || true

    # 3. 业务主体（幂等）
    #    - CLI 用户
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey cli@${REALM}" || true
    #    - Hive 服务（HS2 / Metastore）
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey hive/hadoop@${REALM}" || true
    #    - HDFS
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey nn/namenode-hive2@${REALM}" || true
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey dn/datanode-hive2@${REALM}" || true
    #    - YARN（预留）
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey rm/resourcemanager@${REALM}" || true
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey nm/datanode-hive2@${REALM}" || true
    #    - ZooKeeper（三节点集群）
    #      - Server 登录使用短主机名（与现有 JAAS 保持一致）
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey zookeeper/zoo1@${REALM}" || true
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey zookeeper/zoo2@${REALM}" || true
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey zookeeper/zoo3@${REALM}" || true
    #      - 额外为 HS2 视角准备 FQDN 形式 principal，供 GSSAPI 查找服务票据时使用
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey zookeeper/zookeeper-zoo1-1.dev_db_network@${REALM}" || true
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey zookeeper/zookeeper-zoo2-1.dev_db_network@${REALM}" || true
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey zookeeper/zookeeper-zoo3-1.dev_db_network@${REALM}" || true
    #      - 为 HS2 客户端连接添加 zoo1.test.com FQDN 主体（解决服务主体匹配问题）
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey zookeeper/zoo1.test.com@${REALM}" || true
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey zookeeper/zoo2.test.com@${REALM}" || true
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey zookeeper/zoo3.test.com@${REALM}" || true
    #    - HDFS Web UI（NameNode HTTP/SPNEGO）
    echo -e "${PASS}\n${PASS}" | kadmin.local -q "addprinc -randkey HTTP/namenode-hive2@${REALM}" || true

    # 4. 管理员 keytab（供 kadmin 等内部使用）
    kadmin.local -q "ktadd -norandkey -k ${KRB5_KTNAME} cli@${REALM}" || true
    kadmin.local -q "ktadd -norandkey -k ${KRB5_KTNAME} hive/hadoop@${REALM}" || true

    # 5. 导出各服务 keytab 到共享目录，供其他容器挂载
    #    Hive / CLI
    kadmin.local -q "xst -k ${KEYTAB_DIR}/hive.keytab -norandkey hive/hadoop@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/cli.keytab -norandkey cli@${REALM}" || true
    #    HDFS
    kadmin.local -q "xst -k ${KEYTAB_DIR}/nn-namenode-hive2.keytab -norandkey nn/namenode-hive2@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/dn-datanode-hive2.keytab -norandkey dn/datanode-hive2@${REALM}" || true
    #    YARN（预留）
    kadmin.local -q "xst -k ${KEYTAB_DIR}/rm-resourcemanager.keytab -norandkey rm/resourcemanager@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/nm-datanode-hive2.keytab -norandkey nm/datanode-hive2@${REALM}" || true
    #    ZooKeeper：同一个 keytab 中包含短名、容器 FQDN 和 test.com FQDN 三套 principal
    kadmin.local -q "xst -k ${KEYTAB_DIR}/zoo1.keytab -norandkey zookeeper/zoo1@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/zoo1.keytab -norandkey zookeeper/zookeeper-zoo1-1.dev_db_network@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/zoo1.keytab -norandkey zookeeper/zoo1.test.com@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/zoo2.keytab -norandkey zookeeper/zoo2@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/zoo2.keytab -norandkey zookeeper/zookeeper-zoo2-1.dev_db_network@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/zoo2.keytab -norandkey zookeeper/zoo2.test.com@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/zoo3.keytab -norandkey zookeeper/zoo3@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/zoo3.keytab -norandkey zookeeper/zookeeper-zoo3-1.dev_db_network@${REALM}" || true
    kadmin.local -q "xst -k ${KEYTAB_DIR}/zoo3.keytab -norandkey zookeeper/zoo3.test.com@${REALM}" || true
    #    HDFS Web UI（NameNode HTTP/SPNEGO）
    kadmin.local -q "xst -k ${KEYTAB_DIR}/http-namenode-hive2.keytab -norandkey HTTP/namenode-hive2@${REALM}" || true

    echo "Kerberos principals and keytabs initialized/refreshed."
}

function main() {
    init_user
    /usr/local/bin/supervisord -n -c /etc/supervisord.conf
}

main
