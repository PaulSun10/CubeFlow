// Device-pixel padding keeps the complete stroke inside the backing canvas.
function fitted(width, height, contentWidth, contentHeight, nominalScale) {
    const stroke = Math.max(1, Math.round(nominalScale * 1.25 * (globalThis.cubeFlowDiagramStrokeScale || 1)));
    const inset = Math.ceil(stroke / 2) + 1;
    const scale = Math.min((width - inset * 2) / contentWidth, (height - inset * 2) / contentHeight);
    if (!(scale > 0)) throw new Error('Diagram backing canvas is too small');
    return { scale, stroke, x: (width - contentWidth * scale) / 2, y: (height - contentHeight * scale) / 2 };
}
function snapped(value, scale, translation, stroke) {
    return (Math.round(value * scale + translation - stroke / 2) + stroke / 2 - translation) / scale;
}
module.exports = { fitted, snapped };
