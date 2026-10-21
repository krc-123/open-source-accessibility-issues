"""Collect accessibility-labeled issues and a comparison sample of bug-labeled
issues from the most-starred repositories on GitHub, using only the
unauthenticated REST search API (10 requests a minute).

The script is resumable: it keeps its place in state/ and can be run in
short bursts (it stops cleanly after --budget seconds). Run it until it
prints "all repositories done".

Usage: python3 collect.py <workdir> [--budget 165] [--repos 300]
Writes: <workdir>/repos.json, <workdir>/issues.jsonl, <workdir>/state.json, <workdir>/log.txt
"""
import json, os, sys, time, urllib.request, urllib.parse, urllib.error, argparse, datetime

ap = argparse.ArgumentParser()
ap.add_argument("workdir")
ap.add_argument("--budget", type=float, default=165.0, help="seconds to run before stopping cleanly")
ap.add_argument("--repos", type=int, default=400, help="number of top-starred software repositories to keep")
ap.add_argument("--since", default="2022-01-01", help="only issues created on or after this date")
ap.add_argument("--until", default="2025-06-30", help="only issues created on or before this date")
args = ap.parse_args()

W = args.workdir; os.makedirs(W, exist_ok=True)
REPOS = os.path.join(W, "repos.json"); ISSUES = os.path.join(W, "issues.jsonl"); STATE = os.path.join(W, "state.json"); LOG = os.path.join(W, "log.txt")
T0 = time.time()
A11Y_LABELS = ["accessibility", "a11y", "Accessibility", "A11y", "type: accessibility", "area: accessibility", "area-accessibility", "Area: Accessibility", "accessibility (a11y)", "a11y-accessibility", "c: accessibility", "topic: a11y", "category: accessibility"]

def log(msg):
    with open(LOG, "a") as f:
        f.write(f"{datetime.datetime.utcnow().isoformat()}Z {msg}\n")

