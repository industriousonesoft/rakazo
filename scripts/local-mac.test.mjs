import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

// Exercise the real script and plist generation without touching launchd or Docker.
const source = readFileSync(new URL("./local-mac.sh", import.meta.url), "utf8");
const stub = `#!/bin/bash
printf '%s %s\\n' "$(basename "$0")" "$*" >> "$TEST_CALLS"
case "$(basename "$0")" in
  colima)
    if [[ "$1" == status ]]; then exit "$TEST_COLIMA_STATUS"; fi ;;
  docker)
    if [[ "$1 $2" == 'context inspect' ]]; then
      echo "$TEST_ENDPOINT"
    elif [[ "$1 $2" == 'ps -q' && "$#" == 2 ]]; then
      echo "$TEST_OTHER_CONTAINERS"
    fi ;;
  launchctl)
    if [[ "$1" == bootout && "$3" == *supervisor.plist ]]; then touch "$TEST_CALLS.unloaded"; fi
    if [[ "$1" == print ]]; then
      if [[ "$2" == */local.rakazo.supervisor && -f "$TEST_CALLS.unloaded" ]]; then exit 1; fi
      exit "$TEST_LOADED_STATUS"
    fi ;;
  plutil)
    if [[ -n "$TEST_PREVIOUS_HOST" ]]; then echo "$TEST_PREVIOUS_HOST"; else exit 1; fi ;;
esac
`;

function fixture(t, overrides = {}) {
  const root = mkdtempSync(join(tmpdir(), "rakazo-local-mac-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const dir of ["scripts", "bin", "node_modules", "apps/web/dist", "colima"]) {
    mkdirSync(join(root, dir), { recursive: true });
  }
  writeFileSync(join(root, ".env"), "");
  writeFileSync(join(root, "apps/web/dist/index.html"), "");
  const script = join(root, "scripts/local-mac.sh");
  writeFileSync(
    script,
    source
      .replace(/^state_dir=.*$/m, 'state_dir="$root_dir/state"')
      .replace(/^log_dir=.*$/m, 'log_dir="$root_dir/logs"'),
  );
  for (const name of ["colima", "docker", "launchctl", "plutil", "pnpm", "curl"]) {
    writeFileSync(join(root, "bin", name), stub, { mode: 0o755 });
  }
  const calls = join(root, "calls");
  const env = {
    ...process.env,
    PATH: `${join(root, "bin")}:${process.env.PATH}`,
    COLIMA_HOME: join(root, "colima"),
    TEST_CALLS: calls,
    TEST_COLIMA_STATUS: "0",
    TEST_ENDPOINT: "unix:///tmp/test-colima/docker.sock",
    TEST_LOADED_STATUS: "1",
    TEST_OTHER_CONTAINERS: "",
    TEST_PREVIOUS_HOST: "",
    ...overrides,
  };
  return {
    root,
    run: (action) =>
      execFileSync("bash", [script, action], { env, encoding: "utf8", stdio: "pipe" }),
    calls: () => readFileSync(calls, "utf8"),
    supervisor: () =>
      readFileSync(join(root, "state/agents/local.rakazo.supervisor.plist"), "utf8"),
  };
}

test("start initializes Colima and passes its endpoint to Supervisor", (t) => {
  const f = fixture(t, { TEST_COLIMA_STATUS: "1" });
  f.run("start");
  assert.match(
    f.calls(),
    /colima start --runtime docker --vm-type vz --cpu 4 --memory 4 --disk 100/,
  );
  assert.match(f.calls(), /docker --host unix:\/\/\/tmp\/test-colima\/docker.sock info/);
  assert.match(
    f.supervisor(),
    /<key>DOCKER_HOST<\/key>\s*<string>unix:\/\/\/tmp\/test-colima\/docker.sock<\/string>/,
  );
  assert.match(f.supervisor(), /<key>SANDBOX_CONTROL_VIA_LOOPBACK<\/key>\s*<string>true<\/string>/);
  assert.match(f.calls(), /7091\/health/);
});

test("start preserves an existing Colima profile", (t) => {
  const f = fixture(t, { TEST_COLIMA_STATUS: "1" });
  mkdirSync(join(f.root, "colima/default"));
  writeFileSync(join(f.root, "colima/default/colima.yaml"), "cpu: 8\n");
  f.run("start");
  assert.match(f.calls(), /colima start\n/);
  assert.doesNotMatch(f.calls(), /--cpu/);
});

test("start reloads a registered Supervisor missing the endpoint", (t) => {
  const f = fixture(t, { TEST_LOADED_STATUS: "0" });
  f.run("start");
  assert.match(f.calls(), /launchctl bootout .*local.rakazo.supervisor.plist/);
  assert.match(f.calls(), /launchctl bootstrap .*local.rakazo.supervisor.plist/);
  assert.doesNotMatch(f.calls(), /bootout .*local.rakazo.(api|worker|web).plist/);
});

test("start keeps services when the endpoint is unchanged", (t) => {
  const f = fixture(t, {
    TEST_LOADED_STATUS: "0",
    TEST_PREVIOUS_HOST: "unix:///tmp/test-colima/docker.sock",
  });
  f.run("start");
  assert.doesNotMatch(f.calls(), /colima start|launchctl bootout|launchctl bootstrap/);
});

test("start rejects an unexpected remote Docker endpoint", (t) => {
  const f = fixture(t, { TEST_ENDPOINT: "tcp://example.invalid:2375" });
  assert.throws(() => f.run("start"));
  assert.doesNotMatch(f.calls(), /launchctl bootstrap|compose .* up/);
});

test("stop closes idle Colima even if it was already running before start", (t) => {
  const f = fixture(t);
  f.run("stop");
  assert.match(f.calls(), /compose .* stop postgres/);
  assert.match(f.calls(), /colima stop/);
  assert.doesNotMatch(f.calls(), /down|prune|volume rm/);
});

test("stop retains Colima while other containers run", (t) => {
  const f = fixture(t, { TEST_OTHER_CONTAINERS: "unrelated-container" });
  assert.match(f.run("stop"), /other containers are active/);
  assert.doesNotMatch(f.calls(), /colima stop/);
});
