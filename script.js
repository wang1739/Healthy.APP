const bar = document.querySelector('.topbar');
const menu = document.querySelector('.menu-button');
menu?.addEventListener('click', () => { const open = bar.classList.toggle('open'); menu.setAttribute('aria-expanded', open); });
document.querySelectorAll('.nav a').forEach(a => a.addEventListener('click', () => bar.classList.remove('open')));
addEventListener('scroll', () => bar.classList.toggle('scrolled', scrollY > 26), {passive:true});

const reveal = new IntersectionObserver(entries => entries.forEach(e => { if(e.isIntersecting){ e.target.classList.add('visible'); reveal.unobserve(e.target); }}), {threshold:.14});
document.querySelectorAll('.reveal').forEach(el => reveal.observe(el));

const statObserver = new IntersectionObserver(entries => entries.forEach(entry => { if (!entry.isIntersecting) return; entry.target.querySelectorAll('[data-count]').forEach(el => { const target = +el.dataset.count; const start = performance.now(); const duration = 1300; const tick = now => { const p = Math.min((now-start)/duration, 1); const value = Math.floor(target * (1 - Math.pow(1-p, 3))); el.textContent = value.toLocaleString('zh-CN') + el.dataset.suffix; if(p < 1) requestAnimationFrame(tick); }; requestAnimationFrame(tick); }); statObserver.unobserve(entry.target); }), {threshold:.55});
const stats = document.querySelector('.trust'); if(stats) statObserver.observe(stats);

document.querySelectorAll('.chips button').forEach(button => button.addEventListener('click', () => { document.querySelector('.chips .active')?.classList.remove('active'); button.classList.add('active'); }));
document.querySelectorAll('.billing button').forEach(button => button.addEventListener('click', () => { document.querySelector('.billing .selected')?.classList.remove('selected'); button.classList.add('selected'); }));

document.querySelectorAll('.download-link').forEach(link => link.addEventListener('click', event => {
  event.preventDefault();
  const platform = link.dataset.platform;
  alert(`轻食记 ${platform} 版即将上线，敬请期待！`);
}));
