#!/usr/bin/env bash
# suite: fast
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node - "$repo_root/shell/utils/scripts/skwd-wall.js" <<'JS'
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const adapter = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[2], 'utf8'), adapter);
const rows = adapter.library({wallpapers:[
 {key:'we:42', name:'Scene', type:'we', we_id:'42', thumb:'/cache/42.webp'},
 {key:'we:43', name:'Workshop video', type:'video', video_file:'/workshop/43/movie.mp4', thumb:'/cache/43.webp'},
 {key:'static:a.jpg', name:'a.jpg', type:'static', path:'/walls/a.jpg', preview:'/cache/a.webp'},
 {key:'we:44', type:'we', hidden:true}, {key:'shader:1', type:'shader'}, {type:'we'}
]}, '/walls');
assert.equal(rows.length, 3);
assert.equal(rows[0].path, 'skwd:we:42');
assert.equal(rows[0].parentDir, '/walls/Skwd Wall');
assert.equal(rows[1].mediaPath, '/workshop/43/movie.mp4');
assert.equal(rows[1].skwdKey, 'we:43');
assert.equal(rows[2].thumbnail, '/cache/a.webp');
assert.throws(() => adapter.library({}, '/walls'));
assert.equal(adapter.library({wallpapers:[]}, '/walls').length, 0);
assert.equal(adapter.animated({name:'DP-1', type:'we', we_id:'42'}), true);
assert.equal(adapter.animated({type:'static', path:'/walls/a.jpg'}), false);
assert.equal(adapter.animated({type:'video', path:'/movie.mp4', connected:false}), false);
assert.equal(adapter.animated({type:'video'}), false);
assert.equal(adapter.selection({type:'we', we_id:'42'}, rows), 'skwd:we:42');
assert.equal(adapter.selection({type:'video', path:'/workshop/43/movie.mp4'}, rows), 'skwd:we:43');
assert.equal(adapter.selection({type:'video', path:'/other.mp4'}, rows), '/other.mp4');
assert.equal(adapter.selection(undefined, rows), '');
console.log('skwd picker adapter tests passed');
JS
