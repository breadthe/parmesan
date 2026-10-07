#!/usr/bin/env python3
"""Generates the Parmesan app icon SVGs (Design/AppIcon.svg and Design/AppIcon-small.svg).

A wedge of Parmigiano-Reggiano, modelled as a triangular prism lying on one of its long sides, seen in
a three-quarter view from the front right and above: the triangular cut face towards the viewer, the point
towards the lower left, the thick rind end (slightly curved, like the wheel it came from) towards the
upper right. Each visible face is shaded by how much it faces a top-left light; cut faces use the paste
colours, the wide end the rind colours. A pile of grated shreds sits in front of the wedge (master art only), all on a
dark slate background that fills the icon shape edge to edge (see specs.md → App Icon).

Randomness (fracture, crystals, shreds, slate texture) comes from seeded generators, so the output is
the same on every run. Edit the numbers below and re-run:

    python3 Design/icon.py
    sips -s format png Design/AppIcon.svg --out Design/AppIcon-1024.png
    sips -s format png Design/AppIcon-small.svg --out Design/AppIcon-small.png
    scripts/make-icons.sh
"""
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))


def norm(v):
    length = math.sqrt(sum(c * c for c in v))
    return tuple(c / length for c in v)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def scale(a, k):
    return tuple(x * k for x in a)


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


# Camera: the direction towards the viewer (x right, y away from the viewer, z up), from the front right
# and above. The screen's right and up vectors follow from it; the light comes from the top left, a little
# in front.
VIEW = norm((0.42, -0.86, 0.46))
RIGHT = norm((-VIEW[1], VIEW[0], 0.0))
UP = cross(VIEW, RIGHT)
EX = (RIGHT[0], -UP[0])
EY = (RIGHT[1], -UP[1])
EZ = (RIGHT[2], -UP[2])
LIGHT = norm(add(add(scale(RIGHT, -0.75), scale(UP, 0.85)), scale(VIEW, 0.55)))

# Colours: (lit, shaded) for the cut paste and the rind (see specs.md → Materials & detail).
PASTE = ((0xF3, 0xE2, 0xA6), (0xE8, 0xCF, 0x82))
RIND = ((0xD9, 0xA5, 0x48), (0xB8, 0x86, 0x2F))
EDGE = "#8A6418"
SHRED = ((0xF7, 0xEB, 0xC0), (0xD9, 0xC2, 0x82))

# The wedge: radius (point to rind), the slice's angle, and its thickness (into the picture).
RADIUS, ANGLE, THICKNESS = 340, math.radians(31), 128
ARC_STEPS = 6
SEED = 1024


def project(p):
    x, y, z = p
    return (x * EX[0] + y * EY[0] + z * EZ[0], x * EX[1] + y * EY[1] + z * EZ[1])


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def hexcolor(c):
    return "#%02X%02X%02X" % tuple(max(0, min(255, round(v))) for v in c)


def shade(world_normal, pair, contrast=1.0):
    lit, dark = pair
    t = 1 - max(0.0, dot(world_normal, LIGHT))
    return mix(lit, dark, min(1.0, t * 1.25 * contrast))


class Polyhedron:
    """A convex solid: vertices and faces (vertex indices plus a material). Outward normals are found from
    the solid's centre, so faces can be listed in any winding."""

    def __init__(self, vertices, faces):
        self.vertices = vertices
        centre = scale(tuple(sum(v[c] for v in vertices) for c in range(3)), 1 / len(vertices))
        self.faces = []
        for idx, material in faces:
            a, b, c = (vertices[i] for i in idx[:3])
            normal = norm(cross(sub(b, a), sub(c, a)))
            face_centre = scale(tuple(sum(vertices[i][k] for i in idx) for k in range(3)), 1 / len(idx))
            if dot(normal, sub(face_centre, centre)) < 0:
                normal = scale(normal, -1)
            self.faces.append((idx, material, normal))

    def visible_faces(self):
        """Back-face culling: only faces turned towards the viewer."""
        return [(idx, m, n) for idx, m, n in self.faces if dot(n, VIEW) > 0.02]


