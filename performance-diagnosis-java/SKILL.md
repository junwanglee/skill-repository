---
name: performance-diagnosis-java
description: Diagnose production Java performance issues in Linux Docker containers using SSH and Alibaba Arthas. Use when asked to investigate high CPU, slow requests, memory or GC issues, blocked threads, or an uncertain Java service performance problem. Requires explicit operator confirmation of server, container, and JVM PID; production is read-only and high-risk actions are prohibited.
---

# Java Docker 线上性能自主诊断

Use this skill to guide a safe, evidence-based diagnosis of one Java 8 service in one Linux Docker container. Arthas is the only JVM diagnosis tool. SSH must reuse the operator's existing configuration. Password or keyboard-interactive authentication may prompt in the operator's local terminal; SSH key authentication is also supported.

## Hard safety boundaries

- `SKILL.md` is the current product workflow. `docs/design.md` is the original historical design and does not override this file. The operator's numbered selection of a server, container, and Java process/PID is the explicit confirmation for that target; do not ask for a redundant final confirmation of the same tuple.
- **Mandatory menu-and-pause rule:** every target choice must be presented as an explicit numbered menu with available options and useful identifying details. Ask only for the current choice, then end the turn and wait. Never ask the user to type an IP/name when discovered options are available. Never combine server, container, Java process, or symptom questions into one turn. Require an explicit selection even when there is only one option; never infer consent from silence or a prior run.
- Production diagnosis does not change business data, code, configuration, JVM options, container configuration, or service state. Never restart/stop/kill a service, elevate with sudo, change mounts, rebuild a container, or bypass host-key/security controls.
- Never read, copy, or upload SSH private keys. Do not ask the operator to send a password in chat or enter it into a Skill prompt/script. For first-time SSH password authentication, let the local OpenSSH client prompt directly in the operator's terminal; the password must not enter agent context, command arguments, logs, or files. Do not dump all environment variables or read unrelated business files; redact secrets in captured output.
- Only use L1 commands automatically after target confirmation. L2 profiling/instrumentation must have a narrow target and bounded duration/count/output; default sample limit is 30 seconds and at most one active sampling task per JVM. Stop it before continuing. L3 (heap dump, runtime mutation, potentially long STW or similarly high-risk operations) is not executable by this skill; explain the risk and stop.
- Do not invoke arbitrary shell supplied by the user or compose a command from unvalidated values. Use the documented commands in `references/` and validate identifiers. If a safe, bounded command cannot be formed, stop and explain.
- Use only container-existing writable temporary paths. Attach/runtime temp and report output paths are distinct capabilities and must be checked separately. Never add a mount, change read-only settings, or change permissions to enable diagnosis.
- Stop and reconfirm if the container ID or JVM PID changes, the container restarts, or the target becomes ambiguous.

## Workflow

