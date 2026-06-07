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
    } catch (e) {
        console.error('本地数据解析失败:', e);
        showToast('⚠️ 本地数据损坏，已重置。如已连接 GitHub，将从远端恢复。', 'error');
        localStorage.removeItem(LOCAL_DATA_KEY);
        return null;
    }
}

function saveLocal(data) {
    try { localStorage.setItem(LOCAL_DATA_KEY, JSON.stringify(data)); }
    catch (e) {
        console.error('保存本地数据失败:', e);
        showToast('⚠️ 本地存储空间不足，数据可能无法保存！请清理浏览器存储或连接 GitHub 同步。', 'error');
    }
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
var saveDebounceTimer = null;
var toastTimer = null;

// ========== DOM 缓存（静态元素初始化后缓存，避免重复查询） ==========
var dom = {};
function initDomCache() {
    ['statsBar', 'trashBtn', 'trashOverlay', 'trashPanel', 'trashList',
     'trashCount', 'loadingBar', 'settingsBtn', 'settingsOverlay', 'settingsPanel',
     'connStatus', 'configToken', 'configRepo', 'configBranch', 'btnConnect', 'btnDisconnect', 'btnClearTrash', 'settingsStatus', 'toast']
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
            + '<button class="btn-quadrant-add" data-quadrant="' + q.id + '" aria-label="添加任务">+</button>'
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
    var resp = await fetch(url, { headers: apiHeaders() });
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
        if (!content || !content.trim()) return { q1: [], q2: [], q3: [], q4: [], _trash: [], _ts: 0 };
        var data = JSON.parse(content);
        if (!data._trash) data._trash = [];
        return data;
    } catch (e) {
        fileShas[DATA_FILE_PATH] = null;
        // 仅 404 表示文件尚未创建，返回空数据是合理的
        // 其它错误（网络中断、认证失败等）必须抛出，让 loadAllTasks 回退到本地数据
        var isNotFound = e.message && (e.message.indexOf('404') !== -1 || e.message.indexOf('Not Found') !== -1);
        if (isNotFound) {
            return { q1: [], q2: [], q3: [], q4: [], _trash: [], _ts: 0 };
        }
        throw e;
    }
}

function buildDataObject() {
    var data = { q1: [], q2: [], q3: [], q4: [], _trash: [], _ts: Date.now() };
    tasksCache.forEach(function(t) {
        if (t.deleted) {
            data._trash.push(t);
        } else if (data[t.quadrant]) {
            data[t.quadrant].push(t);
        } else {
            // quadrant 缺失或无效时，兜底归入 q1 防止静默丢失
            data.q1.push(t);
        }
    });
    return data;
}

function debouncedSaveAllData() {
    var data = buildDataObject();
    saveLocal(data);
    if (saveDebounceTimer) clearTimeout(saveDebounceTimer);
    saveDebounceTimer = setTimeout(function() { syncToGitHub(data); }, 500);
}

function syncToGitHub(data) {
    if (!apiToken) return;
    saveFileWithRetry(DATA_FILE_PATH, function() { return data; }, 'Update data').then(function() {
        showToast('已同步', 'success');
    }).catch(function(e) {
        console.error('GitHub 同步失败:', e.message);
        showToast('同步失败', 'error');
    });
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
            // await 之后重新读取本地数据，获取用户在加载窗口内操作的最新时间戳
            var freshLocal = loadLocal();
            var localTs = freshLocal ? (freshLocal._ts || 0) : 0;
            var remoteTs = data._ts || 0;
            if (!freshLocal || remoteTs > localTs) {
                loadTasksIntoCache(data);
                saveLocal(data);
            }
        } catch (e) { console.error('加载远端数据失败:', e.message); }
    }
}

async function ensureFilesExist() {
    var defaultData = { q1: [], q2: [], q3: [], q4: [], _trash: [], _ts: 0 };
    try {
        var url = apiContentsUrl(DATA_FILE_PATH) + '?ref=' + encodeURIComponent(getBranch());
        var info = await apiGet(url);
        // 保存 SHA，避免后续 saveFileWithRetry 再次 GET 获取
        fileShas[DATA_FILE_PATH] = info.sha;
    } catch (e) {
        var body = { message: 'Create ' + DATA_FILE_PATH, content: base64Encode(JSON.stringify(defaultData, null, 2)), branch: getBranch() };
        var result = await apiPut(apiContentsUrl(DATA_FILE_PATH), body);
        // 保存新建文件的 SHA，避免后续冗余 API 请求
        fileShas[DATA_FILE_PATH] = result.content.sha;
    }
}

