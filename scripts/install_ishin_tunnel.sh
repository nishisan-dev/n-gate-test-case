#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

NODE_NAME="${1:?missing node name}"
NODE_IP="${2:?missing node ip}"
CLUSTER_SEEDS_CSV="${3:?missing cluster seeds}"
PACKAGE_URL="https://github.com/nishisan-dev/ishin-gateway/releases/latest/download/ishin-gateway_latest_all.deb"
PACKAGE_PATH="/tmp/ishin-gateway_latest_all.deb"
CLUSTER_DATA_DIR="/var/log/ishin-gateway/ngrid-data"
DASHBOARD_DATA_DIR="/var/lib/ishin-gateway"
RUNTIME_TMP_DIR="/var/log/ishin-gateway/tmp"

apt-get install -y openjdk-25-jre-headless
curl -fL "${PACKAGE_URL}" -o "${PACKAGE_PATH}"
apt-get install -y "${PACKAGE_PATH}"


mkdir -p "${CLUSTER_DATA_DIR}" "${RUNTIME_TMP_DIR}" "${DASHBOARD_DATA_DIR}"
chown -R ishin-gateway:ishin-gateway /var/log/ishin-gateway "${DASHBOARD_DATA_DIR}"

SEEDS_YAML=""
IFS=',' read -ra CLUSTER_SEEDS <<<"${CLUSTER_SEEDS_CSV}"
for seed in "${CLUSTER_SEEDS[@]}"; do
  SEEDS_YAML="${SEEDS_YAML}"$'\n'"    - \"${seed}\""
done

mkdir -p /etc/systemd/system/ishin-gateway.service.d

cat <<EOF >/etc/systemd/system/ishin-gateway.service.d/override.conf
[Service]
Environment=ISHIN_CONFIG=/etc/ishin-gateway/adapter.yaml
Environment=ISHIN_CLUSTER_NODE_ID=${NODE_NAME}
Environment=TMPDIR=${RUNTIME_TMP_DIR}
ExecStart=
ExecStart=/usr/bin/java -Djava.io.tmpdir=${RUNTIME_TMP_DIR} -Dlog4j.configurationFile=/etc/ishin-gateway/log4j2.xml -jar /opt/ishin-gateway/ishin-gateway.jar
ReadWritePaths=/var/log/ishin-gateway
ReadWritePaths=/var/lib/ishin-gateway
EOF

cat <<EOF >/etc/ishin-gateway/adapter.yaml
---
mode: tunnel

tunnel:
  loadBalancing: "least-connections"
  missedKeepalives: 3
  drainTimeout: 30
  bindAddress: "0.0.0.0"
  autoPromoteStandby: true

cluster:
  enabled: true
  host: "${NODE_IP}"
  port: 7100
  clusterName: "ishin-cluster"
  seeds:${SEEDS_YAML}
  replicationFactor: 2
  dataDirectory: "${CLUSTER_DATA_DIR}"

admin:
  enabled: true
  apiKey: "nishisan"

dashboard:
  enabled: true
  port: 9200
  bindAddress: "0.0.0.0"
  allowedIps:
    - "127.0.0.1"
    - "::1"
    - "10.0.0.0/8"
    - "192.168.0.0/16"
  storage:
    path: "${DASHBOARD_DATA_DIR}"
    retentionHours: 24
    scrapeIntervalSeconds: 15
EOF

systemctl daemon-reload
systemctl enable ishin-gateway
systemctl restart ishin-gateway

sleep 2
systemctl --no-pager --full status ishin-gateway
