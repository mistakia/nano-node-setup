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
Install [Loki](https://github.com/grafana/loki/releases/)
```
curl -O -L "https://github.com/grafana/loki/releases/download/v2.5.0/loki-linux-amd64.zip"
unzip "loki-linux-amd64.zip"
chmod a+x "loki-linux-amd64"
mv loki-linux-amd64 /usr/local/bin/
rm loki-linux-amd64.zip
```
Install [Grafana](https://grafana.com/docs/grafana/latest/installation/debian/)

Install [Promtail](https://github.com/grafana/loki/releases/)
```
curl -O -L "https://github.com/grafana/loki/releases/download/v2.5.0/promtail-linux-amd64.zip"
unzip promtail-linux-amd64.zip
chmod a+x promtail-linux-amd64
mv promtail-linux-amd64 /usr/local/bin/
rm promtail-linux-amd64.zip
```
Download system services
```
cd /etc/systemd/system
sudo wget https://raw.githubusercontent.com/mistakia/nano-node-setup/main/services/loki.service
sudo wget https://raw.githubusercontent.com/mistakia/nano-node-setup/main/services/promtail.service
sudo wget https://raw.githubusercontent.com/mistakia/nano-node-setup/main/services/nano-prom.service
sudo wget https://raw.githubusercontent.com/mistakia/nano-node-setup/main/services/nano-export.service
```
Start Services
```
sudo systemctl daemon-reload
sudo systemctl start loki.service
sudo systemctl start promtail.service
sudo systemctl start nano-prom.service
sudo systemctl start nano-export.service
```

# Troubleshooting

## Enable ipv6
Edit /etc/sysctl.conf
```
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.disable_ipv6 = 0
```
