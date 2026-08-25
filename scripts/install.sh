#!/bin/sh
set -e

REPO="imonior/luci-app-adguardhome-dashboard"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

AGH_DIR="/opt/AdGuardHome"
AGH_BIN="/opt/AdGuardHome/AdGuardHome"
AGH_INSTALL_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"

# GitHub 加速代理列表（国内用户可选） / GitHub acceleration proxy list (optional for users in mainland CN)
PROXY_LIST="
https://ghfast.top/
https://gh-proxy.com/
https://kkgithub.com/
"

log() {
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    echo "[$ts] $1"
}

_now_ms() {
    # BusyBox date 不支持 %N 纳秒，直接用秒 × 1000（粒度 1s 足够代理延迟显示，且跨平台兼容） / BusyBox date lacks %N nanoseconds; use seconds × 1000 (1s granularity suffices for proxy latency display and is cross-platform)
    echo $(( $(date +%s 2>/dev/null || echo 0) * 1000 ))
}
_elapsed_ms() { echo $(( $(_now_ms) - $1 )); }

echo ""
echo "========================================================="
echo " AdGuardHome LuCI Dashboard 安装程序"
echo "========================================================="
echo ""

# ── GitHub 连通性检测 & 代理选择 ──────────────────── / GitHub connectivity check & proxy selection
# 测试目标与实际下载用的域名一致：raw.githubusercontent.com / Test target matches the actual download domain: raw.githubusercontent.com
TEST_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/README.md"

PROXY_PREFIX=""

if [ -n "$GITHUB_PROXY" ]; then
    PROXY_PREFIX="$GITHUB_PROXY"
    log "使用环境变量指定代理: $PROXY_PREFIX"
else
    log "检测 GitHub 连通性..."
    _t0=$(_now_ms)
    if curl -fsSL -m 10 -o /dev/null "$TEST_URL" 2>/dev/null; then
        log "GitHub 直连正常 ($(_elapsed_ms $_t0)ms)"
    else
        log "GitHub 直连失败，正在测试代理节点..."

        # 用临时文件记录每个代理的测试结果（path|status|ms），避免脆弱的字符串解析 / Record each proxy's test result in a temp file (path|status|ms) to avoid fragile string parsing
        _results_file=$(mktemp 2>/dev/null || echo "/tmp/agh_proxy_results_$$")
        : > "$_results_file"

        for proxy in $PROXY_LIST; do
            _test_url="${proxy}${TEST_URL}"
            _t1=$(_now_ms)
            if curl -fsSL -m 10 -o /dev/null "$_test_url" 2>/dev/null; then
                echo "${proxy}|ok|$(_elapsed_ms $_t1)" >> "$_results_file"
            else
                echo "${proxy}|fail|0" >> "$_results_file"
            fi
        done

        echo ""
        echo "  #   代理节点          状态"
        echo "  ─────────────────────────────"
        echo "  1)  直连              ✗ 不可用"

        _idx=2
        while IFS='|' read -r _p _s _ms; do
            [ -z "$_p" ] && continue
            _domain=$(echo "$_p" | sed 's|https\{0,1\}://||;s|/$||')
            if [ "$_s" = "ok" ]; then
                printf "  %d)  %-18s ✓ %sms\n" "$_idx" "$_domain" "$_ms"
            else
                printf "  %d)  %-18s ✗ 超时\n" "$_idx" "$_domain"
            fi
            _idx=$((_idx + 1))
        done < "$_results_file"

        CUSTOM_OPT=$_idx
        echo "  ${CUSTOM_OPT})  自定义代理 URL"
        echo ""
        echo "  ⚠ 连通性测试仅供参考，DNS 劫持/透明代理可能导致测试不准"
        echo ""
        printf "请选择 [1-%d，默认 2]: " "$CUSTOM_OPT"
        read -r PROXY_CHOICE
        PROXY_CHOICE=${PROXY_CHOICE:-2}

        if [ "$PROXY_CHOICE" = "$CUSTOM_OPT" ]; then
            printf "请输入自定义代理 URL (例: https://gh.proxy.com/): "
            read -r USER_PROXY
            # 确保以斜杠结尾 / Ensure it ends with a slash
            case "$USER_PROXY" in
                */) PROXY_PREFIX="$USER_PROXY" ;;
                *)  PROXY_PREFIX="${USER_PROXY}/" ;;
            esac
            log "使用自定义代理: $PROXY_PREFIX"
        elif [ "$PROXY_CHOICE" != "1" ]; then
            _i=1
            _picked=""
            while IFS='|' read -r _p _s _ms; do
                if [ "$_i" = "$((PROXY_CHOICE - 1))" ] && [ "$_s" = "ok" ]; then
                    PROXY_PREFIX="$_p"
                    _picked="yes"
                    break
                fi
                _i=$((_i + 1))
            done < "$_results_file"
            if [ -n "$PROXY_PREFIX" ] && [ "$_picked" = "yes" ]; then
                log "使用代理: $PROXY_PREFIX"
            else
                log "无效选择或该节点不可用，使用直连"
            fi
        fi
        rm -f "$_results_file" 2>/dev/null
    fi
