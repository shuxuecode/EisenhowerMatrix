        (function() {
            'use strict';

            // ========== 常量 & 全局变量 ==========
        var CONFIG_KEY = 'eisenhower_github_config';
        var DATA_FILE_PATH = 'eisenhower/data.json';
        var TRASH_FILE_PATH = 'eisenhower/trash.json';

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
             'connStatus', 'configToken', 'configRepo', 'configBranch', 'btnConnect', 'settingsStatus']
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
                    + '<button class="btn-quadrant-add" onclick="App.showInlineInput(\'' + q.id + '\')">+</button>'
                    + '<div class="quadrant-title">' + q.title + ' <span class="quadrant-subtitle-inline">' + q.subtitle + '</span></div>'
                    + '<div class="quadrant-action">' + q.action + '</div>'
                    + '<div class="inline-input-wrap" id="inline-' + q.id + '">'
                    + '<div class="input-row">'
                    + '<input type="text" class="inline-title" placeholder="标题" />'
                    + '<input type="text" class="inline-content" placeholder="内容（可选）" />'
                    + '<button onclick="App.addInlineTask(\'' + q.id + '\')">添加</button>'
                    + '<button onclick="App.hideInlineInput(\'' + q.id + '\')">取消</button>'
                    + '</div></div></div>'
                    + '<div class="quadrant-body"><ul class="task-list" id="list-' + q.id + '"></ul></div>'
                    + '</div>';
            });
            container.innerHTML = html;

            // 绑定内联输入框的键盘快捷键
            QUADRANT_CONFIG.forEach(function(q) {
                var wrap = document.getElementById('inline-' + q.id);
                wrap.querySelector('.inline-title').onkeydown = function(e) {
                    if (e.key === 'Enter' && e.metaKey) addInlineTask(q.id);
                };
                wrap.querySelector('.inline-content').onkeydown = function(e) {
                    if (e.key === 'Enter' && e.metaKey) addInlineTask(q.id);
                };
            });

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
            saveLocks[path] = next.catch(function() {});
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
                if (!content || !content.trim()) return { q1: [], q2: [], q3: [], q4: [] };
                return JSON.parse(content);
            } catch (e) {
                fileShas[DATA_FILE_PATH] = null;
                return { q1: [], q2: [], q3: [], q4: [] };
            }
        }

        async function fetchTrashFile() {
            var branch = getBranch();
            try {
                var url = apiContentsUrl(TRASH_FILE_PATH) + '?ref=' + encodeURIComponent(branch);
                var info = await apiGet(url);
                fileShas[TRASH_FILE_PATH] = info.sha;
                var content = base64Decode(info.content);
                if (!content || !content.trim()) return [];
                return JSON.parse(content);
            } catch (e) {
                fileShas[TRASH_FILE_PATH] = null;
                return [];
            }
        }

        function buildDataObject() {
            var data = { q1: [], q2: [], q3: [], q4: [] };
            tasksCache.forEach(function(t) {
                if (!t.deleted && data[t.quadrant]) {
                    data[t.quadrant].push(t);
                }
            });
            return data;
        }

        function buildTrashArray() {
            return tasksCache.filter(function(t) { return t.deleted; });
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

                try {
                    var url = apiContentsUrl(path) + '?ref=' + encodeURIComponent(branch);
                    var info = await apiGet(url);
                    body.sha = info.sha;
                } catch (e) {}

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

        async function saveAllData() {
            return saveFileWithRetry(DATA_FILE_PATH, buildDataObject, 'Update data');
        }

        async function saveTrashData() {
            return saveFileWithRetry(TRASH_FILE_PATH, buildTrashArray, 'Update trash');
        }

        async function loadAllTasks() {
            tasksCache = [];
            var data = await fetchDataFile();
            ['q1', 'q2', 'q3', 'q4'].forEach(function(key) {
                var tasks = data[key] || [];
                tasks.forEach(function(t) { tasksCache.push(t); });
            });
            var trashTasks = await fetchTrashFile();
            trashTasks.forEach(function(t) { tasksCache.push(t); });
        }

        async function ensureFilesExist() {
            var files = [
                { path: DATA_FILE_PATH, content: JSON.stringify({ q1: [], q2: [], q3: [], q4: [] }, null, 2) },
                { path: TRASH_FILE_PATH, content: JSON.stringify([], null, 2) }
            ];
            for (var i = 0; i < files.length; i++) {
                var f = files[i];
                try {
                    var url = apiContentsUrl(f.path) + '?ref=' + encodeURIComponent(getBranch());
                    await apiGet(url);
                } catch (e) {
                    var body = { message: 'Create ' + f.path, content: base64Encode(f.content), branch: getBranch() };
                    await apiPut(apiContentsUrl(f.path), body);
                }
            }
        }

        // ========== 任务 CRUD 操作 ==========
        async function addInlineTask(quadrant) {
            var wrap = dom['inline-' + quadrant];
            var titleInput = wrap.querySelector('.inline-title');
            var contentInput = wrap.querySelector('.inline-content');
            var title = titleInput.value.trim();
            if (!title) return;
            var content = contentInput.value.trim();
            titleInput.value = '';
            contentInput.value = '';
            wrap.classList.remove('show');
            showLoading();
            var minOrder = tasksCache.filter(function(t) { return t.quadrant === quadrant && !t.deleted; })
                .reduce(function(min, t) { return Math.min(min, t.order || 0); }, 0);
            var newTask = { id: crypto.randomUUID(), title: title, content: content, quadrant: quadrant, done: false, order: minOrder - 1 };
            tasksCache.push(newTask);
            renderQuadrant(quadrant);
            renderStats();
            try { await saveAllData(); }
            catch (e) { showStatus('保存失败: ' + e.message, true); }
            hideLoading();
        }

        async function toggleTask(id) {
            var task = tasksCache.find(function(t) { return t.id === id; });
            if (task && !task.deleted) {
                task.done = !task.done;
                var item = document.querySelector('[data-task-id="' + id + '"]');
                if (item) item.classList.toggle('done');
                renderStats();
                try { await saveAllData(); }
                catch (e) { showStatus('保存失败: ' + e.message, true); }
            }
        }

        function markTaskDeleted(task) {
            task.deleted = true;
            task.deletedAt = Date.now();
            task.originalQuadrant = task.quadrant;
        }

        async function deleteTask(id) {
            var task = tasksCache.find(function(t) { return t.id === id; });
            if (task) {
                var origQuadrant = task.quadrant;
                markTaskDeleted(task);
                showLoading();
                renderQuadrant(origQuadrant);
                renderStats();
                renderTrash();
                try { await saveAllData(); await saveTrashData(); }
                catch (e) { showStatus('保存失败: ' + e.message, true); }
                hideLoading();
            }
        }

        async function restoreTask(id) {
            var task = tasksCache.find(function(t) { return t.id === id; });
            if (task) {
                task.deleted = false;
                task.quadrant = task.originalQuadrant || 'q1';
                delete task.deletedAt;
                delete task.originalQuadrant;
                showLoading();
                renderQuadrant(task.quadrant);
                renderStats();
                renderTrash();
                try { await saveAllData(); await saveTrashData(); }
                catch (e) { showStatus('保存失败: ' + e.message, true); }
                hideLoading();
            }
        }

        async function permanentDelete(id) {
            tasksCache = tasksCache.filter(function(t) { return t.id !== id; });
            renderTrash();
            try { await saveTrashData(); }
            catch (e) { showStatus('保存失败: ' + e.message, true); }
        }

        async function clearTrash() {
            tasksCache = tasksCache.filter(function(t) { return !t.deleted; });
            showLoading();
            renderTrash();
            try { await saveTrashData(); }
            catch (e) { showStatus('保存失败: ' + e.message, true); }
            hideLoading();
            closeTrash();
        }

        async function clearDone() {
            var doneTasks = tasksCache.filter(function(t) { return t.done && !t.deleted; });
            if (doneTasks.length === 0) return;
            var affectedQuadrants = {};
            doneTasks.forEach(function(t) {
                markTaskDeleted(t);
                affectedQuadrants[t.originalQuadrant] = true;
            });
            showLoading();
            Object.keys(affectedQuadrants).forEach(function(q) { renderQuadrant(q); });
            renderStats();
            renderTrash();
            try { await saveAllData(); await saveTrashData(); }
            catch (e) { showStatus('保存失败: ' + e.message, true); }
            hideLoading();
        }

        async function saveEdit(id) {
            var editEl = document.getElementById('task-edit-' + id);
            var title = editEl.querySelector('.edit-title').value.trim();
            if (!title) return;
            var content = editEl.querySelector('.edit-content').value.trim();
            var task = tasksCache.find(function(t) { return t.id === id; });
            if (task) {
                task.title = title;
                task.content = content;
                showLoading();
                if (task.deleted) { renderTrash(); }
                else { renderQuadrant(task.quadrant); renderStats(); }
                try {
                    if (task.deleted) { await saveTrashData(); }
                    else { await saveAllData(); }
                }
                catch (e) { showStatus('保存失败: ' + e.message, true); }
                hideLoading();
            }
        }

        function startEdit(id) {
            document.getElementById('task-display-' + id).style.display = 'none';
            var editEl = document.getElementById('task-edit-' + id);
            editEl.style.display = '';
            editEl.querySelector('.edit-title').focus();
        }

        function cancelEdit(id) {
            document.getElementById('task-display-' + id).style.display = '';
            document.getElementById('task-edit-' + id).style.display = 'none';
        }

        // ========== UI 渲染 — 任务项 HTML 生成 ==========
        function buildTaskHtml(t, index) {
            var hasContent = !!t.content;
            var id = escapeAttr(String(t.id));
            return '<li class="task-item ' + (t.done ? 'done' : '') + '" draggable="true" data-task-id="' + id + '" data-quadrant="' + t.quadrant + '"'
                + ' ondragstart="App.onDragStart(event, \'' + id + '\')" ondragend="App.onDragEnd(event)"'
                + ' ondragover="App.onDragOverItem(event, this)" ondragleave="App.onDragLeaveItem(this)">'
                + '<span class="task-index">' + (index + 1) + '</span>'
                + '<div class="task-check" onclick="App.toggleTask(\'' + id + '\')"></div>'
                + '<div class="task-text" ondblclick="App.startEdit(\'' + id + '\')" id="task-display-' + id + '">'
                + '<div class="task-title">' + escapeHtml(t.title || t.text) + '</div>'
                + (hasContent ? '<div class="task-content">' + escapeHtml(t.content) + '</div>' : '')
                + '</div>'
                + '<div class="task-text" id="task-edit-' + id + '" style="display:none">'
                + '<div class="edit-form">'
                + '<input type="text" class="edit-title" value="' + escapeAttr(t.title || t.text) + '" placeholder="标题" onkeydown="if(event.key===&#39;Enter&#39;&&event.metaKey)App.saveEdit(\'' + id + '\');if(event.key===&#39;Escape&#39;)App.cancelEdit(\'' + id + '\')" />'
                + '<input type="text" class="edit-content" value="' + escapeAttr(t.content || '') + '" placeholder="内容（可选）" onkeydown="if(event.key===&#39;Enter&#39;&&event.metaKey)App.saveEdit(\'' + id + '\');if(event.key===&#39;Escape&#39;)App.cancelEdit(\'' + id + '\')" />'
                + '<div class="edit-form-buttons">'
                + '<button class="btn-edit-save" onclick="App.saveEdit(\'' + id + '\')">保存</button>'
                + '<button class="btn-edit-cancel" onclick="App.cancelEdit(\'' + id + '\')">取消</button>'
                + '</div></div></div>'
                + (hasContent ? '<button class="task-expand" onclick="App.toggleExpand(this)">▼</button>' : '')
                + '<button class="task-delete" onclick="App.deleteTask(\'' + id + '\')">×</button>'
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
                + (done > 0 ? '<button class="clear-btn" onclick="App.clearDone()">清除已完成</button>' : '');
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
                        + (hasContent ? '<div class="trash-content" id="trash-content-' + tid + '" style="display:none;color:var(--white-50);font-size:0.8rem;margin-top:4px;width:100%">' + escapeHtml(t.content) + '</div>' : '')
                        + '<span class="trash-time">' + time + '</span>'
                        + (hasContent ? '<button class="task-expand" onclick="App.toggleTrashDetail(\'' + tid + '\')" style="width:20px;height:20px;font-size:0.6rem">▼</button>' : '')
                        + '<button class="btn-restore" onclick="App.restoreTask(\'' + tid + '\')">恢复</button>'
                        + '<button class="btn-trash-delete" onclick="App.permanentDelete(\'' + tid + '\')">×</button>'
                        + '</li>';
                }).join('');
            }
        }

        function render() {
            // 一次遍历按象限分桶，避免 6 次独立 filter
            var buckets = { q1: [], q2: [], q3: [], q4: [], trash: [] };
            var totalDone = 0;
            var totalActive = 0;
            for (var i = 0; i < tasksCache.length; i++) {
                var t = tasksCache[i];
                if (t.deleted) {
                    buckets.trash.push(t);
                } else {
                    totalActive++;
                    if (t.done) totalDone++;
                    var q = t.quadrant;
                    if (buckets[q]) buckets[q].push(t);
                }
            }

            ['q1', 'q2', 'q3', 'q4'].forEach(function(q) {
                var list = dom['list-' + q];
                var qTasks = buckets[q].sort(function(a, b) { return (a.order || 0) - (b.order || 0); });
                if (qTasks.length === 0) {
                    list.innerHTML = '<div class="empty-tip">暂无任务</div>';
                } else {
                    list.innerHTML = qTasks.map(function(t, i) { return buildTaskHtml(t, i); }).join('');
                }
            });

            dom.statsBar.innerHTML =
                '<div class="stat-card"><div class="stat-count">' + totalActive + '</div><div class="stat-label">总任务</div></div>'
                + '<div class="stat-card"><div class="stat-count">' + (totalActive - totalDone) + '</div><div class="stat-label">待完成</div></div>'
                + '<div class="stat-card"><div class="stat-count">' + totalDone + '</div><div class="stat-label">已完成</div></div>'
                + (totalDone > 0 ? '<button class="clear-btn" onclick="App.clearDone()">清除已完成</button>' : '');

            var deletedTasks = buckets.trash.sort(function(a, b) { return (b.deletedAt || 0) - (a.deletedAt || 0); });
            var trashBtn = dom.trashBtn;
            if (deletedTasks.length === 0) {
                trashBtn.style.display = 'none';
                closeTrash();
            } else {
                trashBtn.style.display = '';
                dom.trashCount.textContent = deletedTasks.length;
                dom.trashList.innerHTML = deletedTasks.map(function(t) {
                    var time = t.deletedAt ? formatTime(t.deletedAt) : '';
                    var hasContent = !!t.content;
                    var tid = escapeAttr(String(t.id));
                    return '<li class="trash-item" id="trash-item-' + tid + '">'
                        + '<span class="trash-title-text">' + escapeHtml(t.title || t.text) + '</span>'
                        + (hasContent ? '<div class="trash-content" id="trash-content-' + tid + '" style="display:none;color:var(--white-50);font-size:0.8rem;margin-top:4px;width:100%">' + escapeHtml(t.content) + '</div>' : '')
                        + '<span class="trash-time">' + time + '</span>'
                        + (hasContent ? '<button class="task-expand" onclick="App.toggleTrashDetail(\'' + tid + '\')" style="width:20px;height:20px;font-size:0.6rem">▼</button>' : '')
                        + '<button class="btn-restore" onclick="App.restoreTask(\'' + tid + '\')">恢复</button>'
                        + '<button class="btn-trash-delete" onclick="App.permanentDelete(\'' + tid + '\')">×</button>'
                        + '</li>';
                }).join('');
            }
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
        function toggleExpand(el) {
            el.closest('.task-item').classList.toggle('expanded');
        }

        function toggleTrashDetail(id) {
            var content = document.getElementById('trash-content-' + id);
            if (content) {
                content.style.display = content.style.display === 'none' ? 'block' : 'none';
            }
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
            bindQuadrantDropEvents();
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
            tasksCache = [];
            fileShas = {};
            dom.settingsBtn.classList.remove('connected');
            updateConnStatus();
            dom.configToken.value = '';
            dom.configRepo.value = '';
            render();
            bindQuadrantDropEvents();
            closeSettings();
            showStatus('已断开连接', false);
        }

        // ========== 拖拽功能 ==========
        function onDragStart(e, taskId) {
            draggedTaskId = taskId;
            e.target.classList.add('dragging');
            e.dataTransfer.effectAllowed = 'move';
            e.dataTransfer.setData('text/plain', taskId);
        }

        function onDragEnd(e) {
            e.target.classList.remove('dragging');
            document.querySelectorAll('.quadrant').forEach(function(q) { q.classList.remove('drag-over'); });
            document.querySelectorAll('.task-item').forEach(function(t) { t.classList.remove('drag-over-item'); });
        }

        function onDragOverItem(e, el) {
            if (draggedTaskId === null) return;
            e.preventDefault();
            e.dataTransfer.dropEffect = 'move';
            var targetId = parseInt(el.dataset.taskId);
            if (targetId !== draggedTaskId) { el.classList.add('drag-over-item'); }
        }

        function onDragLeaveItem(el) { el.classList.remove('drag-over-item'); }

        async function reorderTasks(targetTaskId, before) {
            var draggedTask = tasksCache.find(function(t) { return t.id === draggedTaskId; });
            var targetTask = tasksCache.find(function(t) { return t.id === targetTaskId; });
            if (!draggedTask || !targetTask) return;
            var oldQuadrant = draggedTask.quadrant;
            draggedTask.quadrant = targetTask.quadrant;
            var qTasks = tasksCache.filter(function(t) { return t.quadrant === draggedTask.quadrant && t.id !== draggedTaskId; })
                .sort(function(a, b) { return (a.order || 0) - (b.order || 0); });
            var targetIndex = qTasks.findIndex(function(t) { return t.id === targetTaskId; });
            if (before) qTasks.splice(targetIndex, 0, draggedTask);
            else qTasks.splice(targetIndex + 1, 0, draggedTask);
            qTasks.forEach(function(t, i) { t.order = i; });
            var otherTasks = tasksCache.filter(function(t) { return t.quadrant !== draggedTask.quadrant; })
                .sort(function(a, b) { return (a.order || 0) - (b.order || 0); });
            tasksCache = qTasks.concat(otherTasks);
            showLoading();
            renderQuadrant(draggedTask.quadrant);
            if (oldQuadrant !== draggedTask.quadrant) renderQuadrant(oldQuadrant);
            renderStats();
            try { await saveAllData(); }
            catch (e) { showStatus('保存失败: ' + e.message, true); }
            hideLoading();
        }

        function bindQuadrantDropEvents() {
            var quadrants = ['q1', 'q2', 'q3', 'q4'];
            quadrants.forEach(function(q) {
                var el = dom[q];
                el.ondragover = function(e) { e.preventDefault(); e.dataTransfer.dropEffect = 'move'; el.classList.add('drag-over'); };
                el.ondragleave = function() { el.classList.remove('drag-over'); };
                el.ondrop = async function(e) {
                    e.preventDefault();
                    el.classList.remove('drag-over');
                    if (draggedTaskId === null) return;
                    var dropTarget = e.target.closest('.task-item');
                    if (dropTarget) {
                        var targetId = parseInt(dropTarget.dataset.taskId);
                        var rect = dropTarget.getBoundingClientRect();
                        var midY = rect.top + rect.height / 2;
                        var before = e.clientY < midY;
                        await reorderTasks(targetId, before);
                    } else {
                        var task = tasksCache.find(function(t) { return t.id === draggedTaskId; });
                        if (task && task.quadrant !== q) {
                            var oldQ = task.quadrant;
                            task.quadrant = q;
                            var maxOrder = tasksCache.filter(function(t) { return t.quadrant === q; })
                                .reduce(function(max, t) { return Math.max(max, t.order || 0); }, -1);
                            task.order = maxOrder + 1;
                            showLoading();
                            renderQuadrant(q);
                            renderQuadrant(oldQ);
                            renderStats();
                            try { await saveAllData(); }
                            catch (e) { showStatus('保存失败: ' + e.message, true); }
                            hideLoading();
                        }
                    }
                    draggedTaskId = null;
                };
            });
        }

        // ========== 应用初始化 ==========
        (async function init() {
            initDomCache();
            buildQuadrants();
            if (isConfigured()) {
                connectionAttempted = true;
                var config = loadConfig();
                if (initApi(config)) {
                    dom.settingsBtn.classList.add('connected');
                    updateConnStatus();
                    showLoading();
                    try { await loadAllTasks(); }
                    catch (e) { showStatus('加载数据失败: ' + e.message, true); }
                    hideLoading();
                }
            }
            render();
            bindQuadrantDropEvents();
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
            toggleExpand: toggleExpand,
            deleteTask: deleteTask,
            clearDone: clearDone,
            toggleTrashDetail: toggleTrashDetail,
            restoreTask: restoreTask,
            permanentDelete: permanentDelete,
            toggleTrash: toggleTrash,
            closeTrash: closeTrash,
            clearTrash: clearTrash,
            toggleSettings: toggleSettings,
            closeSettings: closeSettings,
            connectGitHub: connectGitHub,
            disconnectGitHub: disconnectGitHub,
            onDragStart: onDragStart,
            onDragEnd: onDragEnd,
            onDragOverItem: onDragOverItem,
            onDragLeaveItem: onDragLeaveItem
        };
    })();
