# AdGuardHome LuCI Dashboard

**LuCI 2.0 标准 AdGuard Home 管理面板** | **LuCI 2.0 AdGuard Home Dashboard**
**v2.3.0**

为 OpenWrt / ImmortalWrt / iStoreOS 提供完整的 AdGuard Home 管理面板。

---

## 安装 / Install

### 一键安装（推荐）

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh)"
```

安装脚本分两步执行：

1. **AdGuard Home 核心** — 检测 `/opt/AdGuardHome/AdGuardHome` 是否已安装，未安装则调用官方脚本自动安装；已安装则可选择覆盖安装（自动停止运行中的服务）或跳过
2. **LuCI Dashboard** — 从 GitHub 下载菜单注册、Lua Controller、JS View、翻译等文件及 `checksums.sha256` 到临时目录，先做 **sha256 内容指纹校验**（命中代理缓存旧版立即中止并提示换代理），再部署到系统对应位置

> install.sh 在覆盖前会自动把现有的 6 个面板文件备份到 `/root/agh_backup_install_<ts>/`，并在备份目录内生成 `restore.sh`。万一安装失败或想回滚到旧版面板，执行 `sh /root/agh_backup_install_<ts>/restore.sh` 即可（仅恢复面板文件，不动 AGH 核心二进制）。

### 国内加速 / Proxy

脚本启动时自动检测 GitHub 连通性，直连失败会逐个测试代理节点并显示延迟，选择可用的即可：

```
  #   代理节点          状态
  ─────────────────────────────
  1)  直连              ✗ 不可用
  2)  ghfast.top        ✓ 320ms
  3)  gh-proxy.com      ✓ 450ms
  4)  kkgithub.com      ✗ 超时
```

也可通过环境变量直接指定代理（跳过检测）：

```sh
GITHUB_PROXY=https://ghfast.top/ sh -c "$(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh)"
```

> 注意：`curl` 下载脚本本身的 URL 也需要经过代理，如上面示例中 `curl` 的 URL 已加了 `ghfast.top/` 前缀。

### 从本地项目安装

如果已将项目克隆到路由器，在项目目录内运行会自动使用本地文件（无需联网下载）：

```sh
cd /path/to/luci-app-adguardhome-dashboard
sh scripts/install.sh
```

> `install.sh` 支持安装和更新（幂等），自动清理旧版本文件。

## 卸载 / Uninstall

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/uninstall.sh)"
```

---

## 特性 / Features

- **LuCI 2.0 标准架构**：menu.json 注册菜单 + JS View 生命周期管理，非模板渲染
- **后端 RPC**：Lua Controller 提供 13 个 API 端点，无 ACL 越权
- **实时状态监控**：5 秒自动轮询，实时更新版本/运行状态/PID/端口/代理设置/面板版本
- **服务控制台**：启动/停止/重启/注册系统服务，支持 init.d 和二进制双模式
- **混合日志查看器**：分层追加模式，顶部为执行/升级日志（EXEC_LOG），下方追加 AGH 原生日志或系统 logread 的最新 50/100 行；支持手动刷新、升级时 2 秒自动轮询、可选的自动刷新开关（3 秒间隔）、一键清空中间层日志
- **核心版本管理**：检查更新 + 一键升级 + 强制重装，升级进度 2 秒快速轮询实时滚动
- **全局代理选择**：内置 4 候选（直连 / ghfast.top / gh-proxy.com / kkgithub.com）+ 自定义输入，点选模式立即持久化到 `/etc/adguardhome-dashboard.proxy`
- **代理延迟测试**：单点测试 / 批量测试所有候选，测试目标与实际下载域名一致（`raw.githubusercontent.com`），先持久化再测试
- **面板自升级**：检查面板版本（读 `manifest.json`） → 一键升级（在线下载 6 个面板文件覆盖本地），无需手动上传
- **两阶段提交 + 自动回滚**：核心升级和面板升级都采用「下载到临时目录 + 完整性校验 → 备份 + 原子 mv 覆盖」模式，任一步骤失败自动从备份还原已部署文件
- **完整性校验（双重防线）**：① 类型校验 lmo magic `LMO\0` / lua 含 `function` / js 含 `view.extend` / po 含 `msgid`，防止空文件 / 404 HTML / 截断；② **sha256 内容指纹**：install 与面板升级都先下载 `checksums.sha256`，对 6 个面板文件逐一比对 sha256，任何与发布清单不一致的内容（尤其是代理/CDN 缓存的旧版本）都会被拦截并中止升级，避免装上残缺面板
- **备份管理**：列出 `/root/agh_backup_*` 所有备份目录（install/core/dashboard 三类），显示类型/时间戳/文件数/大小/含核心/含 restore.sh；支持一键恢复（仅 install/dashboard 类备份有 restore.sh）、显示恢复命令、删除备份释放空间
- **install 自带备份**：install.sh 部署前自动备份现有 6 个面板文件 + 生成 restore.sh，与面板升级的备份机制完全一致
- **国际化支持**：中英文自动切换，基于 LuCI 系统语言设置（124 条翻译）
- **跨平台**：OpenWrt / ImmortalWrt / iStoreOS

