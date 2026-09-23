// Execute the pinned upstream code. Only its native runtime and tokenizer are
// replaced with transparent test doubles. These fixtures prove model-free
// parity and must never be described as real tokenizer or model outputs.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { stripTypeScriptTypes } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (name) => readFile(path.join(root, name), 'utf8');
const manifest = JSON.parse(await read('test/fixtures/manifest.json'));
const dest = path.join(root, 'tool/.reference');
await mkdir(dest, { recursive: true });
for (const [name, sha] of Object.entries(manifest.source.files)) {
  const source = await read(`tool/reference/${name}`);
  assert.equal(createHash('sha256').update(source).digest('hex'), sha, `Pinned source changed: ${name}`);
  if (name === 'types.ts') continue;
  let js = stripTypeScriptTypes(source, { mode: 'transform' });
  js = js.replace('"./sequence.js"', '"./sequence.mjs"');
  js = js.replace('import * as ort from "onnxruntime-node";', 'const ort = {Tensor: class {constructor(type,data,dims) {Object.assign(this,{type,data,dims});}}};');
  js = js.replace('import { Tokenizer } from "@huggingface/tokenizers";', 'class Tokenizer {constructor() {throw new Error("Real tokenizer unavailable in model-free fixtures");}}');
  js = js.replace(/import \{ ensureBundle \} from "\.\/download.js";/, 'const ensureBundle = () => {throw new Error("Downloads disabled");};');
  await writeFile(path.join(dest, name.replace('.ts', '.mjs')), js);
}
const seq = await import(pathToFileURL(path.join(dest, 'sequence.mjs')));
const { Laya } = await import(pathToFileURL(path.join(dest, 'laya.mjs')));
const config = JSON.parse(await read('test/fixtures/laya_config.json'));
const ids = { cls: 1, sep: 2, mask: 3, pad: 17, maskTok: '[MASK]' };
const encode = (text) => Array.from(text, (c) => c.codePointAt(0) + 100);
const choice = (instructions, criteria) => ({ type: 'choice', instructions, criteria });
const score = (instructions, criteria) => ({ type: 'score', instructions, criteria });
const noul = (instructions, criteria) => ({ type: 'noul', instructions, ...(criteria ? {criteria} : {}) });
const requests = [
  {name: 'plain choice', state: 'hello world', questions: {pick: choice('which one', ['a','bb'])}},
  {name: 'nested unicode mixed', state: {subject: '返金 café e\u0301 😀', n: 3.0, ok: true, x: null, xs: [1,'a\n\t"\\', {yes: false}]}, questions: {choice: choice('pick [MASK] one', {a:'first', b:null, c:''}), score: score('quality', ['low','middle','high','excellent']), truth: noul('is it true')}},
  {name: 'numeric keys and decimal notation', state: {'10':10, '2':2, '01':1, '-1':-1, '4294967295':1, '4294967294':1, floats:[0.1, 1e-7, 1e-6, 1e20, 1e21, -0, 0.00012345, 1.2345678901234567]}, questions: {'10': choice({z:1,'2':'first','1':'zero',prompt:'hello'}, ['10','2','1','01','2']), '2': noul('check', {false:'',true:'absolutely'})}},
  {name:'mask injection',state:'a [MASK][MASK] b',questions:{a:choice('[MASK] choose', {'[MASK]a':'x [MASK] y',b:'[MASK]'})}},
  {name:'long options and header',state:'tail',questions:{a:choice('q'.repeat(600), ['a'.repeat(300),'b'.repeat(300),'c'.repeat(300),'d'.repeat(300),'e'.repeat(300)])}},
  {name:'long state',state:'😀hello '.repeat(250),questions:{a:noul('is it')}},
  {name:'singleton and tie',state:null,questions:{one:choice('', ['only']),tie:choice('', ['first','second'])}, logits: [9,9000,0,0]},
  {name:'too many options',state:'',questions:{a:choice('x',Array.from({length:150},(_,i)=>`option${i}`))}},
  {name:'tiny context truncation',state:'x'.repeat(300),questions:{a:noul('is it')},config:{...config,max_len:64,head_max_len:32}},
  {name:'score expectation',state:'',questions:{a:score('', ['low','high'])},config:{...config,temperature:[1,1,1],temperature_by_options:{}},logits:[Math.log(.25),Math.log(.75)]},
  {name:'noul probability',state:'',questions:{a:noul('')},config:{...config,temperature:[1,1,1],temperature_by_options:{}},logits:[Math.log(.2),Math.log(.8)]},
];
for (const size of [2,3,5,6,10,11,20]) {
  for (const type of ['choice','score']) requests.push({name:`${type} bucket ${size}`,state:[1,2,3],questions:{q:{type,instructions:'choose',criteria:Array.from({length:size},(_,i)=>`label ${i}`)}}});
}
for (let i = 0; i < 20; i++) requests.push({name:`generated ${i}`,state:{i,text:' a\t😀e\u0301\n'.repeat(i)},questions:{a:choice('question '.repeat(i), ['a',' b','']),b:score('score', ['no','yes']),c:noul('check')}});
const fixtures = [];
for (const request of requests) {
  const cfg = request.config ?? config;
  const keys = Object.keys(request.questions);
  const sequences = keys.map((key) => {
    const q = seq.toInternal(request.questions[key]);
    const encodedTexts = [];
    const sequence = seq.buildSequence((text) => {encodedTexts.push(text);return encode(text);},ids,request.state,q,cfg.max_len,cfg.head_max_len);
    return {qid:key,options:seq.renderOptions(q),encodedTexts,...sequence};
  });
  let captured;
  let rawOutputs;
  const session = {run: async (tensors) => {
    captured = Object.fromEntries(Object.entries(tensors).map(([name,t]) => [name,{type:t.type,shape:t.dims,data:Array.from(t.data,(v)=>t.type==='bool'?Boolean(v):Number(v))}]));
    const [n,k] = tensors.marker_pos.dims;
    const logits = Float32Array.from(request.logits ?? Array.from({length:n*k}, (_,i) => ((i*7)%13-6)*.375));
    const act = Float32Array.from(Array.from({length:n*2},(_,i) => i%2 ? .6876543 : .3123457));
    rawOutputs = {logits:{type:'float32',shape:[n,k],data:Array.from(logits)},act_probs:{type:'float32',shape:[n,2],data:Array.from(act)}};
    return {logits:{data:logits,dims:[n,k]},act_probs:{data:act,dims:[n,2]}};
  }};
  const laya = new Laya(session,{encode:(text)=>({ids:encode(text)})},cfg,ids,'synthetic');
  const fixture = {name:request.name,state:request.state,questions:request.questions,config:cfg,serializedState:seq.serializeState(request.state),sequences};
  try {
    fixture.result = await laya.systemOne(request.state,request.questions);
    fixture.tensors = captured;
    fixture.rawOutputs = rawOutputs;
  } catch (error) {
    if (!String(error.message).includes('options do not fit')) throw error;
    fixture.error = error.message;
  }
  fixtures.push(fixture);
}
const data = JSON.stringify({provenance:manifest.model_free,specialIds:ids,cases:fixtures},null,2)+'\n';
await writeFile(path.join(root,'test/fixtures/model_free_cases.json'),data);
// JSON intentionally normalizes negative zero, as the reference serializer does.
assert.equal(JSON.stringify(JSON.parse(data).cases),JSON.stringify(fixtures));
console.log(`Generated ${fixtures.length} upstream model-free fixtures (${Buffer.byteLength(data)} bytes).`);
