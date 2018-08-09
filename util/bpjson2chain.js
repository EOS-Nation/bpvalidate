#!/usr/bin/env node

// Usage: ./bpjson2chain.js <bp.json filepath>

const fs = require("fs");

const bpjsonFilePath = process.argv[2] || "bp.json";
if (!bpjsonFilePath) new Error("bp.json filepath is required");

const bpjson = JSON.parse(fs.readFileSync(bpjsonFilePath));
const bpjsonString = JSON.stringify(JSON.stringify(bpjson));
const owner = bpjson.producer_account_name

console.log(`cleos push action producerjson set '{"owner": "${owner}", "json": ${bpjsonString}}' -p ${owner}@active`);
