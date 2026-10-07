// CubeFlow's independent sector model; no imported algorithm implementation.
const solved=()=>({top:[0,1,1,2,3,3,4,5,5,6,7,7],bottom:[9,9,8,11,11,10,13,13,12,15,15,14],m:0});
function steps(s){const result=[];for(const [i,part] of s.split('/').entries()){if(i)result.push('/');const text=part.trim().replace(/^\(/,'').replace(/\)$/,'');if(!text)continue;const pair=text.split(',').map(Number);if(pair.length!==2||pair.some(v=>!Number.isInteger(v)||Math.abs(v)>6))throw Error('Bad notation');result.push(pair);}return result;}
function apply(seq,state=solved()){for(const step of seq){if(step==='/'){if([state.top,state.bottom].some(a=>a[0]===a[11]||a[5]===a[6]))throw Error('Slice splits corner');const t=state.top.slice(6);state.top.splice(6,6,...state.bottom.slice(0,6));state.bottom.splice(0,6,...t);state.m^=1;}else{for(const [a,n] of [[state.top,step[0]],[state.bottom,step[1]]]){const k=(n+12)%12;a.push(...a.splice(0,k));}}}return state;}
function format(seq){const compact=[];const norm=n=>((n+18)%12)-6;for(const step of seq){if(step==='/'){compact.push('/');continue;}const last=compact.at(-1);if(Array.isArray(last)){last[0]=norm(last[0]+step[0]);last[1]=norm(last[1]+step[1]);}else compact.push(step.map(norm));}return compact.filter(s=>s==='/'||s.some(n=>n)).map(s=>s==='/'?'/':`(${s[0]},${s[1]})`).join(' ');}
const inverse=seq=>seq.slice().reverse().map(s=>s==='/'?'/':s.map(n=>-n));
const key=s=>s.top.join(',')+'|'+s.bottom.join(',');
module.exports={solved,steps,apply,format,inverse,key};
