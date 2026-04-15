let nnn = require("./cubes/nnn")
let clock = require("./cubes/clk")
let megaminx = require("./cubes/megaminx")
let pyraminx = require("./cubes/pyraminx")
let skewb = require("./cubes/skewb")
let squareone = require("./cubes/squareone")

//megaminx, clk, squareone, skewb, pyraminx, nnn (111, 222, etc.)
//just set colorsIn to "default"
module.exports.genImage = (cube, scramble, colorsIn) => {
	if((Number(cube) != NaN) && (Number(cube) % 111 === 0) && (Number(cube) <= 999)) return nnn.genImage(Number(cube)/111, scramble, colorsIn)
	else if(cube === "clk") return clock.genImage(scramble, colorsIn)
	else if(cube === "megaminx") return megaminx.genImage(scramble, colorsIn)
	else if(cube === "pyraminx") return pyraminx.genImage(scramble, colorsIn)
	else if(cube === "skewb") return skewb.genImage(scramble, colorsIn)
	else if(cube === "squareone") return squareone.genImage(scramble, colorsIn)
}