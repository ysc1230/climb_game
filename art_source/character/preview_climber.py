"""CH01 미리보기 렌더(Workbench, 머티리얼 색 + 외곽선). 뒷모습·3/4 두 장."""
import bpy, math, os
from mathutils import Vector
OUT = os.path.expanduser("~/Projects/climb_game/art_source/character")
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "MATERIAL"
sh.show_object_outline = True
sh.object_outline_color = (0.19, 0.16, 0.13)
sh.show_cavity = True
sh.cavity_type = "BOTH"
sh.background_type = "VIEWPORT"
sh.background_color = (0.65, 0.42, 0.29)
sc.render.resolution_x, sc.render.resolution_y = 700, 900
sc.render.film_transparent = False
cam = bpy.data.objects.get("PreviewCam")
if cam is None:
    cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
    sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 60
target = Vector((0, 0, 0.05))
out = []
for name, pos in (("back", Vector((0.0, -3.6, 0.5))), ("three_quarter", Vector((2.4, -2.6, 0.9)))):
    cam.location = pos
    cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, f"preview_{name}.png")
    bpy.ops.render.render(write_still=True)
    out.append(sc.render.filepath)
bpy.data.objects.remove(cam, do_unlink=True)
print(out)
