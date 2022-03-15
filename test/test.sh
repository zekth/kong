#!/bin/bash

http PUT :8001/plugins/c10a18ef-c2a7-46e9-8b09-a2235aaf7d50 name='opentelemetry' \
    config:='{"http_endpoint": "https://ingest.lightstep.com:443/traces/otlp/v0.6", "http_headers": {"Lightstep-Access-Token": [""]}}'

# mockbin
http PUT :8001/services/mockbin host=mockbin.org
http PUT :8001/services/mockbin/routes/mockbin hosts:='["mockbin.local.shoujo.io"]'

# admin api
http PUT :8001/services/admin host=127.0.0.1 port:=8001
http PUT :8001/services/admin/routes/admin hosts:='["admin.local.shoujo.io"]'