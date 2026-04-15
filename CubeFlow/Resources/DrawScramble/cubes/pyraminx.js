"use strict";
var mathlib = require("../mathlib")

var pyraCanvas, ctx;
var hsq3 = Math.sqrt(3) / 2;

function Rotate(arr, theta) {
    return Transform(arr, [Math.cos(theta), -Math.sin(theta), 0, Math.sin(theta), Math.cos(theta), 0]);
}

function Transform(arr) {
    var ret;
    for (var i = 1; i < arguments.length; i++) {
        var trans = arguments[i];
        if (trans.length === 3) {
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

function parseScramble(scramble) {
    let parsed = []
    scramble = scramble.split(" ")
    for(let i = 0; i < scramble.length; i++) {
        if(scramble[i] === "U") {
            parsed[i] = [0, 1, 1]
        } else if(scramble[i] === "U'") {
            parsed[i] = [0, 1, 3]
        } else if(scramble[i] === "u") {
            parsed[i] = [0, 2, 1]
        } else if(scramble[i] === "u'") {
            parsed[i] = [0, 2, 3]
        }


        else if(scramble[i] === "R") {
            parsed[i] = [1, 1, 1]
        } else if(scramble[i] === "R'") {
            parsed[i] = [1, 1, 3]
        } else if(scramble[i] === "r") {
            parsed[i] = [1, 2, 1]
        } else if(scramble[i] === "r'") {
            parsed[i] = [1, 2, 3]
        }


        else if(scramble[i] === "L") {
            parsed[i] = [2, 1, 1]
        } else if(scramble[i] === "L'") {
            parsed[i] = [2, 1, 3]
        } else if(scramble[i] === "l") {
            parsed[i] = [2, 2, 1]
        } else if(scramble[i] === "l'") {
            parsed[i] = [2, 2, 3]
        }


        else if(scramble[i] === "B") {
            parsed[i] = [3, 1, 1]
        } else if(scramble[i] === "B'") {
            parsed[i] = [3, 1, 3]
        } else if(scramble[i] === "b") {
            parsed[i] = [3, 2, 1]
        } else if(scramble[i] === "b'") {
            parsed[i] = [3, 2, 3]
        }
    }
    return parsed
}

var pyraImage = (function() {

    var Canvas = require("canvas")
    pyraCanvas = new Canvas.createCanvas(315, 253.31243060694828);
    ctx = pyraCanvas.getContext('2d');

    var width = 45;
    var posit = [];
    var colors = ['#0f0', '#f00', '#00f', '#ff0'];
    var faceoffx = [3.5, 1.5, 5.5, 3.5];
    var faceoffy = [0, 3 * hsq3, 3 * hsq3, 6.5 * hsq3];
    var g1 = [0, 6, 5, 4];
    var g2 = [1, 7, 3, 5];
    var g3 = [2, 8, 4, 3];
    var flist = [
        [0, 1, 2],
        [2, 3, 0],
        [1, 0, 3],
        [3, 2, 1]
    ];
    var arrx = [-0.5, 0.5, 0];
    var arry1 = [hsq3, hsq3, 0];
    var arry2 = [-hsq3, -hsq3, 0];

    function doMove(axis, power) {
        var len = axis >= 4 ? 1 : 4;
        var f = flist[axis % 4];
        for (var i = 0; i < len; i++) {
            for (var p = 0; p < power; p++) {
                mathlib.circle(posit, f[0] * 9 + g1[i], f[1] * 9 + g2[i], f[2] * 9 + g3[i]);
            }
        }
    }

    function face(f) {
        var inv = f != 0;
        var arroffx = [0, -1, 1, 0, 0.5, -0.5, 0, -0.5, 0.5];
        var arroffy = [0, 2, 2, 2, 1, 1, 2, 3, 3];

        for (var i = 0; i < arroffy.length; i++) {
            arroffy[i] *= inv ? -hsq3 : hsq3;
            arroffx[i] *= inv ? -1 : 1;
        }
        for (var idx = 0; idx < 9; idx++) {
            drawPolygon(ctx, colors[posit[f * 9 + idx]], [arrx, (idx >= 6 != inv) ? arry2 : arry1], [width, faceoffx[f] + arroffx[idx], faceoffy[f] + arroffy[idx]]);
        }
    }

    return function(moveseq, colorsIn) {
        if(colorsIn === "default") {
            colors = "#0f0#f00#00f#ff0".match(colre);
        } else {
            colors = colorsIn.match(colre);
        }
        var cnt = 0;
        for (var i = 0; i < 4; i++) {
            for (var f = 0; f < 9; f++) {
                posit[cnt++] = i;
            }
        }
        var scramble = parseScramble(moveseq);
        for (var i = 0; i < scramble.length; i++) {
            doMove(scramble[i][0] + (scramble[i][1] == 2 ? 4 : 0), scramble[i][2] == 1 ? 1 : 2);
        }

        for (var i = 0; i < 4; i++) {
            face(i);
        }
        return pyraCanvas.toBuffer()
    }
})();

module.exports.genImage = (scramble, colorsIn) => {
    return pyraImage(scramble, colorsIn);
}

var colre = /#[0-9a-fA-F]{3}/g;