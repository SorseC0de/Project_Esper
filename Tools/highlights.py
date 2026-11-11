#!/usr/bin/env python3
"""Cut footage highlights.

Reads a footage run (the app's Footage/ folder: NN_scene.mp4 beside NN_scene.jsonl, written by
the debug footage mode) and mixes the logged sounds under each recording, cuts a clip round every moment worth keeping,
by kind, into _Graphic Assets/_Kickstarter Campaign/FOOTAGE/<kind>/, the whole scripted scenes into
FOOTAGE/scenes/, the computer games whole into FOOTAGE/games/, and mash-ups of everything into
FOOTAGE/ itself.

    ./Tools/highlights.py                      # the last run, from the app's container
    ./Tools/highlights.py /path/to/Footage     # a run copied elsewhere
    ./Tools/highlights.py --out /elsewhere     # another output folder
"""
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
CONTAINER = os.path.expanduser("~/Library/Containers/94CDA9E8-6FFD-40A7-B767-5F6C6BB15E2A/Data/tmp/Footage")


def simulator_run():
    """The last run in a simulator, by the newest `done`."""
    base = os.path.expanduser("~/Library/Developer/CoreSimulator/Devices")
    found = []
    for root, dirs, files in os.walk(base):
        if root.endswith("tmp/Footage") and "done" in files:
            found.append((os.path.getmtime(os.path.join(root, "done")), root))
        if root.count(os.sep) - base.count(os.sep) > 7:
            dirs[:] = []
    return max(found)[1] if found else None
SOUNDS = os.path.join(PROJECT, "ProjectEsper", "Sounds")
OUT = os.path.join(PROJECT, "_Graphic Assets", "_Kickstarter Campaign", "FOOTAGE")
# The game's ambience under the Elements (`Ambience.volume`), and how many sounds one ffmpeg mix takes.
AMBIENCE = {"theElements": ("thunderstorm.m4a", 0.2)}
MIX_BATCH = 100

# Event name -> (kind, seconds before, seconds after). Events not listed are left out.
KINDS = {
    "scored": ("scores", 3.0, 2.5),
    "dunked": ("dunks", 2.5, 2.5),
    "wallJumped": ("wall_jumps", 1.5, 2.5),
    "beamFired": ("beams", 1.5, 4.0),
    "barrierShattered": ("breaks", 3.0, 3.0),
    "scoredOnFreeze": ("breaker_scores", 3.0, 2.5),
    "blastFired": ("blasts", 1.0, 1.5),
    "transformed": ("flostate", 1.0, 2.5),
    "webSwung": ("web_swings", 1.0, 3.0),
    "flew": ("flight", 1.0, 3.0),
    "swatted": ("swats", 2.0, 2.0),
    "slashClashed": ("clashes", 4.0, 2.5),
    "shieldClashed": ("clashes", 4.0, 2.5),
    "snatchClashed": ("clashes", 4.0, 2.5),
    "countered": ("counters", 1.5, 2.5),
    "parried": ("counters", 1.5, 2.5),
    "struck": ("hits", 1.0, 1.5),
    "popped": ("pops", 1.0, 2.0),
    "stolen": ("steals", 1.5, 2.0),
    "lavaBurned": ("lava", 2.0, 2.0),
    "spun": ("spin_moves", 1.0, 2.0),
    "flashed": ("flashes", 1.0, 1.5),
    "warped": ("flashes", 1.0, 1.5),
    "platformMade": ("platforms", 1.0, 2.0),
    "platformShattered": ("platforms", 1.5, 1.5),
    "boltFired": ("bolts", 1.0, 2.0),
    "boltStruck": ("bolts", 1.0, 2.0),
    "fireballThrown": ("fireballs", 1.0, 2.5),
    "pulsed": ("pulses", 1.0, 2.0),
    "sniped": ("pulses", 1.0, 2.0),
    "galeMade": ("gales", 1.0, 2.5),
    "cloneMade": ("clones", 1.0, 2.0),
    "phantomToggled": ("phantom", 1.0, 2.0),
    "portalWarped": ("portals", 1.5, 2.0),
    "hoopfishSpun": ("hoopfish", 2.5, 3.0),
    "surfLanded": ("surf", 2.0, 1.5),
    "shieldPerfect": ("shields", 1.5, 2.0),
    "shieldReflected": ("shields", 1.5, 2.0),
    "shieldBroken": ("shields", 1.5, 2.0),
    "breakerBallCaught": ("snatches", 1.5, 2.0),
    "icicleShattered": ("stage_hazards", 1.5, 1.5),
    "lightningStruck": ("stage_hazards", 1.5, 1.5),
    "stageFireballBurst": ("stage_hazards", 1.5, 1.5),
}
# How many clips of one kind from one scene at most: a beam fired on and on is one clip.
MERGE_GAP = 1.0
MAX_CLIP = 14.0
FPS = 60


