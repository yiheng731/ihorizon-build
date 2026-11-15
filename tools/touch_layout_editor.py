"""Drag the touch controls where you want them, drawn with the same sprites the game uses.

Run it with `touch_layout_editor.bat` (double click) or `python touch_layout_editor.py`.
Drag a control to move it, use the sliders to size them, then press save. The file it
writes, `touch_layout.json`, is exactly what the client reads from its Documents folder,
and it is also what gets baked into the next ipa.

Coordinates are shares of the screen (0..1), so the layout lands in the same place on
any iPhone; sizes are GUI units, the same unit the game's own interface is measured in.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import tkinter as tk
from tkinter import ttk

try:
    from PIL import Image, ImageTk
except ImportError:
    Image = None
    ImageTk = None

PHYSICAL = (1792, 828)
GUI = (598, 276)

BUTTONS = ["jump", "sneak", "attack", "place", "inventory", "chat", "pause"]

SPRITE = {
    "jump": "jump",
    "sneak": "sneak",
    "attack": "attack",
    "place": "use",
    "inventory": "inventory",
    "chat": "chat",
    "pause": "pause",
}

HERE = Path(__file__).resolve().parent
TEXTURES = HERE.parent / "dist/resources/assets/minecraft/textures/gui/sprites/horizon/touch"

DEFAULT = {
    "button_size": 44,
    "stick_size": 120,
    "knob_size": 56,
    "stick": [0.087, 0.812],
    "hotbar": [0.5, 1.0],
    "look_from": 0.34,
    "debug": False,
    "edit": False,
    "buttons_size": {},
    "buttons": {
        "jump": [0.947, 0.877],
        "sneak": [0.947, 0.696],
        "attack": [0.863, 0.877],
        "place": [0.863, 0.696],
        "inventory": [0.947, 0.515],
        "chat": [0.863, 0.515],
        "pause": [0.947, 0.333],
    },
}

OUT = HERE / "touch_layout.json"

BACKGROUND = HERE / "background.jpg"

class Sprites:
    """Loads the mod's PNGs once and hands out copies sized for the canvas."""

    def __init__(self) -> None:
        self.background = None
        self.cache: dict[tuple[str, int], object] = {}
        self.missing: set[str] = set()

    def backdrop(self, width: int, height: int):
        """The phone screenshot, sized to the canvas; None when there is no file."""
        if Image is None or ImageTk is None or not BACKGROUND.exists():
            return None
        key = (str(BACKGROUND), width, height)
        if key in self.cache:
            return self.cache[key]
        image = Image.open(BACKGROUND).convert("RGB").resize((width, height), Image.LANCZOS)
        photo = ImageTk.PhotoImage(image)
        self.cache[key] = photo
        return photo

    def get(self, name: str, size: int):
        if Image is None or ImageTk is None:
            return None
        key = (name, size)
        if key in self.cache:
            return self.cache[key]
        path = TEXTURES / f"{name}.png"
        if not path.exists():
            self.missing.add(name)
            return None
        image = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
        photo = ImageTk.PhotoImage(image)
        self.cache[key] = photo
        return photo

