"""docs/36 시험: probe_fit.py가 만든 placed.blend를 8천·1만 5천 삼각형으로 줄여 원본과 나란히 렌더한다(2026-11-11).
실행: blender -b --python probe_decimate.py → /tmp/tripo/render_*.png
"""
import bpy, math, time
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath="/tmp/tripo/placed.blend")
src=[o for o in bpy.context.scene.objects if o.type=='MESH'][0]
results={}
for target in [8000, 15000]:
    ob=src.copy(); ob.data=src.data.copy(); bpy.context.collection.objects.link(ob)
    n=sum(len(p.vertices)-2 for p in ob.data.polygons)
    m=ob.modifiers.new("dec","DECIMATE"); m.ratio=target/n
    bpy.context.view_layer.objects.active=ob
    t=time.time(); bpy.ops.object.modifier_apply(modifier="dec")
    tris=sum(len(p.vertices)-2 for p in ob.data.polygons)
    print("decimate", target, "->", tris, "tris in", round(time.time()-t,1), "s")
    ob.location.x = 1.9 if target==8000 else 3.8
    results[target]=ob
# 렌더: 정면 직교, Workbench 텍스처
sc=bpy.context.scene
sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO'; sc.display.shading.color_type='TEXTURE'
sc.render.resolution_x=1800; sc.render.resolution_y=1000
cam=bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera=cam
cam.data.type='ORTHO'; cam.data.ortho_scale=6.0
for name,(loc,rot) in {"front":((1.9,6,0.15),(math.radians(90),0,math.radians(180))),"back":((1.9,-6,0.15),(math.radians(90),0,0))}.items():
    cam.location=loc; cam.rotation_euler=rot
    sc.render.filepath=f"/tmp/tripo/render_{name}.png"
    bpy.ops.render.render(write_still=True)
# 손 확대
cam.data.ortho_scale=0.7; cam.location=(1.9+0.72,6,0.68); cam.rotation_euler=(math.radians(90),0,math.radians(180))
sc.render.resolution_x=900; sc.render.resolution_y=600
sc.render.filepath="/tmp/tripo/render_hand.png"; bpy.ops.render.render(write_still=True)
cam.location=(0.72,6,0.68); sc.render.filepath="/tmp/tripo/render_hand_src.png"; bpy.ops.render.render(write_still=True)
