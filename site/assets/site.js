
(function(){
  "use strict";
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- Header shadow on scroll ---------- */
  (function(){
    var header = document.getElementById('site-header');
    if(!header) return;
    var onScroll = function(){ header.classList.toggle('scrolled', window.scrollY > 12); };
    window.addEventListener('scroll', onScroll, {passive:true});
    onScroll();
  })();

  /* ---------- Scroll reveal (IntersectionObserver) ---------- */
  (function(){
    var els = document.querySelectorAll('.reveal');
    if(reduce || !('IntersectionObserver' in window)){
      for(var i=0;i<els.length;i++) els[i].classList.add('in');
      return;
    }
    var io = new IntersectionObserver(function(entries){
      entries.forEach(function(e){
        if(e.isIntersecting){ e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, {threshold:0.14, rootMargin:'0px 0px -8% 0px'});
    els.forEach(function(el){ io.observe(el); });
  })();

  /* ---------- Hero video (respects reduced motion) ---------- */
  (function(){
    var v = document.getElementById('hero-video');
    if(v && !reduce){
      var tryPlay = function(){ var p = v.play(); if(p && p.catch) p.catch(function(){}); };
      if('IntersectionObserver' in window){
        new IntersectionObserver(function(es){
          es.forEach(function(e){ e.isIntersecting ? tryPlay() : v.pause(); });
        }, {threshold:0.1}).observe(v);
      } else { tryPlay(); }
    }
  })();

  /* ---------- Subtle parallax ---------- */
  (function(){
    if(reduce) return;
    var layers = document.querySelectorAll('[data-parallax]');
    if(!layers.length) return;
    var ticking = false;
    var update = function(){
      var y = window.scrollY;
      for(var i=0;i<layers.length;i++){
        var s = parseFloat(layers[i].getAttribute('data-parallax')) || 0.1;
        layers[i].style.transform = 'translate3d(0,' + (y*s).toFixed(1) + 'px,0)';
      }
      ticking = false;
    };
    window.addEventListener('scroll', function(){
      if(!ticking){ requestAnimationFrame(update); ticking = true; }
    }, {passive:true});
  })();

  /* ---------- Canvas: drifting mist + faint lightning ---------- */
  (function(){
    var canvas = document.getElementById('mist-canvas');
    if(!canvas) return;
    var ctx = canvas.getContext('2d');
    if(!ctx) return;
    var W=0, H=0, dpr=1, raf=null, last=0, nextBolt=1600;
    var blobs=[], bolts=[];
    var hues=['212,175,55','20,184,166','139,92,246','226,232,240'];

    function resize(){
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      var r = canvas.getBoundingClientRect();
      W = r.width; H = r.height;
      canvas.width = Math.max(1, Math.round(W*dpr));
      canvas.height = Math.max(1, Math.round(H*dpr));
      ctx.setTransform(dpr,0,0,dpr,0,0);
    }
    function initBlobs(){
      blobs.length = 0;
      var count = Math.max(10, Math.min(26, Math.round((W*H)/46000)));
      for(var i=0;i<count;i++){
        blobs.push({
          x: Math.random()*W,
          y: Math.random()*H,
          r: 130 + Math.random()*230,
          vx: (Math.random()-0.5)*0.16,
          vy: (Math.random()-0.5)*0.09,
          a: 0.02 + Math.random()*0.05,
          hue: hues[Math.floor(Math.random()*3)]
        });
      }
    }
    function drawMist(){
      ctx.clearRect(0,0,W,H);
      ctx.globalCompositeOperation = 'lighter';
      for(var i=0;i<blobs.length;i++){
        var b = blobs[i];
        var g = ctx.createRadialGradient(b.x,b.y,0,b.x,b.y,b.r);
        g.addColorStop(0, 'rgba('+b.hue+','+b.a+')');
        g.addColorStop(1, 'rgba('+b.hue+',0)');
        ctx.fillStyle = g;
        ctx.beginPath(); ctx.arc(b.x,b.y,b.r,0,Math.PI*2); ctx.fill();
      }
      ctx.globalCompositeOperation = 'source-over';
    }
    function stepBlobs(){
      for(var i=0;i<blobs.length;i++){
        var b = blobs[i];
        b.x += b.vx; b.y += b.vy;
        if(b.x < -b.r) b.x = W+b.r; else if(b.x > W+b.r) b.x = -b.r;
        if(b.y < -b.r) b.y = H+b.r; else if(b.y > H+b.r) b.y = -b.r;
      }
    }
    function spawnBolt(){
      var x = W*(0.34 + Math.random()*0.56);
      var steps = 8 + Math.floor(Math.random()*6);
      var segs = [], cx = x;
      for(var i=0;i<=steps;i++){
        segs.push({x:cx, y:(H*0.9)*(i/steps)});
        cx += (Math.random()-0.5)*48;
      }
      bolts.push({segs:segs, life:0, ttl:520, hue: Math.random()<0.6 ? '226,232,240' : '20,184,166'});
    }
    function drawBolts(dt){
      for(var i=bolts.length-1;i>=0;i--){
        var bo = bolts[i]; bo.life += dt;
        var t = bo.life/bo.ttl;
        if(t >= 1){ bolts.splice(i,1); continue; }
        var alpha = Math.sin(t*Math.PI) * 0.45;
        ctx.save();
        ctx.globalCompositeOperation = 'lighter';
        ctx.strokeStyle = 'rgba('+bo.hue+','+alpha+')';
        ctx.lineWidth = 1.3;
        ctx.shadowColor = 'rgba('+bo.hue+','+alpha+')';
        ctx.shadowBlur = 16;
        ctx.beginPath();
        for(var s=0;s<bo.segs.length;s++){
          var p = bo.segs[s];
          if(s===0) ctx.moveTo(p.x,p.y); else ctx.lineTo(p.x,p.y);
        }
        ctx.stroke();
        ctx.restore();
      }
    }
    function frame(ts){
      var dt = last ? Math.min(50, ts-last) : 16;
      last = ts;
      stepBlobs(); drawMist();
      nextBolt -= dt;
      if(nextBolt <= 0){ spawnBolt(); nextBolt = 2800 + Math.random()*4600; }
      drawBolts(dt);
      raf = requestAnimationFrame(frame);
    }
    function start(){ if(!raf){ last = 0; raf = requestAnimationFrame(frame); } }
    function stop(){ if(raf){ cancelAnimationFrame(raf); raf = null; } }

    resize(); initBlobs();

    if(reduce){
      drawMist();               // single static atmospheric frame, no animation
    } else {
      start();
      var hero = document.getElementById('hero');
      if(hero && 'IntersectionObserver' in window){
        new IntersectionObserver(function(es){
          es.forEach(function(e){ e.isIntersecting ? start() : stop(); });
        }, {threshold:0}).observe(hero);
      }
    }

    var rt;
    window.addEventListener('resize', function(){
      clearTimeout(rt);
      rt = setTimeout(function(){ resize(); initBlobs(); if(reduce) drawMist(); }, 160);
    }, {passive:true});
  })();

  /* Waitlist: show success only after the server confirms persistence. */
  (function(){
    const form = document.getElementById('waitlist-form');
    const note = document.getElementById('waitlist-note');
    const button = form.querySelector('button');
    form.addEventListener('submit', async function(e){
      e.preventDefault();
      if (!form.reportValidity()) return;
      button.disabled = true;
      note.hidden = false;
      note.textContent = 'Saving your signup…';
      try {
        const response = await fetch('/api/waitlist', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: form.elements.email.value, consent: form.elements.consent.checked, website: form.elements.website.value }),
          signal: AbortSignal.timeout(12000),
        });
        const result = await response.json();
        if (!response.ok || result.ok !== true) throw new Error(result.error || 'Signup could not be saved. Please try again.');
        note.textContent = "Your interest is registered. Thank you.";
        form.reset();
      } catch (error) {
        note.textContent = error.name === 'TimeoutError' ? 'Signup confirmation timed out. Please try again.' : error.message;
      } finally { button.disabled = false; }
    });
  })();
})();
