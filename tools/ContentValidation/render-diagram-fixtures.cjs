// Offline real-browser raster checks using the same backing-canvas/compositing contract as WKWebView.
const fs=require('fs'),path=require('path');
const root='CubeFlow/Resources/DrawScramble',sources={};
function visit(dir){for(const f of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,f.name);if(f.isDirectory())visit(p);else if(p.endsWith('.js'))sources['./'+path.relative(root,p).replaceAll('\\','/')]=fs.readFileSync(p,'utf8');}}
visit(root);
const cases=JSON.parse(fs.readFileSync('CubeFlow/Resources/Algs/ftoedges.json')).cases;
const runtime=()=>{
 const cache={};let target=320,dpr=2,legacy=false;
 const shim={createCanvas:function(w,h){const viewportHeight=target*h/w,fit=Math.min(target/w,viewportHeight/h),canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.floor(w*fit*dpr));const scale=canvas.width/w;canvas.height=Math.max(1,Math.ceil(h*scale));const native=canvas.getContext.bind(canvas);let prepared=false;canvas.getContext=(type)=>{const c=native(type);if(type==='2d'&&!prepared){c.scale(scale,scale);
   if(legacy && globalThis.cubeFlowDiagramStrokeScale>1){
    const inset=c.lineWidth*globalThis.cubeFlowDiagramStrokeScale*c.miterLimit/2+1/scale;c.translate(inset,inset);c.scale((w-2*inset)/w,(h-2*inset)/h);
    let prototype=Object.getPrototypeOf(c),descriptor;
    while(prototype&&!descriptor){descriptor=Object.getOwnPropertyDescriptor(prototype,'lineWidth');prototype=Object.getPrototypeOf(prototype);}
    if(descriptor)Object.defineProperty(c,'lineWidth',{get:()=>descriptor.get.call(c)/globalThis.cubeFlowDiagramStrokeScale,set:value=>descriptor.set.call(c,value*globalThis.cubeFlowDiagramStrokeScale)});
    c.lineWidth=1;
   }
   prepared=true;}return c;};canvas.toBuffer=()=>canvas;return canvas;}};
 function load(name){if(name==='canvas')return shim;if(cache[name])return cache[name].exports;const m={exports:{}};cache[name]=m;const parent=name.slice(0,name.lastIndexOf('/'));const req=id=>{if(id==='canvas')return shim;const parts=(parent+'/'+id).split('/'),out=[];for(const p of parts){if(p==='..')out.pop();else if(p&&p!=='.')out.push(p);}return load('./'+out.join('/')+(id.endsWith('.js')?'':'.js'));};new Function('require','module','exports',sources[name])(req,m,m.exports);return m.exports;}
 const main=load('./main.js'),results=[],images={};
 if(!nxnOnly){ const fto=load('./cubes/fto.js'),polygons=fto.polygons();
 if(polygons.length!==72||new Set(polygons.map(p=>p.index)).size!==72)throw Error('FTO sticker coverage');
 const area=p=>Math.abs((p[1][0]-p[0][0])*(p[2][1]-p[0][1])-(p[2][0]-p[0][0])*(p[1][1]-p[0][1]))/2;
 const expectedArea=400*Math.sqrt(3);
 for(const p of polygons)if(Math.abs(area(p.points)-expectedArea)>1e-6)throw Error('Unequal FTO sticker area');
 // Interior points cannot belong to another sticker, including across unfolded faces.
 function contains(p,x){const cross=(a,b)=> (b[0]-a[0])*(x[1]-a[1])-(b[1]-a[1])*(x[0]-a[0]);const signs=p.map((a,i)=>cross(a,p[(i+1)%3]));return signs.every(v=>v>1e-7)||signs.every(v=>v< -1e-7);}
 for(const p of polygons){const center=[0,1].map(a=>p.points.reduce((s,v)=>s+v[a],0)/3);if(polygons.filter(q=>contains(q.points,center)).length!==1)throw Error('FTO overlapping net');}
 } let nxnStrokeChecks=0,nxnCornerChecks=0;
 function inspectStroke(canvas,n){const ctx=canvas.getContext('2d'),t=ctx.getTransform(),pixels=ctx.getImageData(0,0,canvas.width,canvas.height).data;const stroke=Math.round(ctx.lineWidth*t.a),raw=n*30*10/9*t.a+t.e,y=Math.floor(15*t.a+t.f);const black=x=>x>=0&&x<canvas.width&&pixels[(y*canvas.width+x)*4+3]>=250&&[0,1,2].every(c=>pixels[(y*canvas.width+x)*4+c]<16);
 for(let edge=0;edge<=n;edge++){const center=Math.round(raw+edge*30*t.a-stroke/2)+stroke/2;let x=Math.floor(center),left=x,right=x;if(!black(x))throw Error('Missing NxN grid edge '+JSON.stringify({n,target,dpr,edge,center,x,y,stroke,raw,transform:[t.a,t.e,t.f],pixel:Array.from(pixels.slice((y*canvas.width+x)*4,(y*canvas.width+x)*4+4))}));while(black(left-1))left--;while(black(right+1))right++;if(right-left+1!==stroke)throw Error('Unequal NxN outer/internal stroke '+n+' '+edge+': '+(right-left+1)+'/'+stroke);nxnStrokeChecks++;}
for(const origin of [[n,n*2],[0,n],[n*3,n],[n,0],[n*2,n],[n,n]])for(const [dx,dy] of [[0,0],[n,0],[n,n],[0,n]]){
 const centerX=Math.round(((origin[0]*10/9+dx)*30*t.a+t.e)-stroke/2)+stroke/2;
 const centerY=Math.round(((origin[1]*10/9+dy)*30*t.a+t.f)-stroke/2)+stroke/2;
 const x=Math.round(centerX+(dx?stroke/2-1:-stroke/2)),y=Math.round(centerY+(dy?stroke/2-1:-stroke/2));
 const p=(y*canvas.width+x)*4;
 if(pixels[p+3]<250||pixels[p]>16||pixels[p+1]>16||pixels[p+2]>16)throw Error('Open/seamed NxN contour corner '+JSON.stringify({n,target,dpr,stroke,x,y}));
 nxnCornerChecks++;
}
}
function inspect(canvas,key,legacyThin=false){const c=canvas.getContext('2d'),data=c.getImageData(0,0,canvas.width,canvas.height).data,w=canvas.width,h=canvas.height;const a=(x,y)=>data[(y*w+x)*4+3];let edge=0,minX=w,minY=h,maxX=-1,maxY=-1;for(let y=0;y<h;y++)for(let x=0;x<w;x++){if(!a(x,y))continue;if(!x||!y||x===w-1||y===h-1)edge++;minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);}if((edge&&!legacyThin)||maxX<0)throw Error(key+' clipped/empty raster');
 // Actual CSS-constrained img -> canvas composition, both backgrounds. Padding must survive the final fit.
 for(const dark of [false,true]){const composed=document.createElement('canvas');composed.width=Math.round(target*dpr);composed.height=Math.ceil(composed.width*h/w);const cc=composed.getContext('2d');cc.fillStyle=dark?'#161616':'#ffffff';cc.fillRect(0,0,composed.width,composed.height);cc.drawImage(canvas,0,0,composed.width,composed.height);const px=cc.getImageData(0,0,composed.width,composed.height).data;const bg=dark?22:255;for(const i of [0,(composed.width-1)*4,(composed.height-1)*composed.width*4])if(px[i]!==bg&&!legacyThin)throw Error('composited boundary clipped '+key);}
 results.push({key,w,h,bounds:[minX,minY,maxX,maxY],edge});}
 for(const strokeScale of [1,1.6,2.6])for(const size of [52,160,320])for(const scale of [1,2,3]){globalThis.cubeFlowDiagramStrokeScale=strokeScale;target=size;dpr=scale;for(const n of [2,3,4,5,6,7]){const canvas=main.genImage(String(n*111),"R U F2 D' L B",'default');inspect(canvas,`${n}x${n}@${size}/${scale}/stroke=${strokeScale}`);if(size>=160)inspectStroke(canvas,n);}if(!nxnOnly)inspect(main.genImage('fto',"U R' F BR D' BL U' L B'",'default'),`fto@${size}/${scale}/stroke=${strokeScale}`);}
 if(!nxnOnly){ legacy=true;
 for(const strokeScale of [1,1.6,2.6])for(const size of [52,160,320])for(const scale of [1,2,3]){
  globalThis.cubeFlowDiagramStrokeScale=strokeScale;target=size;dpr=scale;
  for(const puzzle of ['clk','megaminx','pyraminx','skewb','squareone']){
   // Legacy modules allocate their canvas at require-time. Match a fresh WK document.
   for(const key of Object.keys(cache))delete cache[key];
   inspect(load('./main.js').genImage(puzzle,'','default'),`${puzzle}@${size}/${scale}/stroke=${strokeScale}`,strokeScale===1);
  }
 }
 legacy=false;
 globalThis.cubeFlowDiagramStrokeScale=1;target=308;dpr=2;for(const c of cases){const canvas=main.genImage('fto',c.setup,'default');inspect(canvas,c.id);images[c.imageKey]=canvas.toDataURL('image/png');}
 } document.getElementById('result').textContent=JSON.stringify({results,images,nxnStrokeChecks,nxnCornerChecks,ftoGeometryChecks:nxnOnly?0:72});document.getElementById('summary').textContent=JSON.stringify({renders:results.length,nxnStrokeChecks,nxnCornerChecks});
 document.body.style.background='#161616';document.body.style.color='white';
 const grid=document.createElement('div');grid.style='display:grid;grid-template-columns:repeat(4,180px);gap:12px';for(const c of (nxnOnly?[]:cases)){let div=document.createElement('div');div.style='background:#fff;padding:8px;color:#000';let img=document.createElement('img');img.src=images[c.imageKey];img.style='width:160px;height:auto';div.append(img,document.createTextNode(c.displayName));grid.append(div);}document.body.append(grid);
};
fs.writeFileSync(process.argv[2]||'/tmp/cubeflow-depth-diagrams.html',`<!doctype html><meta charset="utf-8"><pre id="summary"></pre><pre id="result" hidden></pre><script>const nxnOnly=${process.argv.includes("--nxn-only")},sources=${JSON.stringify(sources)},cases=${JSON.stringify(cases)};try{(${runtime.toString()})();}catch(e){document.getElementById('result').textContent=document.getElementById('summary').textContent=JSON.stringify({error:e.stack});}</script>`);
