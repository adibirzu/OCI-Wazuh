const fs = require("fs");
const path = require("path");

const rootDir = path.resolve(__dirname, "..");
const port = process.env.CHROME_DEBUG_PORT || "9223";
const liveDir = path.join(rootDir, "docs/wiki/assets/live");

const captureTargets = [
  {
    name: "wazuh-authenticated-overview",
    match: (tab) => tab.url.includes("127.0.0.1:8443"),
    required: true,
  },
  {
    name: "wazuh-discover-live",
    match: (tab) => tab.url.includes("127.0.0.1:8443") && tab.url.toLowerCase().includes("discover"),
    required: false,
  },
  {
    name: "wazuh-dashboard-live",
    match: (tab) => tab.url.includes("127.0.0.1:8443") && tab.url.toLowerCase().includes("dashboard"),
    required: false,
  },
  {
    name: "oci-log-analytics-explorer",
    match: (tab) => tab.url.includes("cloud.oracle.com/loganalytics") && tab.url.toLowerCase().includes("explorer"),
    required: true,
  },
  {
    name: "oci-log-analytics-dashboard-live",
    match: (tab) => tab.url.includes("cloud.oracle.com/loganalytics") && tab.url.toLowerCase().includes("dashboard"),
    required: false,
  },
];

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`GET ${url} failed: ${response.status} ${response.statusText}`);
  }
  return response.json();
}

async function capturePage(webSocketDebuggerUrl, outputPath) {
  const ws = new WebSocket(webSocketDebuggerUrl);
  let id = 0;
  const pending = new Map();

  ws.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      pending.get(message.id)(message);
      pending.delete(message.id);
    }
  };

  await new Promise((resolve, reject) => {
    ws.onopen = resolve;
    ws.onerror = reject;
  });

  const send = (method, params = {}) => new Promise((resolve) => {
    const callId = ++id;
    pending.set(callId, resolve);
    ws.send(JSON.stringify({ id: callId, method, params }));
  });

  await send("Page.enable");
  await send("Page.bringToFront");
  await send("Emulation.setDeviceMetricsOverride", {
    width: 1440,
    height: 1000,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await sleep(3000);

  const screenshot = await send("Page.captureScreenshot", {
    format: "png",
    fromSurface: true,
    captureBeyondViewport: false,
  });

  if (!screenshot.result || !screenshot.result.data) {
    throw new Error(`Failed to capture ${outputPath}`);
  }

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, Buffer.from(screenshot.result.data, "base64"));
  ws.close();
}

async function main() {
  const tabs = await fetchJson(`http://127.0.0.1:${port}/json/list`);
  const pageTabs = tabs.filter((tab) => tab.type === "page");
  const captured = [];
  const missingRequired = captureTargets
    .filter((target) => target.required && !pageTabs.find(target.match))
    .map((target) => target.name);

  if (missingRequired.length > 0) {
    throw new Error(`Missing required authenticated console tabs: ${missingRequired.join(", ")}`);
  }

  for (const target of captureTargets) {
    const tab = pageTabs.find(target.match);
    if (!tab) {
      console.log(`screenshot=${target.name} skipped=no_matching_tab`);
      continue;
    }
    await capturePage(tab.webSocketDebuggerUrl, path.join(liveDir, `${target.name}.png`));
    captured.push(target.name);
    console.log(`screenshot=${target.name} captured=true`);
  }

  console.log(`screenshots_captured=${captured.join(",")}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
