# 等保三级安全基线加固（Docker + Ansible）

基于 **Docker 容器内运行的 Ansible** 对 Linux 服务器批量实施等保三级（MLPS 三级）安全基线加固，全部任务幂等，可重复执行。

## 加固项

| # | 加固项 | 实现内容 |
|---|--------|----------|
| 1 | 口令策略 | 每 **90 天**定期更换口令（`login.defs` + `chage` 对存量账户生效）；口令长度 **不小于 8 位**，至少包含 **数字/大写字母/小写字母/特殊符号中的 3 类**（`pam_pwquality`） |
| 2 | 登录锁定与超时 | 登录失败 **5 次**锁定 **10 分钟**（`pam_faillock`/`pam_tally2`，root 同样锁定）；登录后 **10 分钟**无操作自动退出（`TMOUT`） |
| 3 | SSH 加固 | **禁用 root 直接 SSH 登录**（`PermitRootLogin no`）；**SSH 端口改为 2222**（可配置），自动处理 firewalld/ufw/SELinux 放行 |
| 4 | 审计日志 | 启用 **auditd** 审计服务并设开机自启；部署等保审计规则（身份鉴别文件、登录会话、SSH 配置、系统时间、主机名/网络配置变更）；日志自动轮转（单文件 30MB、保留 10 份） |

## 适配操作系统

| 系统 | 版本 | 登录锁定实现 |
|------|------|--------------|
| OpenEuler | 20.03 / 22.03 / 24.03 | authselect + pam_faillock |
| Anolis OS | 8 / 23（7 走 tally2） | authselect + pam_faillock |
| Rocky Linux | 8 / 9 | authselect + pam_faillock |
| CentOS | 8 / 9（7 走 tally2） | authselect + pam_faillock |
| Ubuntu | 22.04 / 24.04（20.04 走 tally2） | pam_faillock |
| Kylin V10（银河麒麟） | V10 SP1/SP2/SP3 | authselect + pam_faillock |

> 角色按 `os_family` + 主版本号 + `authselect` 是否存在自动选择实现方式，无需手工分组；Kylin V10 的非数字版本号（"V10"）会自动规范化为 10 再参与版本比较。

## 目录结构

```
dengbao3-ansible/
├── Dockerfile                  # Ansible 控制端镜像（python:3.12-alpine + ansible-core）
├── docker-compose.yml          # host 网络直连目标机，挂载项目与 ~/.ssh 密钥
├── run.sh                      # 一键构建 + 运行
├── ansible.cfg                 # accept-new 主机指纹策略，known_hosts 持久化于 .known_hosts
├── inventory/
│   ├── hosts.yml               # 目标主机清单（按 OS 分组示例）
│   └── group_vars/all.yml      # 全部加固参数（天数/次数/端口等，可调）
├── playbooks/
│   └── site.yml                # 主 playbook（安全预检 + 四个角色 + 新端口验证）
└── roles/
    ├── password_policy/        # 任务1：口令复杂度 + 90 天定期更换
    ├── login_lock/             # 任务2：失败锁定 + 会话超时
    ├── ssh_hardening/          # 任务3：禁 root 登录 + 改 SSH 端口
    └── audit_log/              # 任务4：auditd 审计日志 + 保留策略
```

## 快速开始

1. **目标机准备**：创建普通运维用户并授予 sudo 权限（禁止直接用 root，playbook 有预检会拦截）：

   ```bash
   # RHEL 系（OpenEuler/Anolis/Rocky/CentOS）
   useradd -m -G wheel opsadmin && passwd opsadmin
   # Ubuntu
   useradd -m -G sudo opsadmin && passwd opsadmin
   ```

