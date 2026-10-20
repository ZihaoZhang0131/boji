import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import { spawn, execFileSync, type ChildProcess } from 'node:child_process';
import { createServer as httpsServer, request as httpsRequest } from 'node:https';
import { createServer as httpServer, request as httpRequest } from 'node:http';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { digest } from '../src/contracts.js';

test('real service subprocess survives restart behind trusted local HTTPS; model remains a fixture', async t => {
  const root = mkdtempSync(join(tmpdir(),'boji-https-')), certPath = join(root,'cert.pem'), keyPath = join(root,'key.pem');
  const conf = join(root,'openssl.cnf');
  writeFileSync(conf, '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=Boji fixture only\n[ext]\nsubjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,digitalSignature,keyEncipherment\n');
  execFileSync('/usr/bin/openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1','-keyout',keyPath,'-out',certPath,'-config',conf],{ stdio:'ignore' });
  const tls = { key:readFileSync(keyPath),cert:readFileSync(certPath) };
  const token = randomBytes(32).toString('base64url'), providerKey = randomBytes(32).toString('hex');
  let providerCalls = 0, child: ChildProcess | undefined, logs = '';
  const provider = httpsServer(tls, (req,res) => {
    providerCalls++;
    assert.equal(req.headers.authorization, `Bearer ${providerKey}`);
    req.resume(); req.on('end',() => {
      res.writeHead(200,{'Content-Type':'application/json'});
      res.end(JSON.stringify({ choices:[{ finish_reason:'stop',message:{ content:JSON.stringify({ recognized:true,items:[{ name:'local fixture',estimated_grams:null,kcal:123,assumptions:['Protocol fixture, not AI'] }],total_kcal:123,estimate_range:null,questions:[] }) } }] }));
    });
  });
  provider.listen(0,'127.0.0.1'); await once(provider,'listening');
  const providerPort = (provider.address() as {port:number}).port;
  const reservation = httpServer(); reservation.listen(0,'127.0.0.1'); await once(reservation,'listening');
  const port = (reservation.address() as {port:number}).port; await new Promise<void>(r => reservation.close(() => r()));
  const proxy = httpsServer(tls,(req,res) => {
    const upstream = httpRequest({ host:'127.0.0.1',port,path:req.url,method:req.method,headers:req.headers },response => { res.writeHead(response.statusCode ?? 502,response.headers); response.pipe(res); });
    upstream.on('error',() => { res.writeHead(502); res.end(); }); req.pipe(upstream);
  });
  proxy.listen(0,'127.0.0.1'); await once(proxy,'listening'); const proxyPort = (proxy.address() as {port:number}).port;
  const stop = async () => { if (child && child.exitCode === null) { const exited = once(child,'exit'); child.kill('SIGTERM'); await exited; } };
  t.after(async () => { await stop(); await Promise.all([new Promise<void>(r => { proxy.close(() => r()); proxy.closeAllConnections(); }), new Promise<void>(r => { provider.close(() => r()); provider.closeAllConnections(); })]); rmSync(root,{recursive:true,force:true}); });
  const start = async () => {
    child = spawn(process.execPath,[resolve('dist/src/main.js')],{ env:{ PATH:process.env.PATH, DATA_DIR:join(root,'data'), PORT:String(port), BOJI_OWNERS_JSON:JSON.stringify({personal:digest(token)}), PROVIDER_URL:`https://127.0.0.1:${providerPort}/model`, PROVIDER_NAME:'local-protocol-fixture', PROVIDER_MODEL:'fixture-only', PROVIDER_KEY:providerKey, POLICY_VERSION:'fixture-v1', PROVIDER_RETENTION:'No external calls; temporary fixture memory only', NODE_EXTRA_CA_CERTS:certPath },stdio:['ignore','pipe','pipe'] });
    child.stdout!.on('data',x => {logs += x.toString();}); child.stderr!.on('data',x => {logs += x.toString();});
    let ready = false;
    for (let i=0;i<100;i++) { try { const r = await fetch(`http://127.0.0.1:${port}/health`); await r.arrayBuffer(); if(r.ok){ready=true;break;} } catch {} await delay(20); }
    assert.equal(ready,true,'Child service did not start');
  };
  const request = (path:string, method='GET', body?:unknown):Promise<{status:number;body:any}> => new Promise((resolve,reject) => {
    const req = httpsRequest({ hostname:'127.0.0.1',port:proxyPort,path,method,ca:tls.cert,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'} },res => {
      const chunks:Buffer[]=[]; res.on('data',x=>chunks.push(x));res.on('end',()=>resolve({status:res.statusCode!,body:JSON.parse(Buffer.concat(chunks).toString())}));
    });req.on('error',reject);req.end(body===undefined?undefined:JSON.stringify(body));
  });
  await start(); const config = await request('/v1/config'); assert.equal(config.body.available,true);
  const body = {request_id:randomUUID(),request_created_at:new Date().toISOString(),record_id:randomUUID(),input_revision:1,lifecycle_epoch:0,image_refs:[],note:'synthetic fixture note',locale:'zh-Hans',policy_version:config.body.policy_version};
  const submitted = await request('/v1/food-estimates','POST',body); assert.equal(submitted.status,202);
  const id = submitted.body.job_id;
  let finished:any;
  for(let i=0;i<100;i++){ finished=(await request(`/v1/food-estimates/${id}`)).body;if(finished.status==='succeeded'||finished.status==='failed')break;await delay(20); }
  assert.equal(finished.status,'succeeded');assert.equal(finished.result.total_kcal,123);assert.equal(providerCalls,1);
  await stop();await start();
  assert.equal((await request(`/v1/food-estimates/${id}`)).body.result.total_kcal,123);
  assert.equal((await request('/v1/food-estimates','POST',body)).body.job_id,id);assert.equal(providerCalls,1);
  for(const secret of [token,providerKey,body.note])assert.ok(!logs.includes(secret));
});
