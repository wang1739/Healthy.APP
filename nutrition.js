(() => {
  'use strict';

  const STORAGE_KEY = 'lightbite_nutrition_v1';
  const DEFAULT_GOALS = Object.freeze({kcal:1600,protein:100,carbs:180,fat:50,water:8});
  const MEALS = Object.freeze({
    breakfast:{name:'早餐',icon:'☀',time:'建议 07:00–09:00'},
    lunch:{name:'午餐',icon:'◐',time:'建议 11:30–13:30'},
    dinner:{name:'晚餐',icon:'☾',time:'建议 17:30–19:30'},
    snack:{name:'加餐',icon:'◇',time:'按需补充'}
  });
  const METRICS = ['kcal','protein','carbs','fat'];
  let storageWarning = false;
  let state = loadState();
  let selectedDate = dateKey(new Date());
  let formMode = 'library';
  let selectedFood = null;
  let editingId = null;
  let toastTimer = null;

  const $ = selector => document.querySelector(selector);
  const $$ = selector => [...document.querySelectorAll(selector)];
  const foodDialog = $('#food-dialog');
  const goalsDialog = $('#goals-dialog');
  const foodForm = $('#food-form');

  function dateKey(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  function dateFromKey(key) {
    const [year, month, day] = key.split('-').map(Number);
    return new Date(year, month - 1, day, 12);
  }

  function shiftDate(key, amount) {
    const date = dateFromKey(key);
    date.setDate(date.getDate() + amount);
    return dateKey(date);
  }

  function emptyState() {
    return {goals:{...DEFAULT_GOALS},days:{},customFoods:[]};
  }

  function loadState() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return emptyState();
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== 'object') throw new Error('invalid state');
      return {
        goals:{...DEFAULT_GOALS,...(parsed.goals || {})},
        days:parsed.days && typeof parsed.days === 'object' ? parsed.days : {},
        customFoods:Array.isArray(parsed.customFoods) ? parsed.customFoods : []
      };
    } catch (error) {
      storageWarning = true;
      return emptyState();
    }
  }

  function saveState(message = '') {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
      if (message) showToast(message);
      return true;
    } catch (error) {
      showToast('保存失败，请检查浏览器存储权限');
      return false;
    }
  }

  function getDay(key = selectedDate, create = false) {
    if (!state.days[key] && create) state.days[key] = {entries:[],water:0};
    const day = state.days[key];
    return {
      entries:Array.isArray(day?.entries) ? day.entries : [],
      water:Number.isFinite(+day?.water) ? +day.water : 0
    };
  }

  function ensureDay(key = selectedDate) {
    if (!state.days[key]) state.days[key] = {entries:[],water:0};
    if (!Array.isArray(state.days[key].entries)) state.days[key].entries = [];
    if (!Number.isFinite(+state.days[key].water)) state.days[key].water = 0;
    return state.days[key];
  }

  function totals(entries = getDay().entries) {
    return entries.reduce((sum, entry) => {
      METRICS.forEach(metric => { sum[metric] += Number(entry[metric]) || 0; });
      return sum;
    }, {kcal:0,protein:0,carbs:0,fat:0});
  }

  function round(value, digits = 1) {
    const factor = 10 ** digits;
    return Math.round((Number(value) || 0) * factor) / factor;
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>'"]/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
  }

  function isFuture(key = selectedDate) {
    return key > dateKey(new Date());
  }

  function uid() {
    return globalThis.crypto?.randomUUID?.() || `meal-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  }

  function showToast(message) {
    const toast = $('#toast');
    if (!toast) return;
    toast.textContent = message;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), 2400);
  }

  function renderDate() {
    const current = dateFromKey(selectedDate);
    const today = dateKey(new Date());
    const diff = Math.round((current - dateFromKey(today)) / 86400000);
    $('#date-label').textContent = diff === 0 ? '今天' : diff === -1 ? '昨天' : selectedDate;
    $('#date-full').textContent = new Intl.DateTimeFormat('zh-CN',{month:'long',day:'numeric',weekday:'long'}).format(current);
    $('#next-day').disabled = false;
    $('#today-button').hidden = selectedDate === today;
    $$('.js-add-food').forEach(button => {
      button.disabled = isFuture();
      button.title = isFuture() ? '未来日期不能添加记录' : '';
    });
  }

  function metricText(metric, value, goal) {
    const unit = metric === 'kcal' ? 'kcal' : 'g';
    const difference = goal - value;
    return difference >= 0 ? `还差 ${round(difference, metric === 'kcal' ? 0 : 1)} ${unit}` : `已超出 ${round(Math.abs(difference), metric === 'kcal' ? 0 : 1)} ${unit}`;
  }

  function renderSummary(currentTotals) {
    METRICS.forEach(metric => {
      const card = $(`.summary-card[data-metric="${metric}"]`);
      const value = currentTotals[metric];
      const goal = +state.goals[metric];
      const percent = goal > 0 ? Math.min(100, value / goal * 100) : 0;
      card.querySelector('strong b').textContent = metric === 'kcal' ? Math.round(value) : round(value);
      card.querySelector('p').textContent = `目标 ${goal} ${metric === 'kcal' ? 'kcal' : 'g'}`;
      card.querySelector('i').style.width = `${percent}%`;
      card.querySelector('em').textContent = metricText(metric, value, goal);
      const progress = card.querySelector('[role="progressbar"]');
      progress.setAttribute('aria-valuemin','0');
      progress.setAttribute('aria-valuemax',String(goal));
      progress.setAttribute('aria-valuenow',String(round(value)));
    });
  }

  function calculateScore(currentTotals, entryCount) {
    if (!entryCount) return 0;
    const scores = METRICS.map(metric => {
      const goal = +state.goals[metric] || 1;
      return Math.max(0, 1 - Math.abs(currentTotals[metric] - goal) / goal);
    });
    return Math.round(scores.reduce((sum, value) => sum + value, 0) / scores.length * 100);
  }

  function renderScore(currentTotals, entryCount) {
    const score = calculateScore(currentTotals, entryCount);
    $('#health-score').textContent = score;
    $('#score-ring').style.setProperty('--score',score);
    if (!entryCount) {
      $('#score-title').textContent = '从第一餐开始';
      $('#score-copy').textContent = '记录后会实时计算完成度';
    } else if (score >= 85) {
      $('#score-title').textContent = '今天很均衡';
      $('#score-copy').textContent = '营养摄入正在接近目标';
    } else if (score >= 60) {
      $('#score-title').textContent = '继续保持节奏';
      $('#score-copy').textContent = '下一餐补足营养缺口';
    } else {
      $('#score-title').textContent = '还有调整空间';
      $('#score-copy').textContent = '看看下方的今日建议';
    }
  }

  function renderMeals(day) {
    const container = $('#meal-groups');
    container.innerHTML = Object.entries(MEALS).map(([key, meal]) => {
      const entries = day.entries.filter(entry => entry.meal === key);
      const mealKcal = entries.reduce((sum, entry) => sum + (+entry.kcal || 0), 0);
      const content = entries.length ? entries.map(entry => `
        <article class="meal-item">
          <div><h4>${escapeHtml(entry.name)}</h4><p>${round(entry.grams,0)}g · 蛋白质 ${round(entry.protein)}g · 碳水 ${round(entry.carbs)}g · 脂肪 ${round(entry.fat)}g</p></div>
          <strong>${Math.round(entry.kcal)} kcal</strong>
          <div class="meal-actions"><button type="button" data-action="edit" data-id="${escapeHtml(entry.id)}" aria-label="编辑${escapeHtml(entry.name)}">✎</button><button type="button" data-action="delete" data-id="${escapeHtml(entry.id)}" aria-label="删除${escapeHtml(entry.name)}">×</button></div>
        </article>`).join('') : `<div class="meal-empty"><span>还没有记录${meal.name}</span><button type="button" data-action="add" data-meal="${key}">＋ 添加</button></div>`;
      return `<section class="meal-group"><div class="meal-group-head"><div class="meal-title"><span class="meal-icon">${meal.icon}</span><div><h3>${meal.name}</h3><span>${meal.time}</span></div></div><span class="meal-total">${Math.round(mealKcal)} kcal</span></div><div class="meal-items">${content}</div></section>`;
    }).join('');
  }

  function renderWater(day) {
    const count = Math.max(0,Math.min(30,Math.round(day.water || 0)));
    const goal = Math.max(1,Math.round(state.goals.water || 8));
    $('#water-count').textContent = count;
    $('#water-goal').textContent = goal;
    const visibleCups = Math.min(Math.max(goal,8),12);
    $('#water-cups').innerHTML = Array.from({length:visibleCups},(_,index) => `<span class="water-cup${index < count ? ' full' : ''}" aria-hidden="true"></span>`).join('');
    $('#water-cups').setAttribute('aria-label',`已喝 ${count} 杯，目标 ${goal} 杯`);
    $('#water-minus').disabled = count <= 0;
    $('#water-plus').disabled = count >= 30;
  }

  function makeAdvice(currentTotals, day) {
    if (!day.entries.length) return ['先记录今天的第一餐，我们会帮你计算营养进度。', day.water < state.goals.water / 2 ? '现在喝一杯水，为今天补充一个好开始。' : '饮水节奏不错，继续保持。'];
    const advice = [];
    if (currentTotals.fat > state.goals.fat) advice.push('脂肪已超过目标，下一餐试试清蒸、焯拌或少油做法。');
    if (currentTotals.kcal > state.goals.kcal) advice.push('今日热量已经超出目标，接下来优先选择低热量蔬菜和水。');
    if (currentTotals.protein < state.goals.protein * .7) advice.push(`蛋白质还差约 ${Math.max(0,Math.round(state.goals.protein-currentTotals.protein))}g，可补充鸡胸肉、鸡蛋或豆腐。`);
    if (day.water < state.goals.water * .5) advice.push(`饮水完成不足一半，今天还可以再喝 ${Math.max(0,state.goals.water-day.water)} 杯。`);
    const ratios = METRICS.map(metric => currentTotals[metric] / state.goals[metric]);
    if (ratios.every(ratio => ratio >= .8 && ratio <= 1.1)) advice.push('今天的营养很均衡，保持现在的饮食节奏。');
    if (!advice.length) advice.push('记录得很好，下一餐继续保证主食、蛋白质和蔬菜的搭配。');
    return advice.slice(0,3);
  }

  function renderAdvice(currentTotals, day) {
    $('#advice-list').innerHTML = makeAdvice(currentTotals,day).map(item => `<li>${escapeHtml(item)}</li>`).join('');
  }

  function renderTrend() {
    const data = Array.from({length:7},(_,index) => {
      const key = shiftDate(selectedDate,index-6);
      const value = totals(getDay(key).entries).kcal;
      return {key,value,date:dateFromKey(key)};
    });
    const max = Math.max(state.goals.kcal * 1.25,...data.map(item => item.value),1);
    const targetHeight = Math.min(100,state.goals.kcal / max * 100);
    const chart = $('#trend-chart');
    chart.style.setProperty('--target-position',`${targetHeight}%`);
    chart.innerHTML = data.map(item => {
      const height = Math.min(100,item.value / max * 100);
      const label = new Intl.DateTimeFormat('zh-CN',{weekday:'short'}).format(item.date).replace('周','');
      return `<div class="trend-day${item.key === dateKey(new Date()) ? ' today' : ''}" style="--height:${height}%"><b>${item.value ? Math.round(item.value) : ''}</b><i title="${item.key}：${Math.round(item.value)} kcal"></i><span>${label}</span></div>`;
    }).join('');
  }

  function render() {
    const day = getDay();
    const currentTotals = totals(day.entries);
    renderDate();
    renderSummary(currentTotals);
    renderMeals(day);
    renderWater(day);
    renderScore(currentTotals,day.entries.length);
    renderAdvice(currentTotals,day);
    renderTrend();
  }

  function allFoods() {
    const custom = state.customFoods.map(food => ({...food,category:'我的食物',portions:food.portions || [['常用份量',100]]}));
    return [...(window.LIGHTBITE_FOODS || []),...custom];
  }

  function renderFoodResults(query = '') {
    const keyword = query.trim().toLowerCase();
    const matches = allFoods().filter(food => !keyword || `${food.name}${food.category}`.toLowerCase().includes(keyword)).slice(0,30);
    $('#food-results').innerHTML = matches.length ? matches.map(food => `<button type="button" class="food-option${selectedFood?.id === food.id ? ' selected' : ''}" data-food-id="${escapeHtml(food.id)}" role="option" aria-selected="${selectedFood?.id === food.id}"><b>${escapeHtml(food.name)}</b><span>${escapeHtml(food.category)} · ${Math.round(food.kcal)} kcal/100g</span></button>`).join('') : '<div class="meal-empty"><span>没有找到，试试手动添加</span></div>';
  }

  function chooseFood(id, keepGrams = false) {
    selectedFood = allFoods().find(food => food.id === id) || null;
    renderFoodResults($('#food-search').value);
    const portion = $('#portion-select');
    portion.innerHTML = '<option value="">自定义克数</option>' + (selectedFood?.portions || []).map(([label,grams]) => `<option value="${grams}">${escapeHtml(label)} · ${grams}g</option>`).join('');
    if (selectedFood && !keepGrams) {
      const firstGrams = selectedFood.portions?.[0]?.[1] || 100;
      $('#food-grams').value = firstGrams;
      portion.value = String(firstGrams);
    }
    renderPreview();
  }

  function renderPreview() {
    if (!selectedFood) {
      $('#nutrition-preview').innerHTML = '<span>请选择一种食物</span>';
      return;
    }
    const grams = Math.max(0,+$('#food-grams').value || 0);
    const ratio = grams / 100;
    $('#nutrition-preview').innerHTML = [
      ['热量',`${Math.round(selectedFood.kcal*ratio)} kcal`],
      ['蛋白质',`${round(selectedFood.protein*ratio)} g`],
      ['碳水',`${round(selectedFood.carbs*ratio)} g`],
      ['脂肪',`${round(selectedFood.fat*ratio)} g`]
    ].map(([label,value]) => `<div><b>${value}</b><span>${label}</span></div>`).join('');
  }

  function setFormMode(mode) {
    formMode = mode;
    $$('[data-form-mode]').forEach(button => button.classList.toggle('active',button.dataset.formMode === mode));
    $('#library-fields').hidden = mode !== 'library';
    $('#manual-fields').hidden = mode !== 'manual';
    $('#food-error').textContent = '';
  }

  function openFoodDialog(meal = 'breakfast', entry = null) {
    if (isFuture()) {
      showToast('未来日期不能添加记录');
      return;
    }
    foodForm.reset();
    editingId = entry?.id || null;
    selectedFood = null;
    $('#food-dialog-title').textContent = entry ? '编辑食物' : '添加食物';
    $('#meal-select').value = entry?.meal || meal;
    $('#food-grams').value = '100';
    $('#food-search').value = '';
    $('#portion-select').innerHTML = '<option value="">自定义克数</option>';
    if (entry) {
      setFormMode('manual');
      $('#manual-name').value = entry.name;
      $('#manual-grams').value = entry.grams;
      $('#manual-kcal').value = round(entry.kcal);
      $('#manual-protein').value = round(entry.protein);
      $('#manual-carbs').value = round(entry.carbs);
      $('#manual-fat').value = round(entry.fat);
      $('#save-custom').checked = false;
    } else {
      setFormMode('library');
      renderFoodResults();
      renderPreview();
    }
    $('#food-error').textContent = '';
    foodDialog.showModal();
    setTimeout(() => (entry ? $('#manual-name') : $('#food-search')).focus(),0);
  }

  function validateNumber(value, min, max) {
    const number = Number(value);
    return Number.isFinite(number) && number >= min && number <= max ? number : null;
  }

  function buildLibraryEntry() {
    const grams = validateNumber($('#food-grams').value,1,5000);
    if (!selectedFood) throw new Error('请先选择一种食物');
    if (grams === null) throw new Error('请输入 1–5000 克之间的有效份量');
    const ratio = grams / 100;
    return {name:selectedFood.name,grams,kcal:selectedFood.kcal*ratio,protein:selectedFood.protein*ratio,carbs:selectedFood.carbs*ratio,fat:selectedFood.fat*ratio,source:selectedFood.id};
  }

  function buildManualEntry() {
    const name = $('#manual-name').value.trim();
    const grams = validateNumber($('#manual-grams').value,1,5000);
    const kcal = validateNumber($('#manual-kcal').value,0,10000);
    const protein = validateNumber($('#manual-protein').value,0,1000);
    const carbs = validateNumber($('#manual-carbs').value,0,1000);
    const fat = validateNumber($('#manual-fat').value,0,1000);
    if (!name || name.length > 30) throw new Error('请输入 1–30 个字符的食物名称');
    if (grams === null) throw new Error('请输入 1–5000 克之间的有效份量');
    if ([kcal,protein,carbs,fat].includes(null)) throw new Error('请输入有效且非负的营养数据');
    if ($('#save-custom').checked) saveCustomFood({name,grams,kcal,protein,carbs,fat});
    return {name,grams,kcal,protein,carbs,fat,source:'manual'};
  }

  function saveCustomFood(entry) {
    const ratio = 100 / entry.grams;
    const normalized = {id:`custom-${uid()}`,name:entry.name,kcal:entry.kcal*ratio,protein:entry.protein*ratio,carbs:entry.carbs*ratio,fat:entry.fat*ratio,portions:[['常用份量',entry.grams]]};
    state.customFoods = state.customFoods.filter(food => food.name !== entry.name);
    state.customFoods.push(normalized);
  }

  function saveFoodEntry(event) {
    event.preventDefault();
    try {
      const values = formMode === 'library' ? buildLibraryEntry() : buildManualEntry();
      const day = ensureDay();
      const existing = editingId ? day.entries.find(entry => entry.id === editingId) : null;
      const record = {...values,id:editingId || uid(),meal:$('#meal-select').value,createdAt:existing?.createdAt || new Date().toISOString()};
      if (editingId) day.entries = day.entries.map(entry => entry.id === editingId ? record : entry);
      else day.entries.push(record);
      saveState(editingId ? '记录已更新' : '已添加到今日饮食');
      foodDialog.close();
      render();
    } catch (error) {
      $('#food-error').textContent = error.message;
    }
  }

  function editEntry(id) {
    const entry = getDay().entries.find(item => item.id === id);
    if (entry) openFoodDialog(entry.meal,entry);
  }

  function deleteEntry(id) {
    const day = ensureDay();
    const entry = day.entries.find(item => item.id === id);
    if (!entry || !confirm(`确定删除“${entry.name}”吗？`)) return;
    day.entries = day.entries.filter(item => item.id !== id);
    saveState('记录已删除');
    render();
  }

  function updateWater(amount) {
    if (isFuture()) return showToast('未来日期不能记录饮水');
    const day = ensureDay();
    day.water = Math.max(0,Math.min(30,(+day.water || 0) + amount));
    saveState();
    render();
  }

  function openGoalsDialog() {
    const form = $('#goals-form');
    Object.entries(state.goals).forEach(([key,value]) => { if (form.elements[key]) form.elements[key].value = value; });
    $('#goals-error').textContent = '';
    goalsDialog.showModal();
  }

  function saveGoals(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const ranges = {kcal:[800,5000],protein:[10,500],carbs:[10,800],fat:[10,300],water:[1,30]};
    const next = {};
    for (const [key,[min,max]] of Object.entries(ranges)) {
      const value = validateNumber(form.elements[key].value,min,max);
      if (value === null) {
        $('#goals-error').textContent = `请检查${form.elements[key].closest('label').childNodes[0].textContent.trim()}的范围`;
        return;
      }
      next[key] = value;
    }
    state.goals = next;
    saveState('每日目标已更新');
    goalsDialog.close();
    render();
  }

  function clearSelectedDay() {
    const day = getDay();
    if (!day.entries.length && !day.water) return showToast('当天还没有记录');
    if (!confirm(`确定清空 ${selectedDate} 的全部饮食和饮水记录吗？`)) return;
    delete state.days[selectedDate];
    saveState('当天记录已清空');
    render();
  }

  $$('.js-add-food').forEach(button => button.addEventListener('click',() => {
    const hour = new Date().getHours();
    const meal = hour < 10 ? 'breakfast' : hour < 15 ? 'lunch' : hour < 20 ? 'dinner' : 'snack';
    openFoodDialog(meal);
  }));
  $('#prev-day').addEventListener('click',() => { selectedDate = shiftDate(selectedDate,-1); render(); });
  $('#next-day').addEventListener('click',() => { selectedDate = shiftDate(selectedDate,1); render(); });
  $('#today-button').addEventListener('click',() => { selectedDate = dateKey(new Date()); render(); });
  $('#meal-groups').addEventListener('click',event => {
    const button = event.target.closest('button[data-action]');
    if (!button) return;
    if (button.dataset.action === 'add') openFoodDialog(button.dataset.meal);
    if (button.dataset.action === 'edit') editEntry(button.dataset.id);
    if (button.dataset.action === 'delete') deleteEntry(button.dataset.id);
  });
  $('#water-minus').addEventListener('click',() => updateWater(-1));
  $('#water-plus').addEventListener('click',() => updateWater(1));
  $('#clear-day').addEventListener('click',clearSelectedDay);
  $('#open-goals').addEventListener('click',openGoalsDialog);
  $$('[data-close]').forEach(button => button.addEventListener('click',() => document.getElementById(button.dataset.close)?.close()));
  $$('[data-form-mode]').forEach(button => button.addEventListener('click',() => setFormMode(button.dataset.formMode)));
  $('#food-search').addEventListener('input',event => renderFoodResults(event.target.value));
  $('#food-results').addEventListener('click',event => {
    const option = event.target.closest('[data-food-id]');
    if (option) chooseFood(option.dataset.foodId);
  });
  $('#portion-select').addEventListener('change',event => { if (event.target.value) $('#food-grams').value = event.target.value; renderPreview(); });
  $('#food-grams').addEventListener('input',renderPreview);
  foodForm.addEventListener('submit',saveFoodEntry);
  $('#goals-form').addEventListener('submit',saveGoals);
  [foodDialog,goalsDialog].forEach(dialog => dialog.addEventListener('click',event => { if (event.target === dialog) dialog.close(); }));

  render();
  if (storageWarning) setTimeout(() => showToast('本地记录读取失败，已使用空白数据'),100);
})();
