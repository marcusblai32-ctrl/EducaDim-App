"""Remplit AppIcon.appiconset d'iOS avec le logo EducaDim (utilisé par le workflow iOS)."""
import json
import os
from PIL import Image

base = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
src = Image.open("assets/icon/icon.png").convert("RGBA")
with open(os.path.join(base, "Contents.json")) as f:
    data = json.load(f)
done = 0
for img in data.get("images", []):
    name = img.get("filename")
    if not name:
        continue
    size = float(img["size"].split("x")[0])
    scale = int(img["scale"].rstrip("x"))
    px = int(round(size * scale))
    # iOS refuse la transparence dans l'icône : fond blanc.
    flat = Image.new("RGB", (px, px), (255, 255, 255))
    resized = src.resize((px, px), Image.LANCZOS)
    flat.paste(resized, (0, 0), resized)
    flat.save(os.path.join(base, name))
    done += 1
print(f"{done} icônes iOS créées")
