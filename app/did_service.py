import re
import shlex
import subprocess
import time


class DIDService:
    def __init__(self, did_cfg: dict):
        self.scan_script = did_cfg.get("scan_script")
        self.modify_script = did_cfg.get("modify_script")
        self.priority_script = did_cfg.get("priority_script")

    def _run(self, cmd_list, timeout=300):
        start = time.time()
        proc = subprocess.run(
            cmd_list,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        duration = round(time.time() - start, 2)
        return {
            "returncode": proc.returncode,
            "stdout": proc.stdout or "",
            "stderr": proc.stderr or "",
            "duration_seconds": duration,
            "cmd": " ".join(shlex.quote(x) for x in cmd_list),
        }

    def _validate_rule_name(self, rule_name: str):
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", rule_name or ""):
            raise ValueError("规则名称格式非法（仅允许字母/数字/_/-）")

    def _validate_header_value(self, header_value: str):
        if not re.fullmatch(r"[A-Za-z0-9._:-]{1,200}", header_value or ""):
            raise ValueError("Header值格式非法")

    def _validate_priority(self, priority):
        try:
            p = int(str(priority))
        except Exception:
            raise ValueError("优先级必须为数字")
        if p < 1 or p > 50000:
            raise ValueError("优先级范围必须在 1~50000")
        return str(p)

    def _validate_action(self, action: str):
        if action not in ("add", "delete"):
            raise ValueError("action 必须是 add 或 delete")

    def scan_rules(self):
        if not self.scan_script:
            raise ValueError("未配置 did.scan_script")
        cmd = shlex.split(self.scan_script) + ["--pretty"]
        return self._run(cmd, timeout=120)

    def modify_rule(self, action: str, header_value: str, rule_name: str, priority):
        if not self.modify_script:
            raise ValueError("未配置 did.modify_script")

        self._validate_action(action)
        self._validate_header_value(header_value)
        self._validate_rule_name(rule_name)
        priority_str = self._validate_priority(priority)

        cmd = shlex.split(self.modify_script) + [
            "--action", action,
            "--header-value", header_value,
            "--rule-name", rule_name,
            "--priority", priority_str,
        ]
        return self._run(cmd, timeout=300)

    def modify_priority(self, rule_name: str, priority):
        if not self.priority_script:
            raise ValueError("未配置 did.priority_script")

        self._validate_rule_name(rule_name)
        priority_str = self._validate_priority(priority)

        cmd = shlex.split(self.priority_script) + [
            "--rule-name", rule_name,
            "--priority", priority_str,
        ]
        return self._run(cmd, timeout=180)