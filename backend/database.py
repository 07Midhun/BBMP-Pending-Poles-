import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from pathlib import Path
from dotenv import load_dotenv
from models_db import Base

# Load environment from backend directory and current working directory
backend_env = Path(__file__).resolve().parent / ".env"
if backend_env.exists():
    load_dotenv(dotenv_path=backend_env)
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "").strip()

# Neon connection strings often start with postgres://, which SQLAlchemy requires as postgresql://
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

engine = None
SessionLocal = None

if DATABASE_URL:
    try:
        engine = create_engine(
            DATABASE_URL,
            pool_pre_ping=True,      # Automatically reconnects if Neon compute was sleeping
            pool_recycle=300,       # Recycle connections every 5 minutes
            pool_size=10,
            max_overflow=20,
            connect_args={"sslmode": "require"} if "sslmode" not in DATABASE_URL else {}
        )
        SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
        print("[DATABASE] Neon PostgreSQL engine initialized successfully.")
    except Exception as exc:
        print(f"[DATABASE] Error initializing database engine: {exc}")
else:
    print("[DATABASE] DATABASE_URL not set. Running in local/fallback mode.")

def init_db():
    """Create all tables in Neon if they do not exist."""
    if engine is not None:
        try:
            Base.metadata.create_all(bind=engine)
            print("[DATABASE] Tables verified/created in Neon PostgreSQL.")
            return True
        except Exception as exc:
            print(f"[DATABASE] Failed to create tables in Neon: {exc}")
            return False
    return False

def get_db():
    """Dependency for obtaining a database session."""
    if SessionLocal is None:
        return None
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def is_db_connected() -> bool:
    """Quick health-check probe."""
    if engine is None or SessionLocal is None:
        return False
    try:
        from sqlalchemy import text
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False
