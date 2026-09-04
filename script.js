/* ---------- 配置：上线后只需改这里 ---------- */
const APP_LINKS = {
  iOS: '',      // 例：https://apps.apple.com/cn/app/idXXXXXXXX
  安卓: '',     // 例：https://play.google.com/store/apps/details?id=xxx 或 APK 直链
};
const UA = navigator.userAgent;
const IS_IOS = /iPhone|iPad|iPod/i.test(UA);
const IS_ANDROID = /Android/i.test(UA);
const IS_MOBILE = IS_IOS || IS_ANDROID;

/* ---------- 顶栏、菜单 ---------- */
const bar = document.querySelector('.topbar');
const menu = document.querySelector('.menu-button');
menu?.addEventListener('click', () => { const open = bar.classList.toggle('open'); menu.setAttribute('aria-expanded', open); });
document.querySelectorAll('.nav a').forEach(a => a.addEventListener('click', () => bar.classList.remove('open')));
addEventListener('scroll', () => bar.classList.toggle('scrolled', scrollY > 26), {passive:true});

/* ---------- 导航 scroll-spy：按当前区块高亮 ---------- */
const navLinks = [...document.querySelectorAll('.nav a[href^="#"]')];
const navTargets = navLinks.map(a => document.querySelector(a.getAttribute('href'))).filter(Boolean);
const setActiveNav = id => navLinks.forEach(a => a.classList.toggle('active', a.getAttribute('href') === '#' + id));
if (navTargets.length) {
  const spy = new IntersectionObserver(entries => {
    const visible = entries.filter(e => e.isIntersecting).sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
    if (visible) setActiveNav(visible.target.id);
  }, {rootMargin: '-40% 0px -50% 0px', threshold: [0, .1, .3, .6]});
  navTargets.forEach(t => spy.observe(t));
}

/* ---------- 滚动揭示、数字滚动 ---------- */
const reveal = new IntersectionObserver(entries => entries.forEach(e => { if(e.isIntersecting){ e.target.classList.add('visible'); reveal.unobserve(e.target); }}), {threshold:.14});
document.querySelectorAll('.reveal').forEach(el => reveal.observe(el));

const statObserver = new IntersectionObserver(entries => entries.forEach(entry => { if (!entry.isIntersecting) return; entry.target.querySelectorAll('[data-count]').forEach(el => { const target = +el.dataset.count; const start = performance.now(); const duration = 1300; const tick = now => { const p = Math.min((now-start)/duration, 1); const value = Math.floor(target * (1 - Math.pow(1-p, 3))); el.textContent = value.toLocaleString('zh-CN') + el.dataset.suffix; if(p < 1) requestAnimationFrame(tick); }; requestAnimationFrame(tick); }); statObserver.unobserve(entry.target); }), {threshold:.55});
const stats = document.querySelector('.trust'); if(stats) statObserver.observe(stats);

/* ---------- 食谱分类过滤 ---------- */
const recipeCards = [...document.querySelectorAll('.recipe[data-tags]')];
const recipeEmpty = document.querySelector('.recipe-empty');
const filterRecipes = tag => {
  let shown = 0;
  recipeCards.forEach(card => {
    const tags = card.dataset.tags.split(',').map(t => t.trim());
    const match = tag === 'all' || tags.includes(tag);
    card.hidden = !match;
    if (match) shown++;
  });
  if (recipeEmpty) recipeEmpty.hidden = shown > 0;
};
document.querySelectorAll('.chips button').forEach(button => button.addEventListener('click', () => {
  document.querySelector('.chips .active')?.classList.remove('active');
  button.classList.add('active');
  filterRecipes(button.dataset.tag || 'all');
}));
document.querySelector('.all-recipes-link')?.addEventListener('click', () => {
  document.querySelector('.chips button[data-tag="all"]')?.click();
});

/* ---------- 会员计费方式切换：联动价格 ---------- */
const priceNodes = [...document.querySelectorAll('.price b[data-year]')];
const animatePrice = (el, to) => {
  const from = +el.textContent || 0;
  if (from === to) return;
  const start = performance.now();
  const tick = now => { const p = Math.min((now - start) / 350, 1); el.textContent = Math.round(from + (to - from) * p); if (p < 1) requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
};
const applyBilling = mode => {
  priceNodes.forEach(el => {
    animatePrice(el, +el.dataset[mode]);
    const unit = el.nextElementSibling;
    if (unit) unit.textContent = mode === 'year' ? '/ 月 · 按年付' : '/ 月';
  });
};
document.querySelectorAll('.billing button').forEach(button => button.addEventListener('click', () => {
  document.querySelector('.billing .selected')?.classList.remove('selected');
  button.classList.add('selected');
  applyBilling(button.dataset.billing || 'year');
}));

/* ---------- 下载：按平台跳转，PC 端显示二维码 ---------- */
const qrCard = document.getElementById('qr-card');
if (qrCard && !IS_MOBILE) {
  qrCard.hidden = false;
  qrCard.querySelector('img')?.addEventListener('error', () => qrCard.classList.add('no-img'));
}
document.querySelectorAll('.download-link').forEach(link => {
  const platform = link.dataset.platform;
  const url = APP_LINKS[platform];
  if ((platform === 'iOS' && IS_IOS) || (platform === '安卓' && IS_ANDROID)) link.classList.add('recommended');
  link.addEventListener('click', () => {
    if (url) {
      window.open(url, '_blank', 'noopener,noreferrer');
      return;
    }
    alert(`轻食记 ${platform} 版即将上线，敬请期待！`);
  });
});

/* ---------- FAQ：一次只展开一项 ---------- */
const faqItems = [...document.querySelectorAll('.accordion details')];
faqItems.forEach(item => item.addEventListener('toggle', () => { if (item.open) faqItems.forEach(o => { if (o !== item) o.open = false; }); }));