fi

# 应用代理到所有 GitHub URL / Apply the proxy to all GitHub URLs
if [ -n "$PROXY_PREFIX" ]; then
    RAW_BASE="${PROXY_PREFIX}https://raw.githubusercontent.com/${REPO}/${BRANCH}"
    AGH_INSTALL_URL="${PROXY_PREFIX}${AGH_INSTALL_URL}"
    GH_API_BASE="${PROXY_PREFIX}https://api.github.com"
    echo "proxy=${PROXY_PREFIX}" > /etc/adguardhome-dashboard.proxy 2>/dev/null || true
else
    GH_API_BASE="https://api.github.com"
    rm -f /etc/adguardhome-dashboard.proxy 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════
# 第一部分：安装 AdGuard Home 核心 / Part 1: install the AdGuard Home core
# ═══════════════════════════════════════════════════════════

log "── 第一部分：AdGuard Home 核心 ──"

if [ -f "$AGH_BIN" ]; then
    log "检测到已安装 AdGuard Home ($AGH_BIN)"

    CURRENT_VER=$("$AGH_BIN" --version 2>&1 | awk '{print $NF}')
    case "$CURRENT_VER" in v*) ;; *) CURRENT_VER="v$CURRENT_VER" ;; esac

    LATEST_VER=$(curl -fsSL -m 5 "https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest" 2>/dev/null \
        | awk -F'"' '/tag_name/{print $4; exit}')
    if [ -z "$LATEST_VER" ] && [ "$GH_API_BASE" != "https://api.github.com" ]; then
        LATEST_VER=$(curl -fsSL -m 8 "${GH_API_BASE}/repos/AdguardTeam/AdGuardHome/releases/latest" 2>/dev/null \
            | awk -F'"' '/tag_name/{print $4; exit}')
    fi
    if [ -z "$LATEST_VER" ]; then
        for _p in $PROXY_LIST; do
            LATEST_VER=$(curl -fsSL -m 8 "${_p}https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest" 2>/dev/null \
                | awk -F'"' '/tag_name/{print $4; exit}')
            [ -n "$LATEST_VER" ] && break
        done
    fi

    if [ -n "$CURRENT_VER" ] && [ -n "$LATEST_VER" ]; then
        log "当前版本: $CURRENT_VER    最新版本: $LATEST_VER"
        if [ "$CURRENT_VER" = "$LATEST_VER" ]; then
            log "已是最新版本"
        fi
    elif [ -n "$CURRENT_VER" ]; then
        log "当前版本: $CURRENT_VER (无法获取在线版本)"
    elif [ -n "$LATEST_VER" ]; then
        log "当前版本: 未知    最新版本: $LATEST_VER"
    fi

    echo ""
    echo "  1) 从官方重新下载安装（覆盖当前版本）"
    echo "  2) 跳过，保留当前版本"
    echo ""
    printf "请选择 [1/2，默认 2]: "
    read -r CHOICE
    CHOICE=${CHOICE:-2}

    if [ "$CHOICE" = "1" ]; then
        if pgrep -f 'AdGuardHome' > /dev/null 2>&1; then
            log "检测到 AdGuard Home 正在运行，先停止服务..."
            if [ -f /etc/init.d/AdGuardHome ]; then
                /etc/init.d/AdGuardHome stop 2>/dev/null || true
            elif [ -f /etc/init.d/adguardhome ]; then
                /etc/init.d/adguardhome stop 2>/dev/null || true
            else
                "$AGH_BIN" -s stop 2>/dev/null || true
            fi
            sleep 2
            if pgrep -f 'AdGuardHome' > /dev/null 2>&1; then
                log "警告: 服务未能正常停止，尝试强制终止..."
                killall AdGuardHome 2>/dev/null || true
                sleep 1
            fi
            log "AdGuard Home 已停止"
        fi

        log "从官方脚本重新安装 AdGuard Home..."
        curl -fsSL "$AGH_INSTALL_URL" | sh -s -- -r
        log "AdGuard Home 安装完成"
    else
        log "跳过 AdGuard Home 核心安装，保留当前版本"
    fi
