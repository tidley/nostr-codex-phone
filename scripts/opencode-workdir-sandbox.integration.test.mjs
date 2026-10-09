import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import net from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const wrapper = new URL("./opencode-workdir-sandbox.sh", import.meta.url).pathname;

function run(command, args, options) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, options);
    let stderr = "";
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code, stderr }));
  });
}

test("wrapper preserves private reporter environment", async () => {
  const base = await mkdtemp(join(tmpdir(), "phone-opencode-wrapper-env-"));
  const socket = join(base, "private-report.sock");
  const token = "private-token";
  const reports = [];
  const server = net.createServer((connection) => {
    let input = "";
    connection.setEncoding("utf8");
    connection.on("data", (chunk) => {
      input += chunk;
      const newline = input.indexOf("\n");
      if (newline === -1) return;
      reports.push(JSON.parse(input.slice(0, newline)));
      connection.end("{}\n");
    });
  });
  await new Promise((resolve, reject) => server.listen(socket, (error) => error ? reject(error) : resolve()));
  const child = join(base, "real-opencode.mjs");
  await writeFile(child, `#!/usr/bin/env node
import net from "node:net";
const client = net.createConnection(process.env.HERDR_PANE_REPORT_SOCKET, () => client.write(JSON.stringify({ token: process.env.HERDR_PANE_REPORT_TOKEN, source: "herdr:opencode", agent: "opencode", agent_session_id: "session", session_start_source: "startup" }) + "\\n"));
client.once("data", () => client.destroy());
`, { mode: 0o755 });

  try {
    const result = await run(wrapper, [], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        AGENT_READ_ROOT: process.cwd(),
        HERDR_PANE_REPORT_SOCKET: socket,
        HERDR_PANE_REPORT_TOKEN: token,
        OPENCODE_REAL_BIN: child,
      },
    });
    assert.equal(result.code, 0, result.stderr);
    assert.deepEqual(reports, [{ token, source: "herdr:opencode", agent: "opencode", agent_session_id: "session", session_start_source: "startup" }]);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(base, { recursive: true, force: true });
  }
});

test("wrapper preserves private reporter access for startup and completion", async () => {
  const base = await mkdtemp(join(tmpdir(), "phone-opencode-wrapper-"));
  const socket = join(base, "private-report.sock");
  const token = "private-token";
  const reports = [];
  const server = net.createServer((connection) => {
    let input = "";
    connection.setEncoding("utf8");
    connection.on("data", (chunk) => {
      input += chunk;
      const newline = input.indexOf("\n");
      if (newline === -1) return;
      reports.push(JSON.parse(input.slice(0, newline)));
      connection.end("{}\n");
    });
  });
  await new Promise((resolve, reject) => server.listen(socket, (error) => error ? reject(error) : resolve()));

  const child = join(base, "real-opencode.mjs");
  await writeFile(child, `#!/usr/bin/env node
import net from "node:net";
const send = (message) => new Promise((resolve, reject) => {
  const client = net.createConnection(process.env.HERDR_PANE_REPORT_SOCKET, () => client.write(JSON.stringify(message) + "\\n"));
  client.once("data", () => { client.destroy(); resolve(); });
  client.once("error", reject);
});
await send({ token: process.env.HERDR_PANE_REPORT_TOKEN, source: "herdr:opencode", agent: "opencode", agent_session_id: "session", session_start_source: "startup" });
await send({ token: process.env.HERDR_PANE_REPORT_TOKEN, source: "herdr:opencode", agent: "opencode", agent_session_id: "session", state: "idle", seq: 2, completion: { id: "message", text: "done" } });
`, { mode: 0o755 });

  try {
    const result = await run(wrapper, [], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        AGENT_READ_ROOT: process.cwd(),
        HERDR_PANE_REPORT_SOCKET: socket,
        HERDR_PANE_REPORT_TOKEN: token,
        OPENCODE_REAL_BIN: child,
      },
    });
    assert.equal(result.code, 0, result.stderr);
    assert.deepEqual(reports, [
      { token, source: "herdr:opencode", agent: "opencode", agent_session_id: "session", session_start_source: "startup" },
      { token, source: "herdr:opencode", agent: "opencode", agent_session_id: "session", state: "idle", seq: 2, completion: { id: "message", text: "done" } },
    ]);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(base, { recursive: true, force: true });
  }
});
