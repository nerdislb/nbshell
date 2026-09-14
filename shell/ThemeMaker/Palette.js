.pragma library

var roles = [
    {key: "background", label: "Background", group: "Basics"},
    {key: "foreground", label: "Text", group: "Basics"},
    {key: "dark_foreground", label: "Secondary text", group: "Basics"},
    {key: "bright_foreground", label: "Bright text", group: "Basics"},
    {key: "accent", label: "Accent", group: "Accents"},
    {key: "selection", label: "Selection", group: "Accents"},
    {key: "red", label: "Error / red", group: "Accents"},
    {key: "green", label: "Success / green", group: "Accents"},
    {key: "yellow", label: "Warning / yellow", group: "Accents"},
    {key: "blue", label: "Blue", group: "Accents"},
    {key: "magenta", label: "Magenta", group: "Accents"},
    {key: "cyan", label: "Cyan", group: "Accents"},
    {key: "orange", label: "Orange", group: "Accents"},
    {key: "lighter_background", label: "Raised surface", group: "Surfaces"},
    {key: "dark_background", label: "Dark surface", group: "Surfaces"},
    {key: "darker_background", label: "Backdrop", group: "Surfaces"},
    {key: "muted", label: "Muted / borders", group: "Surfaces"},
    {key: "inactive_border_color", label: "Inactive window border", group: "Surfaces"},
    {key: "outer_border_color", label: "Outer window border", group: "Surfaces"}
];
var bright = ["red", "green", "yellow", "blue", "magenta", "cyan"];
function clone(value) { return JSON.parse(JSON.stringify(value)); }
function hex(r, g, b) {
    return "#" + [r,g,b].map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2,"0")).join("");
}
function rgb(value) {
    return [1,3,5].map(i => parseInt(String(value).slice(i,i+2),16));
}
function mix(a,b,t) { var x=rgb(a), y=rgb(b); return hex(...x.map((v,i)=>v*(1-t)+y[i]*t)); }
function hsl(value) {
    var c=rgb(value).map(v=>v/255), max=Math.max(...c), min=Math.min(...c), d=max-min;
    var l=(max+min)/2, h=0, s=0;
    if (d) {
        s=d/(1-Math.abs(2*l-1));
        h=max===c[0] ? ((c[1]-c[2])/d)%6 : max===c[1] ? (c[2]-c[0])/d+2 : (c[0]-c[1])/d+4;
        h=((h*60)+360)%360;
    }
    return [h,s*100,l*100];
}
function fromHsl(h,s,l) {
    s/=100; l/=100;
    var c=(1-Math.abs(2*l-1))*s, x=c*(1-Math.abs((h/60)%2-1)), m=l-c/2;
    var v=h<60?[c,x,0]:h<120?[x,c,0]:h<180?[0,c,x]:h<240?[0,x,c]:h<300?[x,0,c]:[c,0,x];
    return hex(...v.map(n=>(n+m)*255));
}
function linked(palette) {
    var p=clone(palette), bg=p.background, fg=p.foreground;
    p.lighter_background=mix(bg,fg,.12); p.selection=mix(bg,fg,.18);
    p.muted=mix(bg,fg,.35); p.dark_foreground=mix(fg,bg,.45);
    p.dark_background=mix(bg,"#000000",.25); p.darker_background=mix(bg,"#000000",.4);
    return p;
}
function localUrl(path) { return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : ""; }