else
    log "未检测到 AdGuard Home，开始从官方脚本安装..."
    curl -fsSL "$AGH_INSTALL_URL" | sh
    log "AdGuard Home 安装完成"
fi

echo ""

# ═══════════════════════════════════════════════════════════
# 第二部分：安装 LuCI Dashboard 管理面板 / Part 2: install the LuCI Dashboard management panel
# ═══════════════════════════════════════════════════════════

log "── 第二部分：LuCI Dashboard 管理面板 ──"

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR" 2>/dev/null)"
LOCAL_FILES="$PROJECT_ROOT/files"

TMPDIR=$(mktemp -d)
DOWNLOAD_DIR="$TMPDIR/download"
mkdir -p "$DOWNLOAD_DIR/luci/controller" "$DOWNLOAD_DIR/luci/menu.d" "$DOWNLOAD_DIR/luci/i18n" "$DOWNLOAD_DIR/view"

download_from_github() {
    log "从 GitHub 下载 Dashboard 文件..."
    _cb=$(date +%s 2>/dev/null || echo 0)
    _gh_raw="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

    dl() {
        local path="$1" dest="$2"
        local fname=$(basename "$dest")
        if curl -fsSL -m 30 --connect-timeout 10 --retry 2 \
            -o "$dest" "${RAW_BASE}/${path}?_cb=${_cb}" 2>/dev/null; then
            log "  ✓ $fname"
            return 0
        fi
        for _p in $PROXY_LIST; do
            if curl -fsSL -m 30 --connect-timeout 10 --retry 2 \
                -o "$dest" "${_p}${_gh_raw}/${path}?_cb=${_cb}" 2>/dev/null; then
                log "  ✓ $fname (via $(echo "$_p" | sed 's|https\{0,1\}://||;s|/$||'))"
                return 0
            fi
        done
        if curl -fsSL -m 30 --connect-timeout 10 --retry 2 \
            -o "$dest" "${_gh_raw}/${path}?_cb=${_cb}" 2>/dev/null; then
            log "  ✓ $fname (direct)"
            return 0
        fi
        log "  ✗ 下载失败: $fname（直连和所有代理均失败）"
        log "  提示: 可使用 GITHUB_PROXY=https://ghfast.top/ 环境变量强制指定代理"
        rm -rf "$TMPDIR"
        exit 1
    }
    dl "files/luci/controller/adguardhome.lua"                     "$DOWNLOAD_DIR/luci/controller/adguardhome.lua"
    dl "files/luci/menu.d/luci-app-adguardhome-dashboard.json"     "$DOWNLOAD_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json"
    dl "files/luci/acl.json"                                       "$DOWNLOAD_DIR/luci/acl.json"
    dl "files/view/dashboard.js"                                   "$DOWNLOAD_DIR/view/dashboard.js"
    dl "files/luci/i18n/adguardhome.lmo"                           "$DOWNLOAD_DIR/luci/i18n/adguardhome.lmo"
    dl "files/luci/i18n/adguardhome.zh-cn.lmo"                     "$DOWNLOAD_DIR/luci/i18n/adguardhome.zh-cn.lmo"
    dl "manifest.json"                                              "$DOWNLOAD_DIR/manifest.json"
    # 下载校验和清单（内容指纹，用于 sha256 比对，防止代理缓存旧版本） / Download the checksum manifest (content fingerprint, used for sha256 comparison to prevent stale proxy-cached builds)
    if curl -fsSL -m 30 --connect-timeout 10 --retry 2 \
        -o "$DOWNLOAD_DIR/checksums.sha256" "${RAW_BASE}/checksums.sha256?_cb=${_cb}" 2>/dev/null; then
        log "  ✓ checksums.sha256"
    else
        _cs_ok=0
        for _p in $PROXY_LIST; do
            if curl -fsSL -m 30 --connect-timeout 10 --retry 2 \
                -o "$DOWNLOAD_DIR/checksums.sha256" "${_p}${_gh_raw}/checksums.sha256?_cb=${_cb}" 2>/dev/null; then
                log "  ✓ checksums.sha256 (via $(echo "$_p" | sed 's|https\{0,1\}://||;s|/$||'))"
                _cs_ok=1
                break
            fi
        done
        [ "$_cs_ok" = "1" ] || log "  ⚠ checksums.sha256 下载失败，将仅做语义特征校验"
    fi
    log "所有文件下载完成"
}

