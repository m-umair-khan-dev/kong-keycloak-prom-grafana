import json
import re

dashboard_path = '/home/xflow/kong-keycloak-prom-grafana/components/grafana/dashboards/Kong API Gateway-1772003638547.json'

with open(dashboard_path, 'r') as f:
    dashboard_str = f.read()

# Replace metrics names
dashboard_str = dashboard_str.replace('kong_http_requests_total', 'http_server_request_count_total')
dashboard_str = dashboard_str.replace('kong_kong_latency_ms', 'kong_latency_total_seconds')
dashboard_str = dashboard_str.replace('kong_request_latency_ms', 'kong_latency_internal_seconds')
dashboard_str = dashboard_str.replace('kong_upstream_latency_ms', 'kong_latency_upstream_seconds')
dashboard_str = dashboard_str.replace('kong_bandwidth_bytes', 'http_server_response_size_bytes_sum')

# Nginx connections don't exist anymore, use request count to populate the instance variable
dashboard_str = dashboard_str.replace('label_values(kong_nginx_connections_total,instance)', 'label_values(http_server_request_count_total,instance)')

# Re-parse as json to modify units and regex queries
dashboard = json.loads(dashboard_str)

def walk_and_replace(obj):
    if isinstance(obj, dict):
        if 'expr' in obj and isinstance(obj['expr'], str):
            expr = obj['expr']
            # Replace labels
            expr = re.sub(r'service=~"([^"]*)"', r'kong_service_name=~"\1"', expr)
            expr = re.sub(r'route=~"([^"]*)"', r'kong_route_name=~"\1"', expr)
            expr = re.sub(r'code=~"([^"]*)"', r'http_response_status_code=~"\1"', expr)
            expr = re.sub(r'by \(service\)', r'by (kong_service_name)', expr)
            expr = re.sub(r'by \(route\)', r'by (kong_route_name)', expr)
            expr = re.sub(r'by \(service,code\)', r'by (kong_service_name,http_response_status_code)', expr)
            expr = re.sub(r'by \(route,code\)', r'by (kong_route_name,http_response_status_code)', expr)
            expr = re.sub(r'by \(service,le\)', r'by (kong_service_name,le)', expr)
            expr = re.sub(r'by \(route,le\)', r'by (kong_route_name,le)', expr)
            obj['expr'] = expr
            
        if 'unit' in obj and obj['unit'] == 'ms':
            obj['unit'] = 's'
            
        for k, v in obj.items():
            walk_and_replace(v)
            
    elif isinstance(obj, list):
        for item in obj:
            walk_and_replace(item)

walk_and_replace(dashboard)

# Also update template variables query
for templ in dashboard.get('templating', {}).get('list', []):
    if templ.get('name') == 'service' and isinstance(templ.get('query'), str):
        templ['query'] = 'label_values(http_server_request_count_total,kong_service_name)'
    elif templ.get('name') == 'route' and isinstance(templ.get('query'), str):
        templ['query'] = 'label_values(http_server_request_count_total,kong_route_name)'

with open(dashboard_path, 'w') as f:
    json.dump(dashboard, f, indent=2)

print("Dashboard updated successfully.")
