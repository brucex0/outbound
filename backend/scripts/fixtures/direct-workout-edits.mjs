// Explicit local synthetic QA only. Never mounted by the production entry point.
import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
// Match the deployed backend's UTC process clock for logical training dates.
process.env.TZ = 'UTC';

const backend = fileURLToPath(new URL('../..', import.meta.url)).replace(/\/$/, '');
const output = process.env.OUTBOUND_DIRECT_EDIT_OUTPUT ?? '/tmp/plainstride-workout-edit-fixture';
await mkdir(output, { recursive:true });
const require = createRequire(backend + '/package.json');
// Normal npm ci runs the platform package's symlink hydration postinstall.
const EmbeddedPostgres = (await import('embedded-postgres')).default;
process.env.DATABASE_URL = 'postgresql://fixture:fixture@127.0.0.1:28479/workout_edits?schema=public';
process.env.AUTH_ENABLE_DEBUG_PERSONAS = 'false';
const pg = new EmbeddedPostgres({ databaseDir:output+'/postgres', user:'fixture', password:'fixture', port:28479, persistent:true, onLog:()=>{}, onError:m=>console.error('[fixture-pg]', String(m).slice(0,160)) });
try { await readFile(output+'/postgres/PG_VERSION'); } catch { await pg.initialise(); }
await pg.start();
const client = pg.getPgClient('postgres','127.0.0.1');
await client.connect();
if (!(await client.query("SELECT 1 FROM pg_database WHERE datname='workout_edits'")).rowCount) await client.query('CREATE DATABASE workout_edits');
await client.end();
await new Promise((resolve,reject) => {
  const child=spawn(backend+'/node_modules/.bin/prisma',['db','push','--skip-generate','--schema',backend+'/prisma/schema.prisma'],{cwd:backend,env:process.env,stdio:['ignore','pipe','pipe']});
  let log=''; child.stdout.on('data',d=>log+=d); child.stderr.on('data',d=>log+=d);
  child.on('close',c=>c===0?resolve():reject(new Error('isolated schema push failed: '+log.slice(-1800))));
});
const from = p => import(pathToFileURL(backend+'/dist/'+p));
const {getPrismaClient}=await from('services/prisma.js');
const db=getPrismaClient();
const {Hono}=await import(pathToFileURL(require.resolve('hono')));
const {serve}=await import(pathToFileURL(require.resolve('@hono/node-server')));
const accounts={root:'fixture-edit-root',ui:'fixture-edit-ui',other:'fixture-edit-other',standalone:'fixture-edit-standalone'};
const faults=new Map(), traces=[];
const stable = value => Array.isArray(value) ? '['+value.map(stable).join(',')+']' : value && typeof value==='object' ? '{'+Object.entries(value).sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>JSON.stringify(k)+':'+stable(v)).join(',')+'}' : JSON.stringify(value);
function account(c) { return accounts[c.req.header('x-fixture-account')] ?? (new URL(c.req.url).port==='28480'?accounts.root:accounts.ui); }
async function seed(userId,{planned=true,duration=1710,structured=false}={}) {
  await db.user.deleteMany({where:{id:userId}});
  await db.user.create({data:{id:userId,username:userId,displayName:'Synthetic Runner',onboardingStatus:'completed',termsAcceptedVersion:1}});
  await db.calibrationProgram.create({data:{userId,status:'skipped',targetSessionCount:3,currentSession:'comfortableRun'}});
  if (!planned) return {userId};
  const goal=await db.trainingGoal.create({data:{userId,type:'healthEnergy',priority:'normal',activities:['run'],maxSessionMinutes:60,daysPerWeekTarget:3}});
  const plan=await db.trainingPlan.create({data:{userId,goalId:goal.id,source:'fixture',currentPhase:'base'}});
  const version=await db.trainingPlanVersion.create({data:{planId:plan.id,versionNumber:1,reason:'fixture',summary:'Synthetic plan'}});
  const today=new Date(); today.setUTCHours(0,0,0,0);
  const parts=structured?[['warmup',300,1,2],['interval',300,5,7],['recovery',120,1,2],['interval',300,5,7],['cooldown',300,1,2]]:[['warmup',300,1,2],['main',duration-600,2,4],['cooldown',300,1,2]];
  const workout=await db.plannedWorkout.create({data:{userId,planVersionId:version.id,scheduledDate:today,modality:'run',stimulus:structured?'speed':'easyAerobic',title:structured?'Synthetic intervals':'Easy run',durationSeconds:parts.reduce((n,p)=>n+p[1],0),intensityModel:'rpe',intensityTarget:{min:2,max:4},prescription:{optional:false},blocks:{create:parts.map(([kind,seconds,min,max],index)=>({sortOrder:index,blockType:kind,modality:'run',stimulus:structured?'speed':'easyAerobic',durationSeconds:seconds,steps:{create:{sortOrder:0,kind:kind==='main'?'easy':kind,label:kind==='main'?'Easy run':kind==='warmup'?'Warm up':kind==='cooldown'?'Cool down':kind,durationSeconds:seconds,target:{rpe:[min,max]}}}}))}}});
  return {userId,plannedWorkoutId:workout.id,planId:plan.id,versionId:version.id};
}
for(const [name,id] of Object.entries(accounts)) await seed(id,{planned:name!=='standalone'});
const app=new Hono();
app.use('*',async(c,next)=>{
  const userId=account(c);
  c.set('locale',(c.req.header('accept-language')??'en').startsWith('es')?'es':(c.req.header('accept-language')??'').startsWith('zh')?'zh-Hans':'en');
  c.set('auth',{subject:userId,authenticationKind:'plainstride',provider:'plainstride',providerSubject:userId,internalUserId:userId,sessionId:null,email:null,emails:[],emailVerified:false,name:'Synthetic Runner',picture:null,phoneNumber:null,phoneNumbers:[]});
  if(c.req.path==='/v1/planning/workout-edits/apply') {
    const body=await c.req.raw.clone().text(); let parsed;try{parsed=JSON.parse(body)}catch{}
    const entry={operation:parsed?.change?.operation,key:parsed?.idempotencyKey,requestHash:createHash('sha256').update(parsed?stable({...parsed,reason:parsed.reason??null}):body).digest('hex'),user:userId,at:new Date().toISOString()};
    traces.push(entry);
    const fault=faults.get(userId); faults.delete(userId);
    if(fault?.delay) await new Promise(r=>setTimeout(r,fault.delay));
    if(fault?.fail) {entry.status=503;return c.json({error:'Synthetic temporary save failure.'},503);}
    await next(); entry.status=c.res.status;
    if(fault?.drop && c.res.status===200) c.res=new Response(JSON.stringify({error:'Synthetic response failure after commit.'}),{status:503,headers:{'Content-Type':'application/json'}});
    await writeFile(output+'/ui-trace.json',JSON.stringify(traces,null,2));
    return;
  }
  await next();
});
app.post('/__fixture/reset',async c=>c.json(await seed(account(c),await c.req.json().catch(()=>({})))));
app.post('/__fixture/fail-next',c=>{faults.set(account(c),{fail:true});return c.json({ready:true});});
app.post('/__fixture/delay-next',c=>{faults.set(account(c),{delay:2200});return c.json({ready:true});});
app.post('/__fixture/drop-response-next',c=>{faults.set(account(c),{drop:true});return c.json({ready:true});});
app.get('/__fixture/evidence',async c=>{const userId=account(c);return c.json({edits:await db.workoutEdit.findMany({where:{userId},orderBy:{createdAt:'asc'}}),completions:await db.workoutCompletion.findMany({where:{userId}}),workouts:await db.plannedWorkout.findMany({where:{userId},include:{blocks:{include:{steps:true}}}}),trace:traces.filter(t=>t.user===userId)});});
for(const [prefix,file] of [['planning','planning.js'],['personalization','personalization.js'],['auth','auth.js'],['activities','activities.js'],['statistics','statistics.js'],['notifications','notifications.js'],['recognition','recognition.js']]) app.route('/v1/'+prefix,(await from('routes/'+file)).default);
app.get('/health',c=>c.json({ok:true,synthetic:true}));
app.all('*',c=>c.json({fixture:true}));
app.onError((error,c)=>{console.error('[fixture] request_failed',c.req.path,error.name,error.message.slice(0,200));return c.json({error:'Fixture handler failure.'},500);});
const servers=[serve({fetch:app.fetch,port:28480,hostname:'127.0.0.1'}),serve({fetch:app.fetch,port:28481,hostname:'127.0.0.1'})];
const compiledHash=createHash('sha256').update(await readFile(backend+'/dist/services/planning/workoutEdits.js')).digest('hex');
await writeFile(output+'/fixture-info.json',JSON.stringify({compiledHash,api:'http://127.0.0.1:28480/v1',ui:'http://127.0.0.1:28481/v1',accounts},null,2));
console.log('[fixture] ready loopback API28480 UI28481; isolated synthetic data only');
async function shutdown(){for(const server of servers)await new Promise(r=>server.close(r));await db.$disconnect();await pg.stop();process.exit(0);}
process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