def wedge():
    """The slice, lying on a long side: point at the origin, the rind an arc of the wheel at RADIUS.
    The triangular cut face is at y=0 (towards the viewer), the far one at y=THICKNESS."""
    arc = [(RADIUS * math.cos(ANGLE * i / ARC_STEPS), RADIUS * math.sin(ANGLE * i / ARC_STEPS)) for i in range(ARC_STEPS + 1)]
    front = [(0.0, 0.0, 0.0)] + [(x, 0.0, z) for x, z in arc]
    back = [(0.0, THICKNESS, 0.0)] + [(x, THICKNESS, z) for x, z in arc]
    v = front + back
    n = len(front)
    faces = [
        (list(range(n)), "front"),                       # the triangular cut face (paste)
        (list(range(n, 2 * n)), "far"),
        ([0, 1, n + 1, n], "bottom"),                    # lying on this one
        ([0, n - 1, 2 * n - 1, n], "top"),               # the upper long cut side (paste), catches the light
    ]
    for i in range(1, n - 1):
        faces.append(([i, i + 1, n + i + 1, n + i], "rind"))
    return Polyhedron(v, faces), dict(front=front, back=back)


def fit(points2d, box):
    xs, ys = [p[0] for p in points2d], [p[1] for p in points2d]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    bx, by, bw, bh = box
    k = min(bw / w, bh / h)
    ox = bx + (bw - w * k) / 2 - min(xs) * k
    oy = by + (bh - h * k) / 2 - min(ys) * k
    return lambda p: (ox + p[0] * k, oy + p[1] * k), k


def pts(points):
    return " ".join("%.1f,%.1f" % p for p in points)


def convex_hull(points):
    pts_ = sorted(set(points))
    if len(pts_) <= 2:
        return pts_
    cross2 = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts_:
        while len(lower) >= 2 and cross2(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts_):
        while len(upper) >= 2 and cross2(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def background(small, glow_center):
    """The dark slate field: Apple's icon grid shape (824x824 at 100,100, radius 185), edge to edge."""
    rng = random.Random(SEED + 7)
    texture, rays = "", ""
    if not small:
        # Faint slate grain: a few hundred tiny, very low-contrast flecks.
        flecks = []
        for _ in range(420):
            x, y = rng.uniform(100, 924), rng.uniform(100, 924)
            r = rng.uniform(1.2, 3.6)
            light = rng.random() < 0.5
            flecks.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" opacity="%.3f"/>'
                          % (x, y, r, "#FFFFFF" if light else "#000000", rng.uniform(0.015, 0.045)))
        texture = '<g clip-path="url(#shape)">%s</g>' % "".join(flecks)
        # Very faint radial "slices", like a sunburst etched into the slate.
        cx, cy = glow_center
        lines = []
        for i in range(24):
            a = 2 * math.pi * i / 24 + 0.07
            lines.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>'
                         % (cx, cy, cx + 900 * math.cos(a), cy + 900 * math.sin(a)))
        rays = ('<g clip-path="url(#shape)" stroke="#F3E2A6" stroke-opacity="0.028" stroke-width="3">%s</g>'
                % "".join(lines))
    gx, gy = glow_center
    return f'''  <defs>
    <linearGradient id="slate" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2A2724"/>
      <stop offset="1" stop-color="#161412"/>
    </linearGradient>
    <clipPath id="shape"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
    <filter id="glowBlur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="70"/></filter>
    <filter id="softShadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="18"/></filter>
    <filter id="contactShadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="5"/></filter>
    <filter id="tinyShadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.2"/></filter>
  </defs>
  <!-- Background: macOS icon grid shape, filled edge to edge -->
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#slate)"/>
  {texture}
  <!-- A soft warm glow behind the wedge -->
  <g clip-path="url(#shape)"><ellipse cx="{gx:.1f}" cy="{gy:.1f}" rx="300" ry="250" fill="#7A6646" opacity="{0.42 if not small else 0.4}" filter="url(#glowBlur)"/></g>
  {rays}
'''


def face_gradient(gid, poly, base):
    """A soft sheen across a face: lighter towards the top left, darker towards the bottom right."""
    a = min(poly, key=lambda p: p[0] + p[1])
    z = max(poly, key=lambda p: p[0] + p[1])
    return (f'    <linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{z[0]:.1f}" y2="{z[1]:.1f}">'
            f'<stop offset="0" stop-color="{hexcolor(mix(base, (255, 248, 222), 0.22))}"/>'
            f'<stop offset="1" stop-color="{hexcolor(mix(base, (150, 100, 20), 0.12))}"/></linearGradient>')


