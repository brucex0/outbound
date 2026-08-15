#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
backend_dir="$repo_dir/backend"
persona="${1:-}"
auth_port=9099
api_port="${OUTBOUND_E2E_API_PORT:-3010}"
database_port="${OUTBOUND_E2E_DATABASE_PORT:-54329}"
project_id=outbound-494602
log_dir=$(mktemp -d "${TMPDIR:-/tmp}/plainstride-e2e.XXXXXX")
auth_pid=""
api_pid=""

usage() {
  print "Usage: $0 <new|active|social>"
}

wait_for_url() {
  local url=$1
  local pid=$2
  local label=$3
  for _ in {1..90}; do
    curl --silent --fail --max-time 1 "$url" >/dev/null 2>&1 && return 0
    kill -0 "$pid" 2>/dev/null || { print "$label exited early. See $log_dir" >&2; return 1; }
    sleep 1
  done
  print "Timed out waiting for $label. See $log_dir" >&2
  return 1
}

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  [[ -n "$api_pid" ]] && kill -INT "$api_pid" 2>/dev/null || true
  [[ -n "$auth_pid" ]] && kill -INT "$auth_pid" 2>/dev/null || true
  sleep 2
  [[ -n "$api_pid" ]] && kill -TERM "$api_pid" 2>/dev/null || true
  [[ -n "$auth_pid" ]] && kill -TERM "$auth_pid" 2>/dev/null || true
  if (( exit_code == 0 )); then
    print "Local server E2E passed for persona '$persona'. Logs: $log_dir"
  else
    print "Local server E2E failed. Logs: $log_dir" >&2
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

case "$persona" in
  new) email="new-runner@plainstride.test" ;;
  active) email="active-runner@plainstride.test" ;;
  social) email="social-runner@plainstride.test" ;;
  *) usage >&2; exit 2 ;;
esac

for port in "$auth_port" 4000 4400 4500 "$api_port" "$database_port"; do
  if nc -z 127.0.0.1 "$port" 2>/dev/null; then
    print "Port $port is already in use; stop that service or override the API/database E2E ports." >&2
    exit 1
  fi
done

print "Starting Firebase Auth Emulator..."
(
  cd "$repo_dir"
  exec npx --yes firebase-tools emulators:start --only auth --project "$project_id" --config firebase.json
) >"$log_dir/firebase.log" 2>&1 &
auth_pid=$!
wait_for_url "http://127.0.0.1:$auth_port/" "$auth_pid" "Firebase Auth Emulator"

print "Building and starting local API..."
(cd "$backend_dir" && npm run build) >"$log_dir/api-build.log" 2>&1
(
  cd "$backend_dir"
  exec env \
    PORT="$api_port" \
    OUTBOUND_PG_PORT="$database_port" \
    FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:$auth_port" \
    FIREBASE_PROJECT_ID="$project_id" \
    node scripts/start-local-stack.mjs
) >"$log_dir/api.log" 2>&1 &
api_pid=$!
wait_for_url "http://127.0.0.1:$api_port/health" "$api_pid" "local API"

database_url="postgresql://outbound:outbound@127.0.0.1:$database_port/outbound?schema=public"
print "Resetting deterministic persona data..."
(
  cd "$backend_dir"
  FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:$auth_port" \
  FIREBASE_PROJECT_ID="$project_id" \
  DATABASE_URL="$database_url" \
  npm run seed:e2e
) >"$log_dir/seed.log" 2>&1

print "Authenticating '$persona' through Firebase..."
curl --silent --show-error --fail-with-body \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$email\",\"password\":\"plainstride-test-persona\",\"returnSecureToken\":true}" \
  "http://127.0.0.1:$auth_port/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key" \
  >"$log_dir/auth.json"

