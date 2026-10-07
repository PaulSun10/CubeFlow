const fs=require('fs'),path=require('path');
const engine=require(process.cwd()+'/CubeFlow/Resources/DrawScramble/fto_engine.js');
function steps(s){const r=[];s.split('/').forEach((seg,i)=>{if(i)r.push('/');seg=seg.trim().replace(/^\(/,'').replace(/\)$/,'');if(!seg)return; const p=seg.split(',').map(x=>Number(x.trim()));if(p.length!==2||p.some(x=>!Number.isInteger(x)||Math.abs(x)>6))throw Error(s);r.push(p);});return r;}
const fmt=s=>s.map(x=>x==='/'?'/':`(${x[0]},${x[1]})`).join(' ');
function apply(seq,state={top:[0,1,1,2,3,3,4,5,5,6,7,7],bottom:[9,9,8,11,11,10,13,13,12,15,15,14],m:0}) {for(const s of seq){if(s==='/'){if([state.top,state.bottom].some(a=>a[0]===a[11]||a[5]===a[6]))throw Error('illegal slice '+fmt(seq));const t=state.top.slice(6);state.top.splice(6,6,...state.bottom.slice(0,6));state.bottom.splice(0,6,...t);state.m^=1;}else{for(const [a,n]of[[state.top,s[0]],[state.bottom,s[1]]]){const k=(n+12)%12;a.push(...a.splice(0,k));}}}return state;}

if (!process.argv[2]) throw Error('Usage: node tools/ContentValidation/generate-reference-content.cjs <pinned PBL init.json>');
const src=JSON.parse(fs.readFileSync(process.argv[2]));
let pbl=[];let failures=[];
for(const c of src){try{const seq=steps(c.setup),inv=seq.slice().reverse().map(x=>x==='/'?'/':x.map(v=>-v));const state=apply(seq);if(JSON.stringify(apply(inv,structuredClone(state)))!==JSON.stringify(apply([])))throw Error('inverse');let id=c.top.toLowerCase()+'_'+c.bottom.toLowerCase().replace(/-/g,'solved');pbl.push({id,displayName:`${c.top} / ${c.bottom}`,name:`${c.top} / ${c.bottom}`,group:c.top,subgroup:c.top,imageKey:'sq1pbl_'+id,recognition:'',notes:'Recognition setup from MIT PBL-Manager. Reference solution is the reversed setup, not a curated or speed-optimized algorithm.',setup:fmt(seq),algorithms:[{id:id+'-reference',notation:fmt(inv),isPrimary:true,source:'Inverse setup reference (PBL-Manager, MIT)',tags:['reference','inverse-setup']}],nativeState:state});}catch(e){failures.push([c.top,c.bottom,e.message]);}}
console.log('PBL',pbl.length,'failures',failures.slice(0,5));if(failures.length)throw Error(failures.length+' PBL failures');
fs.writeFileSync('CubeFlow/Resources/Algs/sq1pbl.json',JSON.stringify({puzzle:'SQ1',set:'SQ1PBL',version:1,source:'PBL-Manager (MIT); inverse-setup references, not curated speed algorithms',cases:pbl},null,2)+'\n');
const cases=[];
for(let f=0;f<8;f++)for(let direction=0;direction<2;direction++) {
 const fc=new engine.cubie();
 fc.ep=Array.from(engine.cubie.moveCube[f*2+direction].ep);
 const desired=fc.toFaceCube(),solution=engine.solveState(desired).trim(),setup=engine.inverse(solution);
 const actual=engine.state(setup), colorMap={};for(let face=0;face<8;face++)colorMap[actual[face*9+2]]=face;
 if(!actual.every((value,index)=>colorMap[value]===desired[index])||JSON.stringify(engine.state(setup+' '+solution))!==JSON.stringify(engine.state('')))throw Error('FTO reference verification failed');
 const id=engine.faces[f].toLowerCase()+(direction?'_ccw':'_cw'),name=engine.faces[f]+(direction?' counterclockwise':' clockwise');
 cases.push({id,displayName:name,name,group:engine.faces[f],subgroup:engine.faces[f],imageKey:'ftoedges_'+id,recognition:'Cycle the three edges around the named face; all other pieces are solved relative to the face palette.',notes:'Solver-generated exact edge-cycle reference, up to global face-color orientation. Not a curated speed algorithm or a complete Bencisco/Nautilus set.',setup,algorithms:[{id:id+'-reference',notation:solution,isPrimary:true,source:'Chen Shuang MIT FTO solver; generated reference',tags:['reference','edge-3-cycle']}],nativeState:actual});
}
fs.writeFileSync('CubeFlow/Resources/Algs/ftoedges.json',JSON.stringify({puzzle:'FTO',set:'FTOEDGES',version:1,source:'Chen Shuang (MIT), exact edge-cycle reference solutions generated and verified by CubeFlow',cases},null,2)+'\n');console.log('FTO',cases.length);
