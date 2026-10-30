// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';
import { run_command } from './core.uc';

const HELPER = '/usr/libexec/smartsafehub-rpc-jobs';
const RUNTIME = '/tmp/smartsafehub/rpc-jobs/';

// Only fixed job names reach the privileged launcher. Never accept arbitrary
// executable paths, shell fragments or network locations from the browser.
export function job_state(name) {
 const state = { phase: 'idle', code: '', argument: '', updatedAt: 0 };
 const raw = fs.readfile(RUNTIME + name + '.state');
 if (type(raw) != 'string' || length(raw) > 1024) return state;
 for (let line in split(raw, /\r?\n/)) {
  const fields = split(line, /\t/);
  if (length(fields) != 2) continue;
  if (fields[0] == 'phase' && match(fields[1], /^(starting|running|success|failed)$/) != null)
   state.phase = fields[1];
  else if (fields[0] == 'code' && match(fields[1], /^(NONE|LAUNCH|E[0-9]{1,3})$/) != null)
   state.code = fields[1];
  else if (fields[0] == 'argument' && match(fields[1], /^[0-9]{0,10}$/) != null)
   state.argument = fields[1];
  else if (fields[0] == 'updated' && match(fields[1], /^[0-9]{1,12}$/) != null)
   state.updatedAt = int(fields[1]);
 }
 return state;
};

export function ensure_job(name) {
 return run_command([ HELPER, 'ensure', name ], 1500);
};

export function request_job(name, argument) {
 const command = [ HELPER, 'request', name ];
 if (argument != null) push(command, sprintf('%s', argument));
 return run_command(command, 1500);
};
