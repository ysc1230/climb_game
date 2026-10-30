# docs/04 규칙을 옮긴 R01 의도 경로 간이 정적 계산. 속도 제한·충돌 생략. 실행: python3 -I tools/r01_static_check.py
import math, itertools
ARM=(0.40,0.38); LEG=(0.52,0.48)
def rng(a,b,bmin,bmax,lo,hi):
    f=lambda p: math.sqrt(a*a+b*b+2*a*b*math.cos(math.radians(p)))
    return max(lo,f(bmax)), min(hi,f(bmin))
ARM_R=rng(*ARM,5,155,0.20,0.78); LEG_R=rng(*LEG,5,145,0.25,1.00)
SH={'LH':(-0.20,0.55),'RH':(0.20,0.55)}; HP={'LF':(-0.14,0),'RF':(0.14,0)}
def rot(v,t):
    c,s=math.cos(math.radians(t)),math.sin(math.radians(t)); return (v[0]*c-v[1]*s, v[0]*s+v[1]*c)
def joint(p,limb):
    off=SH.get(limb) or HP[limb]; r=rot(off,p[2]); return (p[0]+r[0],p[1]+r[1])
def dist(a,b): return math.hypot(a[0]-b[0],a[1]-b[1])
def valid(p,att):
    if abs(p[2])>25: return False
    for l,s in att.items():
        d=dist(joint(p,l),s); lo,hi=ARM_R if l in SH else LEG_R
        if not(lo-1e-5<=d<=hi+1e-5): return False
    return True
def supp(p,l,s):
    h=joint(p,l); v=(h[0]-s[0],h[1]-s[1]); n=math.hypot(*v)
    return n>0 and v[1]>=0.05 and v[1]/n>=math.cos(math.radians(60))
def cost(p,att):
    c=0; xs=[s[0] for s in att.values()]
    for l,s in att.items():
        d=dist(joint(p,l),s)
        if l in SH: c+=((d-0.52)/0.78)**2
        elif supp(p,l,s): c+=1.25*((d-0.78)/1.0)**2
    c+=0.2*(p[2]/25)**2 + 0.1*((p[0]-sum(xs)/len(xs)))**2
    return c
def settle(p,att,ticks=600):
    # 04의 근방 탐색(27후보·8라운드)을 여러 틱 반복해 수렴 자세를 구함(속도 제한은 생략)
    for _ in range(ticks):
        start=p; best=p; bc=cost(p,att); step=(0.04,4)
        for _r in range(8):
            imp=False
            for dx,dy,dt in itertools.product((-1,0,1),repeat=3):
                q=(best[0]+dx*step[0],best[1]+dy*step[0],best[2]+dt*step[1])
                if dist(q,start)>0.30 or abs(q[2]-start[2])>15 or not valid(q,att): continue
                cq=cost(q,att)
                if cq<bc-1e-5: best,bc,imp=q,cq,True
            if not imp: step=(step[0]/2,step[1]/2)
        if dist(best,p)<1e-6 and abs(best[2]-p[2])<1e-6: break
        p=best
    return p
S={'H01':(-0.45,1.80),'H02':(0.45,1.80),'F01':(-0.30,0.10),'F02':(0.30,0.10),
   'H03':(-0.50,2.10),'H04':(0.50,2.10),'F03':(-0.35,0.65),'F04':(0.35,0.65),
   'H05':(-0.40,2.55),'H06':(0.40,2.55),'F05':(-0.25,1.15),'F06':(0.25,1.15),
   'GL':(-0.22,3.00),'GR':(0.22,3.00)}
att={'LH':S['H01'],'RH':S['H02'],'LF':S['F01'],'RF':S['F02']}
p=settle((0,0.95,0),att)
print(f"팔 허용 {ARM_R[0]:.3f}~{ARM_R[1]:.3f}m, 다리 허용 {LEG_R[0]:.3f}~{LEG_R[1]:.3f}m")
print(f"시작 수렴 자세 골반=({p[0]:.2f},{p[1]:.2f}) θ={p[2]:.1f}°  (문서 시작값 (0,0.95))")
path=[('LH','H03'),('RH','H04'),('LF','F03'),('RF','F04'),('LH','H05'),('RH','H06'),('LF','F05'),('RF','F06'),('LH','GL'),('RH','GR')]
for limb,tgt in path:
    p4=p
    rest={k:v for k,v in att.items() if k!=limb}
    p3=settle(p4,rest)  # 해당 팔다리를 뗀 뒤 남은 3접점으로 수렴
    lo,hi=ARM_R if limb in SH else LEG_R
    d4=dist(joint(p4,limb),S[tgt]); d3=dist(joint(p3,limb),S[tgt])
    new=dict(rest); new[limb]=S[tgt]
    ok4=valid(p4,new); ok3=valid(p3,new)
    sup3=[k for k in ('LF','RF') if k in rest and supp(p3,k,rest[k])]
    print(f"{limb}->{tgt}: 뗀 직후 거리 {d4:.3f}({'가능' if ok4 else '불가'}) / 3점 수렴 후 거리 {d3:.3f}({'가능' if ok3 else '불가'}) 허용 {lo:.2f}~{hi:.2f} | 3점 자세 골반=({p3[0]:.2f},{p3[1]:.2f}) 지지발={sup3}")
    if not(ok4 or ok3):
        print("  ==> 이 단계에서 경로가 막힘"); break
    att=new; p=settle(p4 if ok4 else p3,att)
    sup=[k for k in ('LF','RF') if supp(p,k,att[k])]
    print(f"   잡은 뒤 수렴 골반=({p[0]:.2f},{p[1]:.2f}) θ={p[2]:.1f}° 지지발={sup}")
