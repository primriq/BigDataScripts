#!/usr/bin/env bash
set -euo pipefail

# ===============================
# Big Data Dev Stack for WSL2 (Ubuntu 22.04)
# Guarded, idempotent, with progress & robust downloads
# ===============================

# ---- Feature toggles ----
FEATURE_HADOOP=true
FEATURE_SPARK=true
FEATURE_HIVE=true
FEATURE_SQOOP=true
FEATURE_ZOOKEEPER=true
FEATURE_KAFKA=true
FEATURE_HBASE=true
FEATURE_AIRFLOW=true
FEATURE_NIFI=true
FEATURE_TRINO=true
FEATURE_OOZIE=false   # legacy; off

# ---- Version pins ----
HADOOP_VER="3.3.6"
SPARK_VER="3.5.1"
SPARK_BUILD="hadoop3"
HIVE_VER="3.1.3"
SQOOP_VER="1.4.7"
ZK_VER="3.8.4"
KAFKA_VER="3.6.1"
KAFKA_SCALA="2.13"
HBASE_VER="2.5.8"
NIFI_VER="1.25.0"
TRINO_VER="442"

# ---- Paths (Linux $HOME only) ----
DEV_DIR="${HOME}/dev"
HADOOP_HOME="${DEV_DIR}/hadoop"
SPARK_HOME="${DEV_DIR}/spark"
HIVE_HOME="${DEV_DIR}/hive"
SQOOP_HOME="${DEV_DIR}/sqoop"
ZK_HOME="${DEV_DIR}/zookeeper"
KAFKA_HOME="${DEV_DIR}/kafka"
HBASE_HOME="${DEV_DIR}/hbase"
NIFI_HOME="${DEV_DIR}/nifi"
TRINO_HOME="${DEV_DIR}/trino"

HDFS_NAME="${HOME}/hadoopdata/namenode"
HDFS_DATA="${HOME}/hadoopdata/datanode"
ZK_DATA="${HOME}/zookeeper/data"
KAFKA_DATA="${HOME}/kafkadata"
AIRFLOW_HOME="${HOME}/airflow"
AIRFLOW_ENV="${AIRFLOW_HOME}/.venv"

# ---- UI helpers ----
RED="$(printf '\033[31m')"; GREEN="$(printf '\033[32m')"; YELLOW="$(printf '\033[33m')"; BLUE="$(printf '\033[34m')"; NC="$(printf '\033[0m')"
msg(){ printf "%b\n" "${BLUE}==>${NC} $*"; }
ok(){ printf "%b\n" "${GREEN}✔${NC} $*"; }
warn(){ printf "%b\n" "${YELLOW}⚠${NC} $*"; }
die(){ printf "%b\n" "${RED}✖ $*${NC}"; exit 1; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "Missing command '$1'. Install via apt and re-run."; }
ensure_dir(){ mkdir -p "$@"; }
append_if_missing(){ local line="$1" file="$2"; grep -Fqx "$line" "$file" 2>/dev/null || echo "$line" >> "$file"; }
check_port_free(){ local p="$1"; if ss -ltn "( sport = :$p )" | tail -n +2 | grep -q .; then die "Port $p is in use. Free it and re-run."; fi; }

trap 'echo -e "\n${RED}Installer aborted. Check bigdata-bootstrap.log for last lines.${NC}"' ERR

