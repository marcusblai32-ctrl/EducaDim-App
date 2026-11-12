"""Génère l'icône Windows (app_icon.ico) à partir d'assets/icon/icon.png (utilisé par le workflow)."""
import os
from PIL import Image

src = Image.open("assets/icon/icon.png").convert("RGBA")
os.makedirs("windows/runner/resources", exist_ok=True)
src.save("windows/runner/resources/app_icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("app_icon.ico créé")
