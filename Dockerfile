# =====================================================================
# 等保三级安全基线加固 - Ansible 控制端容器
# 用法：docker compose build && docker compose run --rm ansible
# =====================================================================
FROM python:3.12-alpine

# openssh-client: ssh/scp; sshpass: 密码认证方式; rsync: 传输优化
RUN apk add --no-cache openssh-client sshpass rsync \
 && pip install --no-cache-dir "ansible-core>=2.16,<2.19"

WORKDIR /ansible

# 默认执行主 playbook（run.sh 可传参覆盖）
ENTRYPOINT ["ansible-playbook"]
CMD ["-i", "inventory/hosts.yml", "playbooks/site.yml"]