# ---- Progress (overall + per-feature) ----
TOTAL_STEPS=0
$FEATURE_HADOOP     && TOTAL_STEPS=$((TOTAL_STEPS+1))
$FEATURE_SPARK      && TOTAL_STEPS=$((TOTAL_STEPS+1))
$FEATURE_HIVE       && TOTAL_STEPS=$((TOTAL_STEPS+1))
$FEATURE_SQOOP      && TOTAL_STEPS=$((TOTAL_STEPS+1))
$FEATURE_ZOOKEEPER  && TOTAL_STEPS=$((TOTAL_STEPS+1))
$FEATURE_KAFKA      && TOTAL_STEPS=$((TOTAL_STEPS+1))
$FEATURE_HBASE      && TOTAL_STEPS=$((TOTAL_STEPS+1))
$FEATURE_AIRFLOW    && TOTAL_STEPS=$((TOTAL_STEPS+1))
$FEATURE_NIFI       && TOTAL_STEPS=$((TOTAL_STEPS+1))
$FEATURE_TRINO      && TOTAL_STEPS=$((TOTAL_STEPS+1))
CURRENT_STEP=0
_feat_name=""; _feat_total=1; _feat_done=0
progress_line(){ local o=$(( CURRENT_STEP*100/(TOTAL_STEPS>0?TOTAL_STEPS:1) )); local f=$(( _feat_done*100/(_feat_total>0?_feat_total:1) )); printf "[ overall %3d%% ] [ %-10s %3d%% ] %s\n" "$o" "$_feat_name" "$f" "$1"; }
feature_begin(){ _feat_name="$1"; _feat_total="${2:-1}"; _feat_done=0; progress_line "starting…"; }
feature_tick(){ _feat_done=$((_feat_done+1)); progress_line "progress…"; }
feature_end(){ _feat_done="$_feat_total"; progress_line "done"; CURRENT_STEP=$((CURRENT_STEP+1)); }

# ---- Mirrors & downloads ----
# in bigdata-bootstrap.sh, replace apache_urls() with:
apache_urls(){  # $1=project path after /dist/, $2=filename
  local p="$1" f="$2"
  echo "https://archive.apache.org/dist/${p}/${f} \
https://mirrors.ocf.berkeley.edu/apache/${p}/${f} \
https://dlcdn.apache.org/${p}/${f} \
https://ftp.jaist.ac.jp/pub/apache/${p}/${f} \
https://mirrors.piconets.webwerks.in/apachemirror/${p}/${f}"
}

fetch_tarball(){  # $1=space-separated URLs, $2=outfile
  local urls="$1" out="$2" ok=""
  rm -f "$out.part" 2>/dev/null || true
  for u in $urls; do
    echo "→ trying $u"
    if wget --inet4-only --progress=dot:giga -t 2 --timeout=20 "$u" -O "$out.part" 2>&1; then
      if tar -tf "$out.part" >/dev/null 2>&1; then mv -f "$out.part" "$out"; ok="yes"; break
      else echo "Archive invalid from this mirror, next…"; fi
    else echo "Download failed from this mirror, next…"; fi
  done
  [ -n "$ok" ] || { rm -f "$out.part"; die "Download failed: $out (all mirrors)"; }
}
fetch_apache_tar_into(){  # $1=project path after /dist/, $2=filename, $3=target_dir, $4=expected_unpacked (optional)
  local proj="$1" file="$2" name="$3" expect
  if [ -n "${4-}" ]; then expect="$4"; else expect="${file%.tar.*}"; fi
  feature_tick; fetch_tarball "$(apache_urls "$proj" "$file")" "$file"
  feature_tick; tar -xf "$file"
  feature_tick; mv -f "$expect" "$name" 2>/dev/null || true
}
fetch_file(){  # Maven Central etc.
  local url="$1" out="$2"
  feature_tick; wget --inet4-only --progress=dot:giga -t 3 --timeout=25 "$url" -O "$out" 2>&1 || die "Download failed: $url"
}

