import os
import subprocess

def make_icns(source_png, output_icns):
    iconset_dir = "AppIcon.iconset"
    if not os.path.exists(iconset_dir):
        os.makedirs(iconset_dir)
    
    # Standard sizes
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]
    
    for size, name in sizes:
        path = os.path.join(iconset_dir, name)
        # Use sips to resize and force sRGB/PNG
        cmd = [
            "sips", "-z", str(size), str(size),
            source_png, "--out", path,
            "-s", "format", "png"
        ]
        subprocess.run(cmd, check=True, capture_output=True)
    
    # Run iconutil
    print(f"Converting {iconset_dir} to {output_icns}...")
    result = subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", output_icns], capture_output=True, text=True)
    
    if result.returncode == 0 and os.path.exists(output_icns):
        print("✅ Success!")
        return True
    else:
        print(f"❌ Failed: {result.stderr}")
        return False

if __name__ == "__main__":
    make_icns("AppIcon.png", "AppIcon.icns")
