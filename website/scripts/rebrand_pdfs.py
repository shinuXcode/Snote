from __future__ import annotations
import hashlib
from pathlib import Path
import fitz
import cairosvg

ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent if ROOT.name == "scripts" else ROOT
DOCS = PROJECT_ROOT / "public" / "docs"
LOGO = PROJECT_ROOT / "public" / "snote-logo.svg"
PDFS = ["app-overview.pdf", "features.pdf", "notifications-admin.pdf", "open-source.pdf", "permissions.pdf", "license.pdf", "sdks.pdf", "terms.pdf", "repository-audit.pdf"]
PNG_LOGO = cairosvg.svg2png(url=str(LOGO), output_width=512, output_height=512)

def rgb_from_int(value):
    return (((value >> 16) & 255) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255)

def font_alias(name):
    n = name.lower()
    bold = "bold" in n or "semibold" in n
    italic = "italic" in n or "oblique" in n
    if bold and italic: return "hebi"
    if bold: return "hebo"
    if italic: return "heit"
    return "helv"

def rebrand_span(text):
    # Keep the actual GitHub repository path unchanged.
    if "github.com/shinuXcode/Snote" in text:
        left, sep, right = text.partition("github.com/shinuXcode/Snote")
        return rebrand_span(left) + sep + right
    text = text.replace("snote-showcase.vercel.app", "@@SNOTEE_SITE@@")
    text = text.replace("Snote", "Snotee")
    text = text.replace("snote", "snotee")
    text = text.replace("@@SNOTEE_SITE@@", "snotee.vercel.app")
    return text

def process(path: Path):
    doc = fitz.open(path)
    edits_count = 0
    for page in doc:
        edits = []
        for block in page.get_text("dict")["blocks"]:
            for line in block.get("lines", []):
                for span in line.get("spans", []):
                    old = span.get("text", "")
                    # The oversized pale SNOTE/SADAB artwork is a background watermark, not UI copy.
                    # Leave that low-opacity treatment intact; replace visible body/headline/footer branding.
                    if float(span.get("size", 9)) >= 40:
                        continue
                    new = rebrand_span(old)
                    if new != old and old.strip():
                        edits.append((fitz.Rect(span["bbox"]), span, new, float(span.get("size", 9))))
        for rect, span, new, fontsize in edits:
            clean = fitz.Rect(rect.x0, rect.y0 - 1.1, rect.x1, rect.y1 + 1.1)
            page.add_redact_annot(clean, fill=(1, 1, 1), cross_out=False)
            edits_count += 1
        if edits:
            page.apply_redactions(images=0, graphics=0, text=0)
            for rect, span, new, fontsize in edits:
                original = span.get("text", "")
                origin = span.get("origin", (rect.x0, rect.y1 - 1.5))
                font = font_alias(span.get("font", ""))
                x0 = rect.x0
                if len(original) > 12 and rect.x0 > 140 and rect.x1 < 455 and fontsize > 15:
                    width = fitz.get_text_length(new, fontname=font, fontsize=fontsize)
                    x0 = max(30, (page.rect.width - width) / 2)
                color = rgb_from_int(span.get("color", 0))
                if original.endswith((" ", "\t")):
                    measured = fitz.get_text_length(new.rstrip(), fontname=font, fontsize=fontsize)
                    available = max(4, rect.width - 5.0)
                    if measured > available:
                        fontsize *= available / measured
                page.insert_text((x0, origin[1]), new, fontname=font, fontsize=fontsize, color=color, overlay=True)
        # The former blue square app mark is replaced by the current black/ivory/lime S-and-stylus mark.
        for image in page.get_images(full=True):
            for rect in page.get_image_rects(image[0]):
                if rect.width >= 90 and rect.height >= 90 and abs(rect.width - rect.height) < 4:
                    page.draw_rect(rect + (-1, -1, 1, 1), color=(1, 1, 1), fill=(1, 1, 1), overlay=True)
                    page.insert_image(rect, stream=PNG_LOGO, keep_proportion=True, overlay=True)
    metadata = dict(doc.metadata or {})
    for key in ("title", "subject", "keywords"):
        if metadata.get(key):
            metadata[key] = rebrand_span(metadata[key])
    doc.set_metadata(metadata)
    temp = path.with_suffix(".tmp.pdf")
    doc.save(temp, garbage=4, deflate=True, clean=True)
    doc.close()
    temp.replace(path)
    return edits_count

def update_manifest():
    manifest = DOCS / "SHA256-MANIFEST.txt"
    rows = ["Snotee PDF verification manifest - regenerated after branding refresh", ""]
    for name in PDFS:
        path = DOCS / name
        data = path.read_bytes()
        rows.append(f"{name}\t{len(data)} bytes\tSHA-256 {hashlib.sha256(data).hexdigest()}")
    manifest.write_text("\n".join(rows) + "\n", encoding="utf-8")

if __name__ == "__main__":
    missing = [name for name in PDFS if not (DOCS / name).exists()]
    if missing:
        raise SystemExit("Missing PDFs: " + ", ".join(missing))
    for name in PDFS:
        print(f"Rebranding {name}: {process(DOCS / name)} spans")
    update_manifest()
