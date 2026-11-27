import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {runScheduledM5} from './m5-scheduled-coordinator.mjs';

// Deliberately offline-only until the native target lease and capture schema are verified.
// CLI refuses all mutation; the coordinator remains exercised through injected test adapters.
const args=process.argv.slice(2);
const manifest=JSON.parse(await readFile(resolve(import.meta.dirname,'../config/orchestration-cutover-manifest.json'),'utf8'));
if(args.includes('--live') || args.includes('--submit') || args.includes('--dispatch')) {
  console.error(JSON.stringify({ok:false,status:'M5_LIVE_CLI_NOT_ADMITTED',dispatched:false}));
  process.exitCode=2;
} else if(manifest.m5OptInCutoverEnabled!==false || manifest.chatGptLoopAuthority!==false) {
  console.error(JSON.stringify({ok:false,status:'M5_CUTOVER_MANIFEST_UNEXPECTED',dispatched:false}));
  process.exitCode=2;
} else {
  console.log(JSON.stringify({ok:true,status:'M5_CLI_OFFLINE_ONLY',dispatched:false,
    nextGate:'NATIVE_GUI_LEASE_AND_CAPTURE_SCHEMA',manifestCutover:false}));
}
