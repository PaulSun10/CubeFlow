"use strict";
var Canvas = require("canvas")
var mathlib = require("../mathlib.js")

var skewbCanvas, ctx;
var hsq3 = Math.sqrt(3) / 2;

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

function parseScramble(scramble) {
    let parsed = []
    scramble = scramble.split(" ")
    for(let i = 0; i < scramble.length; i++) {
        if(scramble[i] === "R") {
            parsed[i] = [0, 1, 1]
        } else if(scramble[i] === "R'") {
            parsed[i] = [0, 1, 3]
        } else if(scramble[i] === "U") {
            parsed[i] = [1, 1, 1]
        } else if(scramble[i] === "U'") {
            parsed[i] = [1, 1, 3]
        } else if(scramble[i] === "L") {
            parsed[i] = [2, 1, 1]
        } else if(scramble[i] === "L'") {
            parsed[i] = [2, 1, 3]
        } else if(scramble[i] === "B") {
            parsed[i] = [3, 1, 1]
        } else if(scramble[i] === "B'") {
            parsed[i] = [3, 1, 3]
        }
    }
    return parsed
}

var skewbImage = (function() {

    var Canvas = require("canvas")
    skewbCanvas = new Canvas.createCanvas(326.26914536239786, 283.280);
    ctx = skewbCanvas.getContext('2d');

    var width = 45;
    var gap = width / 10;
    var posit = [];
    var colors = ['#fff', '#00f', '#f00', '#ff0', '#0f0', '#f80'];

    var ftrans = [
        [width * hsq3, width * hsq3, (width * 4 + gap * 1.5) * hsq3, -width / 2, width / 2, width],
        [width * hsq3, 0, (width * 7 + gap * 3) * hsq3, -width / 2, width, width * 1.5],
        [width * hsq3, 0, (width * 5 + gap * 2) * hsq3, -width / 2, width, width * 2.5 + 0.5 * gap],
        [0, -width * hsq3, (width * 3 + gap) * hsq3, width, -width / 2, width * 4.5 + 1.5 * gap],
        [width * hsq3, 0, (width * 3 + gap) * hsq3, width / 2, width, width * 2.5 + 0.5 * gap],
        [width * hsq3, 0, width * hsq3, width / 2, width, width * 1.5]
    ];

    function doMove(axis, power) {
        for (var p = 0; p < power; p++) {
            switch (axis) {
                case 0: //R
                    mathlib.circle(posit, 2 * 5, 5, 3 * 5);
                    mathlib.circle(posit, 2 * 5 + 4, 5 + 3, 3 * 5 + 2);
                    mathlib.circle(posit, 2 * 5 + 2, 5 + 4, 3 * 5 + 1);
                    mathlib.circle(posit, 2 * 5 + 3, 5 + 1, 3 * 5 + 4);
                    mathlib.circle(posit, 4 * 5 + 4, 0 + 4, 5 * 5 + 3);
                    break;
                case 1: //U
                    mathlib.circle(posit, 0, 5 * 5, 5);
                    mathlib.circle(posit, 2, 5 * 5 + 1, 5 + 2);
                    mathlib.circle(posit, 4, 5 * 5 + 2, 5 + 4);
                    mathlib.circle(posit, 1, 5 * 5 + 3, 5 + 1);
                    mathlib.circle(posit, 4 * 5 + 1, 3 * 5 + 4, 2 * 5 + 2);
                    break;
                case 2: //L
                    mathlib.circle(posit, 4 * 5, 3 * 5, 5 * 5);
                    mathlib.circle(posit, 4 * 5 + 3, 3 * 5 + 3, 5 * 5 + 4);
                    mathlib.circle(posit, 4 * 5 + 1, 3 * 5 + 1, 5 * 5 + 3);
                    mathlib.circle(posit, 4 * 5 + 4, 3 * 5 + 4, 5 * 5 + 2);
                    mathlib.circle(posit, 2 * 5 + 3, 5 + 4, 1);
                    break;
                case 3: //B
                    mathlib.circle(posit, 5, 5 * 5, 3 * 5);
                    mathlib.circle(posit, 5 + 4, 5 * 5 + 3, 3 * 5 + 4);
                    mathlib.circle(posit, 5 + 3, 5 * 5 + 1, 3 * 5 + 3);
                    mathlib.circle(posit, 5 + 2, 5 * 5 + 4, 3 * 5 + 2);
                    mathlib.circle(posit, 2, 4 * 5 + 3, 2 * 5 + 4);
                    break;
            }
        }
    }

    function face(f) {
        var transform = ftrans[f];
        drawPolygon(ctx, colors[posit[f * 5]], [
            [-1, 0, 1, 0],
            [0, 1, 0, -1]
        ], transform);
        drawPolygon(ctx, colors[posit[f * 5 + 1]], [
            [-1, -1, 0],
            [0, -1, -1]
        ], transform);
        drawPolygon(ctx, colors[posit[f * 5 + 2]], [
            [0, 1, 1],
            [-1, -1, 0]
        ], transform);
        drawPolygon(ctx, colors[posit[f * 5 + 3]], [
            [-1, -1, 0],
            [0, 1, 1]
        ], transform);
        drawPolygon(ctx, colors[posit[f * 5 + 4]], [
            [0, 1, 1],
            [1, 1, 0]
        ], transform);
    }

    return function(moveseq, colorsIn) {
        if(colorsIn === "default") {
            colors = "#fff#00f#f00#ff0#0f0#f80".match(colre);
        } else {
            colors = colorsIn.match(colre);
        }
        var cnt = 0;
        for (var i = 0; i < 6; i++) {
            for (var f = 0; f < 5; f++) {
                posit[cnt++] = i;
            }
        }
        var scramble = parseScramble(moveseq);
        for (var i = 0; i < scramble.length; i++) {
            doMove(scramble[i][0], scramble[i][2] == 1 ? 1 : 2);
        }

        for (var i = 0; i < 6; i++) {
            face(i);
        }
        return skewbCanvas.toBuffer();
    }
})();

module.exports.genImage = (scramble, colorsIn) => {
    return skewbImage(scramble, colorsIn);
}

var colre = /#[0-9a-fA-F]{3}/g;