---

## 项目结构 / Structure

```text
luci-app-adguardhome-dashboard/
├── scripts/
│   ├── install.sh        # 安装/更新脚本（Part1: AGH核心 Part2: Dashboard文件 + 自动备份 + 生成 restore.sh）
│   └── uninstall.sh      # 卸载脚本
├── files/
│   ├── luci/
│   │   ├── menu.d/
│   │   │   └── luci-app-adguardhome-dashboard.json  # LuCI 2.0 菜单注册
│   │   ├── acl.json      # rpcd 访问控制权限
│   │   ├── controller/
│   │   │   └── adguardhome.lua  # 后端 Lua Controller (13 个 API 端点)
│   │   └── i18n/
│   │       ├── adguardhome.po       # 英文翻译源文件
│   │       ├── adguardhome.zh-cn.po # 中文翻译源文件
│   │       ├── adguardhome.lmo      # 英文编译翻译（LuCI 二进制格式）
│   │       └── adguardhome.zh-cn.lmo# 中文编译翻译
│   └── view/
│       └── dashboard.js  # LuCI 2.0 JS View (view.extend)
├── tools/
│   └── po2lmo.py         # .po → .lmo 编译工具（开发用，不部署到路由器）
├── checksums.sha256      # 发布用 sha256 清单（install / 面板升级的内容指纹来源）
├── manifest.json         # 包清单（面板自升级版本号来源）
└── README.md             # 项目说明
```

> 路由器本地临时部署包 `changes_package/` 不上传 GitHub（已在 `.gitignore` 屏蔽），仅供手动 scp 到路由器配合 `deploy_atomic.sh` 使用；正式发布后走面板内「检查面板更新 → 升级面板」在线完成。
>
> `changes_package/` 是开发机上 `files/` 目录 6 个部署源（lua/js/2×po/2×lmo）的**精确镜像**，与 `files/` 下文件逐字节一致，任何修改 `files/` 之后必须同步到 `changes_package/` 再上传路由器部署，否则路由器拿到的是旧版本。

---

## API 接口 / API Endpoints

| 路径 | 方法 | 功能 |
|------|------|------|
| `/admin/services/adguardhome/status` | GET | 获取状态（版本/运行/PID/端口/路径/代理/面板版本） |
| `/admin/services/adguardhome/action` | POST | 执行操作（start/stop/restart/install_service/install_core） |
| `/admin/services/adguardhome/set_proxy` | POST | 立即持久化代理到 `/etc/adguardhome-dashboard.proxy` |
| `/admin/services/adguardhome/proxy_test` | POST | 测试代理延迟（目标：`raw.githubusercontent.com`） |
| `/admin/services/adguardhome/check_update` | POST | 检查 AGH 核心 GitHub 最新版本（用持久化代理） |
| `/admin/services/adguardhome/upgrade` | POST | 启动 AGH 核心升级（force=0 用 `--update` / force=1 用安装脚本 `-r`） |
| `/admin/services/adguardhome/check_dashboard_update` | GET | 检查面板自身最新版本（读 GitHub `manifest.json`） |
| `/admin/services/adguardhome/upgrade_dashboard` | POST | 启动面板自升级（在线下载 6 个文件覆盖本地） |
| `/admin/services/adguardhome/log` | GET | 获取混合日志（顶部 EXEC_LOG + 下部 AGH 原生/logread + 头部摘要） |
| `/admin/services/adguardhome/clear_log` | POST | 清空中间层执行/升级日志（EXEC_LOG） |
| `/admin/services/adguardhome/backups` | GET | 列出 `/root/agh_backup_*` 所有备份目录 |
| `/admin/services/adguardhome/restore_backup` | POST | 从指定备份恢复（执行 `<dir>/restore.sh`） |
| `/admin/services/adguardhome/delete_backup` | POST | 删除指定备份目录 |

---

## 升级流程 / Upgrade Flow

### AGH 核心升级（两阶段提交 + 自动回滚）