def render(small):
    rng = random.Random(SEED)
    solid, frame = wedge()
    front, back = frame["front"], frame["back"]

    # The grated pile sits on the ground in front of the wedge, towards its thick end.
    pile_center = (RADIUS * 0.86, -88.0, 0.0)
    pile_radius = 72

    outline = [project(p) for p in solid.vertices]
    if not small:
        for a in range(0, 360, 20):
            r = math.radians(a)
            outline.append(project(add(pile_center, (pile_radius * math.cos(r), pile_radius * math.sin(r), 0))))
    to_screen, k = fit(outline, (160, 190, 704, 640) if not small else (150, 175, 724, 674))
    P = lambda p: to_screen(project(p))

    glow = P(scale(add(front[0], add(front[1], front[-1])), 1 / 3))
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">',
           "  <!-- Generated by Design/icon.py. Edit that and re-run instead of editing this file. -->",
           background(small, glow)]

    # Ground shadows: a soft blurred pool and a tight contact shadow under the wedge's footprint.
    ground = convex_hull([P((v[0], v[1], 0)) for v in solid.vertices])
    out.append('  <g fill="#000000">')
    out.append('    <polygon points="%s" opacity="0.6" filter="url(#softShadow)" transform="translate(14,16)"/>' % pts(ground))
    out.append('    <polygon points="%s" opacity="0.9" filter="url(#contactShadow)" transform="translate(0,3)"/>' % pts(ground))
    out.append("  </g>")

    gradients, shapes = [], []
    contrast = 1.7 if small else 1.0
    faces = sorted(solid.visible_faces(), key=lambda f: dot(centroid(solid, f[0]), VIEW))
    for fi, (idx, material, normal) in enumerate(faces):
        poly = [P(solid.vertices[i]) for i in idx]
        base = shade(normal, RIND if material == "rind" else PASTE, contrast)
        if material == "top":
            base = mix(base, (255, 250, 228), 0.3 if small else 0.12)
        gid = f"f{fi}"
        gradients.append(face_gradient(gid, poly, base))
        # Rind segments get a hairline in their own colour so the joins between them don't show.
        seam = f' stroke="url(#{gid})" stroke-width="1.5"' if material == "rind" else ""
        shapes.append(f'    <polygon points="{pts(poly)}" fill="url(#{gid})"{seam}/>')
    shapes.append(rind_detail(front, back, P, small))
    if not small:
        shapes.append(paste_texture(front, back, P, rng))
        shapes.append(fracture(front, back, P, rng))

    # Outline, then a crisp highlight along the top-left edge and a warm rim light on the right and back.
    silhouette = convex_hull([P(v) for v in solid.vertices])
    shapes.append(f'    <polygon points="{pts([P(p) for p in front])}" fill="none" stroke="{EDGE}" stroke-width="{24 if small else 3}" '
                  f'stroke-linejoin="round" stroke-opacity="{0.9 if small else 0.45}"/>')
    shapes.append(f'    <polygon points="{pts(silhouette)}" fill="none" stroke="{EDGE}" stroke-width="{24 if small else 3}" '
                  f'stroke-linejoin="round" stroke-opacity="{0.9 if small else 0.55}"/>')
    shapes.append(f'    <polyline points="{pts([P(front[0]), P(front[-1]), P(back[-1])])}" fill="none" stroke="#FFF9E0" '
                  f'stroke-width="{8 if small else 3.5}" stroke-linecap="round" stroke-linejoin="round" stroke-opacity="{0.95 if small else 0.8}"/>')
    shapes.append(f'    <polyline points="{pts([P(p) for p in reversed(back[1:])])}" fill="none" stroke="#FFD27A" '
                  f'stroke-width="{7 if small else 3.5}" stroke-linecap="round" stroke-linejoin="round" stroke-opacity="0.6"/>')

    out.append("  <defs>\n" + "\n".join(gradients) + "\n  </defs>")
    out += shapes
    if not small:
        out.append(grated_pile(pile_center, pile_radius, P, k, rng))
    out.append("</svg>\n")
    return "\n".join(out)


