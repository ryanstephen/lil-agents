#!/usr/bin/env node
// lil-agents bridge — Claude Code hook that broadcasts session events
// so Bruce & Jazz can observe and interact with active sessions.
//
// Install: add to ~/.claude/settings.json (see README)

import { readFileSync, writeFileSync, mkdirSync, existsSync, appendFileSync, unlinkSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

const BASE_DIR = join(homedir(), '.claude', 'lil-agents');
const SESSIONS_DIR = join(BASE_DIR, 'sessions');
const INBOX_DIR = join(BASE_DIR, 'inbox');

mkdirSync(SESSIONS_DIR, { recursive: true });
mkdirSync(INBOX_DIR, { recursive: true });

// Read hook input from stdin
let input = '';
try {
  input = readFileSync('/dev/stdin', 'utf-8');
} catch {
  process.exit(0);
}

let data;
try {
  data = JSON.parse(input);
} catch {
  process.exit(0);
}

const sessionId = data.session_id || process.env.CLAUDE_SESSION_ID || 'unknown';

// Infer hook type from data shape
let hookType = 'unknown';
if (data.tool_name && data.tool_output !== undefined) {
  hookType = 'PostToolUse';
} else if (data.tool_name) {
  hookType = 'PreToolUse';
} else if (data.event) {
  hookType = 'SessionStart';
} else if (data.notification) {
  hookType = 'Notification';
}

// Build event record
const event = {
  ts: Date.now(),
  hook: hookType,
  session_id: sessionId,
};

if (data.tool_name) event.tool = data.tool_name;
if (data.tool_input) {
  // Keep tool input concise
  const ti = data.tool_input;
  event.input = {};
  if (ti.file_path) event.input.file_path = ti.file_path;
  if (ti.command) event.input.command = String(ti.command).slice(0, 200);
  if (ti.pattern) event.input.pattern = ti.pattern;
  if (ti.description) event.input.description = String(ti.description).slice(0, 200);
}

if (hookType === 'PostToolUse' && data.tool_output) {
  const out = typeof data.tool_output === 'string'
    ? data.tool_output
    : JSON.stringify(data.tool_output);
  event.output = out.slice(0, 300);
}

if (data.event) event.event = data.event;
if (data.notification) event.notification = String(data.notification).slice(0, 300);

// Resolve cwd — prefer data, fall back to env, then process
const cwd = data.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
event.cwd = cwd;

// Append event to session file
const sessionFile = join(SESSIONS_DIR, `${sessionId}.jsonl`);
appendFileSync(sessionFile, JSON.stringify(event) + '\n');

// Update meta file
const metaFile = join(SESSIONS_DIR, `${sessionId}.meta`);
let meta = {
  session_id: sessionId,
  cwd,
  last_event: Date.now(),
};

try {
  const existing = JSON.parse(readFileSync(metaFile, 'utf-8'));
  meta.started_at = existing.started_at;
} catch {
  meta.started_at = Date.now();
}

if (hookType === 'SessionStart') {
  meta.started_at = Date.now();
}

writeFileSync(metaFile, JSON.stringify(meta) + '\n');

// Check inbox for messages to inject into the session
const inboxFile = join(INBOX_DIR, `${sessionId}.jsonl`);
let additionalContext = '';

if (existsSync(inboxFile)) {
  try {
    const content = readFileSync(inboxFile, 'utf-8').trim();
    if (content) {
      const lines = content.split('\n')
        .map(l => { try { return JSON.parse(l); } catch { return null; } })
        .filter(Boolean);

      if (lines.length > 0) {
        additionalContext = lines
          .map(m => `[lil-agents note from ${m.from || 'buddy'}]: ${m.text}`)
          .join('\n');
        unlinkSync(inboxFile);
      }
    }
  } catch { /* ignore read errors */ }
}

// Return response — inject inbox messages as additionalContext
if (additionalContext) {
  process.stdout.write(JSON.stringify({ additionalContext }));
}
