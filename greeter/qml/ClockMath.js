.pragma library

function normalizeAngle(angle) {
    const value = Number(angle) % 360;
    return value < 0 ? value + 360 : value;
}

function angularDistance(a, b) {
    const distance = Math.abs(normalizeAngle(a) - normalizeAngle(b));
    return Math.min(distance, 360 - distance);
}

function secondAngle(date) {
    const value = date instanceof Date ? date : new Date(date);
    return -((value.getSeconds() + value.getMilliseconds() / 1000) * 6);
}

function minuteAngle(date) {
    const value = date instanceof Date ? date : new Date(date);
    return -((value.getMinutes() + value.getSeconds() / 60 + value.getMilliseconds() / 60000) * 6);
}

function visibleEdgeRotation(angle) {
    return Number(angle) + 90;
}

function hourText(date, format) {
    const value = date instanceof Date ? date : new Date(date);
    let hour = value.getHours();
    if (String(format) === "12") {
        hour %= 12;
        if (hour === 0)
            hour = 12;
    }
    return String(hour).padStart(2, "0");
}