// ========== UUID 生成（兼容不支持 crypto.randomUUID 的环境） ==========
function generateUUID() {
    if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        var r = Math.random() * 16 | 0;
        return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
    });
}

// ========== 任务 CRUD 操作 ==========
var newTaskIds = new Set();
// 标记新添加任务的 ID，仅对这些任务触发入场动画
function markNewTask(id) { newTaskIds.add(id); }

function addInlineTask(quadrant) {
    var wrap = dom['inline-' + quadrant];
    var titleInput = wrap.querySelector('.inline-title');
    var contentInput = wrap.querySelector('.inline-content');
    var title = titleInput.value.trim();
    if (!title) {
        titleInput.classList.add('input-error');
        titleInput.focus();
        setTimeout(function() { titleInput.classList.remove('input-error'); }, 1500);
        return;
    }
    var content = contentInput.value.trim();
    titleInput.value = '';
    contentInput.value = '';
    wrap.classList.remove('show');
    var minOrder = tasksCache.filter(function(t) { return t.quadrant === quadrant && !t.deleted; })
        .reduce(function(min, t) { return Math.min(min, t.order || 0); }, 0);
    var newTask = { id: generateUUID(), title: title, content: content, quadrant: quadrant, done: false, order: minOrder - 1 };
    markNewTask(newTask.id);
    tasksCache.push(newTask);
    renderQuadrant(quadrant);
    renderStats();
    debouncedSaveAllData();
}

function toggleTask(id) {
    var task = tasksCache.find(function(t) { return String(t.id) === id; });
    if (task && !task.deleted) {
        task.done = !task.done;
        var item = document.querySelector('[data-task-id="' + id + '"]');
        if (item) {
            item.classList.toggle('done');
            var checkbox = item.querySelector('.task-check');
            if (checkbox) checkbox.setAttribute('aria-checked', task.done ? 'true' : 'false');
        }
        renderStats();
        debouncedSaveAllData();
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
        debouncedSaveAllData();
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
        debouncedSaveAllData();
    }
}

function permanentDelete(id) {
    if (!confirm('确定要彻底删除此任务吗？此操作不可恢复。')) return;
    tasksCache = tasksCache.filter(function(t) { return String(t.id) !== id; });
    renderTrash();
    debouncedSaveAllData();
}

async function clearTrash() {
    var deletedCount = tasksCache.filter(function(t) { return t.deleted; }).length;
    if (deletedCount === 0) { closeTrash(); return; }
    if (!confirm('确定要清空回收站（共 ' + deletedCount + ' 项）吗？此操作不可恢复。')) return;
    // 取消待执行的 debounce 定时器，防止残留的旧数据推回 GitHub 覆盖清空操作
    if (saveDebounceTimer) { clearTimeout(saveDebounceTimer); saveDebounceTimer = null; }
    tasksCache = tasksCache.filter(function(t) { return !t.deleted; });
    renderTrash();
    var data = buildDataObject();
    saveLocal(data);
    if (apiToken) {
        showLoading();
        try {
            await saveFileWithRetry(DATA_FILE_PATH, function() { return data; }, 'Clear trash');
            showToast('已同步', 'success');
        } catch (e) {
            console.error('清空回收站同步失败:', e.message);
            showToast('同步失败', 'error');
        }
        hideLoading();
    }
    closeTrash();
}

function clearDone() {
    var doneTasks = tasksCache.filter(function(t) { return t.done && !t.deleted; });
    if (doneTasks.length === 0) return;
    var affectedQuadrants = {};
    doneTasks.forEach(function(t) {
        affectedQuadrants[t.quadrant] = true;
        markTaskDeleted(t);
    });
    Object.keys(affectedQuadrants).forEach(function(q) { renderQuadrant(q); });
    renderStats();
    renderTrash();
    debouncedSaveAllData();
}

