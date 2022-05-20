Initial Setup
```
apt-get update
```
Install [Docker](https://docs.docker.com/engine/install/ubuntu/)
```
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```
Install and run prom gateway
```
docker pull prom/pushgateway
docker run -d -p 9091:9091 --name push-gateway prom/pushgateway
```
Install and run prometheus
```
sudo useradd -rs /bin/false prometheus
sudo mkdir /etc/prometheus
cd /etc/prometheus/ && sudo touch prometheus.yml
sudo mkdir -p /data/prometheus
sudo chown prometheus:prometheus /data/prometheus /etc/prometheus/*
```
Get prometheus user id for next step
```
cat /etc/passwd | grep prometheus
```
Start prometheus
```
docker run -d -p 9090:9090 --user 998:997 \
  --name prom-main \
  --net=host \
  -v /etc/prometheus:/etc/prometheus \
  -v /data/prometheus:/data/prometheus \
  prom/prometheus \
  --config.file="/etc/prometheus/prometheus.yml" \
  --storage.tsdb.path="/data/prometheus" \
  --storage.tsdb.retention.size=5GB \
```
Install Nano Prom Exporter
```
apt install python3-pip
pip3 install nano-prom-exporter
```
Install Loki
```
curl -O -L "https://github.com/grafana/loki/releases/download/v2.4.2/loki-linux-amd64.zip"
unzip "loki-linux-amd64.zip"
chmod a+x "loki-linux-amd64"
mv loki-linux-amd64 /usr/local/bin/
rm loki-linux-amd64.zip
```
Install [Grafana](https://grafana.com/docs/grafana/latest/installation/debian/)

Install Promtail
```
curl -O -L "https://github.com/grafana/loki/releases/download/v2.4.2/promtail-linux-amd64.zip"
unzip promtail-linux-amd64.zip
chmod a+x promtail-linux-amd64
mv promtail-linux-amd64 /usr/local/bin/
```

# Troubleshooting

## Enable ipv6
Edit /etc/sysctl.conf
```
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.disable_ipv6 = 0
```
