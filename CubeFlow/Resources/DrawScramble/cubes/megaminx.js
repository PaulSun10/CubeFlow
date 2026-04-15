"use strict";
var megaCanvas, ctx;
var PI = Math.PI;

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

var mgmImage = (function() {

    var Canvas = require("canvas")
    megaCanvas = new Canvas.createCanvas(392, 196);
    ctx = megaCanvas.getContext('2d');

    var moveU = [4, 0, 1, 2, 3, 9, 5, 6, 7, 8, 10, 11, 12, 13, 58, 59, 16, 17, 18, 63, 20, 21, 22, 23, 24, 14, 15, 27, 28, 29, 19, 31, 32, 33, 34, 35, 25, 26, 38, 39, 40, 30, 42, 43, 44, 45, 46, 36, 37, 49, 50, 51, 41, 53, 54, 55, 56, 57, 47, 48, 60, 61, 62, 52, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131];
    var moveR = [81, 77, 78, 3, 4, 86, 82, 83, 8, 85, 87, 122, 123, 124, 125, 121, 127, 128, 129, 130, 126, 131, 89, 90, 24, 25, 88, 94, 95, 29, 97, 93, 98, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 26, 22, 23, 48, 30, 31, 27, 28, 53, 32, 69, 70, 66, 67, 68, 74, 75, 71, 72, 73, 76, 101, 102, 103, 99, 100, 106, 107, 108, 104, 105, 109, 46, 47, 79, 80, 45, 51, 52, 84, 49, 50, 54, 0, 1, 2, 91, 92, 5, 6, 7, 96, 9, 10, 15, 11, 12, 13, 14, 20, 16, 17, 18, 19, 21, 113, 114, 110, 111, 112, 118, 119, 115, 116, 117, 120, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65];
    var moveD = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 33, 34, 35, 14, 15, 38, 39, 40, 19, 42, 43, 44, 45, 46, 25, 26, 49, 50, 51, 30, 53, 54, 55, 56, 57, 36, 37, 60, 61, 62, 41, 64, 65, 11, 12, 13, 47, 48, 16, 17, 18, 52, 20, 21, 22, 23, 24, 58, 59, 27, 28, 29, 63, 31, 32, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 124, 125, 121, 122, 123, 129, 130, 126, 127, 128, 131];
    var moveMaps = [moveU, moveR, moveD];

    var width = 40;
    var cfrac = 0.5;
    var efrac2 = (Math.sqrt(5) + 1) / 2;
    var d2x = (1 - cfrac) / 2 / Math.tan(PI / 5);
    var off1X = 2.6;
    var off1Y = 2.2;
    var off2X = off1X + Math.cos(PI * 0.1) * 3 * efrac2;
    var off2Y = off1Y + Math.sin(PI * 0.1) * efrac2;
    var cornX = [0, d2x, 0, -d2x];
    var cornY = [-1, -(1 + cfrac) / 2, -cfrac, -(1 + cfrac) / 2];
    var edgeX = [Math.cos(PI * 0.1) - d2x, d2x, 0, Math.sin(PI * 0.4) * cfrac];
    var edgeY = [-Math.sin(PI * 0.1) + (cfrac - 1) / 2, -(1 + cfrac) / 2, -cfrac, -Math.cos(PI * 0.4) * cfrac];
    var centX = [Math.sin(0.0) * cfrac, Math.sin(PI * 0.4) * cfrac, Math.sin(PI * 0.8) * cfrac, Math.sin(PI * 1.2) * cfrac, Math.sin(PI * 1.6) * cfrac];
    var centY = [-Math.cos(0.0) * cfrac, -Math.cos(PI * 0.4) * cfrac, -Math.cos(PI * 0.8) * cfrac, -Math.cos(PI * 1.2) * cfrac, -Math.cos(PI * 1.6) * cfrac];
    var colors = ['#fff', '#d00', '#060', '#81f', '#fc0', '#00b', '#ffb', '#8df', '#f83', '#7e0', '#f9f', '#999'];

    function drawFace(state, baseIdx, trans, rot) {
        for (var i = 0; i < 5; i++) {
            drawPolygon(ctx, colors[state[baseIdx + i]], Rotate([cornX, cornY], PI * 2 / 5 * i + rot), trans);
            drawPolygon(ctx, colors[state[baseIdx + i + 5]], Rotate([edgeX, edgeY], PI * 2 / 5 * i + rot), trans);
        }
        drawPolygon(ctx, colors[state[baseIdx + 10]], Rotate([centX, centY], rot), trans);
    }

    function doMove(state, axis, inv) {
        var moveMap = moveMaps[axis];
        var oldState = state.slice();
        if (inv) {
            for (var i = 0; i < 132; i++) {
                state[moveMap[i]] = oldState[i];
            }
        } else {
            for (var i = 0; i < 132; i++) {
                state[i] = oldState[moveMap[i]];
            }
        }
    }

    var movere = /[RD][+-]{2}|U'?/

    return function(moveseq, colorsIn) {
        if(colorsIn === "default") {
            colors = "#fff#d00#060#81f#fc0#00b#ffb#8df#f83#7e0#f9f#999".match(colre);
        } else {
            colors = colorsIn.match(colre)
        }
        var state = [];
        for (var i = 0; i < 12; i++) {
            for (var j = 0; j < 11; j++) {
                state[i * 11 + j] = i;
            }
        }
        var moves = moveseq.split(/\s+/);
        for (var i = 0; i < moves.length; i++) {
            var m = movere.exec(moves[i]);
            if (!m) {
                continue;
            }
            var axis = "URD".indexOf(m[0][0]);
            var inv = /[-']/.exec(m[0][1]);
            doMove(state, axis, inv);
        }
        drawFace(state, 0, [width, off1X, off1Y], 0.0);
        drawFace(state, 11, [width, off1X + Math.cos(PI * 0.1) * efrac2, off1Y + Math.sin(PI * 0.1) * efrac2], PI * 0.2);
        drawFace(state, 22, [width, off1X + Math.cos(PI * 0.5) * efrac2, off1Y + Math.sin(PI * 0.5) * efrac2], PI * 0.6);
        drawFace(state, 33, [width, off1X + Math.cos(PI * 0.9) * efrac2, off1Y + Math.sin(PI * 0.9) * efrac2], PI);
        drawFace(state, 44, [width, off1X + Math.cos(PI * 1.3) * efrac2, off1Y + Math.sin(PI * 1.3) * efrac2], PI * 1.4);
        drawFace(state, 55, [width, off1X + Math.cos(PI * 1.7) * efrac2, off1Y + Math.sin(PI * 1.7) * efrac2], PI * 1.8);
        drawFace(state, 66, [width, off2X + Math.cos(PI * 0.7) * efrac2, off2Y + Math.sin(PI * 0.7) * efrac2], 0.0);
        drawFace(state, 77, [width, off2X + Math.cos(PI * 0.3) * efrac2, off2Y + Math.sin(PI * 0.3) * efrac2], PI * 1.6);
        drawFace(state, 88, [width, off2X + Math.cos(PI * 1.9) * efrac2, off2Y + Math.sin(PI * 1.9) * efrac2], PI * 1.2);
        drawFace(state, 99, [width, off2X + Math.cos(PI * 1.5) * efrac2, off2Y + Math.sin(PI * 1.5) * efrac2], PI * 0.8);
        drawFace(state, 110, [width, off2X + Math.cos(PI * 1.1) * efrac2, off2Y + Math.sin(PI * 1.1) * efrac2], PI * 0.4);
        drawFace(state, 121, [width, off2X, off2Y], PI);
        if (ctx) {
            ctx.fillStyle = "#000";
            ctx.font = "20px serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText("U", width * off1X, width * off1Y);
            ctx.fillText("F", width * off1X, width * (off1Y + Math.sin(PI * 0.5) * efrac2));
        }
        return megaCanvas.toBuffer();
    };
})();

module.exports.genImage = (scramble, colorsIn) => {
    return mgmImage(scramble, colorsIn);
}

var colre = /#[0-9a-fA-F]{3}/g;