def centroid(solid, idx):
    return scale(tuple(sum(solid.vertices[i][c] for i in idx) for c in range(3)), 1 / len(idx))


def on_front(r, a):
    """A point on the triangular cut face, in polar terms: distance from the point and angle."""
    return (r * math.cos(a), 0.0, r * math.sin(a))


def paste_texture(front, back, P, rng):
    """Tyrosine crystals (pale specks, denser towards the rind), small craters and a few darker pits, on
    the cut face and the top face."""
    marks = []
    top0, top1 = front[-1], back[-1]
    for i in range(300):
        on_top = i % 3 == 0
        # Biased towards the rind, where the crystals gather in an aged wheel.
        r = RADIUS * (0.08 + 0.86 * rng.random() ** 0.5)
        if on_top:
            s = r / RADIUS
            p = lerp(lerp(front[0], top0, s), lerp(back[0], top1, s), rng.uniform(0.06, 0.94))
        else:
            p = on_front(r, ANGLE * rng.uniform(0.04, 0.96))
        x, y = P(p)
        roll = rng.random()
        if roll < 0.6:
            radius = rng.uniform(1.3, 3.4)
            marks.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{radius:.1f}" fill="#FFFBEA" opacity="{rng.uniform(0.55, 0.95):.2f}"/>')
        elif roll < 0.88:
            # A small crater: a dark hollow with a pale lip below it.
            radius = rng.uniform(2.5, 6.0) * (0.8 if on_top else 1.0)
            marks.append(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{radius:.1f}" ry="{radius * 0.62:.1f}" fill="#B98E3A" opacity="{rng.uniform(0.25, 0.42):.2f}"/>'
                         f'<ellipse cx="{x + 0.6:.1f}" cy="{y + radius * 0.45:.1f}" rx="{radius * 0.8:.1f}" ry="{radius * 0.3:.1f}" fill="#FFF6D5" opacity="0.45"/>')
        else:
            radius = rng.uniform(1.0, 2.2)
            marks.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{radius:.1f}" fill="#8F6A22" opacity="{rng.uniform(0.35, 0.6):.2f}"/>')
    return "    " + "".join(marks)


def rind_detail(front, back, P, small):
    """The wide end: darker bands along its two edges, and faint dotted lettering (never readable)."""
    out = []
    for t0, t1 in ((0.0, 0.12), (0.88, 1.0)):
        band = [P(lerp(f, b, t0)) for f, b in zip(front[1:], back[1:])] + \
               [P(lerp(f, b, t1)) for f, b in reversed(list(zip(front[1:], back[1:])))]
        out.append(f'<polygon points="{pts(band)}" fill="#8C6420" opacity="{0.55 if small else 0.4}"/>')
    if not small:
        dots = []
        for row, t in enumerate((0.34, 0.5, 0.66)):
            for i in range(11):
                a = ANGLE * (0.1 + 0.8 * i / 10 + (0.04 if row % 2 else 0))
                if a > ANGLE * 0.93:
                    continue
                x, y = P((RADIUS * math.cos(a), THICKNESS * t, RADIUS * math.sin(a)))
                dots.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="2.7" fill="#7A5418" opacity="0.32"/>')
        out.append("".join(dots))
    return "    " + "".join(out)


