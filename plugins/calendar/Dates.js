.pragma library
function date(value) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        var p = value.split('-');
        return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
    }
    return new Date(value);
}
function iso(day) {
    return day.getFullYear() + '-' + ('0' + (day.getMonth() + 1)).slice(-2) + '-' + ('0' + day.getDate()).slice(-2);
}
function add(day, count) {
    return new Date(day.getFullYear(), day.getMonth(), day.getDate() + count);
}
function touches(event, day) {
    return date(event.start) < add(day, 1) && date(event.end) > day;
}
function days(anchor, mode, firstDay) {
    var first = new Date(anchor.getFullYear(), anchor.getMonth(), mode === 'Month' ? 1 : anchor.getDate());
    if (mode !== 'Agenda') first = add(first, -((first.getDay() - firstDay + 7) % 7));
    var count = mode === 'Month' ? 42 : mode === 'Week' ? 7 : 14;
    var result = [];
    for (var i = 0; i < count; i++) result.push(add(first, i));
    return result;
}
// Editor parsing is strict: Date's overflow normalization must not repair input.
function parse(value, allDay) {
    var pattern = allDay ? /^(\d{4})-(\d{2})-(\d{2})$/ : /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:\d{2})$/;
    var m = pattern.exec(value);
    if (!m) throw new Error("Enter valid ISO dates or times with a UTC offset.");
    var wall = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
    if (iso(wall) !== value.slice(0, 10) || (!allDay && (Number(m[4]) > 23 || Number(m[5]) > 59 || Number(m[6] || 0) > 59)))
        throw new Error("Invalid calendar date or time.");
    if (!allDay && m[7] !== 'Z' && (Number(m[7].slice(1,3)) > 23 || Number(m[7].slice(4)) > 59))
        throw new Error("Invalid UTC offset.");
    var result = allDay ? wall : new Date(value);
    if (isNaN(result.getTime())) throw new Error("Invalid calendar date or time.");
    return result;
}
function range(start, end, allDay) {
    var a = parse(start, allDay), b = parse(end, allDay);
    if (b <= a) throw new Error("End must be after start.");
    return [a, b];
}
function timed(day, hour) {
    var value = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour || 0);
    var offset = -value.getTimezoneOffset();
    function pad(n) { return ('0' + n).slice(-2); }
    return iso(value) + 'T' + pad(value.getHours()) + ':00:00' + (offset < 0 ? '-' : '+') + pad(Math.floor(Math.abs(offset) / 60)) + ':' + pad(Math.abs(offset) % 60);
}
function toggle(start, end, allDay) {
    var values = range(start, end, allDay);
    if (allDay) return [timed(values[0], 0), timed(values[1], 0)];
    var a = values[0], b = values[1];
    // Include the last touched local day; midnight is already exclusive.
    var exclusive = (b.getHours() || b.getMinutes() || b.getSeconds() || b.getMilliseconds()) ? add(b, 1) : b;
    return [iso(a), iso(exclusive)];
}

// Form helpers use local wall time. Unedited provider values bypass serialization.
function editorParts(value, allDay, inclusiveEnd) {
    if (!value) return ["", ""];
    var parsed = date(value);
    if (isNaN(parsed.getTime())) return [String(value).slice(0, 10), ""];
    if (allDay && inclusiveEnd) parsed = add(parsed, -1);
    return [iso(parsed), allDay ? "" : ('0' + parsed.getHours()).slice(-2) + ':' + ('0' + parsed.getMinutes()).slice(-2)];
}
function fromEditor(dayText, timeText, allDay, inclusiveEnd) {
    var day;
    try { day = parse(dayText, true); } catch (error) { throw new Error("Enter a valid date using YYYY-MM-DD."); }
    if (allDay) return inclusiveEnd ? iso(add(day, 1)) : dayText;
    var match = /^(\d{2}):(\d{2})$/.exec(timeText);
    if (!match || Number(match[1]) > 23 || Number(match[2]) > 59)
        throw new Error("Enter a valid time using HH:mm.");
    var hour = Number(match[1]), minute = Number(match[2]);
    var local = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minute);
    if (iso(local) !== dayText || local.getHours() !== hour || local.getMinutes() !== minute)
        throw new Error("This local time does not exist because the clocks change. Choose another time.");
    var offset = -local.getTimezoneOffset();
    function pad(number) { return ('0' + number).slice(-2); }
    return dayText + 'T' + pad(hour) + ':' + pad(minute) + ':00'
        + (offset < 0 ? '-' : '+') + pad(Math.floor(Math.abs(offset) / 60)) + ':' + pad(Math.abs(offset) % 60);
}
