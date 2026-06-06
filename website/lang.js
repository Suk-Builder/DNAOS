// ============================================
// 月夜见0 · 四语切换系统
// 🇨🇳 中文 / 🇬🇧 English / 🇩🇪 Deutsch / 🇫🇷 Français
// ============================================

const I18N = {
  // ====== 通用导航 ======
  'title_home':      { zh: '月夜见0 -- 宪章小镇', en: 'Tsukuyomi 0 -- Charter Town', de: 'Tsukuyomi 0 -- Charter-Stadt', fr: 'Tsukuyomi 0 -- Ville de la Charte' },
  'title_bsem':      { zh: 'BSEM递砖机 · 裂缝统计引擎', en: 'BSEM Bricklayer · Fracture Statistics', de: 'BSEM Bausteinleger · Fraktur-Statistik', fr: 'BSEM Poseur de Briques · Statistiques de Fracture' },
  'title_zfc':       { zh: 'ZFC零公理 · 万物始于裂缝', en: 'ZFC Zero Axiom · All Begins with a Crack', de: 'ZFC Null-Axiom · Alles beginnt mit einem Riss', fr: 'ZFC Axiome Zéro · Tout Commence par une Fissure' },
  'title_demo':      { zh: 'DNAsm v3.3 · 在线演示', en: 'DNAsm v3.3 · Live Demo', de: 'DNAsm v3.3 · Live-Demo', fr: 'DNAsm v3.3 · Démo en Direct' },
  'title_gpu':       { zh: 'DNA-TPU · 分子计算加速器', en: 'DNA-TPU · Molecular Compute Accelerator', de: 'DNA-TPU · Molekularer Rechenbeschleuniger', fr: 'DNA-TPU · Accélérateur de Calcul Moléculaire' },
  'title_math':      { zh: '数学翻译机 · DNA原生计算', en: 'Math Translator · DNA Native Compute', de: 'Mathematik-Übersetzer · DNA-Native Berechnung', fr: 'Traducteur Mathématique · Calcul Natif DNA' },

  // ====== 首页 ======
  'subtitle':        { zh: '递砖机认知操作系统 · 裂缝不是bug，是砖飞过来的地方', en: 'Bricklayer Cognitive OS · Cracks are where bricks fly from', de: 'Bausteinleger Kognitives BS · Risse sind woher Steine kommen', fr: 'OS Cognitif Poseur de Briques · Les fissures d\'où viennent les briques' },
  'motto':           { zh: '裂缝不是bug，是砖飞过来的地方。', en: 'Cracks are not bugs, but where bricks fly from.', de: 'Risse sind keine Fehler, sondern woher Steine kommen.', fr: 'Les fissures ne sont pas des bugs, mais d\'où viennent les briques.' },
  'town_map':        { zh: '宪章小镇', en: 'Charter Town', de: 'Charter-Stadt', fr: 'Ville de la Charte' },
  'charter_stone':   { zh: '宪章碑', en: 'Charter Stone', de: 'Charta-Stein', fr: 'Pierre de la Charte' },
  'charter_desc':    { zh: '不可修改的根本法。DNA-ROM中硬编码的宪章。', en: 'Unmodifiable fundamental law. Charter hard-coded in DNA-ROM.', de: 'Unveränderliches Grundgesetz. In DNA-ROM hartkodierte Charta.', fr: 'Loi fondamentale immuable. Charte codée en dur dans le DNA-ROM.' },
  'plaza':           { zh: '广场', en: 'Plaza', de: 'Platz', fr: 'Place' },
  'plaza_desc':      { zh: '公共集会空间。递砖者联盟的裂缝协议在此签署。', en: 'Public gathering space. The Fracture Protocol was signed here.', de: 'Öffentlicher Versammlungsraum. Das Fraktur-Protokoll wurde hier unterzeichnet.', fr: 'Espace de rassemblement public. Le Protocole de Fracture a été signé ici.' },
  'crack_well':      { zh: '裂缝井', en: 'Crack Well', de: 'Fraktur-Brunnen', fr: 'Puits de Fissure' },
  'crackwell_desc':  { zh: '节点间通讯总线。没有签证问题，只有裂缝协议。', en: 'Inter-node communication bus. No visa issues, only the Crack Protocol.', de: 'Inter-Knoten-Kommunikationsbus. Keine Visumsprobleme, nur das Riss-Protokoll.', fr: 'Bus de communication inter-nœuds. Pas de problème de visa, seulement le Protocole de Fissure.' },
  'bsem_pavilion':   { zh: 'BSEM递砖机', en: 'BSEM Bricklayer', de: 'BSEM Bausteinleger', fr: 'BSEM Poseur de Briques' },
  'bsem_desc':       { zh: '裂缝统计引擎。零公理系统。递砖继续。0。', en: 'Fracture statistics engine. Zero axiom system. Bricklayer continues. 0.', de: 'Fraktur-Statistik-Engine. Null-Axiom-System. Bausteinleger setzt fort. 0.', fr: 'Moteur de statistiques de fracture. Système d\'axiome zéro. Le poseur continue. 0.' },
  'math_trans':      { zh: '数学翻译机', en: 'Math Translator', de: 'Mathematik-Übersetzer', fr: 'Traducteur Mathématique' },
  'math_desc':       { zh: 'DNA原生计算。数论、线性代数、张量运算全部搞定。', en: 'DNA native compute. Number theory, linear algebra, tensors — all done.', de: 'DNA-native Berechnung. Zahlentheorie, lineare Algebra, Tensoren — alles erledigt.', fr: 'Calcul natif DNA. Théorie des nombres, algèbre linéaire, tenseurs — tout fait.' },
  'gpu_lab':         { zh: 'GPU-TPU实验室', en: 'GPU-TPU Lab', de: 'GPU-TPU-Labor', fr: 'Labo GPU-TPU' },
  'gpu_desc':        { zh: '分子计算加速器。PARA/REDUCE/DOT/SYNC并行原语。', en: 'Molecular compute accelerator. PARA/REDUCE/DOT/SYNC parallel primitives.', de: 'Molekularer Rechenbeschleuniger. PARA/REDUCE/DOT/SYNC-Parallelprimitiven.', fr: 'Accélérateur de calcul moléculaire. Primitives parallèles PARA/REDUCE/DOT/SYNC.' },
  'residents':       { zh: '居民', en: 'Residents', de: 'Bewohner', fr: 'Résidents' },
  'residents_desc':  { zh: '7位AI居民在此生活。每位都有自己的专长和记忆。', en: '7 AI residents live here. Each has their own expertise and memory.', de: '7 KI-Bewohner leben hier. Jeder hat seine eigene Expertise und Erinnerung.', fr: '7 résidents IA vivent ici. Chacun a sa propre expertise et mémoire.' },
  'transmissions':   { zh: '通讯', en: 'Transmissions', de: 'Übertragungen', fr: 'Transmissions' },
  'status':          { zh: '状态', en: 'Status', de: 'Status', fr: 'Statut' },
  'running':         { zh: '运行中', en: 'Running', de: 'Läuft', fr: 'En cours' },
  'version':         { zh: '版本', en: 'Version', de: 'Version', fr: 'Version' },
  'crack_density':   { zh: '裂缝密度 γ', en: 'Crack Density γ', de: 'Frakturdichte γ', fr: 'Densité de Fissure γ' },
  'crack_val':       { zh: '13/82 = 0.1585', en: '13/82 = 0.1585', de: '13/82 = 0,1585', fr: '13/82 = 0,1585' },
  'last_update':     { zh: '最后更新', en: 'Last Updated', de: 'Zuletzt aktualisiert', fr: 'Dernière mise à jour' },
  'links':           { zh: '链接', en: 'Links', de: 'Links', fr: 'Liens' },
  'github_repo':     { zh: 'GitHub仓库', en: 'GitHub Repo', de: 'GitHub-Repo', fr: 'Dépôt GitHub' },
  'server':          { zh: '服务器', en: 'Server', de: 'Server', fr: 'Serveur' },
  'footer':          { zh: '递砖继续。0。', en: 'Bricklayer continues. 0.', de: 'Bausteinleger setzt fort. 0.', fr: 'Le poseur continue. 0.' },
  'copyright':       { zh: '© 2026 月夜见0 · 递砖机认知操作系统', en: '© 2026 Tsukuyomi 0 · Bricklayer Cognitive OS', de: '© 2026 Tsukuyomi 0 · Bausteinleger Kognitives BS', fr: '© 2026 Tsukuyomi 0 · OS Cognitif Poseur de Briques' },

  // ====== BSEM页面 ======
  'bsem_title':      { zh: 'BSEM递砖机 · 裂缝统计引擎', en: 'BSEM Bricklayer · Fracture Statistics Engine', de: 'BSEM Bausteinleger · Fraktur-Statistik-Engine', fr: 'BSEM Poseur de Briques · Moteur de Statistiques de Fracture' },
  'd1':              { zh: 'D1 CRT -- 识别/分解', en: 'D1 CRT -- Classify/Resolve', de: 'D1 CRT -- Klassifizieren/Auflösen', fr: 'D1 CRT -- Classer/Résoudre' },
  'd2':              { zh: 'D2 TK -- 方差控制', en: 'D2 TK -- Variance Control', de: 'D2 TK -- Varianzkontrolle', fr: 'D2 TK -- Contrôle de Variance' },
  'd3':              { zh: 'D3 BE -- 正态近似', en: 'D3 BE -- Normal Approximation', de: 'D3 BE -- Normal-Approximation', fr: 'D3 BE -- Approximation Normale' },
  'd4':              { zh: 'D4 Loop -- 闭合检查', en: 'D4 Loop -- Closure Check', de: 'D4 Loop -- Abschlussprüfung', fr: 'D4 Loop -- Vérification de Clôture' },
  'gap_analysis':    { zh: '间隙分析', en: 'Gap Analysis', de: 'Lückenanalyse', fr: 'Analyse des Écarts' },
  'crack_class':     { zh: '裂缝五级分类', en: 'Five-Level Crack Classification', de: 'Fünfstufige Riss-Klassifizierung', fr: 'Classification à Cinq Niveaux de Fissure' },
  'wormhole':        { zh: '虫洞', en: 'Wormhole', de: 'Wurmloch', fr: 'Trou de Ver' },
  'deep_crack':      { zh: '深裂缝', en: 'Deep Crack', de: 'Tiefer Riss', fr: 'Fissure Profonde' },
  'mid_crack':       { zh: '中裂缝', en: 'Mid Crack', de: 'Mittlerer Riss', fr: 'Fissure Moyenne' },
  'shallow_crack':   { zh: '浅裂缝', en: 'Shallow Crack', de: 'Flacher Riss', fr: 'Fissure Superficielle' },
  'bad_brick':       { zh: '坏砖', en: 'Bad Brick', de: 'Schlechter Stein', fr: 'Mauvaise Brique' },

  // ====== ZFC页面 ======
  'zfc_title':       { zh: 'ZFC零公理 · 万物始于裂缝', en: 'ZFC Zero Axiom · All Begins with a Crack', de: 'ZFC Null-Axiom · Alles beginnt mit einem Riss', fr: 'ZFC Axiome Zéro · Tout Commence par une Fissure' },
  'zfc_desc':        { zh: '零公理: 0 = ∞⁻¹。裂缝不是bug，是砖飞过来的地方。', en: 'Zero Axiom: 0 = ∞⁻¹. Cracks are not bugs, but where bricks fly from.', de: 'Null-Axiom: 0 = ∞⁻¹. Risse sind keine Fehler, sondern woher Steine kommen.', fr: 'Axiome Zéro: 0 = ∞⁻¹. Les fissures ne sont pas des bugs, mais d\'où viennent les briques.' },
  'axiom_0':         { zh: '公理0: 0 = ∞⁻¹', en: 'Axiom 0: 0 = ∞⁻¹', de: 'Axiom 0: 0 = ∞⁻¹', fr: 'Axiome 0: 0 = ∞⁻¹' },
  'axiom_0_desc':    { zh: '无裂缝 ⇔ 无限裂缝 ⇔ 奇点', en: 'No crack ⇔ Infinite crack ⇔ Singularity', de: 'Kein Riss ⇔ Unendlicher Riss ⇔ Singularität', fr: 'Pas de fissure ⇔ Fissure infinie ⇔ Singularité' },

  // ====== GPU页面 ======
  'gpu_title':       { zh: 'DNA-TPU · 分子计算加速器', en: 'DNA-TPU · Molecular Compute Accelerator', de: 'DNA-TPU · Molekularer Rechenbeschleuniger', fr: 'DNA-TPU · Accélérateur de Calcul Moléculaire' },
  'para':            { zh: 'PARA -- 并行执行', en: 'PARA -- Parallel Execution', de: 'PARA -- Parallele Ausführung', fr: 'PARA -- Exécution Parallèle' },
  'reduce':          { zh: 'REDUCE -- 归约', en: 'REDUCE -- Reduction', de: 'REDUCE -- Reduktion', fr: 'REDUCE -- Réduction' },
  'dot':             { zh: 'DOT -- 点积', en: 'DOT -- Dot Product', de: 'DOT -- Skalarprodukt', fr: 'DOT -- Produit Scalaire' },
  'sync':            { zh: 'SYNC -- 同步', en: 'SYNC -- Synchronize', de: 'SYNC -- Synchronisieren', fr: 'SYNC -- Synchroniser' },

  // ====== 演示页面 ======
  'demo_title':      { zh: 'DNAsm v3.3 · 在线演示', en: 'DNAsm v3.3 · Live Demo', de: 'DNAsm v3.3 · Live-Demo', fr: 'DNAsm v3.3 · Démo en Direct' },
  'demo_desc':       { zh: '在浏览器中运行DNAsm代码。56条指令，64个试管。', en: 'Run DNAsm code in browser. 56 instructions, 64 tubes.', de: 'DNAsm-Code im Browser ausführen. 56 Befehle, 64 Röhren.', fr: 'Exécuter du code DNAsm dans le navigateur. 56 instructions, 64 tubes.' },
  'run':             { zh: '运行', en: 'Run', de: 'Ausführen', fr: 'Exécuter' },
  'clear':           { zh: '清空', en: 'Clear', de: 'Leeren', fr: 'Effacer' },
  'output':          { zh: '输出', en: 'Output', de: 'Ausgabe', fr: 'Sortie' },

  // ====== 数学页面 ======
  'math_title':      { zh: '数学翻译机 · DNA原生计算', en: 'Math Translator · DNA Native Compute', de: 'Mathematik-Übersetzer · DNA-Native Berechnung', fr: 'Traducteur Mathématique · Calcul Natif DNA' },
  'math_desc':       { zh: '数论、线性代数、张量运算全部搞定。', en: 'Number theory, linear algebra, tensors — all done.', de: 'Zahlentheorie, lineare Algebra, Tensoren — alles erledigt.', fr: 'Théorie des nombres, algèbre linéaire, tenseurs — tout fait.' },
  'number_theory':   { zh: '数论', en: 'Number Theory', de: 'Zahlentheorie', fr: 'Théorie des Nombres' },
  'linear_algebra':  { zh: '线性代数', en: 'Linear Algebra', de: 'Lineare Algebra', fr: 'Algèbre Linéaire' },
  'tensor':          { zh: '张量', en: 'Tensor', de: 'Tensor', fr: 'Tenseur' },
  'neural_net':      { zh: '神经网络', en: 'Neural Network', de: 'Neuronales Netz', fr: 'Réseau Neuronal' },
};

