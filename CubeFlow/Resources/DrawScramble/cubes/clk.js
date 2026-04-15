"use strict";
var clkCanvas, ctx, id;
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

var clkImage = (function() {

    var Canvas = require("canvas")
    clkCanvas = new Canvas.createCanvas(375, 180);
    ctx = clkCanvas.getContext('2d');

    function drawClock(color, trans, time, pointer) {
        if (!ctx) {
            return;
        }
        var points = Transform(Rotate([
            [1, 1, 0, -1, -1, -1, 1, 0],
            [0, -1, -8, -1, 0, 1, 1, 0]
        ], time / 6 * PI), trans);
        var x = points[0];
        var y = points[1];

        ctx.beginPath();
        ctx.fillStyle = color;
        ctx.arc(x[7], y[7], trans[0] * 9, 0, 2 * PI);
        ctx.fill();

        ctx.beginPath();
        ctx.fillStyle = pointer;
        ctx.strokeStyle = pointer;
        ctx.moveTo(x[0], y[0]);
        ctx.bezierCurveTo(x[1], y[1], x[1], y[1], x[2], y[2]);
        ctx.bezierCurveTo(x[3], y[3], x[3], y[3], x[4], y[4]);
        ctx.bezierCurveTo(x[5], y[5], x[6], y[6], x[0], y[0]);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
    }

    function drawButton(color, trans) {
        if (!ctx) {
            return;
        }
        var points = Transform([
            [0],
            [0]
        ], trans);
        ctx.beginPath();
        ctx.fillStyle = color;
        ctx.strokeStyle = '#000';
        ctx.arc(points[0][0], points[1][0], trans[0] * 3, 0, 2 * PI);
        ctx.fill();
        ctx.stroke();
    }

    var width = 3;
    var movere = /([UD][RL]|ALL|[UDRLy])(\d[+-]?)?/
    var movestr = ['UR', 'DR', 'DL', 'UL', 'U', 'R', 'D', 'L', 'ALL']

    return function(moveseq, colors) {
        var moves = moveseq.split(/\s+/);
        var moveArr = [
            [0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0], //UR
            [0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0], //DR
            [0, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0], //DL
            [1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0], //UL
            [1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0], //U
            [0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0], //R
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0], //D
            [1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0], //L
            [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0], //ALL
            [11, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0], //UR
            [0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 0, 1, 1, 1], //DR
            [0, 0, 0, 0, 0, 0, 0, 0, 11, 0, 1, 1, 0, 1], //DL
            [0, 0, 11, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0], //UL
            [11, 0, 11, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0], //U
            [11, 0, 0, 0, 0, 0, 11, 0, 0, 1, 0, 1, 1, 1], //R
            [0, 0, 0, 0, 0, 0, 11, 0, 11, 0, 1, 1, 1, 1], //D
            [0, 0, 11, 0, 0, 0, 0, 0, 11, 1, 1, 1, 0, 1], //L
            [11, 0, 11, 0, 0, 0, 11, 0, 11, 1, 1, 1, 1, 1] //ALL
        ]
        var flip = 9;
        var buttons = [0, 0, 0, 0];
        var clks = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        for (var i = 0; i < moves.length; i++) {
            var m = movere.exec(moves[i]);
            if (!m) {
                continue;
            }
            if (m[0] == 'y2') {
                flip = 0;
                continue;
            }
            var axis = movestr.indexOf(m[1]) + flip;
            if (m[2] == undefined) {
                buttons[axis % 9] = 1;
                continue;
            }
            var power = ~~m[2][0];
            power = m[2][1] == '+' ? power : 12 - power;
            for (var j = 0; j < 14; j++) {
                clks[j] = (clks[j] + moveArr[axis][j] * power) % 12;
            }
        }
        clks = [clks[0], clks[3], clks[6], clks[1], clks[4], clks[7], clks[2], clks[5], clks[8],
            12 - clks[2], clks[10], 12 - clks[8], clks[9], clks[11], clks[13], 12 - clks[0], clks[12], 12 - clks[6]
        ];
        buttons = [buttons[3], buttons[2], buttons[0], buttons[1], 1 - buttons[0], 1 - buttons[1], 1 - buttons[3], 1 - buttons[2]];

        var y = [10, 30, 50];
        var x = [10, 30, 50, 75, 95, 115];
        for (var i = 0; i < 18; i++) {
            if(i < 9) {
                drawClock(['#ffffff', '#ffffff'][~~(i / 9)], [width, x[~~(i / 3)], y[i % 3]], clks[i], "#000000");
            } else {
                drawClock(['#000000', '#000000'][~~(i / 9)], [width, x[~~(i / 3)], y[i % 3]], clks[i], "#ffffff");
            }
        }

        var y = [20, 40];
        var x = [20, 40, 85, 105];
        for (var i = 0; i < 8; i++) {
            drawButton(['#919191', '#4c4c4c'][buttons[i]], [width, x[~~(i / 2)], y[i % 2]]);
        }
        return clkCanvas.toBuffer();
    };
})();

module.exports.genImage = (scramble, colorsIn) => {
    return clkImage(scramble, colorsIn);
}

var colre = /#[0-9a-fA-F]{3}/g;