2. **宿主机准备**：生成 SSH 密钥并分发到目标机（或改用密码方式）：

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
   ssh-copy-id -i ~/.ssh/id_ed25519.pub opsadmin@<目标机IP>
   ```

3. **编辑清单**：修改 `inventory/hosts.yml`，填入目标机 IP、`ansible_user`、密钥路径。

4. **执行**：

   ```bash
   cd /opt/dengbao3-ansible
   bash run.sh                 # 执行全部基线项
   ```

## 常用命令

```bash
bash run.sh --check --diff            # 演练模式，只看变更不落地
bash run.sh --tags password_policy    # 只执行口令策略
bash run.sh --tags login_lock         # 只执行登录锁定/会话超时
bash run.sh --tags ssh_hardening      # 只执行 SSH 加固
bash run.sh --tags audit_log          # 只执行审计日志
bash run.sh --list-hosts              # 查看目标主机
docker compose run --rm ansible -m ansible.builtin.setup -a 'filter=ansible_distribution*' all   # 采集目标系统信息
```

## 参数说明（inventory/group_vars/all.yml）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `pass_max_days` | 90 | 口令最长有效期（天） |
| `pass_min_days` | 1 | 两次修改口令最小间隔（天） |
| `pw_minlen` | 8 | 口令最小长度 |
| `pw_minclass` | 3 | 至少 3 类字符（大写/小写/数字/特殊符号） |
| `login_fail_deny` | 5 | 登录失败次数阈值 |
| `login_fail_unlock_time` | 600 | 锁定时长（秒，600=10 分钟） |
| `tmout_seconds` | 600 | 无操作自动退出时长（秒） |
| `ssh_new_port` | 2222 | 修改后的 SSH 端口 |
| `ssh_permit_root_login` | no | 是否允许 root SSH 直接登录 |
| `apply_chage_to_existing_users` | true | 是否对存量可登录账户立即应用 90 天有效期 |
| `audit_max_log_file` | 30 | 单个审计日志文件上限（MB） |
| `audit_num_logs` | 10 | 审计日志轮转保留数量 |
| `audit_buffer_size` | 8192 | 审计规则缓冲区大小 |
| `audit_rules_immutable` | false | true 时审计规则设为不可变（`-e 2`，重启后生效） |

## 注意事项

- **防失联预检**：当 `ssh_permit_root_login=no` 时，若检测到用 root 连接目标机，playbook 会直接 `fail` 并提示先创建运维用户。
- **改端口顺序**：先放行防火墙/SELinux 新端口，再改 `sshd_config` 并 `sshd -t` 校验后重启，避免失联；重启 sshd **不会中断当前已建立的连接**。
- **Ubuntu 22.10+ socket 激活**：新版 Ubuntu/Debian 的 SSH 端口由 `ssh.socket` 决定（sshd_config 的 Port 不生效），playbook 会自动检测并切换为标准 sshd 守护进程监听。
- **PAM 安全防护**：写入 pam_faillock/pam_tally2 前均校验模块文件存在，authfail 行严格置于 pam_unix 之后（成功短路、失败才记录），Ubuntu 侧同步调整 pam_unix 的 success 跳过计数并校验，防止错误 PAM 顺序导致无法登录。
- **容器环境下的审计**：容器/嵌套虚拟化环境中内核审计 netlink 常被宿主占用（EPERM），auditd 无法真正运行；角色会通过 `auditctl -s` 自动检测，不可用时部署全部配置与规则文件、跳过启动并输出警告（真实物理机/虚拟机上正常严格启动，启动失败即中止）。
- **二次执行**：加固完成后，请把 `inventory/hosts.yml` 中 `ansible_port: 2222` 取消注释（与 `ssh_new_port` 一致）。
- **会话超时**：`TMOUT` 对交互式 bash/sh 会话生效（等保基线标准做法）。
- **幂等**：所有任务可重复执行，仅调整不符合项；`--check --diff` 可先预览。

## 实测验证矩阵

| 目标环境 | 登录锁定实现 | 验证结果 |
|----------|--------------|----------|
| Rocky Linux 9（authselect 管理标准安装） | authselect with-faillock + faillock.conf | 加固/锁定/幂等 全部通过 |
| Rocky Linux 9（最小化无 authselect） | 直接写入 pam_faillock（preauth+authfail 正确顺序） | 加固/锁定/幂等 全部通过 |
| Ubuntu 24.04（含 ssh.socket 场景） | pam_faillock（success 计数自适应调整） | 加固/锁定/幂等 全部通过 |
| Rocky Linux 9（全新容器 + 四角色全量） | authselect with-faillock + auditd 审计 | 首跑成功 changed=13；审计规则/保留策略部署、二次运行 changed=0 |

> 锁定功能实测：正确密码可登录 → 连续 5 次错误密码 → 账户锁定、正确密码被拒 → `faillock --user <用户> --reset` 解锁。

## 验证加固效果（可选）

```bash
# 口令策略
grep -E 'PASS_(MAX|MIN|WARN)' /etc/login.defs
grep -E 'minlen|minclass' /etc/security/pwquality.conf
chage -l opsadmin

# 登录锁定 / 会话超时
grep -E 'deny|unlock_time' /etc/security/faillock.conf 2>/dev/null || grep pam_tally2 /etc/pam.d/common-auth
cat /etc/profile.d/00-tmout.sh

# SSH
ss -tlnp | grep sshd
sshd -T | grep -E 'port|permitrootlogin'

# 审计日志
systemctl is-active auditd && systemctl is-enabled auditd
auditctl -l                       # 查看已加载的审计规则
auditctl -s                       # 审计子系统状态（含丢失事件数）
grep -E 'max_log_file|num_logs' /etc/audit/auditd.conf
ausearch -k identity --start today   # 查询今日身份/账户变更事件
aureport --login                    # 登录事件汇总报表
```
