'use strict';
'require view';
'require ui';
'require request';

/* ── 客户端翻译兜底（LuCI 服务端 i18n 不可靠时的 fallback） ── */
var _EN = {
    'AdGuard Home 控制中心': 'AdGuard Home Control Center',
    '实时状态监控 · 服务控制 · 日志查看 · 一键升级': 'Status Monitoring · Service Control · Log Viewer · One-click Upgrade',
    '实时仪表盘': 'Live Dashboard',
    '核心部署': 'Core Deployment',
    '核心版本': 'Core Version',
    '服务状态': 'Service Status',
    '运行状态': 'Running Status',
    'Web 端口': 'Web Port',
    '管理入口': 'Management URL',
    '服务控制台': 'Service Console',
    '版本更新': 'Version Update',
    '日志查看器': 'Log Viewer',
    '启动服务': 'Start Service',
    '重启服务': 'Restart Service',
    '停止服务': 'Stop Service',
    '注册系统服务': 'Register System Service',
    '检查更新': 'Check Update',
    '检查中...': 'Checking...',
    '检查失败': 'Check failed',
    '一键升级': 'Upgrade',
    '强制重装': 'Force Reinstall',
    '刷新日志': 'Refresh Log',
    '执行中...': 'Processing...',
    '操作执行成功': 'Operation succeeded',
    '操作失败: ': 'Operation failed: ',
    '未知错误': 'Unknown error',
    '执行异常: ': 'Execution error: ',
    '确认升级': 'Confirm Upgrade',
    '确认强制重装': 'Confirm Force Reinstall',
    '将下载并安装最新版本的 AdGuard Home 核心。升级期间服务可能短暂中断。': 'Will download and install the latest AdGuard Home core. Service may be briefly interrupted.',
    '将强制下载在线最新版本并覆盖安装当前版本。升级期间服务将中断。': 'Will force download and reinstall the latest version. Service will be interrupted.',
    '取消': 'Cancel',
    '升级任务已启动，请在下方日志查看器中查看进度': 'Upgrade started, check progress in the log viewer below',
    '强制重装任务已启动，请在下方日志查看器中查看进度': 'Force reinstall started, check progress in the log viewer below',
    '升级任务启动失败': 'Upgrade failed to start',
    '升级完成，正在刷新状态': 'Upgrade completed, refreshing status',
    '未检查': 'Not checked',
    '暂无日志': 'No logs available',
    '获取日志失败': 'Failed to get logs',
    '未知': 'Unknown',
    '服务未启动': 'Service not started',
    '当前控制模式：': 'Control mode: ',
    'Init.d 系统服务级调用': 'Init.d System Service',
    'AdGuardHome 二进制直接控制（命令保底）': 'Binary Direct Control (Fallback)',
    '当前版本：': 'Current: ',
    '最新版本：': 'Latest: ',
    '✔ 已下载': '✔ Installed',
    '✖ 未发现程序 (请运行官网命令安装)': '✖ Not found (Run official install command)',
    '✖ 未安装': '✖ Not installed',
    '下载安装': 'Download & Install',
    '下载安装 AdGuard Home': 'Download & Install AdGuard Home',
    '将从 GitHub 官方脚本下载安装 AdGuard Home 核心。安装期间请保持网络连接。': 'Will download and install AdGuard Home core from the official GitHub script. Please keep network connection stable.',
    '确认安装': 'Confirm Install',
    '安装任务已启动，请在下方日志查看器中查看进度': 'Install task started, check progress in the log viewer below',
    '安装任务启动失败': 'Install task failed to start',
    '代理/加速：': 'Proxy / Accelerator:',
    '原始 (github.com)': 'Raw (github.com)',
    '自定义...': 'Custom...',
    '使用代理：': 'Using proxy:',
    '测试': 'Test',
    '延迟: ': 'Latency: ',
    '✔ 已安装系统服务 | ✔ 开机自启已注册': '✔ System service installed | ✔ Auto-start registered',
    '⚠️ 未注册服务 (使用二进制保底控制)': '⚠ Not registered (Using binary fallback)',
    '● 正在运行': '● Running',
    '■ 已停止': '■ Stopped',
    '确认升级': 'Confirm',
    '已是最新版本': 'Already up to date'
};

function _isChinese() {
    try {
        var lang = (L.env && (L.env.locale || L.env.language)) || '';
        if (lang) return lang.indexOf('zh') !== -1;
    } catch(e) {}
    try {
        var h = document.documentElement.lang || navigator.language || '';
        return h.indexOf('zh') !== -1;
    } catch(e) {}
    return true;
}

function T(s) {
    if (_isChinese()) return s;
    var t = _EN[s];
    return t !== undefined ? t : s;
}