def fracture(front, back, P, rng):
    """The thick end is broken, not cut: a jagged, chunky lip just inside the rind on the cut face and the
    top face, with flakes on the break, so it reads as aged hard cheese."""
    out = []
    # Cut face: points along the rind arc, jittered in towards the point.
    edge, inner = [], []
    steps = 18
    for i in range(steps + 1):
        a = ANGLE * i / steps
        edge.append(P(on_front(RADIUS, a)))
        depth = rng.uniform(8, 26) if 0 < i < steps else 3
        inner.append(P(on_front(RADIUS - depth, a)))
    out.append(f'<polygon points="{pts(edge + list(reversed(inner)))}" fill="#E0C26E" opacity="0.95"/>')
    out.append(f'<polyline points="{pts(inner)}" fill="none" stroke="#A9832F" stroke-width="2.4" stroke-opacity="0.7" stroke-linejoin="round"/>')
    # Top face: the same along its edge at the rind.
    edge, inner = [], []
    for i in range(9):
        t = i / 8
        edge.append(P(lerp(front[-1], back[-1], t)))
        depth = rng.uniform(6, 20) if 0 < i < 8 else 3
        inner.append(P(scale(lerp(front[-1], back[-1], t), (RADIUS - depth) / RADIUS)))
    out.append(f'<polygon points="{pts(edge + list(reversed(inner)))}" fill="#EAD38A" opacity="0.95"/>')
    out.append(f'<polyline points="{pts(inner)}" fill="none" stroke="#B08A38" stroke-width="2" stroke-opacity="0.6" stroke-linejoin="round"/>')
    # Chunky flakes standing proud of the cut face near the break.
    for _ in range(10):
        c = on_front(RADIUS - rng.uniform(22, 60), ANGLE * rng.uniform(0.1, 0.9))
        size = rng.uniform(5, 11)
        poly = []
        for j in range(5):
            a = 2 * math.pi * j / 5 + rng.uniform(-0.3, 0.3)
            r = size * rng.uniform(0.6, 1.1)
            poly.append(P(add(c, (r * math.cos(a), -1, r * math.sin(a)))))
        out.append(f'<polygon points="{pts(poly)}" fill="#F7EBBE" stroke="#B69142" stroke-width="1.2" stroke-opacity="0.65"/>')
    return "    " + "".join(out)


def grated_pile(center, radius, P, k, rng):
    """About 60 thin curled shreds in a loose mound, back to front, each with a tiny contact shadow."""
    strands = []
    for _ in range(96):
        r = radius * math.sqrt(rng.random())
        a = rng.uniform(0, 2 * math.pi)
        base = add(center, (r * math.cos(a), r * math.sin(a) * 0.8, 0))
        height = 62 * (1 - (r / radius) ** 2) * rng.uniform(0.65, 1.0)
        start = add(base, (0, 0, height))
        heading = rng.uniform(0, 2 * math.pi)
        length = rng.uniform(20, 38)
        end = add(start, (length * math.cos(heading), length * math.sin(heading), rng.uniform(-14, 6)))
        bend = add(lerp(start, end, 0.5), (rng.uniform(-14, 14), rng.uniform(-14, 14), rng.uniform(6, 18)))
        lit = rng.random() < 0.65
        strands.append((dot(lerp(start, end, 0.5), VIEW), start, bend, end, lit, base))
    strands.sort(key=lambda s: s[0])

    width = max(2.6, 3.4 * k)
    out = ["  <!-- Grated pile -->",
           # A soft occlusion pool under the whole mound.
           f'  <ellipse cx="{P(center)[0]:.1f}" cy="{P(center)[1] + 6:.1f}" rx="{radius * k * 1.05:.1f}" ry="{radius * k * 0.42:.1f}" '
           f'fill="#000000" opacity="0.55" filter="url(#softShadow)"/>',
           "  <g fill=\"none\" stroke-linecap=\"round\">"]
    for _, start, bend, end, lit, base in strands:
        (sx, sy), (bx, by), (ex, ey) = P(start), P(bend), P(end)
        out.append(f'    <path d="M{sx:.1f},{sy + 3:.1f} Q{bx:.1f},{by + 3:.1f} {ex:.1f},{ey + 3:.1f}" stroke="#2A1E0C" '
                   f'stroke-width="{width + 1.5:.1f}" stroke-opacity="0.45" filter="url(#tinyShadow)"/>')
        colour = SHRED[0] if lit else SHRED[1]
        out.append(f'    <path d="M{sx:.1f},{sy:.1f} Q{bx:.1f},{by:.1f} {ex:.1f},{ey:.1f}" stroke="{hexcolor(colour)}" stroke-width="{width:.1f}"/>')
        # A highlight along each strand.
        out.append(f'    <path d="M{sx:.1f},{sy - 1:.1f} Q{bx:.1f},{by - 1.5:.1f} {ex:.1f},{ey - 1:.1f}" stroke="#FFFDF2" '
                   f'stroke-width="{width * 0.32:.1f}" stroke-opacity="{0.7 if lit else 0.35}"/>')
    out.append("  </g>")
    return "\n".join(out)


if __name__ == "__main__":
    for name, small in (("AppIcon.svg", False), ("AppIcon-small.svg", True)):
        with open(os.path.join(HERE, name), "w") as f:
            f.write(render(small))
        print("wrote", name)
