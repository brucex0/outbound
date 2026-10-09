#!/usr/bin/env python3
"""Loopback-only synthetic API for the focused group recovery UI test."""
import json
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def timestamp(offset=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=offset)).isoformat().replace("+00:00", "Z")


names = ["Fixture Runner", "Alice Chen", "Alice Lee", "Maya Rivera", "Jordan Park", "Alex Li", "Rina Test"]
people = [{"id": f"person-{i + 1}", "displayName": name, "avatarUrl": None} for i, name in enumerate(names)]


def group():
    return {
        "id": "ui-recovery-live", "activityEventId": "ui-recovery-event", "status": "active",
        "title": "Recovery group run", "sport": "run", "creatorUserId": "person-1", "currentUserId": "person-1",
        "startedAt": timestamp(-60), "expiresAt": timestamp(3600), "endedAt": None,
        "inviteToken": None, "inviteURL": None,
        "participants": [{
            "id": f"member-{i + 1}", "userId": person["id"], "displayName": person["displayName"],
            "status": "active", "joinedAt": timestamp(-60), "leftAt": None, "lastLocationAt": timestamp(),
            "lastLocation": {"latitude": 47.67 + i * .001, "longitude": -122.12},
            "lastActivitySnapshot": {"elapsedSeconds": 60, "distanceM": 100}
        } for i, person in enumerate(people)]
    }


def event():
    return {
        "id": "ui-recovery-event", "title": "Recovery group run", "activityType": "running",
        "startsAt": timestamp(-60), "endsAt": timestamp(3600), "locationName": None, "paceNote": None,
        "group": None, "creator": people[0], "groups": [], "attendeeCount": len(people),
        "currentUserGoing": True, "compatibility": None, "status": "active", "canParticipate": True,
        "participants": [{"person": person, "status": "going", "outcome": None, "startedAt": timestamp(-30)} for person in people]
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self):
        path = self.path.split("?")[0]
        if self.command in ("POST", "PATCH"):
            self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if path == "/social/activity-events/ui-recovery-event":
            status, payload = 200, event()
        elif path.startswith("/live/group-runs/"):
            status, payload = 200, group()
        else:
            status, payload = 404, {"error": "synthetic_fixture_unavailable"}
        # Paths and counts are synthetic; no request bodies or credentials are logged.
        print(f"{self.command} {path} {status}", flush=True)
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = respond
    do_POST = respond
    do_PATCH = respond


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18763), Handler).serve_forever()
