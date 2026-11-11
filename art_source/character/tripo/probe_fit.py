"""docs/36 시험: Tripo 기본 모델을 B안 몸 크기·방향에 놓고 신체 기준점을 잰다(2026-11-11).
준비: git show origin/main:game/art/characters/climber_tripo_base.glb > /tmp/tripo/base.glb
실행: blender -b --python probe_fit.py  → /tmp/tripo/placed.blend
"""
import bpy, bmesh, math, time
from mathutils import Vector, Matrix
bpy.ops.wm.read_factory_settings(use_empty=True)
t0=time.time()
bpy.ops.import_scene.gltf(filepath="/tmp/tripo/base.glb")
obs=[o for o in bpy.context.scene.objects if o.type=='MESH']
ob=obs[0]
print("import s", round(time.time()-t0,1), "tris", sum(len(p.vertices)-2 for p in ob.data.polygons))
# glTF import already converts +Y up -> Blender Z up. Inspect bounds
bb=[ob.matrix_world @ Vector(c) for c in ob.bound_box]
mn=Vector((min(v.x for v in bb),min(v.y for v in bb),min(v.z for v in bb))); mx=Vector((max(v.x for v in bb),max(v.y for v in bb),max(v.z for v in bb)))
print("bounds", mn, mx)
# --- 방향·크기: 앞(+X) → +Y(벽 쪽, build_climber 규약), 키 1.99, 바닥 z = -0.835(골반 관절 = 원점 가정)
ob.rotation_mode = "XYZ"
ob.rotation_euler = (0, 0, math.radians(90))
ob.scale = (1.99, 1.99, 1.99)
bpy.context.view_layer.update()
bb=[ob.matrix_world @ Vector(c) for c in ob.bound_box]
zmin=min(v.z for v in bb)
ob.location.z = -0.835 - zmin
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active=ob
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
vs=[v.co.copy() for v in ob.data.vertices]
N=240
zs=[v.z for v in vs]; z0,z1=min(zs),max(zs)
xmin=[9]*N; xmax=[-9]*N; center=[False]*N
for v in vs:
    i=min(N-1,int((v.z-z0)/(z1-z0)*N)); xmin[i]=min(xmin[i],v.x); xmax[i]=max(xmax[i],v.x)
    if abs(v.x)<0.015: center[i]=True
H=lambda i: z0+(i+0.5)/N*(z1-z0)
crotch=next(i for i in range(N) if center[i])
arm=max(range(N), key=lambda i: xmax[i]-xmin[i])
print("sole %.3f top %.3f height %.3f" % (z0,z1,z1-z0))
print("crotch z %.3f  armline z %.3f  span %.3f..%.3f" % (H(crotch), H(arm), xmin[arm], xmax[arm]))
for i in range(0,N,8): print("  z=%+.3f x %.3f..%.3f %s" % (H(i), xmin[i], xmax[i], "c" if center[i] else ""))
# 초크백: 허리 높이에서 가장 뒤(-Y)로 튀어나온 점들의 X 평균
back=[v for v in vs if -0.15<v.z<0.15]
by=min(v.y for v in back); bag=[v for v in back if v.y<by+0.05]
print("chalk bag x mean %.3f y %.3f" % (sum(v.x for v in bag)/len(bag), by))
toes=[v for v in vs if v.z<z0+0.03]
print("toe y max %.3f (앞 +Y)" % max(v.y for v in toes))
bpy.ops.wm.save_as_mainfile(filepath="/tmp/tripo/placed.blend")
