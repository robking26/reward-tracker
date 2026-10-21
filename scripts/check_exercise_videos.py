"""Checks exercise demo videos with YouTube's oEmbed endpoint: 200 means public and embeddable.
Usage: python3 scripts/check_exercise_videos.py <file>
The file is either the candidates list ("exerciseID videoID [videoID...]" per line) or ExerciseVideos.swift."""
import json, re, sys, urllib.error, urllib.request

def check(video):
    url = "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=" + video
    try:
        with urllib.request.urlopen(url, timeout=15) as response:
            data = json.load(response)
            return 200, data.get("title", ""), data.get("author_name", "")
    except urllib.error.HTTPError as error:
        return error.code, "", ""
    except Exception as error:  # network trouble: report, don't fail the build
        return 0, str(error), ""

text = open(sys.argv[1], encoding="utf-8").read()
if sys.argv[1].endswith(".swift"):
    rows = [(m.group(1), [m.group(2)]) for m in re.finditer(r'"(\w+)":\s*"([\w-]{11})"', text)]
else:
    rows = [(parts[0], parts[1:]) for parts in (line.split() for line in text.splitlines()) if len(parts) > 1]

bad = 0
for exercise, videos in rows:
    for video in videos:
        code, title, author = check(video)
        bad += code != 200
        print(f"VIDEO {code} {exercise} {video} | {title} | {author}")
print(f"VIDEO checked {sum(len(v) for _, v in rows)}, not embeddable {bad}")
