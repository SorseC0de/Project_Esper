#!/usr/bin/env python3
"""Make a campaign clip from a footage recording: a 1360x1020 MP4 with its sound, and a 1360x1020 GIF
with the corner cutouts, into _Graphic Assets/_Kickstarter Campaign/: twice Kickstarter's 680 column,
so a retina screen shows it pixel for pixel.

    ./Tools/clip.py <recording.mp4> <name> [--from S] [--to S] [--follow path.txt] [--share 0.5] [--out folder] [--scaled WxH] [--mute a,b]

The recording is a footage run's NN_scene.mp4, its NN_scene.jsonl beside it (for the sound and the
frame clock). The clip is cut from the recording at 1:1, never rescaled, so the art's pixels stay
whole: a 1360x1020 window, centred down, at `--share` across, or following `--follow`, the probe's
`path` output (scene frame, ball x, then each player's x), on the middle of the ball and the players,
smoothed. A recording too small for that is framed 4:3 at its full height and scaled to size.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import highlights  # noqa: E402

CAMPAIGN = os.path.join(os.path.dirname(HERE), "_Graphic Assets", "_Kickstarter Campaign")
WIDTH, HEIGHT = 1360, 1020
GIF_FPS = 24
# Where each stage sits across a 1920-wide recording: its left edge in pixels, and its width in sim units
# over the pixels it spans. K&A fills the width; Wreck Center's walls stand 100 in from each side.
STAGE_FRAMES = {"kAndA": (0.0, 370.0, 1920.0), "wreckCenter": (100.0, 340.0, 1720.0)}
# Frames either side the pan's averaged over.
PAN_SMOOTHING = 45


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


def probe_size(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout.strip()
    width, height = out.split(",")
    return int(width), int(height)


def corner_mask(work, width, height):
    """The GIF's alpha: opaque but where the corner art is, flush in the bottom left and top right.
    The corners are drawn for an 800-wide clip and scale with it. The overlays work in RGB: in
    ffmpeg's default YUV they snap to even pixels, which left an odd placement a pixel short of flush."""
    corner = round(100 * width / 800)
    mask = os.path.join(work, "mask.png")
    filters = (f"color=white:s={width}x{height},format=rgb24[ground];"
               f"[0]scale={corner}:{corner}:flags=lanczos,format=rgba,alphaextract,negate,format=rgb24[bl];"
               f"[1]scale={corner}:{corner}:flags=lanczos,format=rgba,alphaextract,negate,format=rgb24[tr];"
               f"[ground][bl]overlay=0:{height - corner}:format=rgb[half];[half][tr]overlay={width - corner}:0:format=rgb,format=gray")
    ffmpeg("-i", os.path.join(CAMPAIGN, "corner_bl.png"), "-i", os.path.join(CAMPAIGN, "corner_tr.png"),
           "-filter_complex", filters, "-frames:v", "1", mask)
    return mask