def run(args, quiet=True):
    return subprocess.run(args, check=True, stdout=subprocess.DEVNULL if quiet else None, stderr=subprocess.DEVNULL if quiet else None)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path], capture_output=True, text=True)
    try:
        return float(out.stdout.strip())
    except ValueError:
        return 0.0


def cut(src, start, end, dst):
    start = max(0.0, start)
    length = max(0.5, end - start)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    run(["ffmpeg", "-y", "-ss", f"{start:.3f}", "-i", src, "-t", f"{length:.3f}", "-c:v", "libx264", "-preset", "fast", "-crf", "16",
         "-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", dst])


def concat(clips, dst):
    if not clips:
        return
    listing = dst + ".txt"
    with open(listing, "w") as handle:
        for clip in clips:
            handle.write("file '" + clip.replace("'", "'\\''") + "'\n")
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", "-movflags", "+faststart", dst])
    os.remove(listing)


def sound_file(name):
    for ext in ("wav", "m4a"):
        path = os.path.join(SOUNDS, name + "." + ext)
        if os.path.exists(path):
            return path
    return None


def mix_sounds(scene, lines, length, work, name):
    """The scene's logged sounds laid at their times into one stereo track; None when there are none."""
    sounds = [(l["t"], l["sound"], l["volume"], l["pan"]) for l in lines if "sound" in l and sound_file(l["sound"])]
    # Loops: from their start to their key's end (or the scene's), looped.
    loops, open_loops = [], {}
    for l in lines:
        if "loop" not in l:
            continue
        if l["on"] and sound_file(l["loop"]):
            open_loops[l["key"]] = (l["t"], l["loop"], l["volume"])
        elif not l["on"] and l["key"] in open_loops:
            start, loop_name, volume = open_loops.pop(l["key"])
            loops.append((start, l["t"], loop_name, volume))
    for start, loop_name, volume in open_loops.values():
        loops.append((start, length, loop_name, volume))
    ambience = AMBIENCE.get(scene["stage"])
    if not sounds and not loops and not ambience:
        return None
    parts = []
    batches = [sounds[i:i + MIX_BATCH] for i in range(0, len(sounds), MIX_BATCH)]
    for number, batch in enumerate(batches):
        args, filters, labels = ["ffmpeg", "-y"], [], []
        for index, (t, sound, volume, pan) in enumerate(batch):
            args += ["-i", sound_file(sound)]
            left, right = min(1.0, 1.0 - pan), min(1.0, 1.0 + pan)
            filters.append(f"[{index}]adelay={int(t * 1000)}|{int(t * 1000)},volume={volume:.3f},pan=stereo|c0={left:.3f}*c0|c1={right:.3f}*c0[s{index}]")
            labels.append(f"[s{index}]")
        filters.append("".join(labels) + f"amix=inputs={len(batch)}:normalize=0:dropout_transition=0,apad=whole_dur={length:.3f}[out]")
        out = os.path.join(work, f"{name}_mix{number}.wav")
        run(args + ["-filter_complex", ";".join(filters), "-map", "[out]", "-t", f"{length:.3f}", out])
        parts.append(out)
    for number, (start, end, loop_name, volume) in enumerate(loops):
        out = os.path.join(work, f"{name}_loop{number}.wav")
        run(["ffmpeg", "-y", "-stream_loop", "-1", "-i", sound_file(loop_name), "-t", f"{max(0.0, end - start):.3f}",
             "-filter_complex", f"[0]volume={volume:.3f},adelay={int(start * 1000)}|{int(start * 1000)},apad=whole_dur={length:.3f}[out]", "-map", "[out]", "-t", f"{length:.3f}", out])
        parts.append(out)
    if ambience:
        out = os.path.join(work, f"{name}_ambience.wav")
        run(["ffmpeg", "-y", "-stream_loop", "-1", "-i", os.path.join(SOUNDS, ambience[0]), "-t", f"{length:.3f}",
             "-filter_complex", f"[0]volume={ambience[1]:.3f}[out]", "-map", "[out]", out])
        parts.append(out)
    if len(parts) == 1:
        return parts[0]
    args, labels = ["ffmpeg", "-y"], []
    for index, part in enumerate(parts):
        args += ["-i", part]
        labels.append(f"[{index}]")
    final = os.path.join(work, f"{name}_mix.wav")
    run(args + ["-filter_complex", "".join(labels) + f"amix=inputs={len(parts)}:normalize=0:dropout_transition=0[out]", "-map", "[out]", "-t", f"{length:.3f}", final])
    return final


def with_sound(video, scene, lines, work, name):
    """The scene's video with its sounds mixed under it, or the video as it is."""
    length = duration(video)
    track = mix_sounds(scene, lines, length, work, name)
    if not track:
        return video
    out = os.path.join(work, name + ".mp4")
    run(["ffmpeg", "-y", "-i", video, "-i", track, "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", out])
    return out


def event_name(text):
    return text.split("(", 1)[0]