function saveEdit(id) {
    var editEl = document.getElementById('task-edit-' + id);
    if (!editEl) return;
    var title = editEl.querySelector('.edit-title').value.trim();
    if (!title) return;
    var content = editEl.querySelector('.edit-content').value.trim();
    var newQuadrant = editEl.querySelector('.edit-quadrant').value;
    var task = tasksCache.find(function(t) { return String(t.id) === id; });
    if (task) {
        var oldQuadrant = task.quadrant;
        task.title = title;
        task.content = content;
        task.quadrant = newQuadrant;
        if (task.deleted) { renderTrash(); }
        else {
            renderQuadrant(task.quadrant);
            if (oldQuadrant !== task.quadrant) renderQuadrant(oldQuadrant);
            renderStats();
        }
        debouncedSaveAllData();
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
        + '<button class="task-check" data-action="toggle" role="checkbox" aria-checked="' + (t.done ? 'true' : 'false') + '" aria-label="标记完成" tabindex="0"></button>'
        + '<div class="task-text" data-action="edit" id="task-display-' + id + '">'
        + '<div class="task-title">' + escapeHtml(t.title) + '</div>'
        + (hasContent ? '<div class="task-content-collapsed">' + escapeHtml(t.content) + '</div>' : '')
        + '</div>'
        + '<div class="task-edit-hidden task-text" id="task-edit-' + id + '">'
        + '<div class="edit-form">'
        + '<input type="text" class="edit-title" value="' + escapeAttr(t.title) + '" placeholder="标题" />'
        + '<input type="text" class="edit-content" value="' + escapeAttr(t.content || '') + '" placeholder="内容（可选）" />'
        + '<select class="edit-quadrant" aria-label="移动到象限">'
        + '<option value="q1"' + (t.quadrant === 'q1' ? ' selected' : '') + '>I 重要且紧急</option>'
        + '<option value="q2"' + (t.quadrant === 'q2' ? ' selected' : '') + '>II 重要不紧急</option>'
        + '<option value="q3"' + (t.quadrant === 'q3' ? ' selected' : '') + '>III 不重要但紧急</option>'
        + '<option value="q4"' + (t.quadrant === 'q4' ? ' selected' : '') + '>IV 不重要不紧急</option>'
        + '</select>'
        + '<div class="edit-form-buttons">'
        + '<button class="btn-edit-save" data-action="save-edit">保存</button>'
        + '<button class="btn-edit-cancel" data-action="cancel-edit">取消</button>'
        + '</div></div></div>'
        + (hasContent ? '<button class="task-expand" data-action="collapse" aria-label="展开内容">▼</button>' : '')
        + '<button class="task-delete" data-action="delete" aria-label="删除任务">×</button>'
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
        // 仅对新添加的任务触发入场动画，已有任务不重复动画
        qTasks.forEach(function(t) {
            if (newTaskIds.has(t.id)) {
                var el = list.querySelector('[data-task-id="' + t.id + '"]');
                if (el) el.classList.add('task-new');
                newTaskIds.delete(t.id);
            }
        });
    }
}

