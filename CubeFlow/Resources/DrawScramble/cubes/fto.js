const Canvas = require('canvas');
const engine = require('../fto_engine');
const raster = require('../raster_geometry');

// Independently unfolded from the eight faces' shared corner incidences.
// Vertex order is native facelet corners 0,4,8; each triangular face has 9 stickers.
const h = Math.sqrt(3) * 60;
const vertices = [
    [[180,0],[120,h],[240,h]], [[0,3*h],[120,3*h],[60,2*h]],
    [[180,2*h],[120,h],[60,2*h]], [[180,2*h],[120,3*h],[240,3*h]],
    [[180,2*h],[60,2*h],[120,3*h]], [[180,2*h],[240,h],[120,h]],
    [[180,0],[60,0],[120,h]], [[180,0],[240,h],[300,0]]
];
const defaults = ['#ffffff','#44ee00','#aaaaaa','#ff8000','#f4f400','#2266ff','#ff0000','#8800dd'];
function point(v, row, column) {
    return [0,1].map(axis => (1-row/3)*v[0][axis] + (row-column)/3*v[1][axis] + column/3*v[2][axis]);
}
function polygons() {
    const result = [];
    vertices.forEach((v,face) => {
        let sticker = 0;
        for (let row=0;row<3;row++) for(let col=0;col<=row;col++) {
            result.push({face,index:face*9+sticker++, points:[point(v,row,col),point(v,row+1,col),point(v,row+1,col+1)]});
            if(col<row) result.push({face,index:face*9+sticker++,points:[point(v,row,col),point(v,row,col+1),point(v,row+1,col+1)]});
        }
    });
    return result;
}
function genImage(scramble, scheme) {
    const colors = scheme==='default' ? defaults : scheme.match(/#[0-9a-fA-F]{6}/g);
    if (!colors || colors.length!==8) throw new Error('FTO needs eight face colors');
    const stickers = engine.state(scramble);
    const canvas = new Canvas.createCanvas(308,3*h+8), ctx=canvas.getContext('2d');
    const fit=raster.fitted(canvas.width,canvas.height,300,3*h,ctx.getTransform().a);
    ctx.setTransform(fit.scale,0,0,fit.scale,fit.x,fit.y);
    const edges = new Map();
    for(const polygon of polygons()) {
        ctx.beginPath(); polygon.points.forEach((p,i) => i ? ctx.lineTo(...p) : ctx.moveTo(...p));
        ctx.closePath();ctx.fillStyle=colors[stickers[polygon.index]];ctx.fill();
        for(let i=0;i<3;i++) {
            const a=polygon.points[i],b=polygon.points[(i+1)%3];
            const key=[a,b].map(p=>p.map(x=>x.toFixed(5)).join(',')).sort().join('|');edges.set(key,[a,b]);
        }
    }
    ctx.beginPath(); for(const [a,b] of edges.values()) {ctx.moveTo(...a);ctx.lineTo(...b);}
    ctx.strokeStyle='#000000';ctx.lineJoin='round';ctx.lineWidth=fit.stroke/fit.scale;ctx.stroke();
    return canvas.toBuffer();
}
module.exports={genImage,polygons,vertices,width:308,height:3*h+8};
