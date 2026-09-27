#!/usr/bin/env bash
# =====================================================================
# 等保三级基线加固 - 一键构建镜像并在 Docker 内执行 Ansible
# 用法：
#   bash run.sh                        # 执行全部基线项
#   bash run.sh --tags password_policy # 只执行口令策略（可选: login_lock/ssh_hardening/audit_log/verify）
#   bash run.sh --list-hosts           # 查看目标主机清单
#   bash run.sh --check --diff         # 演练模式（不改动机）
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

echo "==> 构建 Ansible 容器镜像..."
docker compose build

if [ $# -eq 0 ]; then
  exec docker compose run --rm ansible
else
  exec docker compose run --rm ansible -i inventory/hosts.yml playbooks/site.yml "$@"
fi
