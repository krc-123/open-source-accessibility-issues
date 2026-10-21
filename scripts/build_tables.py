"""Turn the collector's raw files into tidy CSVs.

Reads  <workdir>/repos.json, <workdir>/repos_candidates.json, <workdir>/state.json, <workdir>/issues.jsonl
Writes data/repos.csv            one row per repository in the sample, with issue counts
       data/issues.csv           one row per issue, deduplicated, with days to close and a WCAG category
       data/wcag_categories.csv  the keyword rules used for the category

Usage: python3 scripts/build_tables.py <workdir> data
"""
import json, csv, sys, os, re, datetime, collections

W, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
PULL = datetime.datetime(2026, 10, 21, tzinfo=datetime.timezone.utc)

def dt(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None

# ---- WCAG categories: ordered rules, first match wins. Keyword lists are deliberately plain so the
# classification is auditable; the README reports how many issues fall through to "other".
RULES = [
    ("screen_reader", "4.1.2 Name, Role, Value; 1.3.1 Info and Relationships", r"screen ?reader|voice ?over|\bnvda\b|\bjaws\b|talkback|narrator|\baria\b|aria-?label|accessible (name|view)|accessibility (signal|sound|chime|verbosity)|role=|announce|\blabel(l)?ed\b|alt text|alt attribute|semantic|landmark|live region|assistive tech|verbosity"),
    ("keyboard_focus", "2.1.1 Keyboard; 2.4.7 Focus Visible; 2.4.3 Focus Order", r"keyboard|\bfocus|\btab ?(key|order|index|stop|navigation|bing)\b|shortcut|hotkey|arrow key|escape key|\benter key|focus trap|focusable"),
    ("contrast_color", "1.4.3 Contrast; 1.4.1 Use of Color; 1.4.11 Non-text Contrast", r"contrast|high.contrast|color.?blind|colou?r (alone|only)|forced.colors|dark mode.*(read|see|visib)|hard to (read|see)|unreadable|legib|low.vision|\bwcag\b.*(aa|contrast)|theme.*(read|visib)"),
    ("zoom_text_size", "1.4.4 Resize Text; 1.4.10 Reflow; 1.4.12 Text Spacing", r"\bzoom|font.?size|text.?size|scal(e|ing) (text|font|ui)|\breflow|magnif|large text|text spacing|200%|dpi"),
    ("motion_animation", "2.3.3 Animation from Interactions; 2.2.2 Pause, Stop, Hide", r"reduce[d]? motion|prefers-reduced-motion|animation|flash(ing)?|blink|autoplay|parallax|vestibular"),
    ("captions_media", "1.2.x Time-based Media; 1.1.1 Non-text Content", r"caption|subtitle|transcript|audio description|sign language"),
    ("forms_errors", "3.3.1 Error Identification; 3.3.2 Labels or Instructions; 1.3.5 Identify Input Purpose", r"form (field|input|error|validation)|error message|required field|autocomplete|input purpose|placeholder"),
    ("touch_target_pointer", "2.5.5 Target Size; 2.5.1 Pointer Gestures; 2.5.7 Dragging", r"touch target|target size|tap target|hit area|drag(ging)? (and drop|gesture)|pointer gesture|click area"),
    ("language_reading", "3.1.x Readable; 3.2.x Predictable", r"\blang(uage)? attribute|right-to-left|\brtl\b|dyslexi|plain language|reading level"),
    ("timing", "2.2.1 Timing Adjustable", r"time ?out|session expir|time limit"),
]
with open(os.path.join(OUT, "wcag_categories.csv"), "w", newline="") as f:
    w = csv.writer(f); w.writerow(["category", "wcag_criteria", "regex"]); [w.writerow(r) for r in RULES]
COMPILED = [(c, re.compile(rx, re.I)) for c, _, rx in RULES]

def classify(title, body):
    text = f"{title} \n {body}"
    for c, rx in COMPILED:
        if rx.search(text):
            return c
    return "other"

# ---- repos
repos = json.load(open(os.path.join(W, "repos.json")))
cands = json.load(open(os.path.join(W, "repos_candidates.json")))
state = json.load(open(os.path.join(W, "state.json")))["done"]
with open(os.path.join(OUT, "repos.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["repo", "stars", "language", "created_at", "open_issues", "description", "a11y_issues_total", "a11y_issues_collected", "bug_issues_total", "bug_issues_collected", "collected"])
    for r in repos:
        s = state.get(r["full_name"], {})
        w.writerow([r["full_name"], r["stars"], r["language"], r["created_at"][:10], r["open_issues"], r["description"],
                    s.get("a11y_total", ""), s.get("a11y", ""), s.get("bug_total", ""), s.get("bug", ""), int(bool(s))])
print(f"{len(repos)} repos, {sum(1 for r in repos if r['full_name'] in state)} collected, {len(cands)} candidates", file=sys.stderr)

# ---- issues: deduplicate on (repo, number); an issue that carries both labels counts as accessibility
seen = {}
for line in open(os.path.join(W, "issues.jsonl")):
    it = json.loads(line); key = (it["repo"], it["number"])
    if key in seen and seen[key]["group"] == "accessibility":
        continue
    seen[key] = it
rows = []
cat_counts = collections.Counter()
for it in seen.values():
    c, cl = dt(it["created_at"]), dt(it["closed_at"])
    days = (cl - c).total_seconds() / 86400 if cl else (PULL - c).total_seconds() / 86400
    cat = classify(it["title"], it["body_excerpt"]) if it["group"] == "accessibility" else ""
    if cat: cat_counts[cat] += 1
    rows.append({
        "repo": it["repo"], "number": it["number"], "group": it["group"], "title": it["title"],
        "labels": "|".join(it["labels"]), "also_labeled_bug": int(it["group"] == "accessibility" and any(re.search(r"bug", l, re.I) for l in it["labels"])),
        "state": it["state"], "state_reason": it["state_reason"] or "", "created_at": it["created_at"][:10],
        "closed_at": (it["closed_at"] or "")[:10], "closed": int(bool(cl)), "days_to_close_or_censor": round(days, 1),
        "closed_within_30d": int(bool(cl) and days <= 30), "closed_within_90d": int(bool(cl) and days <= 90), "closed_within_365d": int(bool(cl) and days <= 365),
        "comments": it["comments"], "reactions": it["reactions"], "author_association": it["author_association"] or "",
        "author_is_bot": int(it["author_type"] == "Bot"), "wcag_category": cat,
    })
rows.sort(key=lambda r: (r["repo"], r["group"], r["created_at"]))
with open(os.path.join(OUT, "issues.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
g = collections.Counter(r["group"] for r in rows)
print(f"{len(rows)} issues after dedup: {dict(g)}; categories: {dict(cat_counts)}", file=sys.stderr)
