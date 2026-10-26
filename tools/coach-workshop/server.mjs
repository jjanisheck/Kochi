import http from 'node:http';
import { createReadStream } from 'node:fs';
import { readdir, stat, realpath } from 'node:fs/promises';
import { dirname, resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateCue } from './core.mjs';

const root = dirname(fileURLToPath(import.meta.url));
const theme = resolve(root, '../../app/KochiApp/Resources/Themes/default');
const references = {
  '/reference/background.png': resolve(theme,'avatar/arm-background.png'),
  '/reference/coach.png': resolve(theme,'avatar/general.png'),
  '/reference/idle.mp4': resolve(theme,'videos/idle-1.mp4'),
};
const clients = new Set();
const types = { '.html':'text/html; charset=utf-8', '.css':'text/css; charset=utf-8', '.mjs':'text/javascript; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.json':'application/json', '.png':'image/png', '.jpg':'image/jpeg', '.mp4':'video/mp4', '.glb':'model/gltf-binary', '.fbx':'application/octet-stream' };
const json = (res,status,value) => { res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'}); res.end(JSON.stringify(value)); };

const server = http.createServer(async (req,res) => {
  try {
    const url = new URL(req.url,'http://localhost');
    const pathname = decodeURIComponent(url.pathname);
    if (pathname === '/api/imports' && req.method === 'GET') {
      const files = [];
      for (const name of await readdir(resolve(root,'imports'))) {
        if (!/\.(fbx|glb)$/i.test(name)) continue;
        const info = await stat(resolve(root,'imports',name));
        if (info.isFile()) files.push({name,size:info.size,modified:info.mtimeMs,url:`/imports/${encodeURIComponent(name)}?v=${info.mtimeMs}`});
      }
      return json(res,200,{files:files.sort((a,b) => a.name.localeCompare(b.name))});
    }
    if (pathname === '/api/events' && req.method === 'GET') {
      res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-cache','Connection':'keep-alive'});
      res.write(': connected\n\n'); res.liveCoach=url.searchParams.get('coach')==='1'; clients.add(res);
      const keepalive = setInterval(() => res.write(': keepalive\n\n'),20000);
      req.on('close',() => { clients.delete(res); clearInterval(keepalive); }); return;
    }
    if (pathname === '/api/coach-status' && req.method === 'GET') {
      return json(res,200,{service:'kochi-character-workshop',protocol:1,live:[...clients].some(client=>client.liveCoach)});
    }
    if (pathname === '/api/react' && req.method === 'POST') {
      if (req.headers.origin && req.headers.origin !== `http://${req.headers.host}`) return json(res,403,{error:'Use this workshop’s origin.'});
      if (!req.headers['content-type']?.startsWith('application/json')) return json(res,415,{error:'Use application/json.'});
      let body = '';
      for await (const chunk of req) { body += chunk; if (body.length > 8192) return json(res,413,{error:'Cue is too large.'}); }
      let cue;
      try { cue = validateCue(JSON.parse(body)); } catch (error) { return json(res,400,{error:error.message}); }
      for (const client of clients) client.write(`data: ${JSON.stringify(cue)}\n\n`);
      return json(res,200,{ok:true,viewers:clients.size,cue});
    }
    if (!['GET','HEAD'].includes(req.method)) return json(res,405,{error:'Method not allowed.'});
    if (pathname === '/favicon.ico') { res.writeHead(204); return res.end(); }
    let file = references[pathname];
    if (!file) {
      file = resolve(root,`.${pathname === '/' ? '/index.html' : pathname}`);
      if (!file.startsWith(root + sep)) return json(res,403,{error:'Forbidden.'});
      const canonical = await realpath(file);
      if (!canonical.startsWith(root + sep)) return json(res,403,{error:'Forbidden.'});
    }
    const info = await stat(file);
    if (!info.isFile()) return json(res,404,{error:'Not found.'});
    const headers = { 'Content-Type':types[extname(file)] || 'application/octet-stream', 'Cache-Control':'no-cache','Accept-Ranges':'bytes','X-Content-Type-Options':'nosniff' };
    const range = req.headers.range?.match(/^bytes=(\d+)-(\d*)$/);
    let start = 0, end = info.size - 1, status = 200;
    if (range) {
      start = Number(range[1]); end = range[2] ? Math.min(Number(range[2]),end) : end;
      if (start > end || start >= info.size) { res.writeHead(416,{'Content-Range':`bytes */${info.size}`}); return res.end(); }
      status = 206; headers['Content-Range'] = `bytes ${start}-${end}/${info.size}`;
    }
    headers['Content-Length'] = end - start + 1;
    res.writeHead(status,headers);
    if (req.method === 'HEAD') return res.end();
    createReadStream(file,{start,end}).pipe(res);
  } catch (error) {
    if (!res.headersSent) json(res,error.code === 'ENOENT' ? 404 : 500,{error:error.code === 'ENOENT' ? 'Not found.' : 'Could not complete the request.'});
    else res.end();
  }
});

server.listen(Number(process.env.PORT || 4173),'127.0.0.1',() => console.log(`Character workshop: http://127.0.0.1:${server.address().port}`));