token=$(node -e 'const fs=require("fs"); const value=JSON.parse(fs.readFileSync(process.argv[1])); if (!value.idToken) process.exit(1); process.stdout.write(value.idToken)' "$log_dir/auth.json")
api_base="http://127.0.0.1:$api_port/v1"
for endpoint in auth/me activities social/home social/connections social/groups social/notifications social/blocks; do
  file_name=${endpoint//\//-}
  curl --silent --show-error --fail-with-body \
    -H "Authorization: Bearer $token" \
    "$api_base/$endpoint" >"$log_dir/$file_name.json"
done

print "Asserting '$persona' server state..."
node - "$persona" "$log_dir/auth-me.json" "$log_dir/activities.json" "$log_dir/social-home.json" "$log_dir/social-connections.json" "$log_dir/social-groups.json" "$log_dir/social-notifications.json" "$log_dir/social-blocks.json" <<'NODE'
const fs = require("fs");
const [persona, mePath, activitiesPath, socialPath, connectionsPath, groupsPath, notificationsPath, blocksPath] = process.argv.slice(2);
const read = path => JSON.parse(fs.readFileSync(path, "utf8"));
const me = read(mePath);
const activities = read(activitiesPath).activities ?? [];
const social = read(socialPath);
const connections = read(connectionsPath).connections ?? [];
const groups = read(groupsPath).groups ?? [];
const notifications = read(notificationsPath).notifications ?? [];
const blocks = read(blocksPath).blocks ?? [];
const fail = message => { throw new Error(`[${persona}] ${message}`); };

const expectedNames = { new: "New Runner", active: "Avery Runner", social: "Sage Runner" };
if (me.displayName !== expectedNames[persona]) fail(`expected displayName ${expectedNames[persona]}, got ${me.displayName}`);
if (!me.id || !me.firebaseUid) fail("missing backend user identity");

if (persona === "new") {
  if (activities.length !== 0) fail(`expected 0 activities, got ${activities.length}`);
  if ((social.clubs ?? []).length !== 0) fail("expected no group memberships");
}
if (persona === "active") {
  if (activities.length !== 3) fail(`expected 3 activities, got ${activities.length}`);
  const ids = activities.map(item => item.clientActivityId).sort();
  if (!ids.includes("e2e-active-easy") || !ids.includes("e2e-active-long")) fail("seeded activity IDs are missing");
}
if (persona === "social") {
  if (!(social.clubs ?? []).some(club => club.name === "Plainstride E2E Run Club")) fail("seeded joined group is missing");
  if (!(social.upcomingRuns ?? []).some(run => run.title === "Saturday social 5K")) fail("seeded group run is missing");
  if (!(social.posts ?? []).some(post => post.caption === "Easy miles and good energy today.")) fail("connected feed post is missing");
  if (!connections.some(connection => connection.status === "accepted" && connection.person?.displayName === "Avery Runner")) fail("accepted connection is missing");
  if (!connections.some(connection => connection.status === "pending" && connection.direction === "incoming" && connection.person?.displayName === "New Runner")) fail("incoming connection request is missing");
  if (!groups.some(group => group.name === "Plainstride E2E Run Club" && group.membershipRole === "organizer")) fail("joined group discovery state is missing");
  if (!groups.some(group => group.name === "Sunset E2E Striders" && group.membershipRole == null)) fail("discoverable unjoined group is missing");
  if (!notifications.some(notification => notification.type === "runInvitation")) fail("run invitation notification is missing");
  if (!notifications.some(notification => notification.type === "connectionRequest")) fail("connection request notification is missing");
  if (!blocks.some(block => block.person?.displayName === "Blocked Runner")) fail("block-list seed is missing");
}
console.log(`[e2e] ${persona}: authenticated user and seeded API state verified.`);
NODE

if [[ "$persona" == "social" ]]; then
  print "Exercising Social server mutations..."
  node - "$api_base" "$token" "$auth_port" <<'NODE'
const [apiBase, token, authPort] = process.argv.slice(2);
const headers = { Authorization: `Bearer ${token}` };
const fail = message => { throw new Error(`[social mutations] ${message}`); };
const request = async (path, options = {}, expected = [200]) => {
  const response = await fetch(`${apiBase}${path}`, {
    ...options,
    headers: { ...headers, ...(options.body ? { "Content-Type": "application/json" } : {}), ...options.headers },
  });
  const payload = await response.json();
  if (!expected.includes(response.status)) fail(`${options.method ?? "GET"} ${path} returned ${response.status}: ${JSON.stringify(payload)}`);
  return payload;
};

(async () => {
  let home = await request("/social/home");
  const post = home.posts.find(item => item.caption === "Easy miles and good energy today.");
  const run = home.upcomingRuns.find(item => item.title === "Saturday social 5K");
  if (!post || !run) fail("feed post or group run is missing");

  const search = await request("/social/people/search?q=Avery");
  const activePerson = search.people.find(person => person.displayName === "Avery Runner");
  if (!activePerson || activePerson.relationship?.status !== "accepted") fail("people search did not return the accepted connection");

  let groups = (await request("/social/groups")).groups;
  const discoverableGroup = groups.find(group => group.name === "Sunset E2E Striders");
  if (!discoverableGroup || discoverableGroup.membershipRole != null) fail("discoverable group precondition failed");
  await request(`/social/groups/${discoverableGroup.id}/membership`, { method: "POST" }, [201]);
  groups = (await request("/social/groups")).groups;
  if (!groups.some(group => group.id === discoverableGroup.id && group.membershipRole === "member")) fail("joining a group did not persist");
  await request(`/social/groups/${discoverableGroup.id}/membership`, { method: "DELETE" });
  groups = (await request("/social/groups")).groups;
  if (!groups.some(group => group.id === discoverableGroup.id && group.membershipRole == null)) fail("leaving a group did not persist");

  let runDetail = await request(`/social/group-runs/${run.id}`);
  if (!runDetail.currentUserGoing) fail("seeded RSVP is missing");
  await request(`/social/group-runs/${run.id}/rsvp`, { method: "DELETE" });
  runDetail = await request(`/social/group-runs/${run.id}`);
  if (runDetail.currentUserGoing) fail("leaving a group run did not persist");
  await request(`/social/group-runs/${run.id}/rsvp`, { method: "POST" });
  runDetail = await request(`/social/group-runs/${run.id}`);
  if (!runDetail.currentUserGoing) fail("joining a group run did not persist");

  await request(`/social/posts/${post.id}/cheer`, { method: "DELETE" });
  home = await request("/social/home");
  if (home.posts.find(item => item.id === post.id)?.currentUserCheered) fail("removing a Cheer did not persist");
  await request(`/social/posts/${post.id}/cheer`, { method: "PUT" });
  home = await request("/social/home");
  if (!home.posts.find(item => item.id === post.id)?.currentUserCheered) fail("adding a Cheer did not persist");

  const commentBody = "Automated Social server comment";
  const comment = await request(`/social/posts/${post.id}/comments`, { method: "POST", body: JSON.stringify({ body: commentBody }) }, [201]);
  let comments = (await request(`/social/posts/${post.id}/comments`)).comments;
  if (!comments.some(item => item.id === comment.id && item.body === commentBody)) fail("adding a comment did not persist");
  await request(`/social/comments/${comment.id}`, { method: "DELETE" });
  comments = (await request(`/social/posts/${post.id}/comments`)).comments;
  if (comments.some(item => item.id === comment.id)) fail("deleting a comment did not persist");

  const report = await request("/social/reports", { method: "POST", body: JSON.stringify({ targetType: "post", targetId: post.id, reason: "other", details: "Automated E2E report" }) }, [201]);
  if (!report.id || !report.status) fail("report creation response is incomplete");

  let notifications = (await request("/social/notifications")).notifications;
  const invitation = notifications.find(item => item.type === "runInvitation");
  if (!invitation?.objectId) fail("run invitation precondition failed");
  await request(`/social/invitations/${invitation.objectId}/accept`, { method: "POST" });
  notifications = (await request("/social/notifications")).notifications;
  if (notifications.some(item => item.id === invitation.id)) fail("accepted invitation notification was not dismissed");
  await request("/social/notifications/read-all", { method: "POST" });
  notifications = (await request("/social/notifications")).notifications;
  if (notifications.some(item => item.readAt == null)) fail("marking notifications read did not persist");

  const targetedInvite = await request(`/social/group-runs/${run.id}/invitations`, { method: "POST", body: JSON.stringify({ recipientUserId: activePerson.id }) }, [201]);
  if (!targetedInvite.id || !targetedInvite.token) fail("targeted invitation response is incomplete");
  const referral = await request("/social/referrals", { method: "POST" }, [200, 201]);
  if (!referral.url || !referral.code) fail("referral response is incomplete");

  let blocks = (await request("/social/blocks")).blocks;
  const blocked = blocks.find(item => item.person?.displayName === "Blocked Runner");
  if (!blocked) fail("block precondition failed");
  await request(`/social/users/${blocked.person.id}/block`, { method: "DELETE" });
  blocks = (await request("/social/blocks")).blocks;
  if (blocks.some(item => item.person?.id === blocked.person.id)) fail("unblocking did not persist");
  await request(`/social/users/${blocked.person.id}/block`, { method: "POST" });
  blocks = (await request("/social/blocks")).blocks;
  if (!blocks.some(item => item.person?.id === blocked.person.id)) fail("blocking did not persist");

  let connections = (await request("/social/connections")).connections;
  const incoming = connections.find(item => item.status === "pending" && item.direction === "incoming");
  if (!incoming) fail("incoming request precondition failed");
  await request(`/social/connections/${incoming.id}/accept`, { method: "POST" });
  connections = (await request("/social/connections")).connections;
  if (!connections.some(item => item.id === incoming.id && item.status === "accepted")) fail("accepting a connection did not persist");
  await request(`/social/connections/${incoming.id}`, { method: "DELETE" });
  connections = (await request("/social/connections")).connections;
  if (connections.some(item => item.id === incoming.id)) fail("removing a connection did not persist");

  const authResponse = await fetch(`http://127.0.0.1:${authPort}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: "active-runner@plainstride.test", password: "plainstride-test-persona", returnSecureToken: true }),
  });
  const activeAuth = await authResponse.json();
  if (!authResponse.ok || !activeAuth.idToken) fail("could not authenticate Active Runner for activity sharing");
  const activeHeaders = { Authorization: `Bearer ${activeAuth.idToken}` };
  const activitiesResponse = await fetch(`${apiBase}/activities`, { headers: activeHeaders });
  const activeActivities = await activitiesResponse.json();
  const activity = activeActivities.activities?.[0];
  if (!activity?.id) fail("Active Runner activity is missing");
  const shareResponse = await fetch(`${apiBase}/social/activity-shares`, {
    method: "POST",
    headers: { ...activeHeaders, "Content-Type": "application/json" },
    body: JSON.stringify({ activityId: activity.id, caption: "Easy miles and good energy today.", visibility: "connections" }),
  });
  const sharedPost = await shareResponse.json();
  if (!shareResponse.ok || sharedPost.activity?.id !== activity.id) fail(`activity sharing failed: ${JSON.stringify(sharedPost)}`);

  console.log("[e2e] social: server mutations verified.");
})().catch(error => { console.error(error); process.exit(1); });
NODE
fi