if [ -f "$LOCAL_FILES/luci/controller/adguardhome.lua" ]; then
    log "检测到本地项目文件 ($PROJECT_ROOT)"
    echo ""
    echo "  1) 使用本地文件安装"
    echo "  2) 删除本地项目后从 GitHub 重新下载"
    echo ""
    printf "请选择 [1/2，默认 1]: "
    read -r SRC_CHOICE
    SRC_CHOICE=${SRC_CHOICE:-1}

    if [ "$SRC_CHOICE" = "2" ]; then
        log "删除本地项目目录: $PROJECT_ROOT"
        rm -rf "$PROJECT_ROOT"
        download_from_github
    else
        log "使用本地文件复制..."
        cp "$LOCAL_FILES/luci/controller/adguardhome.lua" "$DOWNLOAD_DIR/luci/controller/"
        cp "$LOCAL_FILES/luci/menu.d/luci-app-adguardhome-dashboard.json" "$DOWNLOAD_DIR/luci/menu.d/"
        cp "$LOCAL_FILES/luci/acl.json" "$DOWNLOAD_DIR/luci/"
        cp "$LOCAL_FILES/view/dashboard.js" "$DOWNLOAD_DIR/view/"
        cp "$LOCAL_FILES/luci/i18n/adguardhome.lmo" "$DOWNLOAD_DIR/luci/i18n/"
        cp "$LOCAL_FILES/luci/i18n/adguardhome.zh-cn.lmo" "$DOWNLOAD_DIR/luci/i18n/"
        cp "$PROJECT_ROOT/manifest.json" "$DOWNLOAD_DIR/manifest.json"
    fi
else
    download_from_github
fi

# ── 辅助：计算 sha256（兼容无 sha256sum 的环境降级到 openssl）── / Helper: compute sha256 (falls back to openssl where sha256sum is unavailable)
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl sha256 "$1" 2>/dev/null | awk '{print $NF}'
    fi
}

# ── 内容校验：sha256 指纹（主） + 语义特征（兜底）── / Content verification: sha256 fingerprint (primary) + semantic feature (fallback)
# 防止代理/CDN 返回缓存中的旧版本（曾因 ghfast.top 缓存旧 dashboard.js 导致备份管理缺失）。 / Prevent proxies/CDNs from serving a cached old build (ghfast.top once cached an old dashboard.js, dropping the backup feature).
# sha256 比对能拦下"任何与发布清单不一致的内容"（不限于缺失某功能）； / sha256 comparison blocks ANY content diverging from the release manifest (not limited to a missing feature);
# 若 checksums.sha256 不可用，则降级为语义特征校验（fetchBackups / list_backups）。 / If checksums.sha256 is unavailable, fall back to semantic feature checks (fetchBackups / list_backups).
verify_one() {
    _src="$1"; _f="$2"
    _ok=1
    if [ -f "$DOWNLOAD_DIR/checksums.sha256" ]; then
        _exp=$(grep -F " $_src" "$DOWNLOAD_DIR/checksums.sha256" 2>/dev/null | awk '{print $1}' | head -n1)
        if [ -n "$_exp" ]; then
            _act=$(sha256_of "$_f")
            if [ -n "$_act" ] && [ "$_exp" != "$_act" ]; then
                log "  ✗ sha256 不匹配: $_src"
                log "    期望: $_exp"
                log "    实际: $_act"
                log "    → 极可能是代理/CDN 缓存的旧版本"
                _ok=0
            fi
        fi
    fi
    case "$_src" in
        files/view/dashboard.js)
            grep -q 'fetchBackups' "$_f" 2>/dev/null || { log "  ✗ dashboard.js 缺少备份管理功能（代理缓存旧版？）"; _ok=0; } ;;
        files/luci/controller/adguardhome.lua)
            grep -q 'list_backups' "$_f" 2>/dev/null || { log "  ✗ adguardhome.lua 缺少备份 API（代理缓存旧版？）"; _ok=0; } ;;
        manifest.json)
            grep -q '"version"' "$_f" 2>/dev/null || { log "  ✗ manifest.json 缺少 version 字段（代理缓存旧版？）"; _ok=0; } ;;
    esac
    return $_ok
}

