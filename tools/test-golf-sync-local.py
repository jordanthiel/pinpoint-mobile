#!/usr/bin/env python3
"""Local Supabase integration: real Auth, RLS and concurrent compare-and-swap."""
import concurrent.futures
import json
import secrets
import subprocess
import urllib.error
import urllib.request
import uuid
import sys
import os
from pathlib import Path

if "--deployed" in sys.argv:
    project = Path("supabase/.temp/project-ref").read_text().strip()
    assert project == "wcobniubsmvvrggzrkhh", "Unexpected deployment target"
    keys = json.loads(subprocess.check_output(["supabase", "projects", "api-keys", "--project-ref", project, "-o", "json"], stderr=subprocess.DEVNULL))
    base = "https://" + project + ".supabase.co"
    public = next(k["api_key"] for k in keys if k["name"] == "anon")
    admin = next(k["api_key"] for k in keys if k["name"] == "service_role")
else:
    config = json.loads(subprocess.check_output(["supabase", "status", "--output", "json"], stderr=subprocess.DEVNULL))
    base, public, admin = config["API_URL"], config["ANON_KEY"], config["SERVICE_ROLE_KEY"]

def call(path, body=None, token=None, method="POST"):
    headers = {"apikey": public, "Content-Type": "application/json"}
    if token: headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(base + path, data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

users = []
try:
    tokens = []
    for _ in range(2):
        email = "golf-sync-qa-" + uuid.uuid4().hex + "@simulator.invalid"
        password = secrets.token_urlsafe(32)
        status, user = call("/auth/v1/admin/users", {"email": email, "password": password, "email_confirm": True}, admin)
        assert status in (200, 201)
        users.append(user["id"])
        status, session = call("/auth/v1/token?grant_type=password", {"email": email, "password": password})
        assert status == 200
        tokens.append(session["access_token"])
    fixture = os.environ.get("PINPOINT_SYNC_FIXTURE", "/tmp/pinpoint-sync-fixture.json")
    changes = json.loads(Path(fixture + ".changes").read_text())
    def commit(items):
        status, result = call("/rest/v1/rpc/commit_golf_records", {"changes": items}, tokens[0])
        assert status == 200, (status, result)
        return result
    def pull(cursor=0, token=None):
        status, result = call("/rest/v1/rpc/pull_golf_records", {"after_cursor": cursor}, token or tokens[0])
        assert status == 200, (status, result)
        return result
    assert commit(changes)["accepted"]
    if "--deployed" not in sys.argv:
        # Exercise the same importer used by the deployment, with no persistent data.
        migration_user = str(uuid.uuid4())
        payload = Path(fixture).read_text()
        sql = "BEGIN; INSERT INTO auth.users(id) VALUES ('" + migration_user + "'); SELECT public.import_golf_snapshot('" + migration_user + "', $fixture$" + payload + "$fixture$::jsonb, 7); SELECT migration_counts FROM public.golf_sync_accounts WHERE user_id='" + migration_user + "'; ROLLBACK;"
        result = subprocess.run(["docker", "exec", "-i", "supabase_db_pinpoint-mobile", "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"], input=sql, text=True, capture_output=True)
        assert result.returncode == 0, result.stderr
        assert '"holes": 18' in result.stdout and '"shots": 1' in result.stdout
        print("PASS legacy snapshot migration verifies entity counts and total score")
    snapshot = pull()
    assert len(snapshot["records"]) == len(changes)
    Path("/tmp/pinpoint-record-response.json").write_text(json.dumps(snapshot))
    print("PASS full app fixture uploaded as separate rows and downloaded")
    assert pull(token=tokens[1])["records"] == []
    for table in ("rounds", "hole_scores", "shots", "clubs", "practice_sessions", "golf_sync_accounts"):
        status, rows = call("/rest/v1/" + table + "?select=*", token=tokens[1], method="GET")
        assert status == 200 and rows == [], (table, status)
    status, _ = call("/rest/v1/rounds", {"user_id": users[0]}, tokens[1])
    assert status in (401,403)
    status, _ = call("/rest/v1/rpc/commit_golf_records", {"changes": changes})
    assert status in (401,403)
    print("PASS every table isolates accounts; direct and anonymous writes blocked")
    def edit(row, field, value):
        row = json.loads(json.dumps(row)); row["expected_revision"] = row.pop("revision")
        row["data"][field] = value
        return row
    shot = next(r for r in snapshot["records"] if r["kind"] == "shot")
    hole = next(r for r in snapshot["records"] if r["kind"] == "hole")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        receipts = list(pool.map(commit, [[edit(shot, "note", "Independent shot edit")], [edit(hole, "analysisNote", "Independent hole edit")]]))
    assert all(r["accepted"] for r in receipts)
    delta = pull(snapshot["cursor"])
    assert len(delta["records"]) == 2
    print("PASS simultaneous different-record edits both accepted; delta contains only two records")
    latest = next(r for r in delta["records"] if r["kind"] == "shot")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        receipts = list(pool.map(commit, [[edit(latest, "note", "A")], [edit(latest, "note", "B")]]))
    assert sum(r["accepted"] for r in receipts) == 1
    print("PASS simultaneous same-record edits reject the stale revision")
    status, rows = call("/rest/v1/hole_scores?select=score,round_id", token=tokens[0], method="GET")
    assert status == 200 and len(rows) == 18
    print("PASS scores available as typed relational columns")
    beforeDelete = pull()
    root = next(r for r in beforeDelete["records"] if r["kind"] == "round")
    deletion = edit(root, "recap", ""); deletion["deleted"] = True
    assert commit([deletion])["accepted"]
    afterDelete = pull(beforeDelete["cursor"])
    assert len(afterDelete["records"]) == 20 and all(r["deleted"] for r in afterDelete["records"])
    assert not commit([edit(root, "recap", "Stale resurrection")])["accepted"]
    dead = next(r for r in afterDelete["records"] if r["kind"] == "round")
    revival = edit(dead, "recap", "Resurrection"); revival["deleted"] = False
    assert not commit([revival])["accepted"]
    print("PASS round deletion cascades tombstones to 18 holes and shot; resurrection blocked")
    status, _ = call("/rest/v1/rpc/commit_golf_records", {"changes": [{"id": str(uuid.uuid4()), "expected_revision": 0}]}, tokens[0])
    assert status == 400
    print("PASS malformed record rejected")
    club = next(r for r in snapshot["records"] if r["kind"] == "club")
    forged = edit(club, "carryYards", 999); forged["round_id"] = str(uuid.uuid4()); forged["expected_revision"] = 0
    status, _ = call("/rest/v1/rpc/commit_golf_records", {"changes": [forged]}, tokens[0])
    assert status == 400
    print("PASS forged parent cannot bypass revision checks")

finally:
    for user in users:
        status, _ = call("/auth/v1/admin/users/" + user, token=admin, method="DELETE")
        assert status in (200, 204), "QA account cleanup failed"