def field(text, name):
    match = re.search(r"\b" + name + r": ([^,)]+)", text)
    return match.group(1) if match else None


def scored_kind(text, scene):
    if field(text, "dunk") == "true":
        return "dunks"
    if field(text, "floater") == "true":
        return "floaters_glass" if "glass" in scene["scene"] else "floaters"
    points = field(text, "points")
    return "jumpshots_3pt" if points in ("3", "6") else "jumpshots"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    source = args[0] if args else (simulator_run() or CONTAINER)
    out = OUT
    if "--out" in sys.argv:
        out = sys.argv[sys.argv.index("--out") + 1]
    if not os.path.isdir(source):
        sys.exit(f"no footage at {source}")
    logs = sorted(f for f in os.listdir(source) if f.endswith(".jsonl"))
    if not logs:
        sys.exit(f"no logs in {source}")
    os.makedirs(out, exist_ok=True)
    work = os.path.join(out, ".work")
    os.makedirs(work, exist_ok=True)
    all_clips, scripted_clips, rows = [], [], []
    for log in logs:
        name = log[:-6]
        video = os.path.join(source, name + ".mp4")
        if not os.path.exists(video):
            print("no video for", name)
            continue
        with open(os.path.join(source, log)) as handle:
            lines = [json.loads(line) for line in handle if line.strip()]
        if not lines or "scene" not in lines[0]:
            continue
        scene, events = lines[0], [l for l in lines[1:] if "event" in l]
        video = with_sound(video, scene, lines[1:], work, name)
        length = duration(video)
        # A computer game kept whole, with its sound.
        if scene["cpu"]:
            dst = os.path.join(out, "games", name + ".mp4")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(video, dst)
            print("game  ", dst)
        # The whole scripted scene, trimmed to its action.
        if not scene["cpu"]:
            dst = os.path.join(out, "scenes", name + ".mp4")
            first = min((e["t"] for e in events), default=0.0)
            last = max((e["t"] for e in events), default=length)
            # The lead-up kept: a clash's exchange, Longball's run in.
            cut(video, first - 4.0, min(length, last + 2.5), dst)
            scripted_clips.append(dst)
            print("scene ", dst)
        # Windows by kind, merged where they run together.
        windows = {}
        for event in events:
            text = event["event"]
            kind = KINDS.get(event_name(text))
            if not kind:
                continue
            folder, before, after = kind
            if folder == "scores":
                folder = scored_kind(text, scene)
            if event_name(text) == "swatted" and field(text, "hit") != "true":
                continue
            windows.setdefault(folder, []).append([event["t"] - before, event["t"] + after, event["frame"]])
        for folder, spans in windows.items():
            spans.sort()
            merged = []
            for span in spans:
                if merged and span[0] <= merged[-1][1] + MERGE_GAP and span[1] - merged[-1][0] <= MAX_CLIP:
                    merged[-1][1] = max(merged[-1][1], span[1])
                else:
                    merged.append(span)
            for start, end, frame in merged:
                dst = os.path.join(out, folder, f"{name}_f{frame:05d}.mp4")
                cut(video, start, min(length, end), dst)
                all_clips.append(dst)
                rows.append((folder, name, frame, round(start, 2), round(end, 2)))
                print("clip  ", dst)
    # The list of clips and the mash-ups cover every run cut into the folder so far.
    csv = os.path.join(out, "clips.csv")
    kept = []
    if os.path.exists(csv):
        with open(csv) as handle:
            for line in handle.read().splitlines()[1:]:
                kind, scene, frame = line.split(",")[:3]
                if os.path.exists(os.path.join(out, kind, f"{scene}_f{int(frame):05d}.mp4")) and (kind, scene, int(frame)) not in {(r[0], r[1], r[2]) for r in rows}:
                    kept.append(line)
    with open(csv, "w") as handle:
        handle.write("kind,scene,frame,start,end\n")
        for line in kept:
            handle.write(line + "\n")
        for row in rows:
            handle.write(",".join(str(v) for v in row) + "\n")
    with open(csv) as handle:
        every = [line.split(",") for line in handle.read().splitlines()[1:]]
    every_clip = [os.path.join(out, kind, f"{scene}_f{int(frame):05d}.mp4") for kind, scene, frame, *_ in every]
    scenes_dir = os.path.join(out, "scenes")
    every_scene = sorted(os.path.join(scenes_dir, f) for f in os.listdir(scenes_dir) if f.endswith(".mp4")) if os.path.isdir(scenes_dir) else []
    concat(every_scene, os.path.join(out, "mashup_scripted.mp4"))
    if "--no-all" not in sys.argv:
        concat(every_clip, os.path.join(out, "mashup_all.mp4"))
    shutil.rmtree(work, ignore_errors=True)
    print(f"{len(all_clips)} clips, {len(scripted_clips)} scenes this run; {len(every_clip)} clips, {len(every_scene)} scenes in {out}")


if __name__ == "__main__":
    main()
