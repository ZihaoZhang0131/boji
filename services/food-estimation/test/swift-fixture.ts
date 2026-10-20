// Test-only loopback fixture for the real Swift client. Never imported by production.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { createServer } from 'node:https';
import { request } from 'node:http';
import { once } from 'node:events';
import { createService } from '../src/server.js';
import { readConfig } from '../src/config.js';
import { digest, validateModelResult } from '../src/contracts.js';
const root = process.env.BOJI_FIXTURE_DIR!, token = process.env.BOJI_FIXTURE_TOKEN!;
if (!root || !token) throw new Error('Test environment required');
const conf = join(root,'openssl.cnf');
writeFileSync(conf, '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=Boji Swift fixture\n[ext]\nsubjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n');
execFileSync('/usr/bin/openssl',['req','-x509','-sha256','-newkey','rsa:2048','-nodes','-days','1','-keyout',join(root,'key.pem'),'-out',join(root,'cert.pem'),'-config',conf],{stdio:'ignore'});
execFileSync('/usr/bin/openssl',['x509','-in',join(root,'cert.pem'),'-outform','der','-out',join(root,'cert.der')]);
const config = readConfig({ DATA_DIR:join(root,'data'), BOJI_OWNERS_JSON:JSON.stringify({ personal:digest(token) }), PROVIDER_URL:'https://fixture.invalid/model', PROVIDER_NAME:'swift-local-fixture', PROVIDER_MODEL:'protocol-only', PROVIDER_KEY:'fixture-only-no-external-call', POLICY_VERSION:'fixture', PROVIDER_RETENTION:'Temporary local test fixture' });
let calls = 0, uploads = 0, lost = false;
const counts = () => writeFileSync(join(root,'counts.json'),JSON.stringify({calls,uploads})); counts();
const service = createService(config,{ provider:async () => { calls++; counts(); return validateModelResult({ recognized:true,items:[{name:'fixture meal',estimated_grams:null,kcal:123,assumptions:['Not real AI']}],total_kcal:123,estimate_range:{low:100,high:150},questions:[] }); } });
const upstream = new URL(await service.listen(0));
const proxy = createServer({key:readFileSync(join(root,'key.pem')),cert:readFileSync(join(root,'cert.pem'))},(req,res) => {
  if(req.url==='/v1/uploads') {uploads++;counts();}
  const lose = req.method==='POST' && req.url==='/v1/food-estimates' && !lost;
  if(lose) lost=true;
  const next=request({hostname:upstream.hostname,port:upstream.port,path:req.url,method:req.method,headers:req.headers},reply=>{
    if(lose){reply.resume();reply.on('end',()=>res.destroy());return;}
    res.writeHead(reply.statusCode??502,reply.headers);reply.pipe(res);
  }); next.on('error',()=>res.destroy());req.pipe(next);
});
proxy.listen(0,'127.0.0.1');await once(proxy,'listening');
writeFileSync(join(root,'ready.json'),JSON.stringify({url:`https://127.0.0.1:${(proxy.address() as {port:number}).port}`}));
process.on('SIGTERM',()=>{proxy.closeAllConnections();proxy.close();void service.close().then(()=>process.exit(0));});