log "校验下载文件内容（sha256 指纹 + 语义特征，防止代理缓存旧版本）..."
_fail=0
verify_one "files/luci/controller/adguardhome.lua"                  "$DOWNLOAD_DIR/luci/controller/adguardhome.lua" || _fail=1
verify_one "files/luci/menu.d/luci-app-adguardhome-dashboard.json" "$DOWNLOAD_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json" || _fail=1
verify_one "files/luci/acl.json"                                    "$DOWNLOAD_DIR/luci/acl.json" || _fail=1
verify_one "files/view/dashboard.js"                                "$DOWNLOAD_DIR/view/dashboard.js" || _fail=1
verify_one "files/luci/i18n/adguardhome.lmo"                        "$DOWNLOAD_DIR/luci/i18n/adguardhome.lmo" || _fail=1
verify_one "files/luci/i18n/adguardhome.zh-cn.lmo"                 "$DOWNLOAD_DIR/luci/i18n/adguardhome.zh-cn.lmo" || _fail=1
verify_one "manifest.json"                                          "$DOWNLOAD_DIR/manifest.json" || _fail=1
if [ "$_fail" = "1" ]; then
    log "内容校验失败：极可能是代理/CDN 缓存了旧版本"
    log "解决: 更换代理 GITHUB_PROXY=https://kkgithub.com/ 或 GITHUB_PROXY=https://gh-proxy.com/ 后重试"
    rm -rf "$TMPDIR"
    exit 1
fi
log "  ✓ 内容校验通过（sha256 指纹 + 语义特征）"

# ── 备份当前安装的文件（与面板升级的两阶段提交保持一致）──────────── / Back up currently-installed files (kept consistent with the panel-upgrade two-phase commit)
TS=$(date '+%Y%m%d_%H%M%S' 2>/dev/null || date +%s 2>/dev/null || echo 0)
BACKUP_DIR="/root/agh_backup_install_${TS}"

# 备份目标：与下面清理/部署完全对应的现有文件 / Backup targets: the existing files that map exactly to the cleanup/deploy below
BACKUP_PAIRS="
/usr/lib/lua/luci/controller/adguardhome.lua|controller/adguardhome.lua
/usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json|menu.d/luci-app-adguardhome-dashboard.json
/usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json|acl.d/luci-app-adguardhome-dashboard.json
/usr/lib/lua/luci/i18n/adguardhome.lmo|i18n/adguardhome.lmo
/usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo|i18n/adguardhome.zh-cn.lmo
/www/luci-static/resources/view/adguardhome/dashboard.js|view/adguardhome/dashboard.js
/usr/share/adguardhome-dashboard/manifest.json|adguardhome-dashboard/manifest.json
"

