// Run only against scripts/fixtures/direct-workout-edits.mjs. All identities are synthetic.
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {pathToFileURL,fileURLToPath} from 'node:url';
const backend=fileURLToPath(new URL('../..',import.meta.url)).replace(/\/$/,'');
const output=process.env.OUTBOUND_DIRECT_EDIT_OUTPUT??'/tmp/plainstride-workout-edit-fixture';
process.env.TZ='UTC';
process.env.DATABASE_URL='postgresql://fixture:fixture@127.0.0.1:28479/workout_edits?schema=public';
const {getPrismaClient}=await import(pathToFileURL(backend+'/dist/services/prisma.js'));
const {compileLiveCoachContext}=await import(pathToFileURL(backend+'/dist/services/liveCoach/liveCoachContextCompiler.js'));
const {buildActivitySuggestion}=await import(pathToFileURL(backend+'/dist/services/planning/activitySuggestion.js'));
const db=getPrismaClient();
const base='http://127.0.0.1:28480';
const selectedCheck=process.env.OUTBOUND_DIRECT_EDIT_CHECK;
const report={scope:'isolated synthetic local API + real PostgreSQL; no test suite, no production',at:new Date().toISOString(),compiledHash:createHash('sha256').update(await readFile(backend+'/dist/services/planning/workoutEdits.js')).digest('hex'),checks:[]};
async function request(path,{method='GET',body,account='root'}={}) {const r=await fetch(base+path,{method,headers:{'content-type':'application/json','x-fixture-account':account},...(body===undefined?{}:{body:JSON.stringify(body)})});return {status:r.status,data:await r.json()};}
const reset=(body={},account='root')=>request('/__fixture/reset',{method:'POST',body,account});
const suggestion=async(account='root')=>(await request('/v1/planning/activity-suggestion',{account})).data;
function command(s,change,reason) {return {plannedWorkoutId:s.primary.plannedWorkoutId??null,suggestionId:s.primary.id,validForDate:s.validForDate,baseRevision:s.editContext.baseRevision,idempotencyKey:randomUUID(),change,...(reason===undefined?{}:{reason})};}
const apply=(body,account='root')=>request('/v1/planning/workout-edits/apply',{method:'POST',body,account});
const evidence=async(account='root')=>(await request('/__fixture/evidence',{account})).data;
const edit=(seconds,effortPreset)=>({operation:'edit',edits:{...(seconds==null?{}:{target:{kind:'time',seconds}}),...(effortPreset?{effortPreset}:{})}});
async function check(name,run) {if(selectedCheck&&!name.includes(selectedCheck))return;try {const detail=await run();report.checks.push({name,status:'pass',detail});console.log('PASS '+name);}catch(e){report.checks.push({name,status:'fail',message:e.message});console.log('FAIL '+name+': '+e.message.slice(0,300));}await writeFile(output+'/backend-checks.json',JSON.stringify(report,null,2));}
const catalog=(await request('/v1/planning/standalone-workouts')).data;
const fiveK=catalog.workouts.find(w=>w.targetDistanceMeters===5000);

