import fs from 'node:fs';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
if (!process.argv[2]) throw Error('Pass path to externally installed cubing 0.63.8 dist/lib/cubing/puzzles/index.js');
const {puzzles} = await import(pathToFileURL(process.argv[2]).href);
const require=createRequire(import.meta.url),engine=require(process.cwd()+'/CubeFlow/Resources/DrawScramble/fto_engine.js');
const kp=await puzzles.fto.kpuzzle(),svg=await puzzles.fto.svg();
const hexFace={'#ffffff':0,'#44ee00':1,'#aaaaaa':2,'#ff8000':3,'#f4f400':4,'#2266ff':5,'red':6,'#ff0000':6,'#8800dd':7};
const stickers=[...svg.matchAll(/id="(C4RNER|EDGES|CENTERS)-l(\d+)-o(\d+)"[^>]*style="fill: (#[0-9a-fA-F]+|red);"/g)].map(m=>({orbit:m[1],pos:+m[2],ori:+m[3],face:hexFace[m[4].toLowerCase()]}));
const lookup={};for(const s of stickers)lookup[`${s.orbit}:${s.pos}:${s.ori}`]=s.face;
if(stickers.length!==72)throw Error('Reference SVG not 72 stickers');
const nativeType=i=>[0,4,8].includes(i%9)?'C4RNER':[1,3,6].includes(i%9)?'EDGES':'CENTERS';
const vectors=['',...engine.faces.flatMap(f=>[f,f+"'"]),"U R' F BR D' BL U' L B'",...JSON.parse(fs.readFileSync('CubeFlow/Resources/Algs/ftoedges.json')).cases.map(c=>c.setup)];
let passed=0;
for(const alg of vectors){const p=kp.defaultPattern().applyAlg(alg).patternData,actual=engine.state(alg),ref={};
 for(const s of stickers){const orbit=p[s.orbit],num=kp.definition.orbits.find(o=>o.orbitName===s.orbit).numOrientations,source=orbit.pieces[s.pos],orientation=(s.ori-orbit.orientation[s.pos]+num)%num;const color=lookup[`${s.orbit}:${source}:${orientation}`];if(color===undefined)throw Error('Missing ref color');const key=`${s.face}:${s.orbit}:${color}`;ref[key]=(ref[key]||0)+1;}
 const count={};actual.forEach((color,i)=>{const key=`${Math.floor(i/9)}:${nativeType(i)}:${color}`;count[key]=(count[key]||0)+1;});
 const sorted=o=>JSON.stringify(Object.entries(o).sort());if(sorted(ref)!==sorted(count)){console.log('Mismatch',alg,ref,count);throw Error('Independent face/orbit color census mismatch');}
 passed++;
}
console.log('Independent cubing.js 0.63.8 puzzle-geometry/KPuzzle census vectors:',passed);

function referenceColors(alg){const p=kp.defaultPattern().applyAlg(alg).patternData;return stickers.map(s=>{const orbit=p[s.orbit],num=kp.definition.orbits.find(o=>o.orbitName===s.orbit).numOrientations;return lookup[`${s.orbit}:${orbit.pieces[s.pos]}:${(s.ori-orbit.orientation[s.pos]+num)%num}`];});}
const calibration=[];let seed=24681357;for(let i=0;i<64;i++){let seq=[];for(let j=0;j<25;j++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;seq.push(engine.faces[seed%8]+((seed>>>8)%2?"'":""));}calibration.push(seq.join(' '));}
const native=calibration.map(alg=>engine.state(alg)),ref=calibration.map(referenceColors),mapping=[];
for(let i=0;i<72;i++){const matches=stickers.map((s,j)=>({s,j})).filter(({s,j})=>s.face===Math.floor(i/9)&&s.orbit===nativeType(i)&&ref.every((row,k)=>row[j]===native[k][i])).map(({j})=>j);if(matches.length!==1)throw Error('nonunique independent sticker mapping '+i+': '+matches);mapping.push(matches[0]);}
const fixtures=vectors.slice(0,18).map(alg=>({alg,facelets:mapping.map(j=>referenceColors(alg)[j])}));
for(const alg of vectors.concat(calibration)){const expected=mapping.map(j=>referenceColors(alg)[j]);if(expected.some((v,i)=>v!==engine.state(alg)[i]))throw Error('Full independent sticker mismatch '+alg);}
console.log('Independent full 72-sticker comparisons:',vectors.length+calibration.length);
const fixturePath='CubeFlow/Resources/Algs/fto_protocol_vectors.json';
if (process.argv.includes('--write-fixtures')) {
 fs.writeFileSync(fixturePath,JSON.stringify({source:'Independent cubing.js 0.63.8 puzzle-geometry reference, not its solver. Sticker correspondence calibrated on 64 deterministic mixed sequences; every sticker cross-checked.',vectors:fixtures},null,2)+'\n');
} else if (JSON.stringify(JSON.parse(fs.readFileSync(fixturePath)).vectors)!==JSON.stringify(fixtures)) {
 throw Error('Bundled independent FTO fixtures differ');
}
