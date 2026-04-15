"use strict";
var Canvas = require("canvas")

var squanCanvas, ctx;
var hsq3 = Math.sqrt(3) / 2;
var PI = Math.PI;

function Rotate(arr, theta) {
    return Transform(arr, [Math.cos(theta), -Math.sin(theta), 0, Math.sin(theta), Math.cos(theta), 0]);
}

function Transform(arr) {
    var ret;
    for (var i = 1; i < arguments.length; i++) {
        var trans = arguments[i];
        if (trans.length == 3) {
            trans = [trans[0], 0, trans[1] * trans[0], 0, trans[0], trans[2] * trans[0]];
        }
        ret = [[], []];
        for (var i = 0; i < arr[0].length; i++) {
            ret[0][i] = arr[0][i] * trans[0] + arr[1][i] * trans[1] + trans[2];
            ret[1][i] = arr[0][i] * trans[3] + arr[1][i] * trans[4] + trans[5];
        }
    }
    return ret;
}

function drawPolygon(ctx, color, arr, trans) {
    if (!ctx) {
        return;
    }
    trans = trans || [1, 0, 0, 0, 1, 0];
    arr = Transform(arr, trans);
    ctx.beginPath();
    ctx.fillStyle = color;
    ctx.moveTo(arr[0][0], arr[1][0]);
    for (var i = 1; i < arr[0].length; i++) {
        ctx.lineTo(arr[0][i], arr[1][i]);
    }
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
}

