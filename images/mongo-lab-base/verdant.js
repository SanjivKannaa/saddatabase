// Verdant (smart greenhouses): db verdant. Deterministic (no random): sites, devices, readings, alerts, users.
const v = db.getSiblingDB('verdant');
const sites = ['Lisbon', 'Porto', 'Braga', 'Faro', 'Evora'];
const base = new Date('2026-11-10T00:00:00Z').getTime();
v.sites.insertMany(sites.map((s, i) => ({ _id: s.toLowerCase(), name: s, greenhouses: 3 + i, opened: new Date(base - (400 + i * 90) * 864e5) })));
const devices = [];
for (let i = 1; i <= 600; i++) devices.push({ _id: 'dev-' + String(i).padStart(4, '0'), site: sites[i % 5], kind: ['temp', 'humidity', 'soil', 'co2'][i % 4],
  firmware: '2.' + (i % 7) + '.0', status: (i % 11 === 0 ? 'decommissioned' : 'active'), installed: new Date(base - (i * 3) * 864e5) });
v.devices.insertMany(devices);
for (let b = 0; b < 30; b++) {
  const batch = [];
  for (let j = 0; j < 2000; j++) { const n = b * 2000 + j; batch.push({ device: 'dev-' + String(1 + n % 600).padStart(4, '0'), ts: new Date(base - n * 60e3),
    value: Math.round((15 + (n * 37 % 200) / 10) * 10) / 10 }); }
  v.readings.insertMany(batch);
}
const alerts = [];
for (let i = 1; i <= 1500; i++) alerts.push({ device: 'dev-' + String(1 + (i * 7) % 600).padStart(4, '0'), level: ['info', 'warn', 'critical'][i % 3],
  msg: 'threshold crossed', at: new Date(base - i * 17 * 60e3), acked: i % 4 === 0 });
v.alerts.insertMany(alerts);
v.users.insertMany(Array.from({ length: 40 }, (_, i) => ({ _id: 'user' + (i + 1), name: 'Grower ' + (i + 1), site: sites[i % 5], role: i < 3 ? 'admin' : 'grower' })));
v.devices.createIndex({ site: 1, status: 1 });
v.readings.createIndex({ device: 1, ts: -1 });
v.alerts.createIndex({ acked: 1, at: -1 });