function renderStats() {
    var tasks = tasksCache.filter(function(t) { return !t.deleted; });
    var total = tasks.length;
    var done = tasks.filter(function(t) { return t.done; }).length;
    var undone = total - done;
    // 避免每次重建 innerHTML，改为更新已有元素的文本
    if (!dom.statTotal) {
        // 首次渲染：创建结构
        dom.statsBar.innerHTML =
            '<div class="stat-card"><div class="stat-count" id="statTotal">' + total + '</div><div class="stat-label">总任务</div></div>'
            + '<div class="stat-card"><div class="stat-count" id="statUndone">' + undone + '</div><div class="stat-label">待完成</div></div>'
            + '<div class="stat-card"><div class="stat-count" id="statDone">' + done + '</div><div class="stat-label">已完成</div></div>'
            + '<div id="clearDoneWrap"></div>';
        dom.statTotal = document.getElementById('statTotal');
        dom.statUndone = document.getElementById('statUndone');
        dom.statDone = document.getElementById('statDone');
        dom.clearDoneWrap = document.getElementById('clearDoneWrap');
    } else {
        // 后续渲染：只更新文本和清除按钮
        dom.statTotal.textContent = total;
        dom.statUndone.textContent = undone;
        dom.statDone.textContent = done;
    }
    dom.clearDoneWrap.innerHTML = done > 0 ? '<button class="clear-btn" data-action="clear-done">清除已完成</button>' : '';
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
                + '<span class="trash-title-text">' + escapeHtml(t.title) + '</span>'
                + (hasContent ? '<div class="trash-content" id="trash-content-' + tid + '">' + escapeHtml(t.content) + '</div>' : '')
                + '<span class="trash-time">' + time + '</span>'
                + (hasContent ? '<button class="task-expand" data-action="trash-detail" aria-label="展开内容">▼</button>' : '')
                + '<button class="btn-restore" data-action="restore" aria-label="恢复任务">恢复</button>'
                + '<button class="btn-trash-delete" data-action="perm-delete" aria-label="彻底删除">×</button>'
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
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
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
    // 两阶段读写分离：先批量测量（读阶段），再批量修改（写阶段），避免布局抖动
    var measurements = [];
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

            // 读阶段：临时添加内容测量高度
            var tempSpace = document.createTextNode(' ');
            var tempSpan = document.createElement('span');
            tempSpan.className = 'task-content-inline';
            tempSpan.textContent = contentText;
            titleDiv.appendChild(tempSpace);
            titleDiv.appendChild(tempSpan);

            var combinedHeight = titleDiv.offsetHeight;
            var computedStyle = getComputedStyle(titleDiv);
            var lineHeightStr = computedStyle.lineHeight;
            var lineHeight;
            if (lineHeightStr === 'normal') {
                lineHeight = parseFloat(computedStyle.fontSize) * 1.2;
            } else {
                var parsed = parseFloat(lineHeightStr);
                if (/\d$/.test(lineHeightStr)) {
                    lineHeight = parsed * parseFloat(computedStyle.fontSize);
                } else {
                    lineHeight = parsed;
                }
            }

            // 立即移除临时元素（写阶段前的清理）
            tempSpan.remove();
            tempSpace.remove();

            measurements.push({ item: item, titleDiv: titleDiv, collapsedDiv: collapsedDiv, expandBtn: expandBtn, contentText: contentText, combinedHeight: combinedHeight, lineHeight: lineHeight });
        }
    });

    // 写阶段：批量 DOM 修改，不再触发额外布局读取
    measurements.forEach(function(m) {
        if (m.combinedHeight <= m.lineHeight * 1.1) {
            var inlineSpan = document.createElement('span');
            inlineSpan.className = 'task-content-inline';
            inlineSpan.textContent = m.contentText;
            m.titleDiv.appendChild(document.createTextNode(' '));
            m.titleDiv.appendChild(inlineSpan);
            m.collapsedDiv.remove();
            m.expandBtn.remove();
        }
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

function showToast(msg, type) {
    var el = dom.toast;
    if (toastTimer) clearTimeout(toastTimer);
    el.textContent = msg;
    el.className = 'toast ' + type + ' show';
    var duration = type === 'error' ? 4000 : 2000;
    toastTimer = setTimeout(function() {
        el.classList.remove('show');
        toastTimer = null;
    }, duration);
}

// ========== 回收站面板 ==========
function toggleTrash() {
    trashExpanded = !trashExpanded;
    var overlay = dom.trashOverlay;
    var panel = dom.trashPanel;
    if (trashExpanded) {
        overlay.classList.add('show');
        panel.classList.add('show');
        // 聚焦到面板内首个交互元素
        var firstBtn = panel.querySelector('button');
        if (firstBtn) firstBtn.focus();
    } else {
        overlay.classList.remove('show');
        panel.classList.remove('show');
        dom.trashBtn.focus();
    }
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
        dom.configToken.value = cfg.token ? '••••••••' : '';
        dom.configToken.dataset.masked = cfg.token ? 'true' : '';
        dom.configRepo.value = cfg.repo || '';
        dom.configBranch.value = cfg.branch || 'main';
        updateConnStatus();
        dom.configToken.focus();
    } else {
        overlay.classList.remove('show');
        panel.classList.remove('show');
        dom.settingsBtn.focus();
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
        dom.btnConnect.textContent = '已连接';
    } else if (connectionAttempted) {
        el.textContent = '未连接';
        el.className = 'conn-status disconnected';
        dom.btnConnect.textContent = '连接';
    } else {
        el.textContent = '';
        el.className = 'conn-status';
        dom.btnConnect.textContent = '连接';
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
        var msg = e.message;
        if (msg.indexOf('401') !== -1) msg = 'Token 无效或已过期';
        else if (msg.indexOf('403') !== -1) msg = '权限不足，请检查 Token 授权范围';
        else if (msg.indexOf('404') !== -1) msg = '仓库不存在或 Token 无权限访问';
        showStatus(msg, true);
        setConnFailed(btn);
        return;
    }

    try { await apiGet(apiRepoUrl() + '/branches/' + encodeURIComponent(branch)); }
    catch (e) {
        var bmsg = e.message;
        if (bmsg.indexOf('404') !== -1) bmsg = '分支 ' + branch + ' 不存在';
        else if (bmsg.indexOf('401') !== -1) bmsg = 'Token 无权限查看分支';
        showStatus(bmsg, true);
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
}

function setConnFailed(btn) {
    dom.settingsBtn.classList.remove('connected');
    updateConnStatus();
    btn.disabled = false;
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
    debouncedSaveAllData();
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
    // Token 输入框：点击时清除掩码让用户输入新 Token
    dom.configToken.addEventListener('focus', function() {
        if (dom.configToken.dataset.masked === 'true') {
            dom.configToken.value = '';
            dom.configToken.dataset.masked = '';
        }
    });

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

    // 矩阵容器 — keydown 委托（编辑表单 + 内联输入 + 任务键盘交互）
    dom.matrixContainer.addEventListener('keydown', function(e) {
        var editEl = e.target.closest('.edit-title, .edit-content');
        if (editEl) {
            var editForm = editEl.closest('[id^="task-edit-"]');
            var id = editForm ? editForm.id.replace('task-edit-', '') : '';
            if ((e.key === 'Enter' && (e.metaKey || e.ctrlKey)) || (e.key === 'Enter' && e.target.classList.contains('edit-title'))) { saveEdit(id); return; }
            if (e.key === 'Escape') { cancelEdit(id); return; }
        }
        // 键盘触发编辑：聚焦到 task-check 时按 Enter 开启编辑模式
        var checkEl = e.target.closest('.task-check');
        if (checkEl && e.key === 'Enter') {
            var item = checkEl.closest('.task-item');
            if (item) startEdit(item.dataset.taskId);
            return;
        }
        var inlineEl = e.target.closest('.inline-title, .inline-content');
        if (inlineEl && e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
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
        draggedTaskId = null;
    });

    dom.matrixContainer.addEventListener('dragover', function(e) {
        if (draggedTaskId === null) return;
        var item = e.target.closest('.task-item');
        if (!item || item.dataset.taskId === draggedTaskId) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        if (!item.classList.contains('drag-over-item')) item.classList.add('drag-over-item');
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
                    debouncedSaveAllData();
                }
            }
            draggedTaskId = null;
        });
    });
}

// ========== 页面关闭保护 ==========
// 如果有待执行的 GitHub 同步定时器，提醒用户等待或手动保存
window.addEventListener('beforeunload', function(e) {
    if (saveDebounceTimer) {
        e.preventDefault();
        e.returnValue = '数据正在同步到 GitHub，请稍候再关闭页面。';
        return e.returnValue;
    }
});

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
    // 如果已配置 GitHub，后台拉取远端数据（内部已包含本地加载逻辑）
    if (apiToken) {
        showLoading();
        var loadSuccess = true;
        try { await loadAllTasks(); } catch (e) {
            loadSuccess = false;
            console.error('初始化加载数据失败:', e.message);
        }
        // 如果远端加载失败（Token 过期、仓库删除等），移除"已连接"状态避免误导
        if (!loadSuccess) {
            dom.settingsBtn.classList.remove('connected');
            connectionAttempted = true;
            updateConnStatus();
        }
        hideLoading();
    } else {
        var local = loadLocal();
        if (local) loadTasksIntoCache(local);
    }
    render();
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