```
阶段1: 备份当前二进制 → /root/agh_backup_core_<ts>/AdGuardHome
阶段2: 执行升级
       ├─ force=1: 多代理下载 install.sh → 停服 → sh install.sh -r
       ├─ force=0 + 有二进制: AdGuardHome --update
       └─ 无二进制: 多代理下载 install.sh → sh install.sh
阶段3: 完整性校验（新二进制存在 + 可执行 + 能输出版本）
阶段4: 校验失败 → 从备份恢复旧二进制 + 重启服务 → 写 FAILED 标记
阶段5: 重启服务 → 写 done 标记
```

### 面板自升级（两阶段提交 + 自动回滚）

```
阶段1: 6 个文件全部下载到 /tmp/agh_dash_new_<ts>/ + 完整性校验
       ├─ 先下载 checksums.sha256（内容指纹清单，来自 GitHub main）
       ├─ 每个文件 sha256 比对（与发布清单一致才放行；代理缓存旧版会被直接拦下）
       ├─ lmo: 校验尾字节 magic 4c4d6f00 (LMO\0)
       ├─ lua: 校验含 'function' + 'list_backups'
       ├─ js:  校验含 'view.extend' + 'fetchBackups'
       └─ po:  校验含 'msgid'
       任一失败 → 写 FAILED 标记 + 自动回滚 → 不动任何目标文件
阶段2: 逐文件备份 + mv 原子覆盖
       任一失败 → 从 /root/agh_backup_dashboard_<ts>/ 还原已部署的 → 写 FAILED 标记
阶段2.5: 在备份目录生成 restore.sh（与 install.sh restore 逻辑一致，恢复 6 个面板文件）
阶段3: 清 LuCI 缓存 + 重启 rpcd/uhttpd → 写 done 标记
```

---

## 代理缓存与内容指纹校验 / Proxy Cache & Content Fingerprint

GitHub 镜像/CDN（如 `ghfast.top`、`gh-proxy.com`）会对 `raw.githubusercontent.com` 的内容做缓存，且往往忽略 `?_cb=` 时间戳参数。如果缓存里是**更早、缺少某些功能的旧版本**，安装/升级会静默装上残缺面板（本项目曾因此导致「备份管理」与「清空日志」按钮不显示）。

为彻底防住这类问题，install 与面板升级都采用 **双重校验**：

1. **sha256 内容指纹（主防线）**：先从 GitHub main 下载 `checksums.sha256`（记录 6 个面板文件的 sha256），再对下载到的每个文件逐一比对 sha256。任何与发布清单不一致的内容（含代理缓存旧版、截断、被替换）都会**立即中止并提示换代理**，不会装上残缺面板。
2. **语义特征（兜底防线）**：当 `checksums.sha256` 因网络等原因不可用时，降级为关键字校验 —— `dashboard.js` 必须含 `fetchBackups`、`adguardhome.lua` 必须含 `list_backups`。

### 本地验证已部署面板是否为最新版

```sh
# 路由器上：面板 JS 是否含备份管理（返回 >0 即正常）
grep -c fetchBackups /www/luci-static/resources/view/adguardhome/dashboard.js

# 仓库内：用发布清单校验本地文件（全部 OK 即与发布一致）
sha256sum -c checksums.sha256
```

### 安装/升级时命中旧版本怎么办

安装日志会出现 `sha256 不匹配` / `内容校验失败`，并提示更换代理：

```sh
# 换用其它代理后重跑
GITHUB_PROXY=https://kkgithub.com/ sh -c "$(curl -fsSL https://kkgithub.com/https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh)"
# 或直接直连 raw.githubusercontent.com（绕过镜像缓存）
curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/files/view/dashboard.js -o /www/luci-static/resources/view/adguardhome/dashboard.js
```

---

## 备份与恢复 / Backup & Restore

### 三类备份目录

| 类型 | 产生时机 | 路径 | 含 restore.sh | 恢复内容 |
|------|------|------|:---:|------|
| install | 安装/更新面板 | `/root/agh_backup_install_<ts>` | ✓ | 6 个面板文件（不动 AGH 核心） |
| dashboard | 面板自升级 | `/root/agh_backup_dashboard_<ts>` | ✓ | 6 个面板文件（不动 AGH 核心） |
| core | AGH 核心升级 | `/root/agh_backup_core_<ts>` | ✗ | 仅含旧二进制（手动 `cp` 恢复） |

### 恢复方式

**面板内**：进入 LuCI → 服务 → AdGuard Home → 备份管理 → 找到对应备份 → 点击「恢复」或「命令」

