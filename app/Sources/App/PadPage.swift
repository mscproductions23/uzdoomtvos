import Foundation

/// The iPhone touch-controller page served by BeamServer at /pad.
/// It connects to ws://<apple-tv>:8081/, sends the access key from its URL first, then streams
/// {"a":[lx,ly,rx,ry,lt,rt],"b":buttons} using the same layout as a real gamepad
/// (bit N of "b" is KEY_PAD_DPAD_UP + N in the engine, see i_gcjoystick.mm).
enum PadPage {
    static let html = #"""
    <!doctype html><html><head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <title>UZDoom Controller</title>
    <style>
    /* Sizes follow the visible height (vh), so the layout fits even with the browser's toolbars showing. */
    html,body{margin:0;height:100%;background:#0c0c0c;color:#eee;font-family:-apple-system,sans-serif;
      overflow:hidden;touch-action:none;-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}
    #pad{position:fixed;inset:0}
    .zone{position:absolute;top:0;bottom:0}
    #left{left:0;width:50%} #right{right:0;width:50%}
    .top{position:absolute;top:max(2.5vh,env(safe-area-inset-top));left:max(3vw,env(safe-area-inset-left));
      right:max(3vw,env(safe-area-inset-right));display:flex;align-items:center;gap:2vw;pointer-events:none}
    .top .group{display:flex;gap:1.5vw;flex:none}
    .btn{pointer-events:auto;border:2px solid #444;background:#1c1c1c;color:#ddd;border-radius:3.5vh;
      font-weight:700;display:flex;align-items:center;justify-content:center;touch-action:none;white-space:nowrap}
    .btn.on{background:#e33;border-color:#e33;color:#fff}
    .small{height:clamp(30px,12vh,46px);padding:0 clamp(8px,2.2vw,16px);font-size:clamp(12px,4.3vh,16px)}
    .round{position:absolute;border-radius:50%}
    #fire{right:max(4vw,env(safe-area-inset-right));bottom:7vh;width:34vh;height:34vh;font-size:6.5vh}
    #use{right:calc(max(4vw,env(safe-area-inset-right)) + 38vh);bottom:4vh;width:25vh;height:25vh;font-size:5vh}
    #jump{right:calc(max(4vw,env(safe-area-inset-right)) + 29vh);bottom:38vh;width:20vh;height:20vh;font-size:4.2vh}
    .stick{position:absolute;width:120px;height:120px;margin:-60px 0 0 -60px;border-radius:60px;border:2px solid #555;display:none}
    .knob{position:absolute;left:35px;top:35px;width:50px;height:50px;border-radius:25px;background:#888}
    .label{position:absolute;bottom:3vh;color:#555;font-size:clamp(11px,4vh,14px);pointer-events:none}
    #lefthint{left:max(4vw,env(safe-area-inset-left))} #righthint{left:calc(50% + 3vw)}
    #status{flex:1;min-width:0;text-align:center;font-size:clamp(11px,4vh,14px);color:#999;
      white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    #status.ok{color:#5c5}
    #rotate{display:none;position:fixed;inset:0;background:#0c0c0c;align-items:center;justify-content:center;
      text-align:center;font-size:20px;padding:30px;line-height:1.4}
    @media (orientation:portrait){#rotate{display:flex}}
    </style></head><body>
    <div id="pad">
      <div class="zone" id="left"></div>
      <div class="zone" id="right"></div>
      <div class="stick" id="lstick"><div class="knob"></div></div>
      <div class="stick" id="rstick"><div class="knob"></div></div>
      <div class="top">
        <div class="group">
          <div class="btn small" data-bit="4">≡ Menu</div>
          <div class="btn small" data-bit="13">Back</div>
          <div class="btn small" data-bit="0">Map</div>
        </div>
        <div id="status">Connecting…</div>
        <div class="group">
          <div class="btn small" data-bit="8">◀ Weapon</div>
          <div class="btn small" data-bit="9">Weapon ▶</div>
        </div>
      </div>
      <div class="btn round" id="use" data-bit="12">USE</div>
      <div class="btn round" id="jump" data-bit="15">JUMP</div>
      <div class="btn round" id="fire" data-fire="1">FIRE</div>
      <div class="label" id="lefthint">Move</div>
      <div class="label" id="righthint">Look</div>
    </div>
    <div id="rotate">Turn your phone sideways to use it as a controller.</div>
    <script>
    const KEY = new URLSearchParams(location.search).get('key') || '';
    const RADIUS = 60;
    const state = { a: [0, 0, 0, 0, 0, 0], b: 0 };
    let dirty = true, ws = null, ready = false;
    const status = document.getElementById('status');

    // Buttons: hold = pressed. Each pointer is tracked so several fingers work at once.
    const held = new Map();   // pointerId -> element
    function press(el, on) {
      el.classList.toggle('on', on);
      if (el.dataset.fire) state.a[5] = on ? 1 : 0;
      else { const bit = 1 << Number(el.dataset.bit); state.b = on ? (state.b | bit) : (state.b & ~bit); }
      dirty = true;
    }
    document.querySelectorAll('.btn').forEach(el => {
      el.addEventListener('pointerdown', e => { e.preventDefault(); e.stopPropagation(); held.set(e.pointerId, el); press(el, true); });
    });

    // Floating sticks: the stick appears where the thumb lands.
    const sticks = {
      left:  { el: document.getElementById('lstick'), ax: 0, id: null, x: 0, y: 0 },
      right: { el: document.getElementById('rstick'), ax: 2, id: null, x: 0, y: 0 },
    };
    for (const name of ['left', 'right']) {
      document.getElementById(name).addEventListener('pointerdown', e => {
        const s = sticks[name];
        if (s.id !== null) return;
        e.preventDefault();
        s.id = e.pointerId; s.x = e.clientX; s.y = e.clientY;
        s.el.style.left = s.x + 'px'; s.el.style.top = s.y + 'px'; s.el.style.display = 'block';
        moveStick(s, e.clientX, e.clientY);
      });
    }
    function moveStick(s, px, py) {
      let dx = px - s.x, dy = py - s.y;
      const len = Math.hypot(dx, dy);
      if (len > RADIUS) { dx *= RADIUS / len; dy *= RADIUS / len; }
      s.el.firstElementChild.style.transform = `translate(${dx}px, ${dy}px)`;
      state.a[s.ax] = dx / RADIUS;
      state.a[s.ax + 1] = -dy / RADIUS;   // +1 = up, like a real gamepad
      dirty = true;
    }
    function endStick(s) {
      s.id = null; s.el.style.display = 'none';
      state.a[s.ax] = 0; state.a[s.ax + 1] = 0; dirty = true;
    }
    window.addEventListener('pointermove', e => {
      for (const s of Object.values(sticks)) if (s.id === e.pointerId) moveStick(s, e.clientX, e.clientY);
    }, { passive: false });
    function release(e) {
      if (held.has(e.pointerId)) { press(held.get(e.pointerId), false); held.delete(e.pointerId); }
      for (const s of Object.values(sticks)) if (s.id === e.pointerId) endStick(s);
    }
    window.addEventListener('pointerup', release);
    window.addEventListener('pointercancel', release);
    document.addEventListener('touchmove', e => e.preventDefault(), { passive: false });
    document.addEventListener('gesturestart', e => e.preventDefault());

    // Keep the phone screen on while playing (Safari 16.4+).
    let wakeLock = null;
    async function keepAwake() {
      try { if (!wakeLock && navigator.wakeLock) wakeLock = await navigator.wakeLock.request('screen'); } catch (_) {}
    }
    document.addEventListener('pointerdown', keepAwake);
    document.addEventListener('visibilitychange', () => { wakeLock = null; if (!document.hidden) keepAwake(); });

    function connect() {
      ready = false;
      ws = new WebSocket(`ws://${location.hostname}:8081/`);
      ws.onopen = () => ws.send(KEY);
      ws.onmessage = e => { if (e.data === 'ok') { ready = true; dirty = true; status.textContent = 'Connected'; status.className = 'ok'; } };
      ws.onclose = () => {
        ready = false;
        status.textContent = 'Reconnecting… (rescan the QR code if this stays)'; status.className = '';
        setTimeout(connect, 2000);
      };
      ws.onerror = () => ws.close();
    }
    connect();

    // Send changes at most once per frame, plus a keep-alive so a dropped touch can't stick.
    let lastSend = 0;
    function tick(t) {
      if (ready && (dirty || t - lastSend > 250)) {
        ws.send(JSON.stringify({ a: state.a.map(v => Math.round(v * 1000) / 1000), b: state.b }));
        dirty = false; lastSend = t;
      }
      requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
    </script></body></html>
    """#
}