await check('omitted optional reason; same plan slot; canonical result and actual phase tree',async()=>{
  await reset();const s=await suggestion();assert.equal(s.primary.durationSeconds,1710);assert.equal(s.editContext.canEditTarget,true);
  const cmd=command(s,edit(1200,'steady'));const r=await apply(cmd);assert.equal(r.status,200,JSON.stringify(r.data));
  assert.equal(r.data.receipt.plannedWorkoutId,s.primary.plannedWorkoutId);assert.equal(r.data.activitySuggestion.primary.workoutEditId,r.data.receipt.workoutEditId);
  assert.equal(r.data.activitySuggestion.primary.workoutRevision,r.data.receipt.revision);assert.equal(r.data.activitySuggestion.primary.durationSeconds,1200);
  const e=await evidence();assert.equal(e.edits.length,1);assert.equal(e.edits[0].reason,null);assert.equal(e.completions.length,0);
  const steps=e.workouts[0].blocks.sort((a,b)=>a.sortOrder-b.sortOrder).flatMap(b=>b.steps);
  assert.deepEqual(steps.map(s=>s.durationSeconds),[300,600,300]);
  assert.deepEqual(steps.map(s=>s.target.rpe),[[1,2],[4,6],[1,2]]);
  const segments=e.edits[0].afterWorkout.effectiveWorkout.guideInstructions.segments;
  assert.deepEqual(segments.map(s=>[s.effort.rpeMin,s.effort.rpeMax]),[[1,2],[4,6],[1,2]]);
  assert.match(segments[1].instruction,/steady/i);
  assert.doesNotMatch(segments[1].instruction,/conversational|easy running/i);
  assert.equal(segments.at(-1).trigger.endSeconds,1200);
  return {plannedIdRetained:true,editLinked:true,reason:null,phaseSeconds:[300,600,300],warmupCooldownTargetsRetained:true};
});
await check('same key replay; mismatched payload rejected; stale revision rejected',async()=>{
  await reset();const s=await suggestion();const cmd=command(s,edit(1200),null);const a=await apply(cmd);assert.equal(a.status,200,JSON.stringify(a.data));
  const replay=await apply({...cmd,reason:undefined});assert.equal(replay.status,200,JSON.stringify(replay.data));assert.equal(replay.data.receipt.workoutEditId,a.data.receipt.workoutEditId);
  assert.equal((await apply({...cmd,change:edit(1500)})).status,409);
  assert.equal((await apply({...cmd,idempotencyKey:randomUUID()})).status,409);
  assert.equal((await evidence()).edits.length,1);return {records:1,normalizedNullAndOmittedReason:true};
});
await check('optional reason is context; no readiness created or forced rest',async()=>{
  await reset();const s=await suggestion();const r=await apply(command(s,edit(1500),'soreness'));assert.equal(r.status,200,JSON.stringify(r.data));
  const e=await evidence();assert.equal(e.edits[0].reason,'soreness');assert.equal(e.edits[0].operation,'edit');assert.equal(e.workouts[0].status,'planned');
  assert.equal(await db.readinessCheckIn.count({where:{userId:'fixture-edit-root'}}),0);return {reason:'soreness',operation:'edit',readinessRows:0};
});
await check('ownership; invalid edit; structured unsupported edit are non-mutating',async()=>{
  await reset();const s=await suggestion();const cmd=command(s,edit(1200));assert.equal((await apply(cmd,'other')).status,409);
  assert.equal((await apply({...cmd,change:edit(1)})).status,400);assert.equal((await evidence()).edits.length,0);
  await reset({structured:true});const structured=await suggestion();assert.equal(structured.editContext.canEditTarget,false);
  assert.equal((await apply(command(structured,edit(1200)))).status,422);assert.equal((await evidence()).edits.length,0);return {ownership409:true,validation400:true,structured422:true};
});
await check('adaptive recovery edits use displayed phases; effort-only materializes original tempo slot',async()=>{
  await reset({tempo:true});const canonical=await suggestion();
  assert.equal(canonical.primary.archetypeId,null);assert.equal(canonical.editContext.canEditTarget,false);assert.equal(canonical.editContext.canEditEffort,false);
  assert.equal((await apply(command(canonical,edit(1200)))).status,422);assert.equal((await evidence()).edits.length,0);
  const seed=(await reset({adaptedRecovery:true})).data;const s=await suggestion();
  assert.equal(s.primary.id,'recovery-run-25');assert.equal(s.primary.plannedWorkoutId,seed.plannedWorkoutId);
  assert.deepEqual(s.decision.safetyFlags,[]);assert.equal(s.editContext.canEditTarget,true);assert.equal(s.editContext.canEditEffort,true);assert.equal(s.editContext.canConvertGoal,false);
  assert.deepEqual(s.primary.effectiveWorkout.steps.map(s=>s.durationSeconds),[300,900,300]);
  assert.equal((await apply(command(s,{operation:'edit',edits:{target:{kind:'distance',meters:3000}}}))).status,422);
  assert.equal((await evidence()).edits.length,0);
  const cmd=command(s,edit(null,'steady'));const saved=await apply(cmd);assert.equal(saved.status,200,JSON.stringify(saved.data));
  const receipt=saved.data.receipt;const fresh=await suggestion();assert.equal(fresh.primary.workoutEditId,receipt.workoutEditId);assert.equal(fresh.primary.durationSeconds,1500);
  assert.equal(fresh.primary.stimulus,'recovery');assert.equal(fresh.editContext.canEditTarget,true);assert.equal(fresh.editContext.canEditEffort,true);assert.equal(fresh.editContext.canConvertGoal,false);
  const e=await evidence();const row=e.workouts.find(w=>w.id===seed.plannedWorkoutId);assert.equal(e.edits.length,1);assert.equal(e.edits[0].operation,'edit');
  assert.equal(row.durationSeconds,1500);assert.equal(row.stimulus,'recovery');assert.equal(row.intensityModel,'rpe');assert.equal(row.isKeyWorkout,false);
  const blocks=row.blocks.sort((a,b)=>a.sortOrder-b.sortOrder);const steps=blocks.flatMap(b=>b.steps);
  assert.deepEqual(blocks.map(b=>b.stimulus),['recovery','recovery','recovery']);assert.deepEqual(steps.map(s=>s.durationSeconds),[300,900,300]);
  assert.deepEqual(steps.map(s=>s.target.rpe),[[2,3],[4,6],[2,3]]);assert.ok(steps.every(s=>!s.target.pace&&!s.target.heartRate));
  assert.equal(e.edits[0].beforeWorkout.structure.stimulus,'threshold');assert.equal(e.edits[0].beforeWorkout.structure.durationSeconds,2520);
  assert.equal(e.edits[0].beforeWorkout.structure.blocks[1].steps[0].target.pace.targetSecondsPerKilometer,330);
  assert.equal(e.edits[0].afterWorkout.suggestion.plannedWorkoutId,seed.plannedWorkoutId);assert.equal(fresh.primary.workoutRevision,receipt.revision);
  const replay=await apply(cmd);assert.equal(replay.status,200);assert.equal(replay.data.receipt.workoutEditId,receipt.workoutEditId);assert.equal((await evidence()).edits.length,1);
  // A later time edit still preserves the displayed recovery warmup and cooldown.
  const shortened=await apply(command(fresh,edit(1200)));assert.equal(shortened.status,200,JSON.stringify(shortened.data));
  const reread=await suggestion();assert.deepEqual(reread.primary.effectiveWorkout.steps.map(s=>s.durationSeconds),[300,600,300]);
  assert.equal(reread.primary.plannedWorkoutId,seed.plannedWorkoutId);
  return {canonicalTempoProtected:true,adaptedRecoveryEditable:true,effortOnlySeconds:1500,oldTempoAudited:true,sameSlot:true,retryOnce:true,timeEditPhaseSeconds:[300,600,300]};
});
await check('adaptive observed baseline uses continuous easy phases instead of original short slot',async()=>{
  const seed=(await reset()).data;const today=new Date();today.setUTCHours(0,0,0,0);
  for(const days of [2,6,10,14,18,22,26]) {
    const startedAt=new Date(today);startedAt.setUTCDate(startedAt.getUTCDate()-days);startedAt.setUTCHours(12);
    await db.activity.create({data:{userId:'fixture-edit-root',type:'running',startedAt,durationSecs:3600,distanceM:10000,avgPace:360}});
  }
  const s=await suggestion();assert.equal(s.primary.archetypeId,'easy-run-observed-baseline');assert.deepEqual(s.decision.safetyFlags,[]);
  assert.equal(s.editContext.canEditTarget,true);assert.equal(s.editContext.canEditEffort,true);assert.equal(s.editContext.canConvertGoal,false);
  assert.deepEqual(s.primary.effectiveWorkout.steps.map(s=>s.durationSeconds),[300,3000,300]);
  const saved=await apply(command(s,edit(2700)));assert.equal(saved.status,200,JSON.stringify(saved.data));
  const fresh=await suggestion();assert.equal(fresh.primary.workoutEditId,saved.data.receipt.workoutEditId);
  assert.deepEqual(fresh.primary.effectiveWorkout.steps.map(s=>s.durationSeconds),[300,2100,300]);assert.equal(fresh.primary.plannedWorkoutId,seed.plannedWorkoutId);
  const e=await evidence();assert.equal(e.workouts[0].durationSeconds,2700);assert.deepEqual(e.workouts[0].blocks.sort((a,b)=>a.sortOrder-b.sortOrder).map(b=>b.durationSeconds),[300,2100,300]);
  return {observedBaselineSeconds:3600,editedSeconds:2700,sameSlot:true,exactPhaseSeconds:[300,2100,300]};
});
await check('real newer readiness invalidates stale command atomically',async()=>{
  await reset();const s=await suggestion();const day=new Date(s.validForDate+'T00:00:00Z');
  await db.readinessCheckIn.create({data:{userId:'fixture-edit-root',date:day,energy:5,soreness:1,sleepQuality:5,stress:1,motivation:5,illnessOrPain:true}});
  assert.equal((await apply(command(s,edit(1200)))).status,409);assert.equal((await evidence()).edits.length,0);return {stale409:true,noEditWritten:true};
});
await check('distance catalog replacement keeps slot and distance goal with estimate',async()=>{
  await reset();const s=await suggestion();const r=await apply(command(s,{operation:'replace',catalogWorkoutId:fiveK.id,catalogVersion:catalog.version}));assert.equal(r.status,200,JSON.stringify(r.data));
  const e=await evidence();assert.equal(e.workouts[0].id,s.primary.plannedWorkoutId);assert.equal(e.workouts[0].distanceMeters,5000);
  assert.equal(r.data.activitySuggestion.primary.distanceMeters,5000);assert.equal(r.data.activitySuggestion.primary.durationSeconds,2100);
  const eff=e.edits[0].afterWorkout.effectiveWorkout;assert.equal(eff.targetDistanceMeters,5000);assert.equal(eff.targetDurationSeconds??null,null);
  return {plannedIdRetained:true,distanceMeters:5000,estimatedSeconds:2100,timeGoal:null};
});
await check('recording older edit after newer replacement uses original snapshot and completion FK',async()=>{
  await reset();const firstSource=await suggestion();const first=await apply(command(firstSource,edit(1200,'veryEasy')));assert.equal(first.status,200,JSON.stringify(first.data));
  const secondSource=await suggestion();const second=await apply(command(secondSource,{operation:'replace',catalogWorkoutId:fiveK.id,catalogVersion:catalog.version}));assert.equal(second.status,200,JSON.stringify(second.data));
  const receipt=first.data.receipt;
  const compiled=await compileLiveCoachContext(db,'fixture-edit-root',{workoutId:receipt.plannedWorkoutId,workoutEditId:receipt.workoutEditId,workoutRevision:receipt.revision,locale:'en',measurementUnitSystem:'metric',sessionIntent:{activityType:'running',goalType:'time'}});
  assert.equal(compiled.context.workout.durationSeconds,1200);assert.equal(compiled.context.workoutExecution.targetDistanceMeters,null);
  assert.equal(compiled.context.workoutExecution.segments.at(-1).trigger.endSeconds,1200);
  const path='/v1/planning/workouts/'+receipt.plannedWorkoutId+'/complete';
  const input={workoutEditId:receipt.workoutEditId,workoutRevision:receipt.revision,completedAt:new Date().toISOString(),durationSeconds:1200,distanceMeters:2800,completionQuality:'completed'};
  await assert.rejects(()=>compileLiveCoachContext(db,'fixture-edit-root',{workoutId:receipt.plannedWorkoutId,workoutEditId:receipt.workoutEditId,workoutRevision:'0'.repeat(64),locale:'en',measurementUnitSystem:'metric',sessionIntent:{activityType:'running',goalType:'time'}}));
  assert.equal((await request(path,{method:'POST',body:{...input,workoutRevision:'0'.repeat(64)}})).status,404);
  assert.equal((await evidence()).completions.length,0);
  const complete=await request(path,{method:'POST',body:input});assert.equal(complete.status,200,JSON.stringify(complete.data));
  assert.equal((await request(path,{method:'POST',body:input})).status,200);
  const e=await evidence();assert.equal(e.completions.length,1);assert.equal(e.completions[0].plannedWorkoutId,receipt.plannedWorkoutId);assert.equal(e.completions[0].workoutEditId,receipt.workoutEditId);assert.equal(e.completions[0].workoutRevision,receipt.revision);assert.equal(e.edits.length,2);
  return {olderGuideSeconds:1200,newerGoalMeters:5000,completionCount:1,originalSlotAndEditFK:true,mismatchedGuideAndCompletionRevisionRejected:true};
});
await check('skip is explicit; same planned slot skipped and no completion created',async()=>{
  await reset();const s=await suggestion();const r=await apply(command(s,{operation:'skip'},'lowEnergy'));assert.equal(r.status,200,JSON.stringify(r.data));
  assert.equal(r.data.activitySuggestion.status,'restRecommended');assert.equal(r.data.activitySuggestion.primary,null);
  const e=await evidence();assert.equal(e.workouts[0].status,'skipped');assert.equal(e.completions.length,0);assert.equal(e.edits[0].operation,'skip');return {skipped:true,completionCount:0};
});
await check('no-plan time edit persists; newer existing Android apply wins',async()=>{
  await reset({planned:false},'standalone');
  // A supported continuous recommendation needs a real recent baseline; an
  // empty new account intentionally receives an uneditable run/walk structure.
  for(const days of [3,10,17]) await db.activity.create({data:{userId:'fixture-edit-standalone',type:'running',startedAt:new Date(Date.now()-days*86400000),durationSecs:3600,distanceM:10000,avgPace:360}});
  const s=await suggestion('standalone');assert.equal(s.primary.plannedWorkoutId??null,null);assert.equal(s.editContext.canEditTarget,true);
  const r=await apply(command(s,edit(Math.max(s.editContext.minimumDurationSeconds,900))),'standalone');assert.equal(r.status,200,JSON.stringify(r.data));
  assert.equal(r.data.receipt.plannedWorkoutId,null);const selected=await suggestion('standalone');assert.equal(selected.primary.workoutEditId,r.data.receipt.workoutEditId);
  const old={idempotencyKey:randomUUID(),workoutId:selected.primary.id,suggestionId:selected.primary.id,validForDate:selected.validForDate,choice:'tired',minutes:15};
  const legacy=await request('/v1/personalization/adjustments/apply',{method:'POST',body:old,account:'standalone'});assert.equal(legacy.status,200,JSON.stringify(legacy.data));
  const newer=await suggestion('standalone');assert.equal(newer.primary.durationMinutes,15);assert.equal(newer.primary.workoutEditId??null,null);return {standaloneNoFakePlan:true,newerExistingConsumerHonored:true};
});
await check('supported flat continuous goal converts time to distance and back',async()=>{
  const seeded=(await reset()).data;await db.workoutBlock.deleteMany({where:{plannedWorkoutId:seeded.plannedWorkoutId}});
  await db.plannedWorkout.update({where:{id:seeded.plannedWorkoutId},data:{durationSeconds:1800,distanceMeters:null,blocks:{create:{sortOrder:0,blockType:'main',modality:'run',stimulus:'easyAerobic',durationSeconds:1800,steps:{create:{sortOrder:0,kind:'easy',label:'Easy run',durationSeconds:1800,target:{rpe:[2,4]}}}}}}});
  const s=await suggestion();assert.equal(s.editContext.canConvertGoal,true);
  const first=await apply(command(s,{operation:'edit',edits:{target:{kind:'distance',meters:2500}}}));assert.equal(first.status,200,JSON.stringify(first.data));assert.equal(first.data.activitySuggestion.primary.distanceMeters,2500);assert.equal(first.data.activitySuggestion.primary.durationSeconds,1050);
  const fresh=await suggestion();const second=await apply(command(fresh,edit(1800)));assert.equal(second.status,200,JSON.stringify(second.data));assert.equal(second.data.activitySuggestion.primary.distanceMeters,null);assert.equal(second.data.activitySuggestion.primary.durationSeconds,1800);
  const e=await evidence();assert.equal(e.workouts[0].id,seeded.plannedWorkoutId);assert.equal(e.workouts[0].blocks[0].distanceMeters,null);assert.equal(e.edits.length,2);return {timeToDistance:true,distanceToTime:true,samePlannedSlot:true};
});
await check('response lost after commit retries without duplicate mutation',async()=>{
  await reset();const s=await suggestion();const cmd=command(s,edit(1200));await request('/__fixture/drop-response-next',{method:'POST',body:{}});
  assert.equal((await apply(cmd)).status,503);assert.equal((await evidence()).edits.length,1);
  const r=await apply(cmd);assert.equal(r.status,200,JSON.stringify(r.data));assert.equal((await evidence()).edits.length,1);return {response503AfterCommit:true,retrySuccess:true,records:1};
});
await check('concurrent identical Apply requests commit once and replay receipt',async()=>{
  await reset();const s=await suggestion();const cmd=command(s,edit(1200));
  const results=await Promise.all([apply(cmd),apply(cmd)]);assert.ok(results.some(r=>r.status===200));
  const success=results.find(r=>r.status===200);const retry=await apply(cmd);assert.equal(retry.status,200,JSON.stringify(retry.data));assert.equal(retry.data.receipt.workoutEditId,success.data.receipt.workoutEditId);assert.equal((await evidence()).edits.length,1);
  return {initialStatuses:results.map(r=>r.status),retry200:true,records:1};
});
await check('competing edits from one revision cannot both commit',async()=>{
  await reset();const s=await suggestion();const commands=[command(s,edit(1200)),command(s,edit(1500))];
  const results=await Promise.all(commands.map(c=>apply(c)));assert.equal(results.filter(r=>r.status===200).length,1);assert.equal((await evidence()).edits.length,1);
  return {initialStatuses:results.map(r=>r.status),committed:1};
});
await check('existing suggestion date/status and unedited catalog provenance remain intact',async()=>{
  await reset();const s=await suggestion();assert.equal(s.primary.catalogWorkout??null,null);assert.ok(s.primary.effectiveWorkout);assert.deepEqual(s.primary.effectiveWorkout.steps.map(s=>s.durationSeconds),[300,1110,300]);
  const tomorrow=new Date();tomorrow.setUTCDate(tomorrow.getUTCDate()+1);const future=await buildActivitySuggestion('fixture-edit-root','reassessing',tomorrow);
  assert.equal(future.validForDate,tomorrow.toISOString().slice(0,10));assert.equal(future.planningStatus,'reassessing');
  return {originalCatalogProvenance:true,realPhases:true,dateForwarded:true,statusForwarded:true};
});
await check('later normal readiness retains actual planned edit provenance; mismatched structure does not',async()=>{
  await reset();const s=await suggestion();const a=await apply(command(s,edit(1200,'steady')));assert.equal(a.status,200,JSON.stringify(a.data));const receipt=a.data.receipt;
  await db.readinessCheckIn.create({data:{userId:'fixture-edit-root',date:new Date(s.validForDate+'T00:00:00Z'),energy:3,soreness:1,sleepQuality:3,stress:1,motivation:3,illnessOrPain:false}});
  const selected=await suggestion();assert.equal(selected.primary.durationSeconds,1200);assert.equal(selected.primary.workoutEditId,receipt.workoutEditId);assert.equal(selected.primary.workoutRevision,receipt.revision);
  const compiled=await compileLiveCoachContext(db,'fixture-edit-root',{workoutId:receipt.plannedWorkoutId,workoutEditId:selected.primary.workoutEditId,workoutRevision:selected.primary.workoutRevision,locale:'en',measurementUnitSystem:'metric',sessionIntent:{activityType:'running',goalType:'time'}});
  assert.equal(compiled.context.workoutExecution.segments.at(-1).trigger.endSeconds,1200);
  const done=await request('/v1/planning/workouts/'+receipt.plannedWorkoutId+'/complete',{method:'POST',body:{workoutEditId:selected.primary.workoutEditId,workoutRevision:selected.primary.workoutRevision,durationSeconds:1200,completionQuality:'completed'}});assert.equal(done.status,200,JSON.stringify(done.data));
  assert.equal((await evidence()).completions[0].workoutEditId,receipt.workoutEditId);
  await reset();const replacementSource=await suggestion();const replacement=await apply(command(replacementSource,{operation:'replace',catalogWorkoutId:fiveK.id,catalogVersion:catalog.version}));assert.equal(replacement.status,200);
  await db.readinessCheckIn.create({data:{userId:'fixture-edit-root',date:new Date(replacementSource.validForDate+'T00:00:00Z'),energy:3,soreness:1,sleepQuality:3,stress:1,motivation:3,illnessOrPain:false}});
  const replaced=await suggestion();assert.equal(replaced.primary.workoutEditId,replacement.data.receipt.workoutEditId);assert.equal(replaced.primary.workoutRevision,replacement.data.receipt.revision);assert.equal(replaced.primary.distanceMeters,5000);
  await reset();const fresh=await suggestion();assert.equal((await apply(command(fresh,edit(1200)))).status,200);
  const block=await db.workoutBlock.findFirst({where:{plannedWorkoutId:fresh.primary.plannedWorkoutId,blockType:'main'},include:{steps:true}});
  assert.ok(block);await db.workoutStep.update({where:{id:block.steps[0].id},data:{durationSeconds:block.steps[0].durationSeconds+60}});
  await db.readinessCheckIn.create({data:{userId:'fixture-edit-root',date:new Date(fresh.validForDate+'T00:00:00Z'),energy:3,soreness:1,sleepQuality:3,stress:1,motivation:3,illnessOrPain:false}});
  assert.equal((await suggestion()).primary?.workoutEditId??null,null);
  return {normalReadinessPreservesEdit:true,catalogReplacementProvenance:true,guideSeconds:1200,completionEditFK:true,mismatchedActualPhaseTreeRejected:true};
});
await check('catalog replacement clears source run-walk state and preserves its own pace restrictions',async()=>{
  await reset({planned:false},'standalone');const s=await suggestion('standalone');assert.equal(s.editContext.canEditTarget,false);
  const easy=catalog.workouts.find(w=>w.sport==='run'&&w.title==='Easy 30');assert.ok(easy);
  const r=await apply(command(s,{operation:'replace',catalogWorkoutId:easy.id,catalogVersion:catalog.version}),'standalone');assert.equal(r.status,200,JSON.stringify(r.data));
  assert.notEqual(r.data.activitySuggestion.primary.runWalk,true);
  const selected=await suggestion('standalone');assert.equal(selected.primary.workoutEditId,r.data.receipt.workoutEditId);
  assert.ok(selected.primary.effectiveWorkout.steps.some(s=>s.coachingTarget?.pace));
  assert.equal(selected.editContext.canEditTarget,false);assert.equal(selected.editContext.limitation,'unsupportedTargets');
  return {sourceRunWalkCleared:true,selectedPaceTargetsRetained:true,unsupportedEditExplicit:true,provenanceRetained:true};
});
report.summary={passed:report.checks.filter(x=>x.status==='pass').length,failed:report.checks.filter(x=>x.status==='fail').length};
await writeFile(output+'/backend-checks.json',JSON.stringify(report,null,2));
console.log(JSON.stringify(report.summary));await db.$disconnect();process.exitCode=report.summary.failed||report.summary.passed===0?1:0;