function _isDark() {
    try {
        var html = document.documentElement;
        var cls = (html.className || '') + ' ' + (document.body ? document.body.className || '' : '');
        if (cls.match(/dark|material|argon/i)) return true;
        var bg = getComputedStyle(document.body || html).backgroundColor || '';
        var m = bg.match(/\d+/g);
        if (m && m.length >= 3) {
            var lum = (parseInt(m[0]) * 299 + parseInt(m[1]) * 587 + parseInt(m[2]) * 114) / 1000;
            return lum < 128;
        }
    } catch(e) {}
    return false;
}

function _themeStyles() {
    var dark = _isDark();
    return {
        panelBg: dark ? 'rgba(255,255,255,0.05)' : '#f9f9f9',
        panelBorder: dark ? 'rgba(255,255,255,0.12)' : '#ddd',
        logBg: dark ? '#0d1117' : '#1e1e1e',
        logColor: '#d4d4d4',
        tableStripe: dark ? 'rgba(255,255,255,0.03)' : 'transparent',
        linkColor: dark ? '#58a6ff' : '#007bff'
    };
}

return view.extend({
    statusData: null,
    pollInterval: null,
    logPollInterval: null,
    rootNode: null,

    versionEl: null,
    runningEl: null,
    portEl: null,
    urlEl: null,
    latestVersionEl: null,
    upgradeBtn: null,
    forceBtn: null,
    checkUpdateBtn: null,
    logEl: null,

    fetchStatus: function() {
        return request.get(L.url('admin/services/adguardhome/status')).then(function(res) {
            return res.json();
        });
    },

    sendAction: function(action) {
        var url = L.url('admin/services/adguardhome/action');
        var data = {};
        if (arguments.length > 1 && arguments[1]) data = arguments[1];
        data.action = action;
        return request.post(url, data).then(function(res) {
            return res.json();
        });
    },

    fetchUpdate: function() {
        var data = {};
        if (this.selectedProxy) data.proxy = this.selectedProxy;
        return request.post(L.url('admin/services/adguardhome/check_update'), data).then(function(res) {
            return res.json();
        });
    },

    sendUpgrade: function(force) {
        var url = L.url('admin/services/adguardhome/upgrade');
        var data = {};
        if (arguments.length > 1 && arguments[1]) data = arguments[1];
        data.force = force ? '1' : '0';
        return request.post(url, data).then(function(res) {
            return res.json();
        });
    },

    fetchLog: function() {
        return request.get(L.url('admin/services/adguardhome/log')).then(function(res) {
            return res.json();
        });
    },

    load: function() {
        var self = this;
        return Promise.all([
            self.fetchStatus().catch(function() {
                return { installed: false, service_installed: false, running: false, version: T('未知'), port: 3000 };
            }),
            self.fetchLog().catch(function() {
                return { content: T('暂无日志') };
            })
        ]);
    },

    render: function(data) {
        var status = data[0];
        var logData = data[1];
        this.statusData = status;

        var isBinInstalled = !!status.installed;
        var isServiceInstalled = !!status.service_installed;
        var isRunning = !!status.running;
        var pid = status.pid || '—';
        var versionStr = status.version || T('未知');
        var port = status.port || 3000;
        var targetUrl = isRunning
            ? window.location.protocol + '//' + window.location.hostname + ':' + port
            : '#';

        var self = this;
        var theme = _themeStyles();

        var versionCode = E('code', {}, versionStr);
        this.versionEl = versionCode;

        var runningSpan = E('span', {
            style: isRunning ? 'color:#2dca73;font-weight:bold' : 'color:#e74c3c;font-weight:bold'
        }, isRunning ? T('● 正在运行') + (pid !== '—' ? ' (PID ' + pid + ')' : '') : T('■ 已停止'));
        this.runningEl = runningSpan;

        var portSpan = E('span', {}, String(port));
        this.portEl = portSpan;

        var urlContainer = E('span', {}, isRunning
            ? [E('a', { href: targetUrl, target: '_blank', style: 'font-weight:bold;color:' + theme.linkColor }, targetUrl)]
            : T('服务未启动')
        );
        this.urlEl = urlContainer;

        var latestVersionCode = E('code', { style: 'margin-right:20px' }, T('未检查'));
        this.latestVersionEl = latestVersionCode;

        var checkUpdateBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'margin-right:10px',
            click: function() { self.checkUpdate(); }
        }, T('检查更新'));
        this.checkUpdateBtn = checkUpdateBtn;

        var upgradeBtn = E('button', {
            class: 'btn cbi-button cbi-button-apply',
            style: 'display:none;margin-right:10px',
            click: function() { self.doUpgrade(false); }
        }, T('一键升级'));
        this.upgradeBtn = upgradeBtn;

        var forceBtn = E('button', {
            class: 'btn cbi-button cbi-button-reset',
            style: 'margin-right:10px',
            click: function() { self.doUpgrade(true); }
        }, T('强制重装'));
        this.forceBtn = forceBtn;

        var logPre = E('pre', {
            style: 'max-height:300px;overflow-y:auto;padding:10px;background:' + theme.logBg + ';color:' + theme.logColor + ';font-size:12px;line-height:1.4;border-radius:4px;white-space:pre-wrap;word-break:break-all'
        }, (logData && logData.content) || T('暂无日志'));
        this.logEl = logPre;

        var refreshLogBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'margin-bottom:10px',
            click: function() { self.refreshLog(); }
        }, T('刷新日志'));

        // 代理选项：内置 + 原始 + 自定义
        var proxyOptions = [
            { label: T('原始 (github.com)'), value: '' },
            { label: 'https://ghfast.top/', value: 'https://ghfast.top/' },
            { label: 'https://gh-proxy.com/', value: 'https://gh-proxy.com/' },
            { label: 'https://kkgithub.com/', value: 'https://kkgithub.com/' },
            { label: T('自定义...'), value: 'custom' }
        ];
        var proxySelect = E('select', { style: 'margin-right:8px' }, proxyOptions.map(function(o) { return E('option', { value: o.value }, o.label); }));
        var proxyCustom = E('input', { type: 'text', placeholder: 'https://ghfast.top/', style: 'width:220px; margin-right:8px; display:none' });
        var proxyTestBtn = E('button', { class: 'btn cbi-button cbi-button-action', style: 'margin-right:8px' }, T('测试'));
        // initialize selectedProxy from backend status if present
        if (this.statusData && this.statusData.proxy) {
            var found = false;
            for (var i=0;i<proxySelect.options.length;i++) {
                if (proxySelect.options[i].value === this.statusData.proxy) { proxySelect.selectedIndex = i; found = true; break; }
            }
            if (!found) { proxySelect.value = 'custom'; proxyCustom.style.display = ''; proxyCustom.value = this.statusData.proxy; }
            this.selectedProxy = this.statusData.proxy;
        } else {
            this.selectedProxy = '';
        }
        proxySelect.addEventListener('change', function() {
            if (proxySelect.value === 'custom') { proxyCustom.style.display = ''; proxyCustom.focus(); self.selectedProxy = proxyCustom.value.trim(); }
            else { proxyCustom.style.display = 'none'; self.selectedProxy = proxySelect.value; }
        });
        proxyCustom.addEventListener('input', function() { self.selectedProxy = proxyCustom.value.trim(); });
        proxyTestBtn.addEventListener('click', function() {
            proxyTestBtn.disabled = true; proxyTestBtn.textContent = '...';
            request.post(L.url('admin/services/adguardhome/proxy_test'), { proxy: self.selectedProxy || '' }).then(function(res) { return res.json(); }).then(function(r) {
                if (r && r.ok) ui.addNotification(null, T('延迟: ') + (r.latency*1000).toFixed(0) + ' ms', 'info');
                else ui.addNotification(null, T('测试') + ' failed', 'error');
            }).catch(function() { ui.addNotification(null, T('测试') + ' failed', 'error'); }).then(function() { proxyTestBtn.disabled = false; proxyTestBtn.textContent = T('测试'); });
        });

        var proxyControls = E('div', { style: 'margin-bottom:12px;' }, [E('strong', {}, T('代理/加速：')), proxySelect, proxyCustom, proxyTestBtn]);

        var node = E('div', { class: 'cbi-map' }, [
            E('h2', {}, T('AdGuard Home 控制中心')),
            E('div', { class: 'cbi-map-descr' }, T('实时状态监控 · 服务控制 · 日志查看 · 一键升级')),

            E('div', { class: 'cbi-section' }, [
                E('h3', {}, T('实时仪表盘')),
                E('table', { class: 'table cbi-section-table', style: 'width:100%; max-width:650px;' }, [
                    E('tr', { class: 'tr' }, [
                        E('td', { class: 'td', style: 'width:32%;font-weight:bold' }, T('核心部署')),
                        E('td', { class: 'td' }, isBinInstalled
                            ? E('span', { style: 'color:#2dca73;font-weight:bold' }, T('✔ 已下载') + ' (' + (status.bin_path || '/opt/AdGuardHome/AdGuardHome') + ')')
                            : E('span', {}, [
                                E('span', { style: 'color:#e74c3c;font-weight:bold' }, T('✖ 未安装')),
                                '  ',
                                E('button', {
                                    class: 'btn cbi-button cbi-button-apply',
                                    style: 'margin-left:8px',
                                    click: function() { self.doInstallCore(); }
                                }, T('下载安装'))
                            ])
                        )
                    ]),
... (file truncated)
