# 项目长期约定 (luci-app-adguardhome-dashboard)

## changes_package/ 的定位（重要）
- **用途**：本地手动上传到路由器做测试用的部署包，**不进 GitHub 项目**（已被 .gitignore 屏蔽）。
- **一致性要求**：其内可部署文件（adguardhome.lua、dashboard.js、*.lmo、*.po、deploy_atomic.sh）必须与 `files/` 主文件保持**字节一致**，才能确保手动上传测的是同一份代码。
- **发布路径以 `files/` + `scripts/install.sh` 为准**：install.sh 从 GitHub `main` 拉 `files/` 下的源文件部署；面板自升级（do_upgrade_dashboard）同理。
- 已建立的习惯：改 `files/` 后，同步 cp 到 `changes_package/` 对应文件，再用 `diff -q` 确认一致。

## 内容指纹校验（防代理/CDN 旧缓存）
- 发布物带根目录 `checksums.sha256`（8 个发布文件的 sha256，key 为 `files/<relpath>`）。
- install.sh 与面板升级（do_upgrade_dashboard，两份 lua）均：`checksums.sha256` 比对（主） + 语义兜底（`fetchBackups`/`list_backups`）；不一致即中止并提示换代理。
- **发布步骤必须重算 `checksums.sha256`**（任何 `files/` 改动后），否则校验会把正确文件判为不匹配。

## 已知已修复的遗留 bug（待 push 后生效）
- `restore_backup` 曾用未定义的 `UPGRADE_LOG` → 改为 `EXEC_LOG`（与前端 `startLogPolling` 完成判定对齐）。
- `_themeStyles()` 缺少 `mutedColor`（已补：深色 rgba(255,255,255,0.55) / 浅色 #888）。
