# Change Summary / 变更说明

Date: 2026-08-24
Author: Automated patch prepared in workspace

## Overview / 概述
This patch improves the AdGuard Home LuCI dashboard upgrade workflow and adds a global proxy/accelerator option with latency testing.

主要改动：
- 将安装脚本调用抽成通用函数 `run_install_script(flags)`。
- `install_core` 默认不再强制覆盖安装（不再默认传 `-r`）；强制重装（force）路径仅在需要时传 `-r`。
- 非强制升级（Upgrade）会优先调用本地二进制的 `--update`（若存在），否则回退到调用安装脚本（不带 `-r`）。
- 新增全局代理/加速器选择控件（内置列表 + 自定义），并在 UI 中提供 latency 测试（后端 `proxy_test` 接口）。
- 统一由 UI 的代理选择决定 `check_update`、`upgrade`、`force reinstall`、`install core` 的网络路径；弹窗仅做确认与说明，不在弹窗重复多选项。
- 后端会持久化用户选定代理到 `/etc/adguardhome-dashboard.proxy`，并在请求中优先使用（可被 UI 覆盖）。

Files changed / 修改文件：
- files/luci/controller/adguardhome.lua
- files/view/dashboard.js

Rationale / 设计理由：
- 按产品要求将 "-r"（重装标志）仅在强制重装路径使用，保留 `install_core` 和普通升级为通用流程，避免非必要覆盖或交互输出写入日志。
- 提供全局代理选择以统一各个操作的网络通道，提高可控性并支持延迟测试以选择最快的代理节点。

Compatibility / 兼容性说明：
- The controller adds a new API endpoint `/admin/services/adguardhome/proxy_test` used by the UI to test proxy latency.
- Ensure the router has `curl` available for the new `proxy_test` and installer calls.

Backup recommendations / 备份建议：
- Always backup `/opt/AdGuardHome` and configuration files before performing a force reinstall.
- The package includes helper scripts to backup current files.


---

If you want a single unified patch file ready for `git apply`, request "generate unified diff" and I will prepare it.