**命令行**：
```sh
# install / dashboard 类备份
sh /root/agh_backup_install_<ts>/restore.sh
sh /root/agh_backup_dashboard_<ts>/restore.sh

# core 类备份（手动）
/etc/init.d/AdGuardHome stop 2>/dev/null || /etc/init.d/adguardhome stop 2>/dev/null
cp /root/agh_backup_core_<ts>/AdGuardHome /opt/AdGuardHome/AdGuardHome
chmod 755 /opt/AdGuardHome/AdGuardHome
/etc/init.d/AdGuardHome start 2>/dev/null || /etc/init.d/adguardhome start 2>/dev/null
```

> 清理备份：在面板「备份管理」点击「删除」，或手动 `rm -rf /root/agh_backup_*`

---

## 混合日志 / Layered Log

```
┌─────────────────────────────────────────┐
│ === AdGuardHome 状态 ===                │  ← 头部摘要
│ AdGuard Home v0.107.52                  │
│ PID: 1234 (running)                     │
│ ========================...             │
│                                         │
│ === 执行/升级日志 ===                    │  ← 中间层 EXEC_LOG
│ [升级/启动/停止动作的输出]                │
│                                         │
│ === 系统/运行日志 (最新) ===             │  ← 运行日志层
│ [AGH 原生日志 tail -n 100]              │
│ 或 [logread -e AdGuardHome tail -n 50]  │
└─────────────────────────────────────────┘
```

**操作**：
- 「刷新日志」按钮：覆盖重刷最新内容，自动滚到底
- 「清空日志」按钮：清空 EXEC_LOG（运行日志由 AGH/系统管理，不受影响）
- 「自动刷新」开关：3 秒间隔自动拉取（升级进行中时让位给升级轮询，避免冲突）

---

## 系统要求 / Requirements

- OpenWrt / ImmortalWrt / iStoreOS
- LuCI 2.0（OpenWrt 21.02+）
- curl（大多数固件已内置）
- 至少 8MB 剩余空间

---

## 注意事项 / Notes

- 安装完成后，在 LuCI → **服务** → **AdGuard Home** 进入仪表盘
- 代理持久化文件：`/etc/adguardhome-dashboard.proxy`
- 执行/升级日志：`/tmp/agh_exec.log`（EXEC_LOG，含 `done` / `FAILED` 标记供前端轮询判定结果）
- 安装日志：`/etc/adguardhome-dashboard.log`
- 备份目录：`/root/agh_backup_{install,core,dashboard}_<ts>`（按时间戳保留，可在面板「备份管理」清理）

---

## 架构 / Architecture

```
浏览器 JS View  ──HTTP──▸  Lua Controller  ──exec──▸  系统命令
(view.extend)              (util.exec)               (pgrep/init.d/binary)
     │                          │
     │ 5s 轮询 status           │ 读取持久化代理
     │ 2s 轮询 log (升级时)     │ 调用 GitHub raw / API
     │ 3s 轮询 log (自动刷新)   │ 写 EXEC_LOG / 备份目录
     └──────────────────────────┘
```

---

## 开发 / Development

### 修改翻译

```sh
# 编辑 .po 后重新编译 .lmo
python3 tools/po2lmo.py files/luci/i18n/adguardhome.po files/luci/i18n/adguardhome.lmo
python3 tools/po2lmo.py files/luci/i18n/adguardhome.zh-cn.po files/luci/i18n/adguardhome.zh-cn.lmo
```

### 发布新版本

1. 修改 `files/` 下的源文件
2. 重新编译 `.po` → `.lmo`
3. **重新生成内容指纹清单**（任何对 `files/` 下文件的改动都必须执行，否则 install/面板升级会判定 sha256 不匹配而中止）：
   ```sh
   sha256sum files/luci/controller/adguardhome.lua \
             files/luci/menu.d/luci-app-adguardhome-dashboard.json \
             files/luci/acl.json \
             files/view/dashboard.js \
             files/luci/i18n/adguardhome.lmo \
             files/luci/i18n/adguardhome.zh-cn.lmo \
             files/luci/i18n/adguardhome.po \
             files/luci/i18n/adguardhome.zh-cn.po > checksums.sha256
   ```
4. 在 `manifest.json` 中按语义化版本 bump `version` 字段（同时核对 `adguardhome.lua` 中 `DASHBOARD_VERSION` 常量保持一致）
5. `git add files/ checksums.sha256 manifest.json && git commit -m "bump dashboard to x.y.z" && git push origin main`

推到 main 后，所有路由器上点「检查面板更新」即可看到新版本并在线升级。

---

**MIT License** | 轻量 · 稳定 · 标准 LuCI 2.0