# ---- Preflight ----
preflight(){
  msg "Preflight: verifying environment"
  if [ -f /proc/sys/kernel/osrelease ] && grep -qi microsoft /proc/sys/kernel/osrelease; then ok "Running in WSL"; else die "This script targets WSL2."; fi
  need_cmd lsb_release; need_cmd uname
  [ "$(uname -m)" = "x86_64" ] || die "Need x86_64."
  ok "Ubuntu $(lsb_release -rs) ($(lsb_release -cs)) on x86_64"

  case "$PWD" in /mnt/*) die "You’re in $PWD (Windows FS). Run: cd ~";; esac
  ok "Linux home: $HOME"

  sudo apt-get update -y
  sudo apt-get install -y curl wget tar gzip unzip jq iproute2 util-linux ca-certificates \
                           python3 python3-venv python3-pip openssh-server \
                           openjdk-8-jdk openjdk-11-jdk
  need_cmd wget
  if ! java -version 2>&1 | grep -q '1\.8\.0'; then
    warn "Switching default java to OpenJDK 8…"
    sudo update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java || true
  fi
  java -version 2>&1 | grep -q '1\.8\.0' || die "Java 8 is not default."
  append_if_missing 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64' "$HOME/.bashrc"
  append_if_missing 'export PATH=$JAVA_HOME/bin:$PATH' "$HOME/.bashrc"
  ok "Java 8 is default"

  ensure_dir "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"

  local mem_gb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}')/1024/1024 ))
  local disk_gb=$(df -Pk "$HOME" | awk 'NR==2{print int($4/1024/1024)}')
  [ "$mem_gb" -ge 8 ] || warn "Detected RAM ~${mem_gb}GB (<8GB). Some services may be unstable."
  [ "$disk_gb" -ge 30 ] || warn "Only ~${disk_gb}GB free."

  msg "Checking ports…"
  for p in 9870 9864 8042 8088 8032 9000 8020 7077 4040 2181 9092 16010 16000 16020 8080 8081 10000 9083; do check_port_free "$p"; done
  ok "Ports look free"

  ensure_dir "$DEV_DIR" "$HDFS_NAME" "$HDFS_DATA" "$ZK_DATA" "$KAFKA_DATA" "$AIRFLOW_HOME" "$HOME/hbasedata"
  ok "Directories prepared"
}

# ---- Installers ----
install_hadoop(){
  feature_begin "Hadoop" 6
  cd "$DEV_DIR"
  if [ ! -d "$HADOOP_HOME" ]; then
    fetch_apache_tar_into "hadoop/common/hadoop-${HADOOP_VER}" "hadoop-${HADOOP_VER}.tar.gz" "hadoop"
  else _feat_done=$((_feat_done+3)); fi
  feature_tick
  append_if_missing "export HADOOP_HOME=$HADOOP_HOME" "$HOME/.bashrc"
  append_if_missing 'export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin' "$HOME/.bashrc"
  cat > "$HADOOP_HOME/etc/hadoop/core-site.xml" <<EOF
<configuration><property><name>fs.defaultFS</name><value>hdfs://localhost:9000</value></property></configuration>
EOF
  cat > "$HADOOP_HOME/etc/hadoop/hdfs-site.xml" <<EOF
<configuration>
  <property><name>dfs.replication</name><value>1</value></property>
  <property><name>dfs.namenode.name.dir</name><value>file:///${HDFS_NAME}</value></property>
  <property><name>dfs.datanode.data.dir</name><value>file:///${HDFS_DATA}</value></property>
</configuration>
EOF
  cat > "$HADOOP_HOME/etc/hadoop/mapred-site.xml" <<'EOF'
<configuration><property><name>mapreduce.framework.name</name><value>yarn</value></property></configuration>
EOF
  cat > "$HADOOP_HOME/etc/hadoop/yarn-site.xml" <<'EOF'
<configuration>
  <property><name>yarn.nodemanager.aux-services</name><value>mapreduce_shuffle</value></property>
  <property><name>yarn.resourcemanager.address</name><value>localhost:8032</value></property>
</configuration>
EOF
  sed -i '/^export JAVA_HOME/d' "$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
  echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64' >> "$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
  feature_tick
  if [ ! -f "${HOME}/.ssh/id_rsa" ]; then
    ssh-keygen -t rsa -P "" -f "${HOME}/.ssh/id_rsa"
    cat "${HOME}/.ssh/id_rsa.pub" >> "${HOME}/.ssh/authorized_keys"; chmod 600 "${HOME}/.ssh/authorized_keys"
  fi
  feature_tick
  [ -f "${HDFS_NAME}/current/VERSION" ] || "$HADOOP_HOME/bin/hdfs" namenode -format -force
  feature_end
}

install_spark(){
  feature_begin "Spark" 5
  cd "$DEV_DIR"
  [ -e "$SPARK_HOME" ] && [ ! -d "$SPARK_HOME" ] && rm -f "$SPARK_HOME"
  if [ ! -d "$SPARK_HOME" ]; then
    fetch_apache_tar_into "spark/spark-${SPARK_VER}" "spark-${SPARK_VER}-bin-${SPARK_BUILD}.tgz" "spark" "spark-${SPARK_VER}-bin-${SPARK_BUILD}"
  else _feat_done=$((_feat_done+3)); fi
  feature_tick
  append_if_missing "export SPARK_HOME=$SPARK_HOME" "$HOME/.bashrc"
  append_if_missing 'export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin' "$HOME/.bashrc"
  feature_tick
  mkdir -p "$SPARK_HOME/conf"
  cat > "$SPARK_HOME/conf/spark-env.sh" <<EOF
HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
EOF
  chmod +x "$SPARK_HOME/conf/spark-env.sh"
  feature_end
}

install_hive(){
  feature_begin "Hive" 5
  cd "$DEV_DIR"
  if [ ! -d "$HIVE_HOME" ]; then
    fetch_apache_tar_into "hive/hive-${HIVE_VER}" "apache-hive-${HIVE_VER}-bin.tar.gz" "hive"
  else _feat_done=$((_feat_done+3)); fi
  feature_tick
  append_if_missing "export HIVE_HOME=$HIVE_HOME" "$HOME/.bashrc"
  append_if_missing 'export PATH=$PATH:$HIVE_HOME/bin' "$HOME/.bashrc"
  mkdir -p "$HIVE_HOME/conf"
  cat > "$HIVE_HOME/conf/hive-env.sh" <<EOF
export HADOOP_HOME=${HADOOP_HOME}
export HIVE_CONF_DIR=${HIVE_HOME}/conf
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
EOF
  feature_tick
  if ! "$HIVE_HOME/bin/schematool" -dbType derby -info >/dev/null 2>&1; then "$HIVE_HOME/bin/schematool" -dbType derby -initSchema; fi
  feature_end
}

install_sqoop(){
  feature_begin "Sqoop" 4
  cd "$DEV_DIR"
  if [ ! -d "$SQOOP_HOME" ]; then
    fetch_apache_tar_into "sqoop/${SQOOP_VER}" "sqoop-${SQOOP_VER}.bin__hadoop-2.6.0.tar.gz" "sqoop"
  else _feat_done=$((_feat_done+3)); fi
  feature_tick
  append_if_missing "export SQOOP_HOME=$SQOOP_HOME" "$HOME/.bashrc"
  append_if_missing 'export PATH=$PATH:$SQOOP_HOME/bin' "$HOME/.bashrc"
  rm -f "$SQOOP_HOME/lib/hadoop-"*.jar || true
  feature_end
}

install_zookeeper(){
  feature_begin "ZooKeeper" 4
  cd "$DEV_DIR"
  if [ ! -d "$ZK_HOME" ]; then
    fetch_apache_tar_into "zookeeper/zookeeper-${ZK_VER}" "apache-zookeeper-${ZK_VER}-bin.tar.gz" "zookeeper"
  else _feat_done=$((_feat_done+3)); fi
  feature_tick
  append_if_missing "export ZK_HOME=$ZK_HOME" "$HOME/.bashrc"
  ensure_dir "$ZK_DATA"
  cat > "$ZK_HOME/conf/zoo.cfg" <<EOF
tickTime=2000
dataDir=${ZK_DATA}
clientPort=2181
initLimit=5
syncLimit=2
EOF
  feature_end
}

install_kafka(){
  feature_begin "Kafka" 4
  cd "$DEV_DIR"
  if [ ! -d "$KAFKA_HOME" ]; then
    fetch_apache_tar_into "kafka/${KAFKA_VER}" "kafka_${KAFKA_SCALA}-${KAFKA_VER}.tgz" "kafka"
  else _feat_done=$((_feat_done+3)); fi
  feature_tick
  append_if_missing "export KAFKA_HOME=$KAFKA_HOME" "$HOME/.bashrc"
  append_if_missing 'export PATH=$PATH:$KAFKA_HOME/bin' "$HOME/.bashrc"
  ensure_dir "$KAFKA_DATA"
  sed -i "s|^log.dirs=.*|log.dirs=${KAFKA_DATA}|" "$KAFKA_HOME/config/server.properties" || \
    append_if_missing "log.dirs=${KAFKA_DATA}" "$KAFKA_HOME/config/server.properties"
  feature_end
}

install_hbase(){
  feature_begin "HBase" 4
  cd "$DEV_DIR"
  if [ ! -d "$HBASE_HOME" ]; then
    fetch_apache_tar_into "hbase/${HBASE_VER}" "hbase-${HBASE_VER}-bin.tar.gz" "hbase"
  else _feat_done=$((_feat_done+3)); fi
  feature_tick
  append_if_missing "export HBASE_HOME=$HBASE_HOME" "$HOME/.bashrc"
  append_if_missing 'export PATH=$PATH:$HBASE_HOME/bin' "$HOME/.bashrc"
  cat > "$HBASE_HOME/conf/hbase-site.xml" <<EOF
<configuration>
  <property><name>hbase.rootdir</name><value>file://${HOME}/hbasedata</value></property>
  <property><name>hbase.zookeeper.property.dataDir</name><value>${ZK_DATA}</value></property>
</configuration>
EOF
  feature_end
}

install_airflow(){
  feature_begin "Airflow" 5
  ensure_dir "$AIRFLOW_HOME"; cd "$AIRFLOW_HOME"
  feature_tick; [ -d "$AIRFLOW_ENV" ] || python3 -m venv "$AIRFLOW_ENV"
  feature_tick; source "$AIRFLOW_ENV/bin/activate"; pip install --upgrade pip wheel setuptools
  feature_tick; pip install "apache-airflow[celery,postgres,redis,cncf.kubernetes]==2.9.2" --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-2.9.2/constraints-3.10.txt"; deactivate || true
  feature_tick; append_if_missing "export AIRFLOW_HOME=${AIRFLOW_HOME}" "$HOME/.bashrc"
  feature_end
}

install_nifi(){
  feature_begin "NiFi" 4
  cd "$DEV_DIR"
  if [ ! -d "$NIFI_HOME" ]; then
    fetch_apache_tar_into "nifi/${NIFI_VER}" "nifi-${NIFI_VER}-bin.tar.gz" "nifi"
  else _feat_done=$((_feat_done+3)); fi
  feature_tick; append_if_missing "export NIFI_HOME=$NIFI_HOME" "$HOME/.bashrc"
  feature_end
}

install_trino(){
  feature_begin "Trino" 6
  cd "$DEV_DIR"
  feature_tick; [ -d "$TRINO_HOME" ] || mkdir -p "$TRINO_HOME"
  feature_tick
  if [ ! -d "$TRINO_HOME/server" ]; then
    fetch_file "https://repo1.maven.org/maven2/io/trino/trino-server/${TRINO_VER}/trino-server-${TRINO_VER}.tar.gz" "trino-server.tgz"
    tar -xf trino-server.tgz; mv "trino-server-${TRINO_VER}" "$TRINO_HOME/server"
  fi
  feature_tick
  if [ ! -f "$TRINO_HOME/trino" ]; then
    fetch_file "https://repo1.maven.org/maven2/io/trino/trino-cli/${TRINO_VER}/trino-cli-${TRINO_VER}-executable.jar" "${TRINO_HOME}/trino"
    chmod +x "${TRINO_HOME}/trino"
  fi
  feature_tick
  mkdir -p "${TRINO_HOME}/etc/catalog"
  cat > "${TRINO_HOME}/etc/config.properties" <<EOF
coordinator=true
node-scheduler.include-coordinator=true
http-server.http.port=8081
discovery-server.enabled=true
discovery.uri=http://localhost:8081
EOF
  echo "node.environment=dev" > "${TRINO_HOME}/etc/node.properties"
  echo "node.id=$(uuidgen 2>/dev/null || echo trino-dev-node)" >> "${TRINO_HOME}/etc/node.properties"
  echo "node.data-dir=${TRINO_HOME}/data" >> "${TRINO_HOME}/etc/node.properties"
  cat > "${TRINO_HOME}/etc/catalog/hive.properties" <<EOF
connector.name=hive
hive.metastore=file
hive.metastore.catalog.dir=file://${HOME}/hive-metastore
hive.config.resources=${HADOOP_HOME}/etc/hadoop/core-site.xml,${HADOOP_HOME}/etc/hadoop/hdfs-site.xml
EOF
  feature_tick; append_if_missing "export TRINO_HOME=$TRINO_HOME" "$HOME/.bashrc"; append_if_missing 'export PATH=$PATH:$TRINO_HOME' "$HOME/.bashrc"
  feature_end
}

print_how_to_start(){
cat <<'EOS'

======================== QUICK START ========================
HDFS + YARN:
  start-dfs.sh && start-yarn.sh
  stop-yarn.sh && stop-dfs.sh
  UIs: NameNode http://localhost:9870 , YARN http://localhost:8088

ZooKeeper:
  $ZK_HOME/bin/zkServer.sh start   # stop | status  (port 2181)

Kafka (ZooKeeper must be up):
  $KAFKA_HOME/bin/kafka-server-start.sh -daemon $KAFKA_HOME/config/server.properties
  $KAFKA_HOME/bin/kafka-server-stop.sh   (port 9092)

Spark:
  spark-shell     (Job UI: http://localhost:4040)

Hive (embedded Derby):
  hive -e 'show databases;'

HBase (standalone):
  $HBASE_HOME/bin/start-hbase.sh   # stop-hbase.sh  (UI: http://localhost:16010)

Airflow:
  source $AIRFLOW_HOME/.venv/bin/activate
  airflow db init
  airflow users create --username admin --firstname a --lastname b --role Admin --email a@b.c --password admin
  airflow webserver -p 8080 & ; airflow scheduler &

NiFi:
  $NIFI_HOME/bin/nifi.sh start      (UI: http://localhost:8080)

Trino:
  $TRINO_HOME/server/bin/launcher run &
  trino --server localhost:8081 --execute "SHOW CATALOGS;"
============================================================
EOS
}

main(){
  msg "==> Preflight: verifying environment"
  preflight
  msg "Installing components under $DEV_DIR"

  $FEATURE_HADOOP    && install_hadoop
  $FEATURE_SPARK     && install_spark
  $FEATURE_HIVE      && install_hive
  $FEATURE_SQOOP     && install_sqoop
  $FEATURE_ZOOKEEPER && install_zookeeper
  $FEATURE_KAFKA     && install_kafka
  $FEATURE_HBASE     && install_hbase
  $FEATURE_AIRFLOW   && install_airflow
  $FEATURE_NIFI      && install_nifi
  $FEATURE_TRINO     && install_trino

  printf "\n[ overall %3d%% ] all enabled components installed.\n" $(( CURRENT_STEP*100 / (TOTAL_STEPS>0?TOTAL_STEPS:1) ))
  $FEATURE_OOZIE || warn "Oozie skipped (legacy; needs Hadoop 2 + Tomcat)."
  print_how_to_start
  ok "Done."
}

main "$@"