class Editor:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        root.title("Horizon touch layout")
        self.data = json.loads(json.dumps(DEFAULT))
        self.adjusting = False
        self.ratio = DEFAULT["knob_size"] / DEFAULT["stick_size"]
        if OUT.exists():
            try:
                self.data.update(json.loads(OUT.read_text(encoding="utf-8")))
            except json.JSONDecodeError as error:
                print(f"ignoring {OUT.name}: {error}", file=sys.stderr)

        self.ratio = (self.data["knob_size"] / self.data["stick_size"]) if self.data["stick_size"] else 0.4667
        self.scale = 0.5
        self.canvas_w = int(PHYSICAL[0] * self.scale)
        self.canvas_h = int(PHYSICAL[1] * self.scale)
        self.sprites = Sprites()
        self.canvas = tk.Canvas(
            root, width=self.canvas_w, height=self.canvas_h, bg="#7d9fc4", highlightthickness=0
        )
        self.canvas.pack(side=tk.TOP, padx=8, pady=8)

        nudges = ttk.Frame(root)
        nudges.pack(side=tk.TOP, fill=tk.X, padx=8, pady=(6, 0))
        ttk.Label(nudges, text="nudge").pack(side=tk.LEFT)
        for label, dx, dy in (("left", -1, 0), ("right", 1, 0), ("up", 0, -1), ("down", 0, 1)):
            ttk.Button(
                nudges, text=label, width=6, command=lambda a=dx, b=dy: self.nudge(a, b)
            ).pack(side=tk.LEFT, padx=2)
        self.step = tk.StringVar(value="0.002")
        ttk.Label(nudges, text="step").pack(side=tk.LEFT, padx=(10, 2))
        ttk.Spinbox(
            nudges, from_=0.001, to=0.05, increment=0.001, width=7, textvariable=self.step
        ).pack(side=tk.LEFT)
        ttk.Label(nudges, text="(or use the arrow keys)").pack(side=tk.LEFT, padx=8)

        bar = ttk.Frame(root)
        bar.pack(side=tk.TOP, fill=tk.X, padx=8)
        self.size = self._slider(bar, "button", 16, 96, self.data["button_size"])
        self.stick = self._slider(bar, "stick", 40, 220, self.data["stick_size"])
        self.knob = self._slider(bar, "knob", 16, 160, self.data["knob_size"])
        for name, var in (("button", self.size), ("stick", self.stick), ("knob", self.knob)):
            var.trace_add("write", lambda *_a, n=name, v=var: self.typed(n, v))

        foot = ttk.Frame(root)
        foot.pack(side=tk.TOP, fill=tk.X, padx=8, pady=8)
        ttk.Button(foot, text="save", command=self.save).pack(side=tk.LEFT)
        ttk.Button(foot, text="reset", command=self.reset).pack(side=tk.LEFT, padx=6)
        self.grid = tk.BooleanVar(value=True)
        self.linked = tk.BooleanVar(value=True)
        ttk.Checkbutton(foot, text="grid", variable=self.grid, command=self.draw).pack(side=tk.LEFT, padx=6)
        ttk.Checkbutton(
            foot, text="stick scales together", variable=self.linked, command=self.relink
        ).pack(side=tk.LEFT, padx=6)
        self.note = ttk.Label(foot, text="click a button to size it, drag to move it")
        self.note.pack(side=tk.LEFT, padx=12)

        self.drag: str | None = None
        self.picked: str | None = None
        root.bind("<Left>", lambda _e: self.nudge(-1, 0))
        root.bind("<Right>", lambda _e: self.nudge(1, 0))
        root.bind("<Up>", lambda _e: self.nudge(0, -1))
        root.bind("<Down>", lambda _e: self.nudge(0, 1))
        self.canvas.bind("<ButtonPress-1>", self.press)
        self.canvas.bind("<B1-Motion>", self.motion)
        self.canvas.bind("<ButtonRelease-1>", self.release)
        self.draw()

    def _slider(self, parent: ttk.Frame, name: str, low: int, high: int, value: float) -> tk.IntVar:
        var = tk.IntVar(value=int(value))
        ttk.Label(parent, text=name).pack(side=tk.LEFT)
        ttk.Scale(
            parent,
            from_=low,
            to=high,
            variable=var,
            length=110,
            command=lambda _v, v=var, n=name: self.sized(n, v),
        ).pack(side=tk.LEFT, padx=(2, 4))
        spin = ttk.Spinbox(
            parent, from_=low, to=high, width=5, textvariable=var,
            command=lambda v=var, n=name: self.sized(n, v),
        )
        spin.pack(side=tk.LEFT, padx=(0, 10))
        spin.bind("<Return>", lambda _e, v=var, n=name: self.sized(n, v))
        spin.bind("<FocusOut>", lambda _e, v=var, n=name: self.sized(n, v))
        return var

    def sized(self, name: str, var: tk.IntVar) -> None:
        if self.adjusting:
            return
        try:
            value = int(var.get())
        except (tk.TclError, ValueError):
            return
        if name == "button" and self.picked:
            self.data.setdefault("buttons_size", {})[self.picked] = value
            self.note.config(text=f"{self.picked} {value} units · {self.px_of(value):.0f} px here · others unchanged")
        elif name in ("stick", "knob") and self.linked.get():
            self.scale_stick(name, value)
        else:
            self.data[f"{name}_size"] = value
            self.note.config(text=f"{name} {value} units · {self.px_of(value):.0f} px here")
        self.draw()

    def nudge(self, dx: int, dy: int) -> None:
        """Move the picked control by one step along one axis."""
        if not self.picked:
            self.note.config(text="pick a control first, then nudge it")
            return
        try:
            step = abs(float(self.step.get()))
        except (tk.TclError, ValueError):
            step = 0.002
        if self.picked == "stick":
            place = list(self.data["stick"])
        elif self.picked == "hotbar":
            place = list(self.data["hotbar"])
        else:
            place = list(self.data["buttons"][self.picked])
        place[0] = round(min(max(place[0] + dx * step, 0.0), 1.0), 4)
        place[1] = round(min(max(place[1] + dy * step, 0.0), 1.0), 4)
        if self.picked == "stick":
            self.data["stick"] = place
        elif self.picked == "hotbar":
            self.data["hotbar"] = place
        else:
            self.data["buttons"][self.picked] = place
        self.note.config(text=f"{self.picked} at {place[0]:.3f}, {place[1]:.3f}")
        self.draw()

    def relink(self) -> None:
        """Pin the ratio that was on screen when the box was ticked."""
        pad = self.data["stick_size"]
        self.ratio = (self.data["knob_size"] / pad) if pad else 0.4667

    def scale_stick(self, name: str, value: int) -> None:
        """Grow the pad and the knob by one ratio, so they stay the same shape."""
        if name == "stick":
            pad = value
            knob = int(round(value * self.ratio))
        else:
            knob = value
            pad = int(round(value / self.ratio)) if self.ratio else value
        pad = min(max(pad, 40), 220)
        knob = min(max(knob, 16), 160)
        self.data["stick_size"] = pad
        self.data["knob_size"] = knob
        self.adjusting = True
        try:
            self.stick.set(pad)
            self.knob.set(knob)
        finally:
            self.adjusting = False
        self.note.config(text=f"stick {pad} / knob {knob} units (ratio {self.ratio:.2f})")

    def typed(self, name: str, var: tk.IntVar) -> None:
        """A number typed into the box, as opposed to a slider drag."""
        try:
            value = int(var.get())
        except (tk.TclError, ValueError):
            return
        self.sized(name, var)

    def px_of(self, gui_units: float) -> float:
        return self.side_px(gui_units)

    def px(self, share: list[float]) -> tuple[float, float]:
        x, y = share
        return x * PHYSICAL[0] * self.scale, y * PHYSICAL[1] * self.scale

    def side_px(self, gui_units: float) -> float:
        """GUI units to canvas pixels: the game's interface is 598 units wide."""
        return gui_units / GUI[0] * PHYSICAL[0] * self.scale

    def side_of(self, name: str) -> int:
        sizes = self.data.get("buttons_size") or {}
        return int(round(self.side_px(sizes.get(name, self.data["button_size"]))))

    def rect_of(self, name: str) -> tuple[float, float, float, float]:
        cx, cy = self.px(self.data["buttons"][name])
        half = self.side_of(name) / 2
        return cx - half, cy - half, cx + half, cy + half

    def stick_rect(self) -> tuple[float, float, float, float]:
        cx, cy = self.px(self.data["stick"])
        half = self.side_px(self.data["stick_size"]) / 2
        return cx - half, cy - half, cx + half, cy + half

    def hotbar_rect(self) -> tuple[float, float, float, float]:
        cx, cy = self.px(self.data["hotbar"])
        half = self.side_px(182) / 2
        height = self.side_px(22)
        return cx - half, cy - height, cx + half, cy

    def draw(self) -> None:
        c = self.canvas
        c.delete("all")
        shot = self.sprites.backdrop(self.canvas_w, self.canvas_h)
        if shot is None:
            horizon = self.canvas_h * 0.55
            c.create_rectangle(0, 0, self.canvas_w, horizon, fill="#8fb6e8", outline="")
            c.create_rectangle(0, horizon, self.canvas_w, self.canvas_h, fill="#6b8f45", outline="")
        else:
            c.create_image(0, 0, image=shot, anchor="nw")
        look = self.data["look_from"]
        c.create_rectangle(
            look * self.canvas_w, 0, self.canvas_w, self.canvas_h, fill="", outline="#b9c6d6",
        )

        if self.grid.get():
            for step in range(1, 10):
                share = step / 10
                colour = "#dfe6ee" if step in (1, 5, 9) else "#a8b7c6"
                c.create_line(share * self.canvas_w, 0, share * self.canvas_w, self.canvas_h, fill=colour)
                c.create_line(0, share * self.canvas_h, self.canvas_w, share * self.canvas_h, fill=colour)

        x0, y0, x1, y1 = self.hotbar_rect()
        c.create_rectangle(x0, y0, x1, y1, outline="#2f2f2f", fill="#4a4a4a")

        pad = self.sprites.get("pad", int(round(self.side_px(self.data["stick_size"]))))
        x0, y0, x1, y1 = self.stick_rect()
        if pad is None:
            c.create_oval(x0, y0, x1, y1, outline="#f0f0f0", fill="#2c3a2c", width=2)
        else:
            c.create_image((x0 + x1) / 2, (y0 + y1) / 2, image=pad)
        knob = self.sprites.get("stick", int(round(self.side_px(self.data["knob_size"]))))
        cx, cy = self.px(self.data["stick"])
        if knob is None:
            half = self.side_px(self.data["knob_size"]) / 2
            c.create_oval(cx - half, cy - half, cx + half, cy + half, fill="#d8d8e0")
        else:
            c.create_image(cx, cy, image=knob)

        for name in BUTTONS:
            size = self.side_of(name)
            x0, y0, x1, y1 = self.rect_of(name)
            art = self.sprites.get(SPRITE[name], size)
            if art is None:
                c.create_rectangle(x0, y0, x1, y1, fill="#1c1c22", outline="#f0f0f4", width=2)
                c.create_text((x0 + x1) / 2, (y0 + y1) / 2, text=name, fill="#f0f0f4", font=("Consolas", 8))
            else:
                c.create_image((x0 + x1) / 2, (y0 + y1) / 2, image=art)
                if self.drag == name or (self.drag is None and self.picked == name):
                    c.create_rectangle(x0, y0, x1, y1, outline="#ffd54a", width=2)
            if self.drag == name:
                share = self.data["buttons"][name]
                c.create_text(
                    (x0 + x1) / 2, y0 - 7, fill="#ffd54a", font=("Consolas", 7),
                    text=f"{name} {share[0]:.3f},{share[1]:.3f}",
                )

        if self.sprites.missing:
            c.create_text(
                8, 8, anchor="nw", fill="#ffd54a", font=("Consolas", 8),
                text="no sprite for: " + ", ".join(sorted(self.sprites.missing)),
            )

    def hit(self, x: float, y: float) -> str | None:
        for name in BUTTONS:
            x0, y0, x1, y1 = self.rect_of(name)
            if x0 <= x <= x1 and y0 <= y <= y1:
                return name
        x0, y0, x1, y1 = self.stick_rect()
        if x0 <= x <= x1 and y0 <= y <= y1:
            return "stick"
        x0, y0, x1, y1 = self.hotbar_rect()
        if x0 <= x <= x1 and y0 <= y <= y1:
            return "hotbar"
        return None

    def press(self, event: tk.Event) -> None:
        self.drag = self.hit(event.x, event.y)
        if self.drag in BUTTONS or self.drag in ("stick", "hotbar"):
            self.picked = self.drag
            self.size.set(int(round((self.data.get("buttons_size") or {}).get(self.drag, self.data["button_size"]))))
            self.note.config(text=f"{self.drag} picked: nudge it or size it")

    def motion(self, event: tk.Event) -> None:
        if self.drag is None:
            return
        x = min(max(event.x / (PHYSICAL[0] * self.scale), 0.0), 1.0)
        y = min(max(event.y / (PHYSICAL[1] * self.scale), 0.0), 1.0)
        share = [round(x, 3), round(y, 3)]
        if self.drag == "stick":
            self.data["stick"] = share
        elif self.drag == "hotbar":
            self.data["hotbar"] = share
        else:
            self.data["buttons"][self.drag] = share
        self.note.config(text=f"{self.drag} at {share[0]:.3f}, {share[1]:.3f}")
        self.draw()

    def release(self, _event: tk.Event) -> None:
        if self.drag is not None:
            self.drag = None
            self.save(quiet=True)
            self.draw()

    def reset(self) -> None:
        self.data = json.loads(json.dumps(DEFAULT))
        self.size.set(self.data["button_size"])
        self.stick.set(self.data["stick_size"])
        self.knob.set(self.data["knob_size"])
        self.draw()

    def save(self, quiet: bool = False) -> None:
        OUT.write_text(json.dumps(self.data, indent=2) + "\n", encoding="utf-8")
        if not quiet:
            self.note.config(text=f"saved {OUT.name}")
        print(json.dumps(self.data, indent=2))

def selftest() -> int:
    """No window: round-trip a copy, so the format is checkable without touching the real file."""
    probe = OUT.with_name("touch_layout.selftest.json")
    probe.write_text(json.dumps(DEFAULT, indent=2) + "\n", encoding="utf-8")
    back = json.loads(probe.read_text(encoding="utf-8"))
    assert back["buttons"].keys() == set(BUTTONS), back["buttons"].keys()
    assert 0.0 <= back["stick"][0] <= 1.0 and 0.0 <= back["stick"][1] <= 1.0
    for name, (x, y) in back["buttons"].items():
        assert 0.0 <= x <= 1.0 and 0.0 <= y <= 1.0, (name, x, y)
    found = sum((TEXTURES / f"{name}.png").exists() for name in set(SPRITE.values()) | {"pad", "stick"})
    probe.unlink(missing_ok=True)
    print(f"ok: selftest with {len(back['buttons'])} buttons, {found} sprites found in {TEXTURES}")
    return 0 if found == 9 else int(bool(sys.stderr.write(f"some sprites are missing under {TEXTURES}\n")))

def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    root = tk.Tk()
    Editor(root)
    root.mainloop()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
