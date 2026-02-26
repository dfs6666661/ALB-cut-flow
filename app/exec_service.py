import shlex
import subprocess
import time
from pathlib import Path


class ExecService:
    def __init__(self, tasks_cfg: dict):
        self.tasks_cfg = tasks_cfg or {}

    def run_task(self, task_key: str):
        if task_key not in self.tasks_cfg:
            raise ValueError(f"未找到任务: {task_key}")

        task = self.tasks_cfg[task_key]
        cmd = task.get("cmd")
        if not cmd:
            raise ValueError(f"任务 {task_key} 未配置 cmd")

        # 简单安全校验：仅允许执行白名单配置中的命令
        cmd_list = shlex.split(cmd)

        start = time.time()
        proc = subprocess.run(
            cmd_list,
            capture_output=True,
            text=True,
            timeout=300  # 最多5分钟，防止卡死
        )
        duration = round(time.time() - start, 2)

        return {
            "task_key": task_key,
            "task_name": task.get("name", task_key),
            "returncode": proc.returncode,
            "stdout": proc.stdout or "",
            "stderr": proc.stderr or "",
            "duration_seconds": duration,
        }