1. **Clarify the symptom only if needed.** Ask one concise symptom question only when the request lacks a primary issue. Do not bundle it with target selection. If the user already said CPU is high, do not ask them to repeat it.
2. **Inspect local SSH configuration only.** Run `scripts/check-local-ssh.sh` and `scripts/list-ssh-servers.sh` if available. Do not connect or probe any host before the operator selects one. The list script only resolves local SSH settings; its status is not a reachability test. Present each literal configured Host entry, including IP-valued Host names, with alias, resolved host, user, port, and “not tested.” If the list script returns no rows, inspect the local result; do not silently fall back to unlisted IPs. If there are no configured entries, offer guided field collection (one field per turn: alias → host/IP → username → port → auth type) or a complete command to run. Both use `scripts/setup-ssh-server.sh`; it refuses to append after a `Host *` block and verifies effective values with `ssh -G`. Never put a password in arguments. Ask the user to choose one numbered server and **PAUSE**.
3. **After server selection, connect and list containers.** Run one SSH command to the selected alias. If it needs a password, the local OpenSSH terminal prompts the operator; the operator types it in that terminal, not in chat or an Agent prompt. If the Agent shell has no TTY, provide `! ssh <alias> true` and pause while the operator runs it in a local terminal and reports success. For aliases created by the setup script, ControlMaster can reuse that authenticated connection for 10 minutes; for existing aliases, explicitly check `ssh -G <alias>` for effective ControlMaster/ControlPath settings. If not enabled, have the operator open a local master connection or configure an approved local alias before running more SSH commands. Stop on authentication failure without repeated retries. After connection, check Docker without sudo and list all running containers. Present every container as a numbered option and **PAUSE before inspecting a container's process list**. If no containers run, stop and report it.
4. **After container selection, identify Java services/processes.** Inspect only the selected container. Enumerate every Java PID with Jar/main class, Java version, and user when available. Present these as numbered Java service options and **PAUSE** for an explicit choice. If there is exactly one Java process, still show option 1 and wait. If none are found, explain what was checked and stop; do not switch containers automatically.
5. **Proceed with the selected JVM.** The operator's Java service/PID menu selection completes target confirmation; briefly restate the chosen server/container/service/PID for visibility, then continue to compatibility checks without asking them to confirm the same target again. Stop and repeat the relevant selection only if identity changes.
6. **Check compatibility before Arthas deployment.** Only after host, container, and PID have each been confirmed in this run, assess OS/architecture, actual JVM Java path/version, Java 8 JDK `tools.jar` availability where required by the launcher, UID/GID, attach permissions and namespace, JVM attach settings, container limits, available disk, and existing writable directories. Separately report attach temp capability and report-output capability. A missing `jcmd`, shell, or one failed probe alone does not prove incompatibility. Use `references/java-compatibility.md`. If an additional operator choice or approval is needed, present it and pause.
7. **Prepare Arthas only after compatibility passes.** Run `scripts/prepare-arthas.sh`. If local cache is absent, it downloads `https://arthas.aliyun.com/arthas-boot.jar`, verifies the JAR manifest is version 4.3.5, then stores it under `~/.performance-diagnosis/arthas/versions/4.3.5/` with a local SHA-256 record. If cached, it checks that record before use. The first digest is learned from the first HTTPS download, not an independent publisher signature; do not claim signature verification. Transfer local→host via SCP and host→container via Docker CP using a unique task directory; remote host/container need not access the internet.
8. **Plan diagnosis by evidence.** Before starting, run `scripts/arthas-task.sh status --task-id <id>` for any unfinished local task; recover/stop it before creating a new task. Create a task record with `scripts/arthas-task.sh init --task-id <id> --host <alias> --container-id <id> --pid <pid>`. Start with L1 environment/JVM/Docker/Linux facts. Use `scripts/arthas-batch.sh` for bounded allowlisted Arthas L1 commands; it automatically calls `scripts/prepare-arthas.sh` when `--arthas-boot` is omitted, and requires a timeout utility with a maximum 30-second wall clock. Choose only the relevant strategy in `references/` and state why each next command is useful. Keep raw outputs with timestamps and command context. Do not infer a root cause from a single ambiguous signal.
9. **Bound L2 work and PAUSE for approval.** For trace/watch/monitor/profiler, narrow the method/class, cap duration/count/output, record start/stop, and ensure there is only one active sampling task. Before starting any L2 action, present its target, command class, reason, duration/count/output limits, and stop plan; **end the turn and wait for explicit approval**. Default limit is 30 seconds. Do not pass L2 commands through the L1 wrapper. If a process supervisor/timeout and the corresponding Arthas stop command cannot be enforced, do not start L2.
10. **Collect and return artifacts.** Prefer an existing writable container temp or existing writable mount, then `docker cp`/SCP. Text that Arthas can safely emit to stdout may be captured there. Do not attempt file-based profiling when no safe output path exists. Verify file size and SHA-256 after transfer; on failure retain remote artifacts and record recovery details.
11. **Stop and clean up this task only.** Send the documented stop operation for any active profiler, then issue Arthas `stop`/detach for this session and verify it has exited. Update the local record with `scripts/arthas-task.sh finish --task-id <id> --result completed|failed|stopped`. Remove only files created under this task's unique directory after successful local verification. Never kill an unknown process or delete another task/session's files. If cleanup cannot be safely attributed, leave it and report.
12. **Write the report.** Use `templates/performance-report.md`, include evidence, uncertainty, unavailable checks and artifact list. Save under `~/.performance-diagnosis/diagnostics/<host>/<container>/<task-id>/` with restrictive permissions. Redact secrets.

### Required interaction pattern

The pauses above are control-flow requirements, not conversational suggestions. Always render choices as numbered options, ask exactly one question, and stop. Never replace available options with a free-text request for an IP/name. Do not combine server, password login, container, Java service/PID, or missing symptom prompts in one turn. The server, container, and Java PID selections are sufficient target confirmation; do not add a duplicate final confirmation. Resume only after the operator completes the current action/selection. Example:

```text
I found these configured SSH targets:
1. `beta` — deploy@192.0.2.10:22 — interactive auth required or unavailable
2. `staging` — ops@192.0.2.20:2222 — not tested

Which server should I use? Reply with 1 or 2. I will wait before connecting.
```

## Command tiers

- **L1, low-impact read-only:** Arthas `dashboard`, `thread`, `jvm`, `memory`, `version`; Docker `ps`, `inspect`, `stats --no-stream`, bounded `logs --tail`; Linux `uptime`, `free`, `df`, `ss -s`; bounded `vmstat`. Run only against the confirmed target.
- **L2, controlled instrumentation:** `trace`, `monitor`, `watch`, `profiler start/stop`. Use only with a scoped target and enforceable caps. No unbounded wildcard matching.
- **L3, prohibited in v1:** heap dump, dynamic class/VM mutation, JVM option changes, service/container lifecycle actions, or any operation likely to cause large pauses/resource spikes.

## References

- SSH and target selection: `references/ssh-management.md`, `references/docker-detection.md`
- Compatibility, deployment and command policy: `references/java-compatibility.md`, `references/arthas-deployment.md`, `references/arthas-command-reference.md`, `references/security-policy.md`
- Symptom strategies: `references/cpu-diagnosis.md`, `references/interface-diagnosis.md`, `references/memory-diagnosis.md`, `references/gc-diagnosis.md`, `references/thread-diagnosis.md`
- Output: `references/report-template.md`, `templates/environment-report.md`, `templates/performance-report.md`
- End-to-end usage example: read `references/usage-guide.md` when the operator needs onboarding or a worked example; it supplements, but does not override, the safety rules in this file.
- Optional local checks and SSH onboarding: `scripts/` (use `setup-ssh-server.sh` when adding a host)
- Arthas bounded batch execution and local task ledger: `scripts/arthas-batch.sh`, `scripts/arthas-task.sh`

## Scope of v1

Supports Linux Docker Java services, SSH password/keyboard-interactive or key-based access, one host/container/JVM per run, and Arthas as the JVM tool. It does not support bare-metal Java, Kubernetes, parallel diagnosis, automatic fixes, heap dumps, or automated production configuration changes.
