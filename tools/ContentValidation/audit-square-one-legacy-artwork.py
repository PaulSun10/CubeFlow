"""Read-only geometry audit of frozen 150x300 legacy diagrams; requires Pillow.

Measure black radial piece separators (and the red slice guide) on both layer
views. Native sector order runs opposite positive screen angle. No artwork is
edited, resampled, or imported; the output is geometry plus asset hashes.
"""
from PIL import Image
import math,json,hashlib,sys
from pathlib import Path
rows=json.loads(Path('CubeFlow/Resources/Algs/sq1cs.json').read_text())['cases']
def cycle(b):return min(b[i:]+b[:i]for i in range(12))
results=[];uncertain=[]
for c in rows:
 asset=Path('CubeFlow/Resources/Algs/SQ1CSImages/'+c['imageKey']+'.png')
 im=Image.open(asset).convert('RGBA');layers=[]
 assert im.size==(150,300),(c['id'],im.size)
 for cy in[74.5,224.5]:
  scores=[]
  for a in range(12):
   th=math.radians(a*30);hits=0
   for r in range(15,42):
    near=[]
    for d in[-1.5,-1,-.5,0,.5,1,1.5]:
     x=round(74.5+r*math.cos(th)-d*math.sin(th));y=round(cy+r*math.sin(th)+d*math.cos(th));R,G,B,A=im.getpixel((x,y));near.append(A>0 and(max(R,G,B)<20 or(R>180 and G<30 and B<30)))
    hits+=any(near)
   scores.append(hits)
  if any(5<n<12 for n in scores):uncertain.append((c['id'],cy,scores))
  ring=''.join('1'if n>12 else'0'for n in scores)
  assert '00'not in ring+ring[0],(c['id'],ring,scores)
  layers.append(cycle(ring[::-1])) # image positive screen angle vs native negative angle
 results.append({'id':c['id'],'name':c['name'],'shapeID':'|'.join(layers),
                 'assetSHA256':hashlib.sha256(asset.read_bytes()).hexdigest()})
assert not uncertain,uncertain
print('uncertain',uncertain)
print('unique',len(set(r['shapeID']for r in results)))
Path(sys.argv[1] if len(sys.argv)>1 else 'tools/ContentValidation/square-one-legacy-artwork.json').write_text(json.dumps(results,indent=2)+'\n')