def pan_commands(path, lines, video_width, window, stage_frame, start, fps, out):
    """The window's left edge over time, as ffmpeg sendcmd lines, from the probe's path."""
    rows = []
    for line in open(path):
        parts = line.split()
        if len(parts) >= 3 and parts[0].isdigit():
            xs = [float(v) for v in parts[1:]]
            rows.append((int(parts[0]), (min(xs) + max(xs)) / 2))
    # A logged event ties the scene's frames to the video's time.
    events = [l for l in lines if "event" in l and "frame" in l]
    if not events:
        sys.exit("no events in the log to line the path up with the video")
    offset = events[0]["t"] - events[0]["frame"] / 60
    left_edge, stage_width, stage_pixels = (value * video_width / 1920 if index != 1 else value for index, value in enumerate(stage_frame))
    scale = stage_pixels / stage_width
    lefts = [min(max(left_edge + x * scale - window / 2, 0), video_width - window) for _, x in rows]
    smooth = [sum(lefts[max(0, i - PAN_SMOOTHING): i + PAN_SMOOTHING + 1]) / len(lefts[max(0, i - PAN_SMOOTHING): i + PAN_SMOOTHING + 1]) for i in range(len(lefts))]
    first_frame = rows[0][0]
    with open(out, "w") as handle:
        step = 0
        while True:
            t = step / fps
            frame = round((start + t - offset) * 60)
            index = min(max(frame - first_frame, 0), len(smooth) - 1)
            handle.write(f"{t:.4f} crop@pan x {int(round(smooth[index] / 2)) * 2};\n")
            step += 1
            if index == len(smooth) - 1 and frame - first_frame > len(smooth) + fps:
                break


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("recording")
    parser.add_argument("name")
    parser.add_argument("--from", dest="start", type=float, default=0.0)
    parser.add_argument("--to", dest="end", type=float)
    parser.add_argument("--follow")
    parser.add_argument("--share", type=float, default=0.5)
    parser.add_argument("--out", default=CAMPAIGN)
    parser.add_argument("--mute", default="", help="sounds left out of the mix, by name: a scene start's leftovers")
    parser.add_argument("--scaled", help="WxH: framed 4:3 at the recording's full height and scaled to this, as the 680-wide clips were")
    args = parser.parse_args()
    width, height = (int(v) for v in args.scaled.split("x")) if args.scaled else (WIDTH, HEIGHT)

    log = args.recording[:-4] + ".jsonl"
    with open(log) as handle:
        lines = [json.loads(line) for line in handle if line.strip()]
    scene = lines[0]
    work = tempfile.mkdtemp(prefix="clip_")
    try:
        muted = set(filter(None, args.mute.split(",")))
        mixed = highlights.with_sound(args.recording, scene, [l for l in lines[1:] if l.get("sound") not in muted], work, "mixed")
        end = args.end if args.end is not None else highlights.duration(mixed)
        length = end - args.start
        video_width, video_height = probe_size(args.recording)
        whole = not args.scaled and video_width >= width and video_height >= height
        window, window_height = (width, height) if whole else (video_height * 4 // 3, video_height)
        top = (video_height - window_height) // 2
        resize = "" if whole else f",scale={width}:{height}:flags=lanczos"
        if video_width > window:
            if args.follow:
                stage_frame = STAGE_FRAMES.get(scene["stage"])
                if stage_frame is None:
                    sys.exit(f"no frame for {scene['stage']} in STAGE_FRAMES")
                commands = {fps: os.path.join(work, f"pan{fps}.cmd") for fps in (60, GIF_FPS)}
                for fps, out in commands.items():
                    pan_commands(args.follow, lines, video_width, window, stage_frame, args.start, fps, out)
                frame = {fps: f"sendcmd=f='{out}',crop@pan={window}:{window_height}:0:{top}" for fps, out in commands.items()}
            else:
                left = int((video_width - window) * args.share) // 2 * 2
                frame = {fps: f"crop={window}:{window_height}:{left}:{top}" for fps in (60, GIF_FPS)}
        else:
            frame = {fps: f"crop={video_width}:{window_height}:0:{top}" for fps in (60, GIF_FPS)}

        mp4 = os.path.join(args.out, args.name + ".mp4")
        ffmpeg("-ss", f"{args.start:.3f}", "-i", mixed, "-t", f"{length:.3f}",
               "-vf", f"{frame[60]}{resize}",
               "-c:v", "libx264", "-crf", "14", "-preset", "slow", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", mp4)

        frames = os.path.join(work, "frames")
        os.makedirs(frames)
        mask = corner_mask(work, width, height)
        ffmpeg("-ss", f"{args.start:.3f}", "-i", args.recording, "-loop", "1", "-t", f"{length:.3f}", "-i", mask, "-filter_complex",
               f"[0:v]fps={GIF_FPS},{frame[GIF_FPS]}{resize},format=rgba[v];[1:v]fps={GIF_FPS},format=gray[m];[v][m]alphamerge=shortest=1",
               "-t", f"{length:.3f}", os.path.join(frames, "f%05d.png"))
        gif = os.path.join(args.out, args.name + ".gif")
        pictures = sorted(os.path.join(frames, f) for f in os.listdir(frames))
        # gifski shrinks to about 800x600 unless told the size.
        subprocess.run(["gifski", "--fps", str(GIF_FPS), "--quality", "100", "--extra", "--width", str(width), "--height", str(height), "-o", gif, *pictures],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for path in (mp4, gif):
            print(f"{path}  {os.path.getsize(path) / 1e6:.1f} MB")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
