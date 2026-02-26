import logging
import subprocess
from datetime import datetime
from functools import wraps
from logging.handlers import RotatingFileHandler
from pathlib import Path

from flask import Flask, render_template, request, jsonify, session, redirect, url_for
from werkzeug.security import check_password_hash

from app.config import load_config
from app.exec_service import ExecService
from app.did_service import DIDService


def setup_logging(app, log_file):
    log_path = Path(log_file)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    handler = RotatingFileHandler(
        log_file,
        maxBytes=5 * 1024 * 1024,
        backupCount=3,
        encoding="utf-8"
    )
    handler.setLevel(logging.INFO)
    formatter = logging.Formatter("[%(asctime)s] %(levelname)s %(message)s")
    handler.setFormatter(formatter)

    app.logger.setLevel(logging.INFO)
    # 避免重复添加 handler（比如 debug/reload 场景）
    if not app.logger.handlers:
        app.logger.addHandler(handler)
    else:
        app.logger.addHandler(handler)


def create_app():
    cfg = load_config()
    app = Flask(__name__, template_folder="../templates")
    app.config["SECRET_KEY"] = cfg["app"]["secret_key"]

    setup_logging(app, cfg.get("logging", {}).get("file", "logs/app.log"))

    # 原有按钮任务（中间件切换 / ALB切流）
    tasks_cfg = cfg.get("tasks", {})
    exec_svc = ExecService(tasks_cfg)

    # DID 白名单规则相关脚本
    did_cfg = cfg.get("did", {})
    did_svc = DIDService(did_cfg)

    # 登录配置
    auth_cfg = cfg.get("auth", {})
    auth_enabled = auth_cfg.get("enabled", False)
    auth_username = auth_cfg.get("username", "admin")
    auth_password = auth_cfg.get("password")  # 明文兼容（不推荐）
    auth_password_hash = auth_cfg.get("password_hash")  # 推荐

    def is_logged_in():
        if not auth_enabled:
            return True
        return session.get("logged_in") is True

    def login_required(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            if not is_logged_in():
                if request.path.startswith("/api/"):
                    return jsonify({"ok": False, "error": "未登录或会话已失效"}), 401
                return redirect(url_for("login"))
            return func(*args, **kwargs)
        return wrapper

    def verify_password(input_password: str) -> bool:
        if auth_password_hash:
            return check_password_hash(auth_password_hash, input_password)
        return auth_password is not None and input_password == auth_password

    # 前端按钮分组
    query_tasks = [
        {"key": "alb_rule_traffic", **tasks_cfg.get("alb_rule_traffic", {})},
        {"key": "check_middleware_switch", **tasks_cfg.get("check_middleware_switch", {})},
    ]
    middleware_tasks = [
        {"key": "middleware_to_az1", **tasks_cfg.get("middleware_to_az1", {})},
        {"key": "middleware_to_az2", **tasks_cfg.get("middleware_to_az2", {})},
        {"key": "middleware_restore", **tasks_cfg.get("middleware_restore", {})},
    ]
    alb_tasks = [
        {"key": "alb_to_az1", **tasks_cfg.get("alb_to_az1", {})},
        {"key": "alb_to_az2", **tasks_cfg.get("alb_to_az2", {})},
        {"key": "alb_restore", **tasks_cfg.get("alb_restore", {})},
    ]

    @app.route("/login", methods=["GET", "POST"])
    def login():
        if not auth_enabled:
            return redirect(url_for("index"))

        if request.method == "GET":
            return render_template("login.html", error=None)

        username = (request.form.get("username") or "").strip()
        password = request.form.get("password") or ""

        if username == auth_username and verify_password(password):
            session["logged_in"] = True
            session["username"] = username
            app.logger.info("login success user=%s", username)
            return redirect(url_for("index"))

        app.logger.warning(
            "login failed user=%s ip=%s",
            username,
            request.headers.get("X-Forwarded-For", request.remote_addr)
        )
        return render_template("login.html", error="用户名或密码错误")

    @app.route("/logout", methods=["GET"])
    def logout():
        user = session.get("username", "unknown")
        session.clear()
        app.logger.info("logout user=%s", user)
        return redirect(url_for("login"))

    @app.route("/", methods=["GET"])
    @login_required
    def index():
        return render_template(
            "index.html",
            query_tasks=query_tasks,
            middleware_tasks=middleware_tasks,
            alb_tasks=alb_tasks,
            now=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            machine_name=cfg.get("app", {}).get("machine_name", "EC2"),
            current_user=session.get("username", "anonymous"),
        )

    @app.route("/api/run-task", methods=["POST"])
    @login_required
    def run_task():
        data = request.get_json(force=True)
        task_key = (data.get("task_key") or "").strip()

        if not task_key:
            return jsonify({"ok": False, "error": "缺少 task_key"}), 400

        try:
            result = exec_svc.run_task(task_key)
            app.logger.info(
                "user=%s task=%s returncode=%s duration=%ss",
                session.get("username", "anonymous"),
                result["task_key"],
                result["returncode"],
                result["duration_seconds"],
            )
            return jsonify({"ok": True, "result": result})
        except subprocess.TimeoutExpired:
            app.logger.error(
                "user=%s task=%s timeout",
                session.get("username", "anonymous"),
                task_key
            )
            return jsonify({"ok": False, "error": "命令执行超时（超过300秒）"}), 500
        except Exception as e:
            app.logger.exception(
                "user=%s task=%s failed",
                session.get("username", "anonymous"),
                task_key
            )
            return jsonify({"ok": False, "error": str(e)}), 500

    @app.route("/api/did/scan", methods=["POST"])
    @login_required
    def did_scan():
        try:
            result = did_svc.scan_rules()
            app.logger.info(
                "user=%s did_scan returncode=%s duration=%ss",
                session.get("username", "anonymous"),
                result["returncode"],
                result["duration_seconds"],
            )
            return jsonify({"ok": True, "result": result})
        except subprocess.TimeoutExpired:
            app.logger.error("user=%s did_scan timeout", session.get("username", "anonymous"))
            return jsonify({"ok": False, "error": "扫描超时"}), 500
        except Exception as e:
            app.logger.exception("user=%s did_scan failed", session.get("username", "anonymous"))
            return jsonify({"ok": False, "error": str(e)}), 500

    @app.route("/api/did/modify", methods=["POST"])
    @login_required
    def did_modify():
        data = request.get_json(force=True)
        action = (data.get("action") or "").strip()
        header_value = (data.get("header_value") or "").strip()
        rule_name = (data.get("rule_name") or "").strip()
        priority = data.get("priority")

        try:
            result = did_svc.modify_rule(action, header_value, rule_name, priority)
            app.logger.info(
                "user=%s did_modify action=%s rule=%s priority=%s returncode=%s duration=%ss",
                session.get("username", "anonymous"),
                action,
                rule_name,
                priority,
                result["returncode"],
                result["duration_seconds"],
            )
            return jsonify({"ok": True, "result": result})
        except subprocess.TimeoutExpired:
            app.logger.error("user=%s did_modify timeout", session.get("username", "anonymous"))
            return jsonify({"ok": False, "error": "规则修改超时"}), 500
        except Exception as e:
            app.logger.exception("user=%s did_modify failed", session.get("username", "anonymous"))
            return jsonify({"ok": False, "error": str(e)}), 400

    @app.route("/api/did/priority", methods=["POST"])
    @login_required
    def did_priority():
        data = request.get_json(force=True)
        rule_name = (data.get("rule_name") or "").strip()
        priority = data.get("priority")

        try:
            result = did_svc.modify_priority(rule_name, priority)
            app.logger.info(
                "user=%s did_priority rule=%s priority=%s returncode=%s duration=%ss",
                session.get("username", "anonymous"),
                rule_name,
                priority,
                result["returncode"],
                result["duration_seconds"],
            )
            return jsonify({"ok": True, "result": result})
        except subprocess.TimeoutExpired:
            app.logger.error("user=%s did_priority timeout", session.get("username", "anonymous"))
            return jsonify({"ok": False, "error": "优先级修改超时"}), 500
        except Exception as e:
            app.logger.exception("user=%s did_priority failed", session.get("username", "anonymous"))
            return jsonify({"ok": False, "error": str(e)}), 400

    return app