module("luci.controller.adguardhome", package.seeall)

local util = require "luci.util"
local fs = require "nixio.fs"
local http = require "luci.http"

local BIN_PATHS = {
    "/opt/AdGuardHome/AdGuardHome",
    "/usr/bin/AdGuardHome",
    "/usr/local/bin/AdGuardHome"
}

local INIT_SCRIPTS = {
    "/etc/init.d/AdGuardHome",
    "/etc/init.d/adguardhome"
}

local CONFIG_PATHS = {
    "/opt/AdGuardHome/AdGuardHome.yaml",
    "/etc/AdGuardHome.yaml",
    "/etc/adguardhome/adguardhome.yaml"
}

-- 统一运行时日志路径（挂载于 /tmp tmpfs 内存文件系统）
local EXEC_LOG = "/tmp/agh_exec.log"
local PROXY_CONF = "/etc/adguardhome-dashboard.proxy"
local DASHBOARD_VERSION = "2.2.0"
local DASH_REPO = "imonior/luci-app-adguardhome-dashboard"
local DASH_BRANCH = "main"

-- 面板文件清单
local DASH_FILES = {
    { src = "files/view/dashboard.js",                  dst = "/www/luci-static/resources/view/adguardhome/dashboard.js", base = "dashboard.js", kind = "js",  min_size = 10000 },
    { src = "files/luci/i18n/adguardhome.po",           dst = "/usr/lib/lua/luci/i18n/adguardhome.po",           base = "adguardhome.po",        kind = "po",  min_size = 500 },
    { src = "files/luci/i18n/adguardhome.zh-cn.po",     dst = "/usr/lib/lua/luci/i18n/adguardhome.zh-cn.po",     base = "adguardhome.zh-cn.po",  kind = "po",  min_size = 500 },
    { src = "files/luci/i18n/adguardhome.lmo",           dst = "/usr/lib/lua/luci/i18n/adguardhome.lmo",           base = "adguardhome.lmo",       kind = "lmo", min_size = 100 },
    { src = "files/luci/i18n/adguardhome.zh-cn.lmo",     dst = "/usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo",     base = "adguardhome.zh-cn.lmo", kind = "lmo", min_size = 100 },
    { src = "files/luci/controller/adguardhome.lua",    dst = "/usr/lib/lua/luci/controller/adguardhome.lua",    base = "adguardhome.lua",       kind = "lua", min_size = 5000 }
}

local PRIMARY_PROXY = ""
local PROXY_LIST = {}

local function get_persisted_proxy()
    if fs.access(PROXY_CONF) then
        local content = fs.readfile(PROXY_CONF) or ""
        local saved = content:match("proxy%s*=%s*(%S*)")
        if saved then return saved end
    end
    return ""
end

