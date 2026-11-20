print("frames \(frames.count), looks \(looks.count)")
if mode == "gpu" { runGPU() } else { runMaps() }
