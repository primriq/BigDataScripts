# 🧠 Big Data Development Environment Setup (PrimrIQ WSL Installer)

This guide explains how to install a **complete Big Data ecosystem** — Hadoop, Spark, Hive, Kafka, HBase, Airflow, NiFi, and Trino — on **Windows 10/11 via WSL2 (Ubuntu 22.04 or 24.04)** using a single automated installer:  
👉 **`bigdata-bootstrap.sh`**

---

## 🚀 Overview

This script automatically:
- Installs **Java 8 & 11**  
- Installs all required dependencies  
- Downloads & configures Hadoop, Spark, Hive, Kafka, HBase, Airflow, NiFi, Trino  
- Fixes directory permissions  
- Validates ports and environment  

No manual setup required — everything runs in one go.

---

## 🧩 System Requirements

| Requirement | Minimum |
|--------------|----------|
| OS | Windows 10 / 11 |
| WSL | Version 2 |
| Ubuntu | 22.04 or newer |
| RAM | 8 GB |
| Free Disk Space | 30 GB |

---

## ⚙️ Verify WSL Installation

Open **PowerShell (as Administrator)** and run:

```powershell
wsl --status
```

If WSL isn’t installed yet:

```powershell
wsl --install -d Ubuntu
```

---

## 🧱 Step-by-Step Installation Guide

### 🪄 Step 1 — Update Ubuntu packages

Inside your Ubuntu terminal (in WSL):

```bash
sudo apt update && sudo apt upgrade -y
```

This ensures all system libraries and packages are current.

---

### 🧰 Step 2 — Install essential tools

Run:
```bash
sudo apt install -y curl wget tar gzip unzip jq iproute2 util-linux ca-certificates
```

These are required for downloads, configuration, and networking utilities.

---

### 🔁 Step 3 — Restart WSL

After updating packages and tools, restart WSL:
```bash
wsl --shutdown
```

Then reopen Ubuntu from the Start Menu or by typing:
```powershell
wsl
```

---

### 👤 Step 4 — Verify sudo privileges

Check your user groups:
```bash
groups
```

You should see `sudo` in the list.

If not, run:
```bash
sudo usermod -aG sudo $USER
newgrp sudo
```

---

### 📦 Step 5 — Download the installer

Move to your home directory and download the script:
```bash
cd ~
wget https://raw.githubusercontent.com/primriq/BigDataScripts/refs/heads/main/bigdata-bootstrap.sh -O bigdata-bootstrap.sh
chmod +x bigdata-bootstrap.sh
```

---

### ▶️ Step 6 — Run the installer

Run the setup script with logging enabled:
```bash
./bigdata-bootstrap.sh 2>&1 | tee bigdata-bootstrap.log
```

The script will:
- Install OpenJDK 8 and 11  
- Configure Java 8 as the default  
- Install Python, pip, venv, and Airflow dependencies  
- Download, extract, and configure Hadoop, Spark, Hive, Sqoop, ZooKeeper, Kafka, HBase, Airflow, NiFi, and Trino  
- Create and fix permissions for directories like `~/dev`, `~/hadoopdata`, `~/airflow`, etc.  
- Cache tarballs for faster reinstallation  

⏱ Estimated time: 25–45 minutes (depending on internet speed)

---

## 🧠 Verify Installation

Once it completes:
```bash
source ~/.bashrc
```

Then check:
```bash
hadoop version
spark-shell --version
hive --version
```

---

## 🧰 Start Services

### 🗃 Hadoop (HDFS + YARN)
```bash
start-dfs.sh
start-yarn.sh
```
Check:
- NameNode UI → [http://localhost:9870](http://localhost:9870)
- YARN UI → [http://localhost:8088](http://localhost:8088)

### ⚙️ Spark
```bash
spark-shell
```
Job UI → [http://localhost:4040](http://localhost:4040)

### 🐝 Hive
```bash
hive -e 'show databases;'
```

### 🐘 HBase
```bash
start-hbase.sh
```
UI → [http://localhost:16010](http://localhost:16010)

### 🦒 ZooKeeper
```bash
$ZK_HOME/bin/zkServer.sh start
```

### 🦠 Kafka
```bash
$KAFKA_HOME/bin/kafka-server-start.sh -daemon $KAFKA_HOME/config/server.properties
```
Stop:
```bash
$KAFKA_HOME/bin/kafka-server-stop.sh
```

### ☁️ Airflow
```bash
source $AIRFLOW_HOME/.venv/bin/activate
airflow db init
airflow users create --username admin --firstname a --lastname b --role Admin --email a@b.c --password admin
airflow webserver -p 8080 &
airflow scheduler &
```
UI → [http://localhost:8080](http://localhost:8080)

### 🌊 NiFi
```bash
$NIFI_HOME/bin/nifi.sh start
```
UI → [http://localhost:8080](http://localhost:8080)

### ⚡ Trino
```bash
$TRINO_HOME/server/bin/launcher run &
trino --server localhost:8081 --execute "SHOW CATALOGS;"
```
UI → [http://localhost:8081](http://localhost:8081)

---

## 🧹 Cleanup and Reset

To completely remove all installed components:
```bash
sudo rm -rf ~/dev ~/hadoopdata ~/zookeeper ~/kafkadata ~/airflow ~/hbasedata ~/bigdata-cache
```

Re-run the installer:
```bash
./bigdata-bootstrap.sh
```

It will skip already-installed components and repair missing ones.

---

## 🧰 Troubleshooting

| Problem | Solution |
|----------|-----------|
| `Permission denied` errors | `sudo chown -R $USER:$USER ~/dev ~/hadoopdata ~/airflow` |
| Port already in use | `sudo lsof -i :<port>` and kill the process |
| Slow or failed downloads | Script automatically retries with `aria2` |
| Java mismatch | `sudo update-alternatives --config java` → select Java 8 |

---

## 🧠 Verified Components

| Component | Version | Default Port/UI |
|------------|----------|----------------|
| Hadoop | 3.3.6 | 9870 |
| Spark | 3.5.1 | 4040 |
| Hive | 3.1.3 | 10000 |
| Sqoop | 1.4.7 | CLI only |
| ZooKeeper | 3.8.4 | 2181 |
| Kafka | 3.6.1 | 9092 |
| HBase | 2.5.8 | 16010 |
| Airflow | 2.9.2 | 8080 |
| NiFi | 1.25.0 | 8080 |
| Trino | 442 | 8081 |

---

## 🧠 Developed By

**PrimrIQ**  
Empowering learners with hands-on experience in Big Data, ML, and Cloud technologies.
