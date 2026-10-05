// JD Pools: pool-caustics background for the sign-in lander.
// Ported from jdpoolstech apps/collab/src/app/signin/WaterCanvas.tsx (same shader, same cost controls:
// 55% resolution, dpr capped at 1.5, ~30fps, paused when hidden, one frozen frame under reduced motion).
// If WebGL is unavailable the canvas stays empty and the CSS ground carries the screen.
(function () {
  var VERT = "\nattribute vec2 a_pos;\nvoid main() { gl_Position = vec4(a_pos, 0.0, 1.0); }\n";
  var FRAG = "\nprecision highp float;\n\nuniform vec2  u_res;\nuniform float u_time;\nuniform vec3  u_tint;\n\n#define TAU 6.28318530718\n\nvoid main() {\n  vec2 uv = gl_FragCoord.xy / u_res;\n  float aspect = u_res.x / max(u_res.y, 1.0);\n\n  // \u26a0\ufe0f THE -250.0 IS LOAD-BEARING, and leaving it out is what turned the first\n  // build into a flat blue wash. The accumulator below divides by p, so p\n  // has to stay LARGE: at p \u2248 250 the reciprocal term lands under 1 and c\n  // settles around 0.6, which is the range 1.17 - pow(c, 1.4) was written\n  // for. Feed it a tidy p \u2248 2 instead and the term blows up to ~90, c goes\n  // negative, and pow(|c|, 8) saturates every pixel to white.\n  //\n  // \u26a0\ufe0f THE PATTERN IS PERIODIC IN TAU, so the domain scale is also the tile\n  // count. Scaling by 2.6 gave three visible repeats across a laptop screen\n  // with hard seams between them. One period over the HEIGHT is the most the\n  // screen can show without repeating vertically, and the small rotation stops\n  // what does repeat horizontally from lining its seams up with the edges.\n  float ca = cos(0.36), sa = sin(0.36);\n  vec2 r = uv * vec2(aspect, 1.0);\n  r = vec2(r.x * ca - r.y * sa, r.x * sa + r.y * ca);\n  vec2 p = r * TAU - 250.0;\n  vec2 i = p;\n  float c = 1.0;\n  const float inten = 0.0045;\n\n  float t0 = u_time + 23.0;\n  for (int n = 0; n < 5; n++) {\n    float t = t0 * (1.0 - (3.5 / float(n + 1)));\n    i = p + vec2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));\n    c += 1.0 / length(vec2(\n      p.x / (sin(i.x + t) / inten),\n      p.y / (cos(i.y + t) / inten)\n    ));\n  }\n\n  c /= 5.0;\n  c = 1.17 - pow(c, 1.4);\n  // 11, not the 8 this is descended from. At 8 the ridges are wide enough to\n  // merge and the whole thing reads as smoke; the higher exponent keeps only\n  // the bright cores, which is what light on water actually leaves behind.\n  float g = clamp(pow(abs(c), 11.0), 0.0, 1.0);\n\n  // Light enters at the SURFACE, so the ridges belong up top and should be\n  // spent by the time the eye reaches the card.\n  float depth = smoothstep(0.02, 0.88, uv.y);\n\n  // ...and a calm well in the middle, so the card never has to out-shout a lit\n  // backdrop to stay readable.\n  float d = length((uv - vec2(0.5, 0.46)) * vec2(aspect, 1.0));\n  float calm = smoothstep(0.14, 0.60, d);\n\n  float a = g * depth * mix(0.18, 1.0, calm) * 0.8;\n\n  // Hot cores go white, the falloff keeps the brand cyan \u2014 which is what light\n  // on water actually does, and what stops a single flat tint reading as gas.\n  vec3 col = mix(u_tint, vec3(1.0), clamp(g * 1.35, 0.0, 1.0));\n\n  // Premultiplied: the canvas composites with mix-blend-mode: screen.\n  gl_FragColor = vec4(col * a, a);\n}\n";

  function compile(gl, type, src) {
    var sh = gl.createShader(type);
    if (!sh) return null;
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) { gl.deleteShader(sh); return null; }
    return sh;
  }

  function start(canvas) {
    var gl = canvas.getContext('webgl', { alpha: true, antialias: false, depth: false, stencil: false, premultipliedAlpha: true, powerPreference: 'low-power' });
    if (!gl) return;
    var vs = compile(gl, gl.VERTEX_SHADER, VERT);
    var fs = compile(gl, gl.FRAGMENT_SHADER, FRAG);
    if (!vs || !fs) return;
    var prog = gl.createProgram();
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return;
    gl.useProgram(prog);

    var buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    var loc = gl.getAttribLocation(prog, 'a_pos');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

    var uRes = gl.getUniformLocation(prog, 'u_res');
    var uTime = gl.getUniformLocation(prog, 'u_time');
    // The cyan bar under the J.D.Pools wordmark.
    gl.uniform3f(gl.getUniformLocation(prog, 'u_tint'), 0x00 / 255, 0x95 / 255, 0xda / 255);

    var SCALE = 0.55;
    function resize() {
      var dpr = Math.min(window.devicePixelRatio || 1, 1.5);
      var w = Math.max(1, Math.round(canvas.clientWidth * dpr * SCALE));
      var h = Math.max(1, Math.round(canvas.clientHeight * dpr * SCALE));
      if (canvas.width === w && canvas.height === h) return;
      canvas.width = w;
      canvas.height = h;
      gl.viewport(0, 0, w, h);
      gl.uniform2f(uRes, w, h);
    }
    function draw(seconds) {
      resize();
      gl.uniform1f(uTime, seconds);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    var reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    if (window.ResizeObserver) {
      new ResizeObserver(function () { if (reduced.matches) draw(18); }).observe(canvas);
    }
    if (reduced.matches) { draw(18); return; }

    var raf = 0, last = 0, t0 = performance.now(), FRAME = 1000 / 30;
    function loop(now) {
      raf = requestAnimationFrame(loop);
      if (now - last < FRAME) return;
      last = now;
      draw(((now - t0) / 1000) * 0.085);
    }
    raf = requestAnimationFrame(loop);
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) { cancelAnimationFrame(raf); raf = 0; }
      else if (!raf) { last = 0; raf = requestAnimationFrame(loop); }
    });
  }

  // Pending state for the Microsoft button: a server round trip sits between the click and the
  // redirect, and on a slow connection people click again.
  function wireSignIn() {
    var form = document.querySelector('[data-jdp-signin]');
    if (!form) return;
    form.addEventListener('submit', function () {
      var btn = form.querySelector('button');
      if (!btn) return;
      btn.disabled = true;
      btn.setAttribute('aria-busy', 'true');
      var mark = btn.querySelector('svg');
      if (mark) {
        var spin = document.createElement('span');
        spin.className = 'sgn-spinner';
        spin.setAttribute('aria-hidden', 'true');
        mark.replaceWith(spin);
      }
    });
  }

  function init() {
    var canvas = document.querySelector('canvas.sgn-water');
    if (canvas) start(canvas);
    wireSignIn();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
