#!/usr/bin/env python3
"""Exercise the local Auth/Edge Function boundary and database quota; no provider key needed."""
import json
import secrets
import subprocess
import urllib.error
import urllib.request
import uuid

config = json.loads(subprocess.check_output(["supabase", "status", "--output", "json"], stderr=subprocess.DEVNULL))
base = config["API_URL"]
admin = config["SERVICE_ROLE_KEY"]
public = config["ANON_KEY"]

def call(path, body=None, token=None, method="POST"):
    headers = {"apikey": public, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=15) as result:
            return result.status, json.load(result)
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())

user_id = None
try:
    status, _ = call("/functions/v1/golf-ai", {"operation": "coach"})
    assert status == 401, "Unauthenticated request was not rejected"
    print("PASS unauthenticated Edge Function request rejected")
    email = "pinpoint-ai-qa-" + uuid.uuid4().hex + "@simulator.invalid"
    password = secrets.token_urlsafe(32)
    status, user = call("/auth/v1/admin/users", {"email": email, "password": password, "email_confirm": True}, admin)
    assert status in (200, 201), "Test user creation failed"
    user_id = user["id"]
    status, session = call("/auth/v1/token?grant_type=password", {"email": email, "password": password})
    assert status == 200, "Test sign-in failed"
    token = session["access_token"]
    # Invalid operation performs no OpenAI request even if a provider key is configured.
    status, body = call("/functions/v1/golf-ai", {"operation": "qa-no-provider-call"}, token)
    assert status in (400, 503), "Unexpected authenticated Edge Function result"
    print("PASS authenticated Edge Function reachable; " + ("provider key not configured" if status == 503 else "provider configured"))
    # Edge handler may have consumed one slot for the valid-session invalid-operation check.
    allowed = 0
    for _ in range(101):
        status, accepted = call("/rest/v1/rpc/consume_golf_ai_request", {}, token)
        assert status == 200, "Quota RPC failed"
        allowed += accepted is True
    assert allowed in (99, 100), "Quota did not enforce the daily boundary"
    status, accepted = call("/rest/v1/rpc/consume_golf_ai_request", {}, token)
    assert status == 200 and accepted is False, "Exhausted quota did not remain blocked"
    print("PASS per-user daily quota enforced in Postgres")
    status, _ = call("/rest/v1/rpc/consume_golf_ai_request", {})
    assert status in (401, 403, 404), "Anonymous quota access was not rejected"
    print("PASS quota function rejects anonymous requests")
finally:
    if user_id:
        status, _ = call("/auth/v1/admin/users/" + user_id, token=admin, method="DELETE")
        assert status in (200, 204), "Test user cleanup failed"
        print("PASS temporary QA account and quota row removed")
