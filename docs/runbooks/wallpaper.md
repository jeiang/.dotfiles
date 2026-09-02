# Runbook: Wallpaper set

Operator runbook for the rotating wallpaper set on artemis and zakkart.
Review [`AGENTS.md`](../../AGENTS.md) before running any command here.

| Path | Role |
| --- | --- |
| `assets/wallpapers/` | pristine photos, the only thing you edit by hand |
| `assets/wallpapers-kanabox/` | what both hosts read; recolored or copied originals |
| `modules/nixos/hyprland/default.nix` | artemis: hyprpaper reads the directory, 30 min, random |
| `modules/darwin/preferences.nix` | zakkart: symlinks `~/Pictures/Wallpapers` to the directory |

`just wallpaper` recolors every image in `assets/wallpapers/` whose name is
missing from `assets/wallpapers-kanabox/`. Names already present are left
alone, so a photo kept in its original colors is just a copy.

## Add or replace photos

1. Downscale to 3840 px wide before committing; the repo carries the bytes
    forever. Fill in the original name on both commands:

    ```sh
    nix run nixpkgs#imagemagick -- IN.jpg -resize '3840x3840>' -quality 90 assets/wallpapers/NAME.jpg
    ```

2. `just wallpaper` to produce the recolor.
3. Compare, and decide per photo. The recolor flattens green foliage and
    kills blue flowers; warm, low-saturation night shots survive it well:

    ```sh
    nix run nixpkgs#imagemagick -- assets/wallpapers/NAME.jpg -resize 1000x assets/wallpapers-kanabox/NAME.jpg -resize 1000x +append /tmp/compare.jpg
    ```

4. To keep the original instead, overwrite the recolor:

    ```sh
    cp assets/wallpapers/NAME.jpg assets/wallpapers-kanabox/NAME.jpg
    ```

5. To remove a photo, delete it from both directories.
6. Commit both directories, deploy, then follow the two host sections below.

## Palette change

`just wallpaper` skips existing outputs, so delete the recolored ones first.
Originals kept as copies must be re-copied afterwards:

```sh
rm assets/wallpapers-kanabox/*.jpg
just wallpaper
```

Then re-copy any photo that is meant to stay original (step 4 above).

## artemis after a deploy

hjem only relinks `~/.config/hypr/hyprpaper.conf`; the running hyprpaper
keeps its old config and its old image list. Restart it from a shell on the
host, inside the session environment:

```sh
systemctl --user stop 'app-*-hyprpaper-*.scope'
export $(systemctl --user show-environment | grep -E '^(HYPRLAND_INSTANCE_SIGNATURE|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS)=' | xargs)
uwsm app -- hyprpaper </dev/null >/dev/null 2>&1 &
```

Check with a screenshot rather than logs; hyprpaper 0.8 has no `listloaded`:

```sh
nix run nixpkgs#grim -- -s 0.25 /tmp/wp-check.png
```

## zakkart after a switch

Activation moves the `~/Pictures/Wallpapers` symlink to the new store path.
macOS remembers the folder by path, so rotation normally continues. If it
stops, or the picker shows an empty folder, remove the folder entry in
System Settings > Wallpaper and redo step 8 of
[`zakkart-bootstrap.md`](zakkart-bootstrap.md).

## Do not try again

Every scripted route for zakkart was tested live on macOS 26 and failed:

- System Events `picture rotation` / `change interval` / `random order`
  return error -10000.
- System Events `set picture of every desktop` writes only the current
  Space, and running it deletes the all-Spaces entry that the "Show on all
  Spaces" toggle creates.
- Editing `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`
  directly made WallpaperAgent reset the entire store to factory defaults.

On artemis, `hyprctl hyprpaper reload` no longer exists in hyprpaper 0.8;
the directory `path` with `timeout` and `order` is the only rotation surface.
