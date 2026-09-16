"""Generate the cave's rock asset set in Blender, headless.

Run:  blender --background --python tools/gen_rocks.py
Out:  assets/models/*.glb  and  tools/preview/*.png

Every piece is built from a primitive plus displacement driven by procedural texture, so
there is no source art to licence or credit and the whole set regenerates from this file.

Poly budgets are deliberately small. These are placed by MultiMesh in their hundreds, and
the cave already draws ~250 wall slabs, so each piece is decimated to a target it can
afford at that count.
"""

import math
import os
import sys

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models")
PREVIEW = os.path.join(ROOT, "tools", "preview")


# --------------------------------------------------------------------------- helpers

def wipe():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.textures, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def noise_texture(name, kind, size, depth=2, seed=0):
    """A legacy texture datablock, which is what the Displace modifier consumes."""
    tex = bpy.data.textures.new(name, type=kind)
    tex.noise_scale = size
    if hasattr(tex, "noise_depth"):
        tex.noise_depth = depth
    if hasattr(tex, "noise_basis"):
        tex.noise_basis = "VORONOI_F2_F1" if seed % 2 else "BLENDER_ORIGINAL"
    return tex


def displace(obj, tex, strength, mid=0.5):
    m = obj.modifiers.new(name="Displace_" + tex.name, type="DISPLACE")
    m.texture = tex
    m.strength = strength
    m.mid_level = mid
    return m


def decimate(obj, faces):
    """Collapse down to roughly a face budget."""
    current = len(obj.data.polygons)
    if current <= faces:
        return
    m = obj.modifiers.new(name="Decimate", type="DECIMATE")
    m.decimate_type = "COLLAPSE"
    m.ratio = max(0.05, float(faces) / float(current))


def bake(obj):
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError as err:
            print("  skipped modifier %s: %s" % (m.name, err))


def unwrap(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    try:
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    except RuntimeError:
        bpy.ops.uv.cube_project(cube_size=1.0)
    bpy.ops.object.mode_set(mode="OBJECT")


def finish(obj, name, faces, smooth=True):
    decimate(obj, faces)
    bake(obj)
    unwrap(obj)
    if smooth:
        # Blender 4.1 removed mesh.use_auto_smooth in favour of a Smooth by Angle
        # modifier, so only touch it on versions that still have it.
        bpy.ops.object.shade_smooth()
        if hasattr(obj.data, "use_auto_smooth"):
            obj.data.use_auto_smooth = True
    obj.name = name
    obj.data.name = name
    return obj


def export(obj, name):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(MODELS, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_materials="NONE")
    print("  wrote %s  (%d tris)" % (os.path.basename(path), len(obj.data.polygons)))


# --------------------------------------------------------------------------- assets

def boulder(index):
    """An irregular rock chunk. Two displacement passes: large lobes, then surface grit.

    Displacement strength has to stay small relative to the object's own size. At 0.55 on a
    radius-1 sphere the first attempt produced spiky crumpled stars rather than rocks; a
    rock is mostly convex with gentle large-scale variation, so the lobes run shallow and
    wide and the grit is barely there.
    """
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0)
    obj = bpy.context.active_object
    displace(obj, noise_texture("lobe%d" % index, "DISTORTED_NOISE", 1.9, 2, index), 0.17)
    displace(obj, noise_texture("grit%d" % index, "CLOUDS", 0.55, 2, index + 7), 0.05)
    obj.scale = (1.0, 0.72 + 0.18 * (index % 3), 0.86 + 0.12 * (index % 2))
    bpy.ops.object.transform_apply(scale=True)
    return finish(obj, "boulder_%02d" % index, 220)


def wall_panel(index):
    """A displaced slab that fronts a flat wall face so the cave stops reading as boxes.

    Solidify runs BEFORE the displacement. Thickening an already-displaced sheet pushed its
    peaks apart into separated shards, which looked like shattered glass rather than a rock
    face; giving the slab depth first means the displacement moves a solid surface.
    """
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=22, y_subdivisions=22, size=2.0)
    obj = bpy.context.active_object
    obj.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    solid = obj.modifiers.new(name="Solid", type="SOLIDIFY")
    solid.thickness = 0.22
    displace(obj, noise_texture("strata%d" % index, "CLOUDS", 2.2, 2, index), 0.20)
    displace(obj, noise_texture("chip%d" % index, "DISTORTED_NOISE", 0.8, 2, index + 3), 0.06)
    return finish(obj, "wall_panel_%02d" % index, 600)


def stalactite(index):
    """A tapered spike. Cones alone read as traffic cones, so the taper is uneven."""
    bpy.ops.mesh.primitive_cone_add(vertices=9, radius1=0.5, radius2=0.04, depth=2.4)
    obj = bpy.context.active_object
    bpy.ops.object.modifier_add(type="SUBSURF")
    obj.modifiers["Subdivision"].levels = 2
    displace(obj, noise_texture("drip%d" % index, "CLOUDS", 0.5, 2, index), 0.18)
    return finish(obj, "stalactite_%02d" % index, 150)


def rubble(index):
    """Small angular debris. Flat shaded, so the facets catch light like broken stone."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.5)
    obj = bpy.context.active_object
    displace(obj, noise_texture("shard%d" % index, "DISTORTED_NOISE", 1.1, 2, index), 0.11)
    obj.scale = (1.0, 0.55, 0.8)
    bpy.ops.object.transform_apply(scale=True)
    return finish(obj, "rubble_%02d" % index, 90, smooth=False)


# --------------------------------------------------------------------------- preview

def render_preview(name):
    """Render a turntable-ish still so the result can actually be checked."""
    scene = bpy.context.scene
    # Engine identifiers move between releases; whatever the file opens with is fine.
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = 480
    scene.render.resolution_y = 360
    scene.render.film_transparent = False
    scene.render.filepath = os.path.join(PREVIEW, name + ".png")

    bpy.ops.object.camera_add(location=(3.2, -3.2, 2.2),
                              rotation=(math.radians(64), 0, math.radians(45)))
    scene.camera = bpy.context.active_object
    bpy.ops.object.light_add(type="AREA", location=(3, -3, 4))
    bpy.context.active_object.data.energy = 900
    bpy.ops.object.light_add(type="AREA", location=(-3, 2, 2))
    bpy.context.active_object.data.energy = 250
    try:
        bpy.ops.render.render(write_still=True)
        print("  preview -> %s.png" % name)
    except RuntimeError as err:
        print("  preview failed: %s" % err)


# --------------------------------------------------------------------------- main

def main():
    os.makedirs(MODELS, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    print("Blender %s" % bpy.app.version_string)

    jobs = []
    for i in range(5):
        jobs.append(("boulder_%02d" % i, boulder, i))
    for i in range(4):
        jobs.append(("wall_panel_%02d" % i, wall_panel, i))
    for i in range(3):
        jobs.append(("stalactite_%02d" % i, stalactite, i))
    for i in range(4):
        jobs.append(("rubble_%02d" % i, rubble, i))

    made = []
    for name, fn, index in jobs:
        wipe()
        print("%s ..." % name)
        try:
            obj = fn(index)
            export(obj, name)
            made.append(name)
        except Exception as err:  # keep going; one bad piece should not stop the set
            print("  FAILED: %s" % err)

    # One contact sheet per family is enough to judge the set.
    for name in ("boulder_00", "wall_panel_00", "stalactite_00", "rubble_00"):
        if name not in made:
            continue
        wipe()
        bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + ".glb"))
        render_preview(name)

    print("\nGenerated %d of %d assets into %s" % (len(made), len(jobs), MODELS))


if __name__ == "__main__":
    main()
