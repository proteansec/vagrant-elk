#!/bin/bash

dir="/opt"
elasticsearchurl="https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.6.0.tar.gz"
kibanaurl="https://download.elastic.co/kibana/kibana/kibana-4.1.1-linux-x64.tar.gz"
logstashurl="https://download.elastic.co/logstash/logstash/logstash-1.5.2.tar.gz"

# Install Java: todo must manually say 'OK' to apply to Oracle rules
ppa="webupd8team/java"
if ! grep -h "^deb.*$ppa" /etc/apt/sources.list.d/* > /dev/null 2>&1; then
  echo "Installing Java."
  sudo add-apt-repository -y ppa:webupd8team/java
  sudo apt-get update
  # Automatically accept Oracle license.
  echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
  echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
  sudo apt-get -y install oracle-java8-installer
fi


# Install ElasticSearch
if [ ! -d "/opt/elasticsearch/" ]; then
  echo "Installing ElasticSearch."
  cd "$dir"
  sudo wget --quiet --directory-prefix . ${elasticsearchurl}
  sudo mkdir -p "elasticsearch"
  sudo tar xzf elasticsearch-*.tar.gz -C "elasticsearch" --strip-components=1
  sudo rm /opt/elasticsearch-*.tar.gz
  echo "network.host: localhost" >> elasticsearch/config/elasticsearch.yml
fi

# Install Kibana
if [ ! -d "/opt/kibana/" ]; then
  echo "Installing Kibana"
  cd "$dir"
  sudo wget --quiet --directory-prefix . ${kibanaurl}
  sudo mkdir -p "kibana"
  sudo tar xzf kibana-*.tar.gz -C "kibana" --strip-components=1
  sudo rm /opt/kibana-*.tar.gz
  sudo sed -i "s/host: \"0.0.0.0\"/host: \"127.0.0.1\"/g" kibana/config/kibana.yml
fi

# Install Logstash
if [ ! -d "/opt/logstash/" ]; then
  echo "Installing Logstash."
  cd "$dir"
  sudo wget --quiet --directory-prefix . ${logstashurl}
  sudo mkdir -p "logstash/"
  sudo tar xzf logstash-*.tar.gz -C "logstash" --strip-components=1
  sudo rm /opt/logstash-*.tar.gz
  sudo mkdir -p "logstash/conf.d/"
  cat > /opt/logstash/conf.d/10-syslog.conf <<- 'EOF'
input {
  syslog {
    port => 5514
    type => "syslog"
  }
  tcp {
    port => 5515
    type => "syslog"
  }
}

filter {
  if [type] == "syslog" {
    grok {
      match => { "message" => "%{SYSLOGTIMESTAMP:syslog_timestamp} %{SYSLOGHOST:syslog_hostname} %{DATA:syslog_program}(?:\[%{POSINT:syslog_pid}\])?: %{GREEDYDATA:syslog_message}" }
      add_field => [ "received_at", "%{@timestamp}" ]
      add_field => [ "received_from", "%{host}" ]
    }
    syslog_pri { }
    date {
      match => [ "syslog_timestamp", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
    }
  }
}

output {
  elasticsearch { host => localhost }
  stdout { codec => rubydebug }
}
EOF
fi

# Supervisor
echo "Installing supervisor."
sudo apt-get install -y supervisor
sudo mkdir -p "/etc/supervisor/conf.d/"
cat > /etc/supervisor/conf.d/default.conf <<- 'EOF'
[supervisord]
nodaemon=true

[include]
files = /etc/supervisor/conf.d/*.conf
EOF
cat > /etc/supervisor/conf.d/elasticsearch.conf <<- 'EOF'
[program:elasticsearch]
command=/opt/elasticsearch/bin/elasticsearch -f
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/elasticsearch.out.log
stderr_logfile=/var/log/supervisor/elasticsearch.err.log
EOF
cat > /etc/supervisor/conf.d/kibana.conf <<- 'EOF'
[program:kibana]
command=/opt/kibana/bin/kibana
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/kibana.out.log
stderr_logfile=/var/log/supervisor/kibana.err.log
EOF
cat > /etc/supervisor/conf.d/logstash.conf <<- 'EOF'
[program:logstash]
command=/opt/logstash/bin/logstash -f /etc/logstash/conf.d/ 
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/logstash.out.log
stderr_logfile=/var/log/supervisor/logstash.err.log
EOF

sudo /etc/init.d/supervisor start


