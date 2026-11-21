import shutil
from pathlib import Path

import pytest

from clipper.config import charger_config
from clipper.db import Base

RACINE = Path(__file__).resolve().parent.parent


@pytest.fixture
def cfg(tmp_path):
    """Une config réelle (config.yaml + prompts) mais des données dans un dossier temporaire."""
    shutil.copy(RACINE / "config.yaml", tmp_path / "config.yaml")
    shutil.copytree(RACINE / "prompts", tmp_path / "prompts")
    return charger_config(tmp_path / "config.yaml")


@pytest.fixture
def base(cfg):
    b = Base(cfg.chemin_base)
    yield b
    b.fermer()
