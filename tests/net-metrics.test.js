const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const source = fs.readFileSync(path.join(__dirname, "../shell/Services/NetMetrics.js"), "utf8");
const metrics = {};
vm.createContext(metrics);
vm.runInContext(source, metrics);

const routes = `Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT
lo 00000000 00000000 0000 0 0 0 00000000 0 0 0
wlan0 0000FEA9 00000000 0001 0 0 600 00FFFFFF 0 0 0
eth0 00000000 0101A8C0 0003 0 0 100 00000000 0 0 0
`;
assert.equal(metrics.defaultInterface(routes), "eth0");
assert.equal(metrics.defaultInterface("Iface Destination Gateway Flags\n"), "");

const devices = `Inter-| Receive | Transmit
 face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed
    lo: 10 1 0 0 0 0 0 0 20 2 0 0 0 0 0 0
  eth0: 123456 12 0 0 0 0 0 0 654321 21 0 0 0 0 0 0
`;
assert.deepEqual(
    JSON.parse(JSON.stringify(metrics.interfaceCounters(devices, "eth0"))),
    { rx: 123456, tx: 654321 }
);
assert.equal(metrics.interfaceCounters(devices, "wlan0"), null);
assert.equal(metrics.interfaceCounters("bad", "eth0"), null);

console.log("Network metrics parsers: OK");