def get(url):
    """GET with rate-limit handling. Returns (json, headers) or raises."""
    while True:
        req = urllib.request.Request(url, headers={"User-Agent": "open-source-accessibility-issues (research; krc-123)", "Accept": "application/vnd.github+json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                body = json.loads(r.read().decode("utf-8")); h = dict(r.headers)
            remaining = int(h.get("X-RateLimit-Remaining", "1")); reset = int(h.get("X-RateLimit-Reset", "0"))
            if remaining <= 0:
                wait = max(0, reset - time.time()) + 1
                if time.time() - T0 + wait > args.budget:
                    # Not enough budget left to wait out the window; let the caller stop cleanly.
                    globals()["STOP_AFTER_THIS"] = True
                else:
                    log(f"rate limit reached; sleeping {wait:.0f}s"); time.sleep(wait)
            return body, h
        except urllib.error.HTTPError as e:
            if e.code in (403, 429):
                reset = int(e.headers.get("X-RateLimit-Reset", "0")); retry = e.headers.get("Retry-After")
                wait = float(retry) if retry else max(5, reset - time.time() + 1)
                wait = min(wait, 90)
                log(f"HTTP {e.code}; sleeping {wait:.0f}s"); time.sleep(wait)
                if time.time() - T0 > args.budget:
                    raise TimeoutError("budget exhausted while rate limited")
                continue
            raise
        except (urllib.error.URLError, OSError) as e:
            # transient network trouble (SSL EOF, reset, timeout): wait and retry
            log(f"network error {type(e).__name__}: {str(e)[:80]}; retrying in 8s"); time.sleep(8)
            if time.time() - T0 > args.budget:
                raise TimeoutError("budget exhausted during network errors")
            continue

STOP_AFTER_THIS = False
def out_of_time():
    return STOP_AFTER_THIS or time.time() - T0 > args.budget

# ---- 1. Repository list --------------------------------------------
# The raw top of GitHub by stars is dominated by curated lists, books, tutorials and
# interview prep. Those have no user interface and no accessibility bugs to handle, so
# the candidate pool is the 1,000 most-starred repositories (the search API's ceiling)
# filtered to projects that ship software, from which the first N are kept.
import re
SOFTWARE_LANGS = {"TypeScript", "JavaScript", "Python", "Rust", "Go", "C++", "Java", "C", "C#", "Kotlin", "Swift", "Dart",
                  "Vue", "Ruby", "PHP", "Elixir", "Scala", "Objective-C", "Lua", "Zig", "Haskell", "Clojure", "Svelte", "CSS", "SCSS"}
NOT_SOFTWARE = re.compile(r"awesome|curated|interview|roadmap|\bbook|tutorial|cheat.?sheet|learn|course|guide|resources|collection|algorithms?\b|system.design|coding|papers|prompts|best.practice|skills|handbook|examples|boilerplate|starter|template|list of|questions|study|notes|wiki|archive|dataset|benchmark", re.I)
if not os.path.exists(REPOS):
    pool = []
    for p in range(1, 11):
        q = urllib.parse.quote("stars:>5000 archived:false")
        body, _ = get(f"https://api.github.com/search/repositories?q={q}&sort=stars&order=desc&per_page=100&page={p}")
        for r in body["items"]:
            pool.append({"full_name": r["full_name"], "stars": r["stargazers_count"], "language": r.get("language"),
                         "topics": r.get("topics", []), "created_at": r["created_at"], "open_issues": r["open_issues_count"],
                         "has_issues": r["has_issues"], "description": (r.get("description") or "")[:200]})
        log(f"repo page {p}: {len(pool)} candidates so far")
        if len(body["items"]) < 100:
            break
    json.dump(pool, open(os.path.join(W, "repos_candidates.json"), "w"), indent=1)
    def is_software(r):
        text = r["full_name"] + " " + r["description"] + " " + " ".join(r["topics"])
        return r["language"] in SOFTWARE_LANGS and r["has_issues"] and not NOT_SOFTWARE.search(text)
    repos = [r for r in pool if is_software(r)][:args.repos]
    json.dump(repos, open(REPOS, "w"), indent=1)
    log(f"kept {len(repos)} software repositories out of {len(pool)} candidates")
repos = json.load(open(REPOS))

state = json.load(open(STATE)) if os.path.exists(STATE) else {"done": {}, "requests": 0}

def search_issues(q, max_pages):
    items, total = [], None
    for page in range(1, max_pages + 1):
        url = f"https://api.github.com/search/issues?q={urllib.parse.quote(q)}&per_page=100&page={page}&sort=created&order=desc"
        body, _ = get(url); state["requests"] += 1
        total = body.get("total_count", 0); items += body.get("items", [])
        if len(body.get("items", [])) < 100 or out_of_time():
            break
    return items, total

def slim(it, repo, group):
    labels = [l["name"] for l in it.get("labels", [])]
    return {"repo": repo, "group": group, "number": it["number"], "title": it["title"][:300], "labels": labels,
            "state": it["state"], "state_reason": it.get("state_reason"), "created_at": it["created_at"],
            "closed_at": it.get("closed_at"), "updated_at": it["updated_at"], "comments": it.get("comments", 0),
            "reactions": (it.get("reactions") or {}).get("total_count", 0), "author_type": (it.get("user") or {}).get("type"),
            "author_association": it.get("author_association"), "locked": it.get("locked", False),
            "body_excerpt": (it.get("body") or "")[:600].replace("\n", " ")}

window = f"created:{args.since}..{args.until}"
label_q = "label:" + ",".join(f'"{l}"' for l in A11Y_LABELS)

for repo in repos:
    name = repo["full_name"]
    if name in state["done"]:
        continue
    if out_of_time():
        break
    if not repo.get("has_issues", True):
        state["done"][name] = {"a11y": 0, "bug": 0, "note": "issues disabled"}; continue
    try:
        a11y, a_total = search_issues(f"repo:{name} is:issue {label_q} {window}", max_pages=5)
        bug, b_total = search_issues(f"repo:{name} is:issue label:bug,\"type: bug\",\"kind/bug\",\"Type: Bug\",\"bug report\" {window}", max_pages=2)
    except TimeoutError:
        break
    with open(ISSUES, "a") as f:
        for it in a11y: f.write(json.dumps(slim(it, name, "accessibility")) + "\n")
        for it in bug: f.write(json.dumps(slim(it, name, "bug")) + "\n")
    state["done"][name] = {"a11y": len(a11y), "a11y_total": a_total, "bug": len(bug), "bug_total": b_total}
    json.dump(state, open(STATE, "w"))
    log(f"{name}: a11y {len(a11y)}/{a_total}, bug {len(bug)}/{b_total}")

json.dump(state, open(STATE, "w"))
done = len(state["done"]); print(f"{done}/{len(repos)} repositories done, {state['requests']} search requests so far")
if done >= len(repos):
    print("all repositories done")
