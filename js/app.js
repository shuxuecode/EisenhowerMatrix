(function() {
    'use strict';

    // ========== 常量 & 全局变量 ==========
var CONFIG_KEY = 'eisenhower_github_config';
var DATA_FILE_PATH = 'eisenhower/data.json';
var LOCAL_DATA_KEY = 'eisenhower_data';

function loadLocal() {
    try {
        var raw = localStorage.getItem(LOCAL_DATA_KEY);
        if (!raw) return null;
        return JSON.parse(raw);
    } catch (e) { return null; }
}

function saveLocal(data) {
    try { localStorage.setItem(LOCAL_DATA_KEY, JSON.stringify(data)); } catch (e) {}
}

var tasksCache = [];
var fileShas = {};
var apiToken = '';
var apiRepoOwner = '';
var apiRepoName = '';
var saveLocks = {};
var connectionAttempted = false;
var trashExpanded = false;
var settingsVisible = false;
var draggedTaskId = null;

// ========== DOM 缓存（静态元素初始化后缓存，避免重复查询） ==========
var dom = {};
function initDomCache() {
    ['statsBar', 'trashBtn', 'trashOverlay', 'trashPanel', 'trashList',
     'trashCount', 'loadingBar', 'settingsBtn', 'settingsOverlay', 'settingsPanel',
     'connStatus', 'configToken', 'configRepo', 'configBranch', 'btnConnect', 'btnDisconnect', 'btnClearTrash', 'settingsStatus']
    .forEach(function(id) { dom[id] = document.getElementById(id); });
}

// ========== 象限配置（动态生成 DOM） ==========
var QUADRANT_CONFIG = [
    { id: 'q2', num: 'II',  cls: 'q2', title: '✨ 重要不紧急', subtitle: '价值最高，重点投入', action: '📅 制定计划，安排时间专注完成' },
    { id: 'q1', num: 'I',   cls: 'q1', title: '🔥 重要且紧急', subtitle: '危机模式，立即处理', action: '⚡ 立即执行，不可拖延' },
    { id: 'q4', num: 'IV',  cls: 'q4', title: '💤 不重要不紧急', subtitle: '浪费时间，尽量消除', action: '🚫 尽量避免，减少消耗' },
    { id: 'q3', num: 'III', cls: 'q3', title: '😅 不重要但紧急', subtitle: '干扰陷阱，学会拒绝', action: '🤝 授权他人，学会委婉拒绝' }
];

function buildQuadrants() {
    var container = document.getElementById('matrixContainer');
    var html = '';
    QUADRANT_CONFIG.forEach(function(q) {
        html += '<div class="quadrant ' + q.cls + '" id="' + q.id + '">'
            + '<div class="quadrant-header">'
            + '<div class="quadrant-number">' + q.num + '</div>'
            + '<button class="btn-quadrant-add" data-quadrant="' + q.id + '">+</button>'
            + '<div class="quadrant-title">' + q.title + ' <span class="quadrant-subtitle-inline">' + q.subtitle + '</span></div>'
            + '<div class="quadrant-action">' + q.action + '</div>'
            + '<div class="inline-input-wrap" id="inline-' + q.id + '" data-quadrant="' + q.id + '">'
            + '<div class="input-row">'
            + '<input type="text" class="inline-title" placeholder="标题" />'
            + '<input type="text" class="inline-content" placeholder="内容（可选）" />'
            + '<button class="btn-inline-add" data-quadrant="' + q.id + '">添加</button>'
            + '<button class="btn-inline-cancel" data-quadrant="' + q.id + '">取消</button>'
            + '</div></div></div>'
            + '<div class="quadrant-body"><ul class="task-list" id="list-' + q.id + '"></ul></div>'
            + '</div>';
    });
    container.innerHTML = html;

    // 缓存 buildQuadrants 创建的持久 DOM 节点
    QUADRANT_CONFIG.forEach(function(q) {
        dom[q.id] = document.getElementById(q.id);
        dom['list-' + q.id] = document.getElementById('list-' + q.id);
        dom['inline-' + q.id] = document.getElementById('inline-' + q.id);
    });
    dom.matrixContainer = container;
}

// ========== 文件写入互斥锁 ==========
function withLock(path, fn) {
    var prev = saveLocks[path] || Promise.resolve();
    var next = prev.then(function() { return fn(); });
    // 失败时重置锁，让下一次写入干净启动
    saveLocks[path] = next.catch(function() { saveLocks[path] = null; });
    return next;
}

// ========== 配置管理 ==========
function loadConfig() {
    try { return JSON.parse(localStorage.getItem(CONFIG_KEY)) || { token: '', repo: '', branch: 'main' }; }
    catch (e) { return { token: '', repo: '', branch: 'main' }; }
}

function saveConfig(config) { localStorage.setItem(CONFIG_KEY, JSON.stringify(config)); }

function getBranch() { return loadConfig().branch || 'main'; }

function isConfigured() {
    var cfg = loadConfig();
    return cfg.token && cfg.repo;
}

// ========== GitHub API 核心 ==========
function apiHeaders() {
    return {
        'Authorization': 'token ' + apiToken,
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json'
    };
}

function parseApiError(respStatus, respText) {
    try {
        var err = JSON.parse(respText);
        return err.message || ('HTTP ' + respStatus);
    } catch (e) {
        return 'HTTP ' + respStatus + ' ' + respText;
    }
}

async function apiGet(url) {
    var resp = await fetch(url, { headers: apiHeaders(), cache: 'no-store' });
    if (!resp.ok) {
        var errText = await resp.text();
        throw new Error(parseApiError(resp.status, errText));
    }
    return await resp.json();
}

async function apiPut(url, body) {
    var resp = await fetch(url, { method: 'PUT', headers: apiHeaders(), body: JSON.stringify(body), cache: 'no-store' });
    var respText = await resp.text();
    if (!resp.ok) {
        throw new Error(parseApiError(resp.status, respText));
    }
    return JSON.parse(respText);
}

function base64Encode(str) {
    return btoa(encodeURIComponent(str).replace(/%([0-9A-F]{2})/g, function(m, p1) {
        return String.fromCharCode('0x' + p1);
    }));
}

function base64Decode(base64) {
    if (!base64) return '';
    return decodeURIComponent(atob(base64).split('').map(function(c) {
        return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
    }).join(''));
}

function initApi(config) {
    if (!config.token || !config.repo) return false;
    apiToken = config.token;
    var parts = config.repo.split('/');
    if (parts.length !== 2) return false;
    apiRepoOwner = parts[0].trim();
    apiRepoName = parts[1].trim();
    return true;
}

function apiRepoUrl() {
    return 'https://api.github.com/repos/' + apiRepoOwner + '/' + apiRepoName;
}

function apiContentsUrl(path) {
    return apiRepoUrl() + '/contents/' + path;
}

// ========== 数据文件读写 ==========
async function fetchDataFile() {
    var branch = getBranch();
    try {
        var url = apiContentsUrl(DATA_FILE_PATH) + '?ref=' + encodeURIComponent(branch);
        var info = await apiGet(url);
        fileShas[DATA_FILE_PATH] = info.sha;
        var content = base64Decode(info.content);
        if (!content || !content.trim()) return { q1: [], q2: [], q3: [], q4: [], _trash: [] };
        var data = JSON.parse(content);
        if (!data._trash) data._trash = [];
        return data;
    } catch (e) {
        fileShas[DATA_FILE_PATH] = null;
        return { q1: [], q2: [], q3: [], q4: [], _trash: [] };
    }
}

function buildDataObject() {
    var data = { q1: [], q2: [], q3: [], q4: [], _trash: [] };
    tasksCache.forEach(function(t) {
        if (t.deleted) {
            data._trash.push(t);
        } else if (data[t.quadrant]) {
            data[t.quadrant].push(t);
        }
    });
    return data;
}

function saveAllData() {
    var data = buildDataObject();
    saveLocal(data);
    syncToGitHub();
}

function syncToGitHub() {
    if (!apiToken) return;
    saveFileWithRetry(DATA_FILE_PATH, buildDataObject, 'Update data').catch(function() {});
}

function isConflictError(e) {
    return e.message && e.message.indexOf('is at') !== -1 && e.message.indexOf('but expected') !== -1;
}

async function saveFileWithRetry(path, buildDataFn, commitMessage) {
    return withLock(path, async function() {
        var branch = getBranch();
        var data = buildDataFn();
        var content = JSON.stringify(data, null, 2);
        var encoded = base64Encode(content);
        var body = { message: commitMessage, content: encoded, branch: branch };

        if (fileShas[path]) {
            body.sha = fileShas[path];
        } else {
            try {
                var url = apiContentsUrl(path) + '?ref=' + encodeURIComponent(branch);
                var info = await apiGet(url);
                body.sha = info.sha;
            } catch (e) {}
        }

        for (var attempt = 0; attempt < 2; attempt++) {
            try {
                var result = await apiPut(apiContentsUrl(path), body);
                fileShas[path] = result.content.sha;
                return result;
            } catch (e) {
                if (attempt === 0 && isConflictError(e)) {
                    var retryUrl = apiContentsUrl(path) + '?ref=' + encodeURIComponent(branch);
                    var retryInfo = await apiGet(retryUrl);
                    body.sha = retryInfo.sha;
                    continue;
                }
                throw e;
            }
        }
    });
}

function loadTasksIntoCache(data) {
    tasksCache = [];
    ['q1', 'q2', 'q3', 'q4'].forEach(function(key) {
        (data[key] || []).forEach(function(t) { tasksCache.push(t); });
    });
    (data._trash || []).forEach(function(t) { tasksCache.push(t); });
}

async function loadAllTasks() {
    var local = loadLocal();
    if (local) loadTasksIntoCache(local);
    if (isConfigured() && apiToken) {
        try {
            var data = await fetchDataFile();
            loadTasksIntoCache(data);
            saveLocal(data);
        } catch (e) {}
    }
}

async function ensureFilesExist() {
    var defaultData = { q1: [], q2: [], q3: [], q4: [], _trash: [] };
    try {
        var url = apiContentsUrl(DATA_FILE_PATH) + '?ref=' + encodeURIComponent(getBranch());
        await apiGet(url);
    } catch (e) {
        var body = { message: 'Create ' + DATA_FILE_PATH, content: base64Encode(JSON.stringify(defaultData, null, 2)), branch: getBranch() };
        await apiPut(apiContentsUrl(DATA_FILE_PATH), body);
    }
}

// ========== 任务 CRUD 操作 ==========
function addInlineTask(quadrant) {
    var wrap = dom['inline-' + quadrant];
    var titleInput = wrap.querySelector('.inline-title');
    var contentInput = wrap.querySelector('.inline-content');
    var title = titleInput.value.trim();
    if (!title) return;
    var content = contentInput.value.trim();
    titleInput.value = '';
    contentInput.value = '';
    wrap.classList.remove('show');
    var minOrder = tasksCache.filter(function(t) { return t.quadrant === quadrant && !t.deleted; })
        .reduce(function(min, t) { return Math.min(min, t.order || 0); }, 0);
    var newTask = { id: crypto.randomUUID(), title: title, content: content, quadrant: quadrant, done: false, order: minOrder - 1 };
    tasksCache.push(newTask);
    renderQuadrant(quadrant);
    renderStats();
    saveAllData();
}

function toggleTask(id) {
    var task = tasksCache.find(function(t) { return String(t.id) === id; });
    if (task && !task.deleted) {
        task.done = !task.done;
        var item = document.querySelector('[data-task-id="' + id + '"]');
        if (item) item.classList.toggle('done');
        renderStats();
        saveAllData();
    }
}

function markTaskDeleted(task) {
    task.deleted = true;
    task.deletedAt = Date.now();
    task.originalQuadrant = task.quadrant;
}

function deleteTask(id) {
    var task = tasksCache.find(function(t) { return String(t.id) === id; });
    if (task) {
        var origQuadrant = task.quadrant;
        markTaskDeleted(task);
        renderQuadrant(origQuadrant);
        renderStats();
        renderTrash();
        saveAllData();
    }
}

function restoreTask(id) {
    var task = tasksCache.find(function(t) { return String(t.id) === id; });
    if (task) {
        task.deleted = false;
        task.quadrant = task.originalQuadrant || 'q1';
        delete task.deletedAt;
        delete task.originalQuadrant;
        renderQuadrant(task.quadrant);
        renderStats();
        renderTrash();
        saveAllData();
    }
}

function permanentDelete(id) {
    tasksCache = tasksCache.filter(function(t) { return String(t.id) !== id; });
    renderTrash();
    saveAllData();
}

function clearTrash() {
    tasksCache = tasksCache.filter(function(t) { return !t.deleted; });
    renderTrash();
    saveAllData();
    closeTrash();
}

function clearDone() {
    var doneTasks = tasksCache.filter(function(t) { return t.done && !t.deleted; });
    if (doneTasks.length === 0) return;
    var affectedQuadrants = {};
    doneTasks.forEach(function(t) {
        markTaskDeleted(t);
        affectedQuadrants[t.originalQuadrant] = true;
    });
    Object.keys(affectedQuadrants).forEach(function(q) { renderQuadrant(q); });
    renderStats();
    renderTrash();
    saveAllData();
}

function saveEdit(id) {
    var editEl = document.getElementById('task-edit-' + id);
    if (!editEl) return;
    var title = editEl.querySelector('.edit-title').value.trim();
    if (!title) return;
    var content = editEl.querySelector('.edit-content').value.trim();
    var task = tasksCache.find(function(t) { return String(t.id) === id; });
    if (task) {
        task.title = title;
        task.content = content;
        if (task.deleted) { renderTrash(); }
        else { renderQuadrant(task.quadrant); renderStats(); }
        saveAllData();
    }
}

function startEdit(id) {
    document.getElementById('task-display-' + id).classList.add('task-edit-hidden');
    var editEl = document.getElementById('task-edit-' + id);
    editEl.classList.remove('task-edit-hidden');
    editEl.querySelector('.edit-title').focus();
}

function cancelEdit(id) {
    document.getElementById('task-display-' + id).classList.remove('task-edit-hidden');
    document.getElementById('task-edit-' + id).classList.add('task-edit-hidden');
}

// ========== UI 渲染 — 任务项 HTML 生成 ==========
function buildTaskHtml(t, index) {
    var hasContent = !!t.content;
    var id = escapeAttr(String(t.id));
    return '<li class="task-item ' + (t.done ? 'done' : '') + '" draggable="true" data-task-id="' + id + '" data-quadrant="' + t.quadrant + '">'
        + '<span class="task-index">' + (index + 1) + '</span>'
        + '<div class="task-check" data-action="toggle"></div>'
        + '<div class="task-text" data-action="edit" id="task-display-' + id + '">'
        + '<div class="task-title">' + escapeHtml(t.title || t.text) + '</div>'
        + (hasContent ? '<div class="task-content-collapsed">' + escapeHtml(t.content) + '</div>' : '')
        + '</div>'
        + '<div class="task-edit-hidden task-text" id="task-edit-' + id + '">'
        + '<div class="edit-form">'
        + '<input type="text" class="edit-title" value="' + escapeAttr(t.title || t.text) + '" placeholder="标题" />'
        + '<input type="text" class="edit-content" value="' + escapeAttr(t.content || '') + '" placeholder="内容（可选）" />'
        + '<div class="edit-form-buttons">'
        + '<button class="btn-edit-save" data-action="save-edit">保存</button>'
        + '<button class="btn-edit-cancel" data-action="cancel-edit">取消</button>'
        + '</div></div></div>'
        + (hasContent ? '<button class="task-expand" data-action="collapse">▼</button>' : '')
        + '<button class="task-delete" data-action="delete">×</button>'
        + '</li>';
}

function renderQuadrant(q) {
    var list = dom['list-' + q];
    var qTasks = tasksCache.filter(function(t) { return t.quadrant === q && !t.deleted; })
        .sort(function(a, b) { return (a.order || 0) - (b.order || 0); });
    if (qTasks.length === 0) {
        list.innerHTML = '<div class="empty-tip">暂无任务</div>';
    } else {
        list.innerHTML = qTasks.map(function(t, i) { return buildTaskHtml(t, i); }).join('');
    }
}

function renderStats() {
    var tasks = tasksCache.filter(function(t) { return !t.deleted; });
    var total = tasks.length;
    var done = tasks.filter(function(t) { return t.done; }).length;
    var undone = total - done;
    dom.statsBar.innerHTML =
        '<div class="stat-card"><div class="stat-count">' + total + '</div><div class="stat-label">总任务</div></div>'
        + '<div class="stat-card"><div class="stat-count">' + undone + '</div><div class="stat-label">待完成</div></div>'
        + '<div class="stat-card"><div class="stat-count">' + done + '</div><div class="stat-label">已完成</div></div>'
        + (done > 0 ? '<button class="clear-btn" data-action="clear-done">清除已完成</button>' : '');
}

function renderTrash() {
    var deletedTasks = tasksCache.filter(function(t) { return t.deleted; })
        .sort(function(a, b) { return (b.deletedAt || 0) - (a.deletedAt || 0); });
    var trashBtn = dom.trashBtn;
    var trashCount = dom.trashCount;
    var trashList = dom.trashList;
    if (deletedTasks.length === 0) {
        trashBtn.style.display = 'none';
        closeTrash();
    } else {
        trashBtn.style.display = '';
        trashCount.textContent = deletedTasks.length;
        trashList.innerHTML = deletedTasks.map(function(t) {
            var time = t.deletedAt ? formatTime(t.deletedAt) : '';
            var hasContent = !!t.content;
            var tid = escapeAttr(String(t.id));
            return '<li class="trash-item" id="trash-item-' + tid + '">'
                + '<span class="trash-title-text">' + escapeHtml(t.title || t.text) + '</span>'
                + (hasContent ? '<div class="trash-content" id="trash-content-' + tid + '">' + escapeHtml(t.content) + '</div>' : '')
                + '<span class="trash-time">' + time + '</span>'
                + (hasContent ? '<button class="task-expand" data-action="trash-detail">▼</button>' : '')
                + '<button class="btn-restore" data-action="restore">恢复</button>'
                + '<button class="btn-trash-delete" data-action="perm-delete">×</button>'
                + '</li>';
        }).join('');
    }
}

function render() {
    ['q1', 'q2', 'q3', 'q4'].forEach(function(q) { renderQuadrant(q); });
    renderStats();
    renderTrash();
    applyContentWrapping();
}

function formatTime(timestamp) {
    var d = new Date(timestamp);
    var pad = function(n) { return String(n).padStart(2, '0'); };
    return (d.getMonth() + 1) + '/' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
}

function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function escapeAttr(str) {
    return str.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ========== UI 交互 - 输入框 ==========
function showInlineInput(quadrant) {
    var wrap = dom['inline-' + quadrant];
    wrap.classList.toggle('show');
    if (wrap.classList.contains('show')) {
        wrap.querySelector('.inline-title').focus();
    }
}

function hideInlineInput(quadrant) {
    var wrap = dom['inline-' + quadrant];
    wrap.classList.remove('show');
}

// ========== UI 交互 - 展开/收起 ==========
function toggleTrashDetail(id) {
    var content = document.getElementById('trash-content-' + id);
    if (content) {
        content.classList.toggle('show');
    }
}

function toggleCollapse(id) {
    var item = document.querySelector('[data-task-id="' + id + '"]');
    if (item) item.classList.toggle('collapsed-show');
}

function applyContentWrapping() {
    requestAnimationFrame(function() {
        QUADRANT_CONFIG.forEach(function(q) {
            var list = dom['list-' + q];
            if (!list) return;
            var items = list.querySelectorAll('.task-item');
            for (var i = 0; i < items.length; i++) {
                var item = items[i];
                var collapsedDiv = item.querySelector('.task-content-collapsed');
                var expandBtn = item.querySelector('.task-expand');
                if (!collapsedDiv || !expandBtn) continue;

                var titleDiv = item.querySelector('.task-title');
                var contentText = collapsedDiv.textContent;

                // Temporarily add content inline to measure combined height
                var tempSpace = document.createTextNode(' ');
                var tempSpan = document.createElement('span');
                tempSpan.className = 'task-content-inline';
                tempSpan.className = 'task-content-inline';
                tempSpan.textContent = contentText;
                titleDiv.appendChild(tempSpace);
                titleDiv.appendChild(tempSpan);

                var combinedHeight = titleDiv.offsetHeight;

                // Remove temp elements
                tempSpan.remove();
                tempSpace.remove();

                // Get line height in pixels
                var computedStyle = getComputedStyle(titleDiv);
                var lineHeightStr = computedStyle.lineHeight;
                var lineHeight;
                if (lineHeightStr === 'normal') {
                    lineHeight = parseFloat(computedStyle.fontSize) * 1.2;
                } else {
                    var parsed = parseFloat(lineHeightStr);
                    // Unitless factor: multiply by font-size to get pixels
                    if (/\d$/.test(lineHeightStr)) {
                        lineHeight = parsed * parseFloat(computedStyle.fontSize);
                    } else {
                        lineHeight = parsed;
                    }
                }

                // If title + content fits in one line, show inline; otherwise keep collapsed
                if (combinedHeight <= lineHeight * 1.1) {
                    var inlineSpan = document.createElement('span');
                    inlineSpan.className = 'task-content-inline';
                    inlineSpan.className = 'task-content-inline';
                    inlineSpan.textContent = contentText;
                    titleDiv.appendChild(document.createTextNode(' '));
                    titleDiv.appendChild(inlineSpan);
                    collapsedDiv.remove();
                    expandBtn.remove();
                }
            }
        });
    });
}

// ========== UI 交互 - 加载/状态 ==========
var loadingTimer = null;
var loadingWidth = 0;

function showLoading() {
    var bar = dom.loadingBar;
    loadingWidth = 0;
    bar.style.width = '0';
    bar.classList.add('active');
    loadingTimer = setInterval(function() {
        // 越往后递增越小，模拟逐渐趋近但不达到 90%
        var inc = Math.max(1, (90 - loadingWidth) * 0.12);
        loadingWidth = Math.min(90, loadingWidth + inc);
        bar.style.width = loadingWidth + '%';
    }, 250);
}

function hideLoading() {
    var bar = dom.loadingBar;
    clearInterval(loadingTimer);
    loadingTimer = null;
    // 迅速填满并淡出
    bar.style.width = '100%';
    bar.style.transition = 'width 0.15s ease, opacity 0.2s ease 0.15s';
    setTimeout(function() {
        bar.classList.remove('active');
        bar.style.width = '0';
        bar.style.transition = 'width 0.3s ease';
    }, 200);
}

function showStatus(msg, isError) {
    var el = dom.settingsStatus;
    el.textContent = msg;
    el.className = 'status-msg' + (isError ? ' error' : '');
    if (!isError) {
        setTimeout(function() { el.textContent = ''; el.className = 'status-msg'; }, 3000);
    }
}

// ========== 回收站面板 ==========
function toggleTrash() {
    trashExpanded = !trashExpanded;
    var overlay = dom.trashOverlay;
    var panel = dom.trashPanel;
    if (trashExpanded) { overlay.classList.add('show'); panel.classList.add('show'); }
    else { overlay.classList.remove('show'); panel.classList.remove('show'); }
}

function closeTrash() {
    trashExpanded = false;
    dom.trashOverlay.classList.remove('show');
    dom.trashPanel.classList.remove('show');
}

// ========== 设置面板 & GitHub 连接 ==========
function toggleSettings() {
    settingsVisible = !settingsVisible;
    var overlay = dom.settingsOverlay;
    var panel = dom.settingsPanel;
    if (settingsVisible) {
        overlay.classList.add('show');
        panel.classList.add('show');
        var cfg = loadConfig();
        dom.configToken.value = cfg.token || '';
        dom.configRepo.value = cfg.repo || '';
        dom.configBranch.value = cfg.branch || 'main';
        updateConnStatus();
    } else {
        overlay.classList.remove('show');
        panel.classList.remove('show');
    }
    dom.settingsStatus.textContent = '';
    dom.settingsStatus.className = 'status-msg';
}

function updateConnStatus() {
    var el = dom.connStatus;
    var connected = dom.settingsBtn.classList.contains('connected');
    if (connected) {
        el.textContent = '已连接';
        el.className = 'conn-status connected';
    } else if (connectionAttempted) {
        el.textContent = '未连接';
        el.className = 'conn-status disconnected';
    } else {
        el.textContent = '';
        el.className = 'conn-status';
    }
}

function closeSettings() {
    settingsVisible = false;
    dom.settingsOverlay.classList.remove('show');
    dom.settingsPanel.classList.remove('show');
}

async function connectGitHub() {
    connectionAttempted = true;
    dom.settingsStatus.textContent = '';
    dom.settingsStatus.className = 'status-msg';
    var token = dom.configToken.value.trim();
    var repoStr = dom.configRepo.value.trim();
    var branch = dom.configBranch.value.trim() || 'main';
    if (!token) { showStatus('请输入 Token', true); return; }
    if (!repoStr || repoStr.indexOf('/') === -1) { showStatus('请输入有效的仓库名 (owner/repo)', true); return; }
    var btn = dom.btnConnect;
    btn.disabled = true;
    btn.textContent = '连接中...';
    var config = { token: token, repo: repoStr, branch: branch };

    if (!initApi(config)) {
        showStatus('仓库格式错误', true);
        setConnFailed(btn);
        return;
    }

    try { await apiGet(apiRepoUrl()); }
    catch (e) {
        showStatus('Token 或仓库无效: ' + e.message, true);
        setConnFailed(btn);
        return;
    }

    try { await apiGet(apiRepoUrl() + '/branches/' + encodeURIComponent(branch)); }
    catch (e) {
        showStatus('分支不存在: ' + e.message, true);
        setConnFailed(btn);
        return;
    }

    saveConfig(config);
    showLoading();
    try { await ensureFilesExist(); }
    catch (e) {
        showStatus('创建数据文件失败: ' + e.message, true);
        setConnFailed(btn);
        hideLoading();
        return;
    }
    try { await loadAllTasks(); }
    catch (e) {
        showStatus('加载数据失败: ' + e.message, true);
        setConnFailed(btn);
        hideLoading();
        return;
    }

    dom.settingsBtn.classList.add('connected');
    updateConnStatus();
    closeSettings();
    render();
    hideLoading();
    showStatus('连接成功，数据加载完成', false);
    btn.disabled = false;
    btn.textContent = '连接';
}

function setConnFailed(btn) {
    dom.settingsBtn.classList.remove('connected');
    updateConnStatus();
    btn.disabled = false;
    btn.textContent = '连接';
}

function disconnectGitHub() {
    connectionAttempted = false;
    saveConfig({ token: '', repo: '', branch: 'main' });
    apiToken = '';
    apiRepoOwner = '';
    apiRepoName = '';
    fileShas = {};
    dom.settingsBtn.classList.remove('connected');
    updateConnStatus();
    dom.configToken.value = '';
    dom.configRepo.value = '';
    closeSettings();
    showStatus('已断开连接', false);
}

// ========== 拖拽功能 ==========

function reorderTasks(targetTaskId, before) {
    var draggedTask = tasksCache.find(function(t) { return String(t.id) === draggedTaskId; });
    var targetTask = tasksCache.find(function(t) { return String(t.id) === targetTaskId; });
    if (!draggedTask || !targetTask) return;
    var oldQuadrant = draggedTask.quadrant;
    draggedTask.quadrant = targetTask.quadrant;
    var qTasks = tasksCache.filter(function(t) { return t.quadrant === draggedTask.quadrant && String(t.id) !== draggedTaskId; })
        .sort(function(a, b) { return (a.order || 0) - (b.order || 0); });
    var targetIndex = qTasks.findIndex(function(t) { return String(t.id) === targetTaskId; });
    if (before) qTasks.splice(targetIndex, 0, draggedTask);
    else qTasks.splice(targetIndex + 1, 0, draggedTask);
    qTasks.forEach(function(t, i) { t.order = i; });
    var otherTasks = tasksCache.filter(function(t) { return t.quadrant !== draggedTask.quadrant; })
        .sort(function(a, b) { return (a.order || 0) - (b.order || 0); });
    tasksCache = qTasks.concat(otherTasks);
    renderQuadrant(draggedTask.quadrant);
    if (oldQuadrant !== draggedTask.quadrant) renderQuadrant(oldQuadrant);
    renderStats();
    saveAllData();
}

// ========== 全局事件委托 ==========
var eventsBound = false;

function bindGlobalEvents() {
    if (eventsBound) return;
    eventsBound = true;

    // 静态元素
    dom.trashBtn.addEventListener('click', toggleTrash);
    dom.trashOverlay.addEventListener('click', closeTrash);
    dom.settingsBtn.addEventListener('click', toggleSettings);
    dom.settingsOverlay.addEventListener('click', closeSettings);
    dom.btnConnect.addEventListener('click', connectGitHub);
    dom.btnDisconnect.addEventListener('click', disconnectGitHub);
    dom.btnClearTrash.addEventListener('click', clearTrash);

    // 矩阵容器 — click 委托
    dom.matrixContainer.addEventListener('click', function(e) {
        var qBtn = e.target.closest('.btn-quadrant-add');
        if (qBtn) { showInlineInput(qBtn.dataset.quadrant); return; }
        var addBtn = e.target.closest('.btn-inline-add');
        if (addBtn) { addInlineTask(addBtn.dataset.quadrant); return; }
        var cancelBtn = e.target.closest('.btn-inline-cancel');
        if (cancelBtn) { hideInlineInput(cancelBtn.dataset.quadrant); return; }

        var item = e.target.closest('.task-item');
        if (!item) return;
        var id = item.dataset.taskId;
        if (e.target.closest('.task-check')) { toggleTask(id); return; }
        if (e.target.closest('.task-delete')) { deleteTask(id); return; }
        if (e.target.closest('.task-expand')) { toggleCollapse(id); return; }
        if (e.target.closest('.btn-edit-save')) { saveEdit(id); return; }
        if (e.target.closest('.btn-edit-cancel')) { cancelEdit(id); }
    });

    // 矩阵容器 — dblclick 委托（编辑）
    dom.matrixContainer.addEventListener('dblclick', function(e) {
        var display = e.target.closest('[id^="task-display-"]');
        if (display) { startEdit(display.id.replace('task-display-', '')); }
    });

    // 矩阵容器 — keydown 委托（编辑表单 + 内联输入）
    dom.matrixContainer.addEventListener('keydown', function(e) {
        var editEl = e.target.closest('.edit-title, .edit-content');
        if (editEl) {
            var editForm = editEl.closest('[id^="task-edit-"]');
            var id = editForm ? editForm.id.replace('task-edit-', '') : '';
            if (e.key === 'Enter' && e.metaKey) { saveEdit(id); return; }
            if (e.key === 'Escape') { cancelEdit(id); return; }
        }
        var inlineEl = e.target.closest('.inline-title, .inline-content');
        if (inlineEl && e.key === 'Enter' && e.metaKey) {
            var wrap = inlineEl.closest('.inline-input-wrap');
            if (wrap) addInlineTask(wrap.dataset.quadrant);
        }
    });

    // 矩阵容器 — drag 委托
    dom.matrixContainer.addEventListener('dragstart', function(e) {
        var item = e.target.closest('.task-item');
        if (!item) return;
        draggedTaskId = item.dataset.taskId;
        item.classList.add('dragging');
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', draggedTaskId);
    });

    dom.matrixContainer.addEventListener('dragend', function(e) {
        document.querySelectorAll('.quadrant').forEach(function(q) { q.classList.remove('drag-over'); });
        document.querySelectorAll('.task-item').forEach(function(t) { t.classList.remove('drag-over-item'); });
    });

    dom.matrixContainer.addEventListener('dragover', function(e) {
        if (draggedTaskId === null) return;
        var item = e.target.closest('.task-item');
        if (!item || item.dataset.taskId === draggedTaskId) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        item.classList.add('drag-over-item');
    });

    dom.matrixContainer.addEventListener('dragleave', function(e) {
        var item = e.target.closest('.task-item');
        if (!item) return;
        var rel = e.relatedTarget;
        if (!rel || !item.contains(rel)) { item.classList.remove('drag-over-item'); }
    });

    // 回收站面板 — click 委托
    dom.trashPanel.addEventListener('click', function(e) {
        var trashItem = e.target.closest('.trash-item');
        if (!trashItem) return;
        var id = trashItem.id.replace('trash-item-', '');
        if (e.target.closest('.btn-restore')) { restoreTask(id); return; }
        if (e.target.closest('.btn-trash-delete')) { permanentDelete(id); return; }
        if (e.target.closest('.task-expand')) { toggleTrashDetail(id); }
    });

    // 统计栏 — click 委托
    dom.statsBar.addEventListener('click', function(e) {
        if (e.target.closest('.clear-btn')) clearDone();
    });

    // 象限级拖放（拖到空白区域时移动象限）
    ['q1', 'q2', 'q3', 'q4'].forEach(function(q) {
        var el = dom[q];
        el.addEventListener('dragover', function(e) { e.preventDefault(); e.dataTransfer.dropEffect = 'move'; el.classList.add('drag-over'); });
        el.addEventListener('dragleave', function() { el.classList.remove('drag-over'); });
        el.addEventListener('drop', function(e) {
            e.preventDefault();
            el.classList.remove('drag-over');
            if (draggedTaskId === null) return;
            var dropTarget = e.target.closest('.task-item');
            if (dropTarget) {
                var targetId = dropTarget.dataset.taskId;
                var rect = dropTarget.getBoundingClientRect();
                var midY = rect.top + rect.height / 2;
                reorderTasks(targetId, e.clientY < midY);
            } else {
                var task = tasksCache.find(function(t) { return String(t.id) === draggedTaskId; });
                if (task && task.quadrant !== q) {
                    var oldQ = task.quadrant;
                    task.quadrant = q;
                    var maxOrder = tasksCache.filter(function(t) { return t.quadrant === q; })
                        .reduce(function(max, t) { return Math.max(max, t.order || 0); }, -1);
                    task.order = maxOrder + 1;
                    renderQuadrant(q);
                    renderQuadrant(oldQ);
                    renderStats();
                    saveAllData();
                }
            }
            draggedTaskId = null;
        });
    });
}

// ========== 应用初始化 ==========
(async function init() {
    initDomCache();
    buildQuadrants();
    bindGlobalEvents();
    if (isConfigured()) {
        connectionAttempted = true;
        var config = loadConfig();
        if (initApi(config)) {
            dom.settingsBtn.classList.add('connected');
            updateConnStatus();
        }
    }
    // 始终从本地加载以支持离线使用
    var local = loadLocal();
    if (local) loadTasksIntoCache(local);
    render();
    // 如果已配置 GitHub，后台拉取远端数据
    if (apiToken) {
        showLoading();
        try { await loadAllTasks(); } catch (e) {}
        hideLoading();
        render();
    }
})();

// Export public API
window.App = {
    showInlineInput: showInlineInput,
    addInlineTask: addInlineTask,
    hideInlineInput: hideInlineInput,
    toggleTask: toggleTask,
    saveEdit: saveEdit,
    cancelEdit: cancelEdit,
    startEdit: startEdit,
    deleteTask: deleteTask,
    clearDone: clearDone,
    toggleTrashDetail: toggleTrashDetail,
    toggleCollapse: toggleCollapse,
    restoreTask: restoreTask,
    permanentDelete: permanentDelete,
    toggleTrash: toggleTrash,
    closeTrash: closeTrash,
    clearTrash: clearTrash,
    toggleSettings: toggleSettings,
    closeSettings: closeSettings,
    connectGitHub: connectGitHub,
    disconnectGitHub: disconnectGitHub
};
    })();
