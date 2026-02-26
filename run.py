from app.main import create_app
from app.config import load_config

app = create_app()

if __name__ == "__main__":
    cfg = load_config()
    app.run(
        host=cfg["app"]["host"],
        port=cfg["app"]["port"],
        debug=cfg["app"]["debug"]
    )