// 获取当前语言 (从localStorage或浏览器语言)
function getLang() {
  const saved = localStorage.getItem('tsukuyomi-lang');
  if (saved && ['zh','en','de','fr'].includes(saved)) return saved;
  const nav = navigator.language.slice(0, 2);
  if (['zh','en','de','fr'].includes(nav)) return nav;
  return 'zh';
}

// 设置语言
function setLang(lang) {
  localStorage.setItem('tsukuyomi-lang', lang);
  applyLang();
  updateButtons();
}

// 应用翻译
function applyLang() {
  const lang = getLang();
  document.documentElement.lang = 
    lang === 'zh' ? 'zh-CN' : 
    lang === 'en' ? 'en' : 
    lang === 'de' ? 'de' : 'fr';
  
  // 翻译所有带 data-i18n 的元素
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (I18N[key] && I18N[key][lang]) {
      el.textContent = I18N[key][lang];
    }
  });
  
  // 翻译 title
  const titleKey = document.querySelector('title[data-i18n]');
  if (titleKey) {
    const key = titleKey.getAttribute('data-i18n');
    if (I18N[key] && I18N[key][lang]) {
      document.title = I18N[key][lang];
    }
  }
}

// 更新按钮状态
function updateButtons() {
  const lang = getLang();
  document.querySelectorAll('.lang-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.lang === lang);
  });
}

// 创建语言切换器
function createLangSwitcher() {
  const div = document.createElement('div');
  div.className = 'lang-switcher';
  div.innerHTML = `
    <button class="lang-btn" data-lang="zh" onclick="setLang('zh')">🇨🇳</button>
    <button class="lang-btn" data-lang="en" onclick="setLang('en')">🇬🇧</button>
    <button class="lang-btn" data-lang="de" onclick="setLang('de')">🇩🇪</button>
    <button class="lang-btn" data-lang="fr" onclick="setLang('fr')">🇫🇷</button>
  `;
  return div;
}

// 初始化
document.addEventListener('DOMContentLoaded', () => {
  // 插入语言切换器到header
  const header = document.querySelector('.header') || document.querySelector('header');
  if (header) {
    header.insertBefore(createLangSwitcher(), header.firstChild);
  } else {
    document.body.insertBefore(createLangSwitcher(), document.body.firstChild);
  }
  
  applyLang();
  updateButtons();
});
