// Squeeze-Scroll: squeeze and hold the Pencil Pro, then move it up/down above the glass to scroll.
// Tip: set Squeeze on the iPad (Settings → Pencil) to "None", otherwise its action runs too.

// Points scrolled per full iPad height of Pencil movement (change with up.storage.set("speed", 3000)).
const speed = up.storage.get("speed") || 2400;
let active = false;
let lastX = null, lastY = null;

up.on("gesture", g => {
  if (g.name === "pencil.squeezeBegan") { active = true; lastX = lastY = null; up.toast("↕︎ Scroll", 0.7); }
  if (g.name === "pencil.squeezeEnded") { active = false; }
});

up.filter(s => {
  if (!active || s.phase !== "hover") return s;
  if (lastY !== null) up.scroll((s.x - lastX) * speed, (s.y - lastY) * speed);
  lastX = s.x; lastY = s.y;
  return null; // keep the cursor where it is while scrolling
});
