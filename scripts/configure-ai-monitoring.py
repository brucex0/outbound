#!/usr/bin/env python3
"""Idempotent AI log metrics/alerts; reuse the API's existing operator channel."""
import argparse
import json
import subprocess
import urllib.error
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project', default='outbound-494602')
parser.add_argument('--account', default='bruce.xia74@gmail.com')
parser.add_argument('--service', default='outbound-api')
parser.add_argument('--apply', action='store_true')
args = parser.parse_args()
project = 'projects/' + args.project
base_filter = 'resource.type="cloud_run_revision" AND resource.labels.service_name="' + args.service + '"'
metrics = [
    ('plainstride_ai_generations', 'AI generation outcomes', base_filter + ' AND jsonPayload.event="ai_generation"', {'operation': 'EXTRACT(jsonPayload.operation)', 'outcome': 'EXTRACT(jsonPayload.outcome)'}),
    ('plainstride_ai_failures', 'Terminal AI generation failures', base_filter + ' AND jsonPayload.event="ai_generation" AND jsonPayload.outcome="failure"', {'operation': 'EXTRACT(jsonPayload.operation)', 'category': 'EXTRACT(jsonPayload.category)'}),
    ('plainstride_ai_capacity_errors', 'AI rate limit and timeout attempts', base_filter + ' AND jsonPayload.event="ai_attempt" AND (jsonPayload.category="rate_limited" OR jsonPayload.category="timeout")', {'operation': 'EXTRACT(jsonPayload.operation)', 'category': 'EXTRACT(jsonPayload.category)'}),
    ('plainstride_ai_slow_generations', 'AI successful requests exceeding the latency target', base_filter + ' AND jsonPayload.event="ai_generation" AND jsonPayload.outcome="success" AND ((jsonPayload.operation="assistant" AND jsonPayload.elapsed_ms>8000) OR (jsonPayload.operation="live_coach" AND jsonPayload.elapsed_ms>25000))', {'operation': 'EXTRACT(jsonPayload.operation)'}),
]
if not args.apply:
    print(json.dumps({'metrics': [m[0] for m in metrics], 'alerts': ['2 terminal failures in 10 minutes', '3 rate limit/timeout attempts in 5 minutes', '3 slow successful generations in 10 minutes'], 'notification_channels': 'reuse Outbound API 5xx errors channels'}, indent=2))
    raise SystemExit(0)
token = subprocess.check_output(['gcloud', 'auth', 'print-access-token', '--account=' + args.account], text=True).strip()

def api(host, path, method='GET', body=None):
    request = urllib.request.Request('https://' + host + '/v3/' + path if host.startswith('monitoring') else 'https://' + host + '/v2/' + path,
        data=json.dumps(body).encode() if body is not None else None, method=method,
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # This configuration-only API diagnostic contains no AI prompts or runner data.
        detail = json.load(error).get('error', {}).get('message', 'No diagnostic')
        raise RuntimeError('Monitoring configuration request failed: HTTP ' + str(error.code) + ': ' + detail) from None

policies = api('monitoring.googleapis.com', project + '/alertPolicies').get('alertPolicies', [])
channels = next((p.get('notificationChannels', []) for p in policies if p.get('displayName') == 'Outbound API 5xx errors'), [])
if not channels:
    raise SystemExit('Existing API operator notification channel not found; no alerts changed.')
existing = {m['name']: m for m in api('logging.googleapis.com', project + '/metrics').get('metrics', [])}
for name, description, log_filter, labels in metrics:
    body = {'name': name, 'description': description, 'filter': log_filter, 'metricDescriptor': {'metricKind': 'DELTA', 'valueType': 'INT64',
        'labels': [{'key': key, 'valueType': 'STRING', 'description': key} for key in labels]}, 'labelExtractors': labels}
    api('logging.googleapis.com', project + '/metrics' + ('/' + name if name in existing else ''), 'PUT' if name in existing else 'POST', body)
    print('Configured metric: ' + name)
for name, metric, seconds, threshold in [
    ('Outbound AI terminal failures', 'plainstride_ai_failures', 600, 1),
    ('Outbound AI capacity errors', 'plainstride_ai_capacity_errors', 300, 2),
    ('Outbound AI slow responses', 'plainstride_ai_slow_generations', 600, 2),
]:
    body = {'displayName': name, 'combiner': 'OR', 'enabled': True, 'notificationChannels': channels,
        'documentation': {'mimeType': 'text/markdown', 'content': 'Inspect structured ai_generation and ai_attempt logs. See docs/ai-reliability.md. Do not include prompts, responses or runner data in incident messages.'},
        'alertStrategy': {'autoClose': '1800s'},
        'conditions': [{'displayName': name, 'conditionThreshold': {
            'filter': 'resource.type="cloud_run_revision" AND metric.type="logging.googleapis.com/user/' + metric + '"',
            'comparison': 'COMPARISON_GT', 'thresholdValue': threshold, 'duration': '0s', 'trigger': {'count': 1},
            'aggregations': [{'alignmentPeriod': str(seconds) + 's', 'perSeriesAligner': 'ALIGN_SUM', 'crossSeriesReducer': 'REDUCE_SUM'}]}}]}
    prior = next((p for p in policies if p.get('displayName') == name), None)
    if prior:
        body['name'] = prior['name']
    api('monitoring.googleapis.com', prior['name'] if prior else project + '/alertPolicies', 'PATCH' if prior else 'POST', body)
    print('Configured alert: ' + name)