local function load_proxies()
    PRIMARY_PROXY = get_persisted_proxy()
    PROXY_LIST = {}
    if PRIMARY_PROXY ~= "" then
        PROXY_LIST[#PROXY_LIST + 1] = PRIMARY_PROXY
    end
    local builtins = {
        "https://ghfast.top/",
        "https://gh-proxy.com/",
        "https://kkgithub.com/"
    }
    for _, p in ipairs(builtins) do
        local found = false
        for _, existing in ipairs(PROXY_LIST) do
            if existing == p then found = true; break end
        end
        if not found then
            PROXY_LIST[#PROXY_LIST + 1] = p
        end
    end
end

local function is_safe_proxy(p)
    if p == nil then return false end
    if p == "" then return true end
    if p:match("['\"`$;|&()<>%s\\]") then return false end
    if not p:match("^https?://[%w%.%-/_:]+$") then return false end
    return true
end

local function try_with_proxies(url)
    local tried = {}
    local function attempt(target, timeout)
        local out = util.exec("curl -m " .. timeout .. " -fsSL '" .. target .. "' 2>/dev/null")
        if out and #out > 10 then return out end
        return nil
    end
    if PRIMARY_PROXY ~= "" then
        local r = attempt(PRIMARY_PROXY .. url, 10)
        if r then return r end
        tried[PRIMARY_PROXY] = true
    end
    local r = attempt(url, 5)
    if r then return r end
    tried[""] = true
    for _, proxy in ipairs(PROXY_LIST) do
        if not tried[proxy] then
            local rr = attempt(proxy .. url, 10)
            if rr then return rr end
            tried[proxy] = true
        end
    end
    return ""
end

local function find_binary()
    for _, p in ipairs(BIN_PATHS) do
        if fs.access(p, 'r') then
            return p
        end
    end
    local which_out = util.exec("which AdGuardHome 2>/dev/null")
    which_out = which_out and which_out:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if which_out ~= "" and fs.access(which_out, 'r') then
        return which_out
    end
    return nil
end

local function find_init_script()
    for _, p in ipairs(INIT_SCRIPTS) do
        if fs.access(p) then
            return p
        end
    end
    return nil
end

function index()
    entry({"admin", "services", "adguardhome", "status"}, call("get_status"), nil, true)
    entry({"admin", "services", "adguardhome", "action"}, call("do_action"), nil, true)
    entry({"admin", "services", "adguardhome", "set_proxy"}, call("set_proxy"), nil, true)
    entry({"admin", "services", "adguardhome", "proxy_test"}, call("proxy_test"), nil, true)
    entry({"admin", "services", "adguardhome", "check_update"}, call("check_update"), nil, true)
    entry({"admin", "services", "adguardhome", "upgrade"}, call("do_upgrade"), nil, true)
    entry({"admin", "services", "adguardhome", "check_dashboard_update"}, call("check_dashboard_update"), nil, true)
    entry({"admin", "services", "adguardhome", "upgrade_dashboard"}, call("do_upgrade_dashboard"), nil, true)
    entry({"admin", "services", "adguardhome", "log"}, call("get_log"), nil, true)
end

function get_status()
    local status = {
        installed = false,
        service_installed = false,
        running = false,
        pid = nil,
        version = "",
        port = 3000,
        bin_path = "",
        init_script = "",
        proxy = "",
        dashboard_version = DASHBOARD_VERSION
    }

    status.proxy = get_persisted_proxy()

    local bin_path = find_binary()
    local init_script = find_init_script()

    status.installed = bin_path ~= nil
    status.service_installed = init_script ~= nil
    status.bin_path = bin_path or ""
    status.init_script = init_script or ""

    local pid_out = util.exec("pgrep -f 'AdGuardHome' 2>/dev/null")
    local pid = pid_out and pid_out:match("(%d+)") or nil
    if pid then
        status.running = true
        status.pid = tonumber(pid)
    elseif init_script then
        local svc_out = util.exec(init_script .. " status 2>&1")
        if svc_out and svc_out:match("[Rr]unning") then
            status.running = true
        end
    end

    if bin_path then
        local ver = util.exec(bin_path .. " --version 2>&1")
        if ver then
            local v = ver:match("version v?([%d%.]+)")
            if not v then v = ver:match("([%d%.]+)") end
            if v then status.version = "v" .. v end
        end
    end

    for _, p in ipairs(CONFIG_PATHS) do
        if fs.access(p) then
            local content = fs.readfile(p)
            if content then
                local port = content:match("bind_port:%s*(%d+)")
                if not port then
                    port = content:match("http:.-address:%s*[%d%.]+:(%d+)")
                end
                if not port then
                    port = content:match("http:.-address:%s*:(%d+)")
                end
                if port then
                    status.port = tonumber(port)
                    break
                end
            end
        end
    end

    http.prepare_content("application/json")
    http.write_json(status)
end

local function post_value(key)
    local val = http.formvalue(key)
    if val and val ~= "" then return val end
    local content_type = http.getenv("CONTENT_TYPE") or ""
    if content_type:match("json") then
        local body = http.content()
        if body then
            local v = body:match('"' .. key .. '"%s*:%s*"(.-)"')
            if v then return v end
            v = body:match('"' .. key .. '"%s*:%s*(%d+)')
            if v then return v end
        end
    end
    return nil
end

function do_action()
    local action = post_value("action")

    if action ~= "start" and action ~= "stop" and action ~= "restart" and action ~= "install_service" and action ~= "install_core" then
        http.prepare_content("application/json")
        http.write_json({ success = false, error = "invalid action" })
        return
    end

    if action == "install_core" then
        load_proxies()
        launch_core_upgrade(true)
        http.prepare_content("application/json")
        http.write_json({ success = true })
        return
    end

    local bin_path = find_binary()
    local init_script = find_init_script()
    local cmd

    if action == "install_service" then
        if bin_path then
            cmd = bin_path .. " -s install"
        else
            http.prepare_content("application/json")
            http.write_json({ success = false, error = "binary not found" })
            return
        end
    else
        if init_script then
            cmd = init_script .. " " .. action
        elseif bin_path then
            cmd = bin_path .. " -s " .. action
        else
            http.prepare_content("application/json")
            http.write_json({ success = false, error = "no init script or binary found" })
            return
        end
    end

    local time_str = os.date("%Y-%m-%d %H:%M:%S")
    -- 单次同步动作重置清空日志文件（>），并将运行标准输出重定向回日志
    util.exec("echo '[" .. time_str .. "] Executing action: " .. action .. "' > " .. EXEC_LOG)
    local result = util.exec(cmd .. " 2>&1 | tee -a " .. EXEC_LOG)
    
    http.prepare_content("application/json")
    http.write_json({ success = true, output = result })
end

function check_update()
    load_proxies()
    local output = try_with_proxies("https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest")
    local latest = ""
    if output and #output > 0 then
        latest = output:match('"tag_name"%s*:%s*"(.-)"') or ""
    end
    http.prepare_content("application/json")
    http.write_json({ latest_version = latest })
end

function launch_core_upgrade(force)
    local bin_path = find_binary()
    local ts = os.date("%Y%m%d_%H%M%S") or ("t" .. os.time())
    local backup_dir = "/root/agh_backup_core_" .. ts
    local candidates_str = table.concat(PROXY_LIST, " ")
    local init_scripts_str = table.concat(INIT_SCRIPTS, " ")
    local bin_paths_str = table.concat(BIN_PATHS, " ")
    local install_base = "https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"

    local L = {}
    local function add(line) L[#L + 1] = line end

    add("#!/bin/sh")
    add("TS=" .. ts)
    add("BACKUP_DIR='" .. backup_dir .. "'")
    add("LOG='" .. EXEC_LOG .. "'")
    add("BIN_PATH='" .. (bin_path or "") .. "'")
    add("FORCE='" .. (force and "1" or "0") .. "'")
    add("PRIMARY_PROXY='" .. PRIMARY_PROXY .. "'")
    add("PROXY_CANDIDATES='" .. candidates_str .. "'")
    add("INIT_SCRIPTS='" .. init_scripts_str .. "'")
    add("BIN_PATHS='" .. bin_paths_str .. "'")
    add("INSTALL_BASE='" .. install_base .. "'")
    add("")
    add("cleanup() { rm -f /tmp/agh_install_${TS}.sh 2>/dev/null; }")
    add("trap 'cleanup' EXIT INT TERM")
    add("")
    add("get_version() {")
    add("  [ -x \"$1\" ] || return 1")
    add("  \"$1\" --version 2>/dev/null | grep -oE 'v?[0-9]+\\.[0-9]+\\.[0-9]+' | head -n1")
    add("}")
    add("")
    add("svc() {")
    add("  for s_i in $INIT_SCRIPTS; do")
    add("    [ -f \"$s_i\" ] && \"$s_i\" \"$1\" 2>/dev/null && return 0")
    add("  done")
    add("  return 1")
    add("}")
    add("")
    add("fetch_installer() {")
    add("  fi_out=\"$1\"")
    add("  fi_seen='__init__'")
    add("  for fi_p in \"$PRIMARY_PROXY\" \"\" $PROXY_CANDIDATES; do")
    add("    [ \"$fi_p\" = \"$fi_seen\" ] && continue")
    add("    fi_seen=\"$fi_p\"")
    add("    if [ -n \"$fi_p\" ]; then fi_url=\"${fi_p}${INSTALL_BASE}\"; else fi_url=\"$INSTALL_BASE\"; fi")
    add("    echo \"   try: $fi_url\" >> \"$LOG\"")
    add("    if curl -m 30 -fsSL -o \"$fi_out\" \"$fi_url\" 2>>\"$LOG\"; then")
    add("      [ -s \"$fi_out\" ] && return 0")
    add("    fi")
    add("  done")
    add("  return 1")
    add("}")
    add("")
    add("echo '=== AdGuardHome core upgrade task started ===' > \"$LOG\"")
    add("")
    add("echo '>> Phase 1: backup current binary' >> \"$LOG\"")
    add("OLD_VERSION=''")
    add("if [ -n \"$BIN_PATH\" ] && [ -f \"$BIN_PATH\" ]; then")
    add("  mkdir -p \"$BACKUP_DIR\"")
    add("  cp -a \"$BIN_PATH\" \"$BACKUP_DIR/AdGuardHome\" 2>/dev/null || cp \"$BIN_PATH\" \"$BACKUP_DIR/AdGuardHome\"")
    add("  chmod 755 \"$BACKUP_DIR/AdGuardHome\" 2>/dev/null")
    add("  OLD_VERSION=$(get_version \"$BIN_PATH\")")
    add("  echo \"   backed up: $BIN_PATH (v${OLD_VERSION:-unknown})\" >> \"$LOG\"")
    add("else")
    add("  echo '   no existing binary to backup (fresh install)' >> \"$LOG\"")
    add("fi")
    add("")
    add("echo '>> Phase 2: execute upgrade' >> \"$LOG\"")
    add("UPGRADE_RC=1")
    add("TMP_INST=\"/tmp/agh_install_${TS}.sh\"")
    add("if [ \"$FORCE\" = \"1\" ]; then")
    add("  echo '   mode: force reinstall (install script -r)' >> \"$LOG\"")
    add("  if fetch_installer \"$TMP_INST\"; then")
    add("    svc stop >> \"$LOG\" 2>&1 || pkill -f AdGuardHome 2>/dev/null")
    add("    sleep 2")
    add("    sh \"$TMP_INST\" -r >> \"$LOG\" 2>&1")
    add("    UPGRADE_RC=$?")
    add("  else")
    add("    echo '   [download failed] install.sh' >> \"$LOG\"")
    add("    UPGRADE_RC=1")
    add("  fi")
    add("elif [ -n \"$BIN_PATH\" ]; then")
    add("  echo '   mode: AdGuardHome --update' >> \"$LOG\"")
    add("  \"$BIN_PATH\" --update >> \"$LOG\" 2>&1")
    add("  UPGRADE_RC=$?")
    add("else")
    add("  echo '   mode: install script (no existing binary)' >> \"$LOG\"")
    add("  if fetch_installer \"$TMP_INST\"; then")
    add("    sh \"$TMP_INST\" >> \"$LOG\" 2>&1")
    add("    UPGRADE_RC=$?")
    add("  else")
    add("    echo '   [download failed] install.sh' >> \"$LOG\"")
    add("    UPGRADE_RC=1")
    add("  fi")
    add("fi")
    add("rm -f \"$TMP_INST\" 2>/dev/null")
    add("echo \"   upgrade exit code: $UPGRADE_RC\" >> \"$LOG\"")
    add("")
    add("echo '>> Phase 3: verify new binary' >> \"$LOG\"")
    add("NEW_BIN=''")
    add("for v_p in $BIN_PATHS \"$BIN_PATH\"; do")
    add("  [ -z \"$v_p\" ] && continue")
    add("  if [ -f \"$v_p\" ]; then NEW_BIN=\"$v_p\"; break; fi")
    add("done")
    add("if [ -z \"$NEW_BIN\" ]; then")
    add("  v_w=$(which AdGuardHome 2>/dev/null | tr -d '[:space:]')")
    add("  [ -n \"$v_w\" ] && [ -f \"$v_w\" ] && NEW_BIN=\"$v_w\"")
    add("fi")
    add("VERIFY_OK=1")
    add("if [ -z \"$NEW_BIN\" ] || [ ! -f \"$NEW_BIN\" ]; then")
    add("  echo '   [verify] binary not found after upgrade' >> \"$LOG\"")
    add("  VERIFY_OK=0")
    add("else")
    add("  [ -x \"$NEW_BIN\" ] || chmod 755 \"$NEW_BIN\" 2>/dev/null")
    add("  if [ ! -x \"$NEW_BIN\" ]; then")
    add("    echo \"   [verify] binary not executable: $NEW_BIN\" >> \"$LOG\"")
    add("    VERIFY_OK=0")
    add("  fi")
    add("fi")
    add("NEW_VERSION=''")
    add("if [ \"$VERIFY_OK\" = \"1\" ]; then")
    add("  if \"$NEW_BIN\" --version 2>/dev/null | grep -q '.'; then")
    add("    NEW_VERSION=$(get_version \"$NEW_BIN\")")
    add("    [ -z \"$NEW_VERSION\" ] && NEW_VERSION='unknown'")
    add("    echo \"   new binary: $NEW_BIN (v$NEW_VERSION)\" >> \"$LOG\"")
    add("  else")
    add("    echo \"   [verify] binary cannot run: $NEW_BIN\" >> \"$LOG\"")
    add("    VERIFY_OK=0")
    add("  fi")
    add("fi")
    add("")
    add("if [ \"$VERIFY_OK\" != \"1\" ]; then")
    add("  echo '>> Phase 4: rollback (verify failed)' >> \"$LOG\"")
    add("  if [ -n \"$BIN_PATH\" ] && [ -f \"$BACKUP_DIR/AdGuardHome\" ]; then")
    add("    svc stop >> \"$LOG\" 2>&1 || pkill -f AdGuardHome 2>/dev/null")
    add("    sleep 1")
    add("    mkdir -p \"$(dirname \"$BIN_PATH\")\"")
    add("    cp -a \"$BACKUP_DIR/AdGuardHome\" \"$BIN_PATH\" 2>/dev/null || cp \"$BACKUP_DIR/AdGuardHome\" \"$BIN_PATH\"")
    add("    chmod 755 \"$BIN_PATH\" 2>/dev/null")
    add("    echo \"   restored old binary: $BIN_PATH\" >> \"$LOG\"")
    add("    svc start >> \"$LOG\" 2>&1")
    add("    echo '   service restarted with old binary' >> \"$LOG\"")
    add("  else")
    add("    echo '   no backup to restore (was fresh install)' >> \"$LOG\"")
    add("  fi")
    add("  echo \"=== core upgrade FAILED: verify (exit=$UPGRADE_RC) ===\" >> \"$LOG\"")
    add("  exit 2")
    add("fi")
    add("")
    add("echo '>> Phase 5: restart service' >> \"$LOG\"")
    add("svc restart >> \"$LOG\" 2>&1 || { svc stop >> \"$LOG\" 2>&1; sleep 1; svc start >> \"$LOG\" 2>&1; }")
    add("echo \"=== core upgrade done (v${OLD_VERSION:-none} -> v${NEW_VERSION:-?}) ===\" >> \"$LOG\"")

    local scrpath = "/tmp/agh_core_upgrade_runner.sh"
    local f = io.open(scrpath, "w")
    if not f then return false end
    f:write(table.concat(L, "\n"))
    f:close()
    os.execute("chmod 755 " .. scrpath)
    -- 注意：ShellRunner 脚本执行前清写 EXEC_LOG 由 shell 头部定义
    os.execute("sh " .. scrpath .. " 2>&1 &")
    return true
end

function do_upgrade()
    load_proxies()
    local force = post_value("force")
    launch_core_upgrade(force == "1")
    http.prepare_content("application/json")
    http.write_json({ success = true })
end

function set_proxy()
    local proxy = post_value("proxy") or ""
    if not is_safe_proxy(proxy) then
        http.prepare_content("application/json")
        http.write_json({ success = false, error = "invalid proxy" })
        return
    end
    local tmp = PROXY_CONF .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then
        http.prepare_content("application/json")
        http.write_json({ success = false, error = "write failed" })
        return
    end
    f:write("proxy=" .. proxy .. "\n")
    f:close()
    os.rename(tmp, PROXY_CONF)
    os.execute("chmod 644 " .. PROXY_CONF .. " 2>/dev/null")
    load_proxies()
    http.prepare_content("application/json")
    http.write_json({ success = true, proxy = PRIMARY_PROXY })
end

function proxy_test()
    load_proxies()
    local proxy = post_value("proxy")
    if proxy == nil then proxy = PRIMARY_PROXY end
    if not is_safe_proxy(proxy) then
        http.prepare_content("application/json")
        http.write_json({ ok = false, error = "invalid proxy" })
        return
    end
    local test_url = "https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/README.md"
    local target = (proxy == "") and test_url or (proxy .. test_url)

    local cmd = "curl -m 8 -fsSL -o /dev/null -w 'TIME:%{time_total}' '" .. target .. "' 2>/dev/null; echo 'EXIT:'$?"
    local out = util.exec(cmd) or ""
    local latency_str = out:match("TIME:([%d%.]+)") or ""
    local exit_str = out:match("EXIT:(%d+)") or "1"
    local ok = (exit_str == "0")
    local latency = tonumber(latency_str)
    if latency then latency = math.floor(latency * 1000) end
    http.prepare_content("application/json")
    http.write_json({ ok = ok, latency = latency })
end

function get_log()
    local content = ""

    if fs.access(EXEC_LOG) then
        local data = fs.readfile(EXEC_LOG)
        if data and #data > 0 then
            content = data
        end
    end

    if content == "" then
        local agh_logs = {
            "/opt/AdGuardHome/data/agh.log",
            "/var/log/AdGuardHome.log",
            "/tmp/AdGuardHome.log"
        }
        for _, lf in ipairs(agh_logs) do
            if fs.access(lf) then
                local data = fs.readfile(lf)
                if data and #data > 50 then
                    content = data
                    break
                end
            end
        end
    end

    if content == "" then
        content = util.exec("logread -e 'AdGuardHome' 2>/dev/null")
    end
    if not content or content == "" then
        content = util.exec("logread 2>/dev/null | grep -i 'adguard'")
    end

    local bin_path = find_binary()
    local summary = ""
    if bin_path then
        local ver = util.exec(bin_path .. " --version 2>&1") or ""
        ver = ver:gsub("^%s+", ""):gsub("%s+$", "")
        summary = "=== AdGuardHome 状态 ===\n" .. ver .. "\n"
        local pid_out = util.exec("pgrep -f 'AdGuardHome' 2>/dev/null")
        if pid_out and pid_out:match("%d") then
            summary = summary .. "PID: " .. (pid_out:match("(%d+)") or "N/A") .. " (running)\n"
        else
            summary = summary .. "Status: stopped\n"
        end
        summary = summary .. "========================\n\n"
    end

    if not content or content == "" then
        content = "No logs available"
    end

    http.prepare_content("application/json")
    http.write_json({ content = summary .. content })
end

local function semver_compare(a, b)
    if not a or not b then return nil end
    local at, bt = {}, {}
    for n in string.gmatch(a, "%d+") do at[#at + 1] = tonumber(n) or 0 end
    for n in string.gmatch(b, "%d+") do bt[#bt + 1] = tonumber(n) or 0 end
    if #at == 0 or #bt == 0 then return nil end
    local maxn = #at > #bt and #at or #bt
    for i = 1, maxn do
        local ai = at[i] or 0
        local bi = bt[i] or 0
        if ai < bi then return -1 end
        if ai > bi then return 1 end
    end
    return 0
end

function check_dashboard_update()
    load_proxies()
    local manifest_url = "https://raw.githubusercontent.com/" .. DASH_REPO .. "/" .. DASH_BRANCH .. "/manifest.json"
    local body = try_with_proxies(manifest_url)
    if not body or body == "" then
        http.prepare_content("application/json")
        http.write_json({
            current_version = DASHBOARD_VERSION,
            latest_version = "",
            need_update = false,
            error = "fetch_failed"
        })
        return
    end
    local ver = body:match('"version"%s*:%s*"([^"]+)"')
    if not ver then
        http.prepare_content("application/json")
        http.write_json({
            current_version = DASHBOARD_VERSION,
            latest_version = "",
            need_update = false,
            error = "parse_failed"
        })
        return
    end
    local cmp = semver_compare(DASHBOARD_VERSION, ver)
    local need = (cmp and cmp < 0) or false
    http.prepare_content("application/json")
    http.write_json({
        current_version = DASHBOARD_VERSION,
        latest_version = ver,
        need_update = need
    })
end

function do_upgrade_dashboard()
    load_proxies()
    local ts = os.date("%Y%m%d_%H%M%S") or ("t" .. os.time())
    local backup_dir = "/root/agh_backup_dashboard_" .. ts
    local tmpdir = "/tmp/agh_dash_new_" .. ts
    local candidates_str = table.concat(PROXY_LIST, " ")

    local L = {}
    local function add(line) L[#L + 1] = line end

    add("#!/bin/sh")
    add("TS=" .. ts)
    add("BACKUP_DIR='" .. backup_dir .. "'")
    add("TMPDIR='" .. tmpdir .. "'")
    add("BASE='https://raw.githubusercontent.com/" .. DASH_REPO .. "/" .. DASH_BRANCH .. "/'")
    add("PRIMARY_PROXY='" .. PRIMARY_PROXY .. "'")
    add("PROXY_CANDIDATES='" .. candidates_str .. "'")
    add("LOG='" .. EXEC_LOG .. "'")
    add("")
    add("mkdir -p \"$BACKUP_DIR\" \"$TMPDIR\"")
    add("cleanup() { rm -rf \"$TMPDIR\" 2>/dev/null; rm -f \"${TMPDIR}_runner.sh\" 2>/dev/null; }")
    add("trap 'cleanup' EXIT INT TERM")
    add("")
    add("verify_file() {")
    add("  v_path=\"$1\"; v_min=\"$2\"; v_kind=\"$3\"")
    add("  [ -f \"$v_path\" ] || { echo \"   [verify] not exist: $v_path\" >> \"$LOG\"; return 1; }")
    add("  [ -s \"$v_path\" ] || { echo \"   [verify] empty: $v_path\" >> \"$LOG\"; return 1; }")
    add("  v_sz=$(wc -c < \"$v_path\" 2>/dev/null | tr -d '[:space:]')")
    add("  [ -n \"$v_sz\" ] || v_sz=0")
    add("  [ \"$v_sz\" -ge \"$v_min\" ] 2>/dev/null || { echo \"   [verify] size $v_sz < $v_min: $v_path\" >> \"$LOG\"; return 1; }")
    add("  case \"$v_kind\" in")
    add("    lmo)")
    add("      v_hex=$(tail -c 4 \"$v_path\" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d '[:space:]')")
    add("      [ \"$v_hex\" = \"4c4d4f00\" ] || { echo \"   [verify] LMO magic bad: $v_path ($v_hex)\" >> \"$LOG\"; return 1; }")
    add("      ;;")
    add("    lua)")
    add("      grep -q 'function' \"$v_path\" 2>/dev/null || { echo \"   [verify] lua no 'function': $v_path\" >> \"$LOG\"; return 1; }")
    add("      ;;")
    add("    js)")
    add("      grep -q 'view.extend' \"$v_path\" 2>/dev/null || { echo \"   [verify] js no 'view.extend': $v_path\" >> \"$LOG\"; return 1; }")
    add("      ;;")
    add("    po)")
    add("      grep -q 'msgid' \"$v_path\" 2>/dev/null || { echo \"   [verify] po no 'msgid': $v_path\" >> \"$LOG\"; return 1; }")
    add("      ;;")
    add("  esac")
    add("  return 0")
    add("}")
    add("")
    add("download_one() {")
    add("  d_src=\"$1\"; d_out=\"$2\"")
    add("  d_rel=\"${BASE}${d_src}\"")
    add("  d_seen='__init__'")
    add("  for d_p in \"$PRIMARY_PROXY\" \"\" $PROXY_CANDIDATES; do")
    add("    [ \"$d_p\" = \"$d_seen\" ] && continue")
    add("    d_seen=\"$d_p\"")
    add("    if [ -n \"$d_p\" ]; then d_url=\"${d_p}${d_rel}\"; else d_url=\"$d_rel\"; fi")
    add("    echo \"   try: $d_url\" >> \"$LOG\"")
    add("    if curl -m 30 -fsSL -o \"$d_out\" \"$d_url\" 2>>\"$LOG\"; then")
    add("      [ -s \"$d_out\" ] && { echo \"   ok: $d_src\" >> \"$LOG\"; return 0; }")
    add("    fi")
    add("  done")
    add("  echo \"   [download failed] all candidates failed: $d_src\" >> \"$LOG\"")
    add("  return 1")
    add("}")
    add("")
    add("DEPLOYED=''")
    add("rollback_all() {")
    add("  echo '>> auto rollback deployed files...' >> \"$LOG\"")
    add("  for r_f in $DEPLOYED; do")
    add("    r_b=\"$BACKUP_DIR$r_f\"")
    add("    if [ -f \"$r_b\" ]; then")
    add("      mkdir -p \"$(dirname \"$r_f\")\"")
    add("      cp -a \"$r_b\" \"$r_f\" 2>/dev/null || cp \"$r_b\" \"$r_f\"")
    add("      chmod 644 \"$r_f\" 2>/dev/null")
    add("      echo \"   restored: $r_f\" >> \"$LOG\"")
    add("    fi")
    add("  done")
    add("}")
    add("")
    add("deploy_one() {")
    add("  e_tmp=\"$1\"; e_dst=\"$2\"")
    add("  if [ -f \"$e_dst\" ]; then")
    add("    e_bdir=\"$BACKUP_DIR$(dirname \"$e_dst\")\"")
    add("    mkdir -p \"$e_bdir\"")
    add("    cp -a \"$e_dst\" \"$e_bdir/$(basename \"$e_dst\")\" 2>/dev/null || cp \"$e_dst\" \"$e_bdir/$(basename \"$e_dst\")\"")
    add("  fi")
    add("  mkdir -p \"$(dirname \"$e_dst\")\"")
    add("  if mv -f \"$e_tmp\" \"$e_dst\" 2>/dev/null; then")
    add("    chmod 644 \"$e_dst\" 2>/dev/null")
    add("    DEPLOYED=\"$DEPLOYED $e_dst\"")
    add("    echo \"   deployed: $e_dst\" >> \"$LOG\"")
    add("    return 0")
    add("  else")
    add("    echo \"   [mv failed]: $e_dst\" >> \"$LOG\"")
    add("    return 1")
    add("  fi")
    add("}")
    add("")
    add("fail_task() {")
    add("  f_reason=\"$1\"")
    add("  rollback_all")
    add("  echo \"=== dashboard upgrade FAILED: $f_reason ===\" >> \"$LOG\"")
    add("  exit 2")
    add("}")
    add("")
    add("echo '=== Dashboard upgrade task started ===' > \"$LOG\"")
    add("echo '>> Phase 1: download & verify' >> \"$LOG\"")

    for i = 1, #DASH_FILES do
        local f = DASH_FILES[i]
        local tmp_path = "$TMPDIR/" .. f.base
        add("download_one '" .. f.src .. "' '" .. tmp_path .. "' || fail_task 'download " .. f.src .. "'")
        add("verify_file '" .. tmp_path .. "' " .. tostring(f.min_size) .. " " .. f.kind .. " || fail_task 'verify " .. f.src .. "'")
    end

    add("echo '>> Phase 2: backup & deploy' >> \"$LOG\"")
    for i = 1, #DASH_FILES do
        local f = DASH_FILES[i]
        local tmp_path = "$TMPDIR/" .. f.base
        add("deploy_one '" .. tmp_path .. "' '" .. f.dst .. "' || fail_task 'deploy " .. f.src .. "'")
    end

    add("echo '>> Phase 3: clear cache & restart services' >> \"$LOG\"")
    add("rm -rf /tmp/luci-* 2>/dev/null || true")
    add("rm -f /tmp/luci-indexcache.* /tmp/luci-modulecache.* 2>/dev/null || true")
    add("find /tmp -name '*.luac' -delete 2>/dev/null || true")
    add("/etc/init.d/rpcd restart 2>/dev/null >> \"$LOG\" 2>&1 || true")
    add("/etc/init.d/uhttpd restart 2>/dev/null >> \"$LOG\" 2>&1 || true")
    add("echo '=== dashboard upgrade done (v" .. DASHBOARD_VERSION .. " -> upstream) ===' >> \"$LOG\"")

    local scrpath = tmpdir .. "_runner.sh"
    local f = io.open(scrpath, "w")
    if not f then
        http.prepare_content("application/json")
        http.write_json({ success = false, error = "script write failed" })
        return
    end
    f:write(table.concat(L, "\n"))
    f:close()
    os.execute("chmod 755 " .. scrpath)
    os.execute("sh " .. scrpath .. " 2>&1 &")
    http.prepare_content("application/json")
    http.write_json({ success = true })
end
