import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {Tokenizer} from './.reference/node_modules/@huggingface/tokenizers/dist/tokenizers.mjs';

const directory = new URL('../example/assets/tokenizer/',import.meta.url);
const raw = await readFile(new URL('tokenizer.json',directory),'utf8');
const config = await readFile(new URL('tokenizer_config.json',directory),'utf8');
const tokenizer = new Tokenizer(JSON.parse(raw),JSON.parse(config));
const strings = [
  '', 'hello world','Hello, world!',' hello','  hello','hello  world','hello   ',
  ' \t\n\r','a\tb\nc\r\nd','a'.repeat(400),' '.repeat(25),' '.repeat(48),
  'café','cafe\u0301','Ångström','A\u030Angstro\u0308m','e\u0301\u0323',
  '😀 👨‍👩‍👧‍👦 🏳️‍🌈','返金 日本語 中文','हिन्दी','مرحبا','한글','\u1100\u1161',
  "I'm we've you're he'll I'd can't DON'T Isn't it's",'1234 1.25 -8 1e-6',
  '[CLS] hello [SEP]','  [MASK]after','before\t\n [MASK]after','[MASK][MASK]',
  'foo|||EMAIL_ADDRESS|||bar','<|endoftext|> [UNK] [PAD] [unused0]',
  ' a\u0085b\u00a0c\ufeffd\u2003e\u2028f\u2029g','foo\u0000bar',
  '\\ \" / 😀 [MASK]','[[MASK]]','[mask]','a  b   c    d',
];
for (const token of JSON.parse(raw).added_tokens) strings.push(`before ${token.content} after`);
for (let i=0;i<75;i++) strings.push(Array.from({length:3+i},(_,j)=>['a',' b','\t','\n','😀','é','e\u0301','1','!',' ','[MASK]','返金'][((i+5)*7+j*11)%12]).join(''));
const fixture = {
  provenance:{implementation:'@huggingface/tokenizers@0.2.0',tokenizer_sha256:createHash('sha256').update(raw).digest('hex'),tokenizer_config_sha256:createHash('sha256').update(config).digest('hex'),add_special_tokens:false},
  specialIds:Object.fromEntries(['[CLS]','[SEP]','[MASK]','[PAD]'].map(t=>[t,tokenizer.token_to_id(t)])),
  cases:strings.map(text=>({text,ids:tokenizer.encode(text,{add_special_tokens:false}).ids})),
};
await writeFile(new URL('../test/fixtures/tokenizer_cases.json',import.meta.url),JSON.stringify(fixture,null,2)+'\n');
console.log(`Generated ${strings.length} real tokenizer fixtures.`);