_backup_count=0
for pair in $BACKUP_PAIRS; do
    src=$(echo "$pair" | cut -d'|' -f1)
    rel=$(echo "$pair" | cut -d'|' -f2)
    if [ -f "$src" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        cp -a "$src" "$BACKUP_DIR/$rel" 2>/dev/null || cp "$src" "$BACKUP_DIR/$rel"
        _backup_count=$((_backup_count + 1))
        log "  备份: $src  ->  $BACKUP_DIR/$rel"
    fi
done

# 注意：install 不备份 AdGuardHome 核心二进制，核心安装/升级的回滚由 AGH 官方安装脚本和核心升级流程单独管理 / Note: install does NOT back up the AdGuardHome core binary; core rollback is handled separately by AGH's official script and the core-upgrade flow

if [ "$_backup_count" -gt 0 ]; then
    log "本次备份 $_backup_count 个面板文件至: $BACKUP_DIR"

    # 生成 restore.sh：用户可一键恢复到本次安装前的状态（仅面板文件，不含 AGH 核心） / Generate restore.sh: one-click restore to the pre-install state (panel files only, no AGH core)
    cat > "$BACKUP_DIR/restore.sh" <<EOF
#!/bin/sh
# 一键恢复 LuCI Dashboard 到 $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) 安装前的状态 / One-click restore of the LuCI Dashboard to its pre-install state
# 备份目录: $BACKUP_DIR / Backup dir: $BACKUP_DIR
# 仅恢复面板文件，不涉及 AdGuardHome 核心二进制 / Restore panel files only; does not touch the AdGuardHome core binary
set -u
BACKUP_DIR='$BACKUP_DIR'

restore_one() {
    r_rel="\$1"
    r_dst="\$2"
    r_src="\$BACKUP_DIR/\$r_rel"
    if [ -f "\$r_src" ]; then
        mkdir -p "\$(dirname "\$r_dst")"
        cp -a "\$r_src" "\$r_dst" 2>/dev/null || cp "\$r_src" "\$r_dst"
        chmod 644 "\$r_dst" 2>/dev/null
        echo "  restored: \$r_dst"
    else
        echo "  (skip) no backup: \$r_rel"
    fi
}

echo "=== 从 \$BACKUP_DIR 恢复 LuCI Dashboard ==="

echo ">> 恢复面板文件..."
restore_one 'controller/adguardhome.lua'                                   '/usr/lib/lua/luci/controller/adguardhome.lua'
restore_one 'menu.d/luci-app-adguardhome-dashboard.json'                  '/usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json'
restore_one 'acl.d/luci-app-adguardhome-dashboard.json'                   '/usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json'
restore_one 'i18n/adguardhome.lmo'                                         '/usr/lib/lua/luci/i18n/adguardhome.lmo'
restore_one 'i18n/adguardhome.zh-cn.lmo'                                   '/usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo'
restore_one 'view/adguardhome/dashboard.js'                                '/www/luci-static/resources/view/adguardhome/dashboard.js'
restore_one 'adguardhome-dashboard/manifest.json'                      '/usr/share/adguardhome-dashboard/manifest.json'

echo ">> 清理缓存并重启服务..."
rm -rf /tmp/luci-* 2>/dev/null
rm -f /tmp/luci-indexcache.* /tmp/luci-modulecache.* 2>/dev/null
find /tmp -name '*.luac' -delete 2>/dev/null
/etc/init.d/rpcd restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null

echo "=== 恢复完成（仅面板文件，AGH 核心未受影响）==="
echo "请刷新浏览器查看效果。"
EOF
    chmod 755 "$BACKUP_DIR/restore.sh" 2>/dev/null
    log "恢复脚本已生成: $BACKUP_DIR/restore.sh"
else
    log "本次安装为全新部署，无旧文件可备份"
fi

# ── 清理旧版本文件 ────────────────────────────────── / Clean up old-version files
log "清理旧版本文件..."
rm -f /usr/lib/lua/luci/controller/adguardhome.lua
rm -f /usr/share/luci/controller/adguardhome.lua
rm -rf /usr/lib/lua/luci/view/adguardhome
rm -rf /www/luci-static/resources/view/adguardhome
rm -f /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json
rm -f /usr/share/luci/menu.d/luci-app-adguardhome.json
rm -f /usr/share/rpcd/acl.d/luci-app-adguardhome.json
rm -f /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json
rm -f /usr/lib/lua/luci/i18n/adguardhome.lmo
rm -f /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo

# ── 创建目标目录 ──────────────────────────────────── / Create target directories
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/share/luci/menu.d
mkdir -p /usr/share/rpcd/acl.d
mkdir -p /usr/lib/lua/luci/i18n
mkdir -p /www/luci-static/resources/view/adguardhome
mkdir -p /usr/share/adguardhome-dashboard

# ── 部署文件 ──────────────────────────────────────── / Deploy files
log "部署文件到系统目录..."
cp "$DOWNLOAD_DIR/luci/controller/adguardhome.lua"                     /usr/lib/lua/luci/controller/adguardhome.lua
cp "$DOWNLOAD_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json"     /usr/share/luci/menu.d/
cp "$DOWNLOAD_DIR/luci/acl.json"                                       /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json
cp "$DOWNLOAD_DIR/view/dashboard.js"                                   /www/luci-static/resources/view/adguardhome/dashboard.js
cp "$DOWNLOAD_DIR/luci/i18n/adguardhome.lmo"                           /usr/lib/lua/luci/i18n/
cp "$DOWNLOAD_DIR/luci/i18n/adguardhome.zh-cn.lmo"                     /usr/lib/lua/luci/i18n/
cp "$DOWNLOAD_DIR/manifest.json"                                       /usr/share/adguardhome-dashboard/manifest.json

# ── 设置权限 ──────────────────────────────────────── / Set permissions
chmod 644 /usr/lib/lua/luci/controller/adguardhome.lua \
          /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json \
          /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json \
          /usr/lib/lua/luci/i18n/adguardhome.lmo \
          /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo \
          /usr/share/adguardhome-dashboard/manifest.json \
          /www/luci-static/resources/view/adguardhome/dashboard.js

# ── 清除缓存 & 重启服务 ──────────────────────────── / Clear cache & restart services
log "清除 LuCI 缓存并重启服务..."
rm -rf /tmp/luci-* 2>/dev/null || true
rm -rf /tmp/luci-indexcache.* /tmp/luci-modulecache.* 2>/dev/null || true
find /tmp -name '*.luac' -delete 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

# ── 部署验证 ──────────────────────────────────────── / Deployment verification
log "验证部署文件..."
if grep -q 'loadc' /usr/lib/lua/luci/controller/adguardhome.lua 2>/dev/null; then
    log "⚠ 警告: controller.lua 仍包含旧代码 (i18n.loadc)"
    log "  可能是 GitHub CDN 缓存未刷新，请尝试以下方法:"
    log "  1) 等待几分钟后重新运行安装"
    log "  2) 使用代理: GITHUB_PROXY=https://ghfast.top/ sh install.sh"
    log "  3) 手动验证: curl -fsSL '${RAW_BASE}/files/luci/controller/adguardhome.lua' | grep loadc"
else
    log "  ✓ controller.lua 验证通过"
fi
if grep -q 'fetchBackups' /www/luci-static/resources/view/adguardhome/dashboard.js 2>/dev/null; then
    log "  ✓ dashboard.js 验证通过（含备份管理）"
else
    log "⚠ 警告: dashboard.js 缺少备份管理功能（可能是代理缓存的旧版本）"
    log "  手动重拉: curl -fsSL '${RAW_BASE}/files/view/dashboard.js' -o /www/luci-static/resources/view/adguardhome/dashboard.js"
fi
if [ -f /usr/share/adguardhome-dashboard/manifest.json ] && grep -q '"version"' /usr/share/adguardhome-dashboard/manifest.json 2>/dev/null; then
    log "  ✓ manifest.json 验证通过"
else
    log "⚠ 警告: manifest.json 未部署或缺少 version 字段"
fi

rm -rf "$TMPDIR"

echo ""
echo "========================================================="
echo " 安装完成！"
echo ""
echo " AdGuard Home 核心:"
[ -f "$AGH_BIN" ] && echo "   ✓ $AGH_BIN" || echo "   ✗ 未安装"
echo ""
echo " LuCI Dashboard:"
echo "   Controller:  /usr/lib/lua/luci/controller/adguardhome.lua"
echo "   Menu:        /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json"
echo "   ACL:         /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json"
echo "   JS View:     /www/luci-static/resources/view/adguardhome/dashboard.js"
echo "   i18n (en):   /usr/lib/lua/luci/i18n/adguardhome.lmo"
echo "   i18n (zh):   /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo"
echo ""
if [ "$_backup_count" -gt 0 ] 2>/dev/null; then
    echo " 备份信息:"
    echo "   备份目录:   $BACKUP_DIR"
    echo "   备份文件数: $_backup_count"
    echo "   恢复脚本:   $BACKUP_DIR/restore.sh"
    echo ""
    echo "   恢复到安装前状态:"
    echo "     sh $BACKUP_DIR/restore.sh"
    echo ""
    echo "   或在面板 → 服务 → AdGuard Home → 备份管理 中操作"
fi
echo ""
echo " 请刷新浏览器 → LuCI → 服务 → AdGuard Home"
echo "========================================================="
