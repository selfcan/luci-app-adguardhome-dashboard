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

local UPGRADE_LOG = "/tmp/agh_upgrade.log"
local PROXY_CONF = "/etc/adguardhome-dashboard.proxy"

-- 代理列表: 安装时写入的配置优先，否则使用内置列表
local PROXY_LIST = {}

local function load_proxies()
    -- 读取安装时保存的代理配置
    if fs.access(PROXY_CONF) then
        local content = fs.readfile(PROXY_CONF)
        if content then
            local saved = content:match("proxy%s*=%s*(%S+)")
            if saved and saved ~= "" then
                PROXY_LIST[1] = saved
            end
        end
    end
    -- 内置代理兜底
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

local function gh_url(raw_url)
    if PROXY_LIST[1] and PROXY_LIST[1] ~= "" then
        return PROXY_LIST[1] .. raw_url
    end
    return raw_url
end

local function try_with_proxies(url)
    -- 始终先尝试直连（5 秒超时，快速失败）
    local direct = util.exec("curl -m 5 -fsSL '" .. url .. "' 2>/dev/null")
    if direct and #direct > 10 then
        return direct
    end
    -- 直连失败，逐个尝试代理（已配置的 + 内置的）
    for _, proxy in ipairs(PROXY_LIST) do
        local proxied = util.exec("curl -m 10 -fsSL '" .. proxy .. url .. "' 2>/dev/null")
        if proxied and #proxied > 10 then
            return proxied
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
    -- 菜单入口由 menu.d/luci-app-adguardhome-dashboard.json 注册（LuCI 2.0 标准）
    -- i18n 翻译由 menu.json 的 "i18n" 字段告知调度器自动加载
    -- 此处仅注册 API 子路由
    entry({"admin", "services", "adguardhome", "status"}, call("get_status"), nil, true)
    entry({"admin", "services", "adguardhome", "action"}, call("do_action"), nil, true)
    entry({"admin", "services", "adguardhome", "check_update"}, call("check_update"), nil, true)
    entry({"admin", "services", "adguardhome", "upgrade"}, call("do_upgrade"), nil, true)
    entry({"admin", "services", "adguardhome", "log"}, call("get_log"), nil, true)
    entry({"admin", "services", "adguardhome", "proxy_test"}, call("proxy_test"), nil, true)
end

-- 通用的调用上游安装脚本函数，flags 表示附加参数字符串（如 "-r")
local function run_install_script(flags)
    load_proxies()
    local install_url = gh_url("https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh")
    os.execute("echo '=== AdGuardHome 安装任务开始 ===' > " .. UPGRADE_LOG)
    local cmd = "curl -fsSL '" .. install_url .. "' | sh"
    if flags and flags ~= "" then
        cmd = cmd .. " -s -- " .. flags
    end
    cmd = cmd .. " >> " .. UPGRADE_LOG .. " 2>&1 &"
    os.execute(cmd)
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
        init_script = ""
    }

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
            if v then
                status.version = "v" .. v
            else
                v = ver:match("([%d%.]+)")
                if v then
                    status.version = "v" .. v
                end
            end
        end
    end

    for _, p in ipairs(CONFIG_PATHS) do
        if fs.access(p) then
            local content = fs.readfile(p)
            if content then
                -- AdGuardHome.yaml web 端口有两种格式:
                -- 旧版 (<v0.107.33): 顶层 bind_port: 3000
                -- 新版 (>=v0.107.36): http: 段下 address: 0.0.0.0:3000
                -- 注意: 通用 port: 是 dns 段的 DNS 端口 (53)，不能用来取 web 端口
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

        -- 返回当前已配置的 GitHub 代理（如有）以便前端预填
        if fs.access(PROXY_CONF) then
            local content = fs.readfile(PROXY_CONF)
            if content then
                local saved = content:match("proxy%s*=%s*(%S+)")
                if saved and saved ~= "" then
                    status.proxy = saved
                end
            end
        end
    end

    http.prepare_content("application/json")
    http.write_json(status)
end