var sq1Image = (function() {
    var sqa = hsq3 + 1;
    var sqb = sqa * Math.sqrt(2);

    function SqCubie() {
        this.ul = 0x011233;
        this.ur = 0x455677;
        this.dl = 0x998bba;
        this.dr = 0xddcffe;
        this.ml = 0;
    }

    SqCubie.prototype.pieceAt = function(idx) {
        var ret;
        if (idx < 6) {
            ret = this.ul >> ((5 - idx) << 2);
        } else if (idx < 12) {
            ret = this.ur >> ((11 - idx) << 2);
        } else if (idx < 18) {
            ret = this.dl >> ((17 - idx) << 2);
        } else {
            ret = this.dr >> ((23 - idx) << 2);
        }
        return ret & 0xf;
    }

    SqCubie.prototype.doMove = function(move) {
        var temp;
        move <<= 2;
        if (move > 24) {
            move = 48 - move;
            temp = this.ul;
            this.ul = (this.ul >> move | this.ur << 24 - move) & 0xffffff;
            this.ur = (this.ur >> move | temp << 24 - move) & 0xffffff;
        } else if (move > 0) {
            temp = this.ul;
            this.ul = (this.ul << move | this.ur >> 24 - move) & 0xffffff;
            this.ur = (this.ur << move | temp >> 24 - move) & 0xffffff;
        } else if (move == 0) {
            temp = this.ur;
            this.ur = this.dl;
            this.dl = temp;
            this.ml = 1 - this.ml;
        } else if (move >= -24) {
            move = -move;
            temp = this.dl;
            this.dl = (this.dl << move | this.dr >> 24 - move) & 0xffffff;
            this.dr = (this.dr << move | temp >> 24 - move) & 0xffffff;
        } else if (move < -24) {
            move = 48 + move;
            temp = this.dl;
            this.dl = (this.dl >> move | this.dr << 24 - move) & 0xffffff;
            this.dr = (this.dr >> move | temp << 24 - move) & 0xffffff;
        }
    }

    function doMove(move, sc) {
        if (move[0] != 0) {
            sc.doMove(move[0]);
        }
        if (move[1] != 0) {
            sc.doMove(-move[1]);
        }
        if (move[2] != 0) {
            sc.doMove(0);
        }
    }

    var ep = [
        [0, -0.5, 0.5],
        [0, -hsq3 - 1, -hsq3 - 1]
    ];
    var cp = [
        [0, -0.5, -hsq3 - 1, -hsq3 - 1],
        [0, -hsq3 - 1, -hsq3 - 1, -0.5]
    ];
    var cpr = [
        [0, -0.5, -hsq3 - 1],
        [0, -hsq3 - 1, -hsq3 - 1]
    ];
    var cpl = [
        [0, -hsq3 - 1, -hsq3 - 1],
        [0, -hsq3 - 1, -0.5]
    ];

    var eps = Transform(ep, [0.66, 0, 0]);
    var cps = Transform(cp, [0.66, 0, 0]);

    var udcol = 'UD';
    var ecol = 'R-B-L-F-F-L-B-R-';
    var ccol = 'RBBLLFFRRFFLLBBR';
    var colors = {
        'U': '#ff0',
        'R': '#f80',
        'F': '#0f0',
        'D': '#fff',
        'L': '#f00',
        'B': '#00f'
    };

    var width = 45;

    var movere = /^\s*\(\s*(-?\d+),\s*(-?\d+)\s*\)\s*$/

    function drawPosit(ctx, sc, colors) {
        for (var i = 0; i < 24; i++) {
            var trans = i < 12 ? [width, sqb, sqb] : [width, sqb * 3, sqb];
            var val = sc.pieceAt(i);
            var colorUD = colors[udcol[val >= 8 ? 1 : 0]];
            var cRot = -(i < 12 ? (i - 1) : (i - 6)) * PI / 6;
            var eRot = -(i < 12 ? i : (i - 5)) * PI / 6;
            if (val % 2 == 1) {
                drawPolygon(ctx, colors[ccol[val - 1]], Rotate(cpr, cRot), trans);
                drawPolygon(ctx, colors[ccol[val]], Rotate(cpl, cRot), trans);
                drawPolygon(ctx, colorUD, Rotate(cps, cRot), trans);
                i++;
            } else {
                drawPolygon(ctx, colors[ecol[val]], Rotate(ep, eRot), trans);
                drawPolygon(ctx, colorUD, Rotate(eps, eRot), trans);
            }
        }
    }

    return function(moveseq, colorsIn) {

        squanCanvas = new Canvas.createCanvas(495, 283.5);
        ctx = squanCanvas.getContext('2d');

        let cols = ""
        if(colorsIn === "default") {
            cols = "#ff0#f80#0f0#fff#f00#00f".match(colre);
        } else {
            cols = colorsIn.match(colre);
        }
        colors = {
            'U': cols[0],
            'R': cols[1],
            'F': cols[2],
            'D': cols[3],
            'L': cols[4],
            'B': cols[5]
        };
        var sc = new SqCubie();
        var moves = moveseq.split('/');
        var tomove = [];
        for (var i = 0; i < moves.length; i++) {
            if (/^\s*$/.exec(moves[i])) {
                tomove.push([0, 0, 1]);
                continue;
            }
            var m = movere.exec(moves[i]);
            tomove.push([(~~m[1] + 12) % 12, (~~m[2] + 12) % 12, 1]);
        }
        tomove.push([0, 0, 1]);
        for (var i = 0; i < tomove.length; i++) {
            doMove(tomove[i], sc);
        }

        for (var i = 0; i < 2; i++) {
            var trans = i == 0 ? [width, sqb, sqb + sqa] : [width, sqb * 3, sqb - sqa - 0.7];
            drawPolygon(ctx, colors['L'], [[-sqa, -sqa, -0.5, -0.5], [0, 0.7, 0.7, 0]], trans);
            if (sc.ml == 0) {
                drawPolygon(ctx, colors['L'], [[sqa, sqa, -0.5, -0.5], [0, 0.7, 0.7, 0]], trans);
            } else {
                drawPolygon(ctx, colors['R'], [[hsq3, hsq3, -0.5, -0.5], [0, 0.7, 0.7, 0]], trans);
            }
        }
        drawPosit(ctx, sc, colors);

        return squanCanvas.toBuffer()
    }
})();

module.exports.genImage = (scramble, colorsIn) => {
    return sq1Image(scramble, colorsIn);
}

var colre = /#[0-9a-fA-F]{3}/g;
