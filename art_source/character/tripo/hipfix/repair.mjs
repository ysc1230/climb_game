import {readGLB} from './glb.mjs';import fs from 'node:fs';
const root=new URL('./',import.meta.url),g=readGLB(new URL('source.glb',root)),j=g.j,pr=j.meshes[0].primitives[0],p=g.accessor(pr.attributes.POSITION),ji=g.accessor(pr.attributes.JOINTS_0),we=g.accessor(pr.attributes.WEIGHTS_0),idx=g.accessor(pr.indices).array.flat();
const names=j.skins[0].joints.map(i=>j.nodes[i].name),byName=Object.fromEntries(names.map((n,i)=>[n,i]));
const parent=p.array.map((_,i)=>i);function find(i){while(parent[i]!==i){parent[i]=parent[parent[i]];i=parent[i];}return i;}function union(a,b){parent[find(a)]=find(b);}const same=new Map;for(let i=0;i<p.array.length;i++){const key=p.array[i].map(x=>x.toFixed(5)).join(',');if(same.has(key))union(i,same.get(key));else same.set(key,i);}for(let i=0;i<idx.length;i+=3){union(idx[i],idx[i+1]);union(idx[i],idx[i+2]);}const comps=new Map;for(let i=0;i<p.array.length;i++){const k=find(i);if(!comps.has(k))comps.set(k,[]);comps.get(k).push(i);}const sorted=[...comps.values()].sort((a,b)=>b.length-a.length);console.log(JSON.stringify(sorted.map(ids=>({n:ids.length,min:[0,1,2].map(c=>Math.min(...ids.map(i=>p.array[i][c]))),max:[0,1,2].map(c=>Math.max(...ids.map(i=>p.array[i][c])))})).slice(0,20),null,2));
const smooth=(a,b,x)=>{let t=Math.max(0,Math.min(1,(x-a)/(b-a)));return t*t*(3-2*t);};
let edited=0;const counts={};
for(let i=0;i<p.array.length;i++){
 const [x,y,z]=p.array[i];if(y<-.2||y>.17)continue;
 // Restrict the left/right leg transition; accessories behind right hip stay pelvis-bound.
 const weights=Object.fromEntries(ji.array[i].map((id,k)=>[names[id],we.array[i][k]]).filter(([n,v])=>v>0));
 const lower=(weights.thigh_L||0)+(weights.thigh_R||0)+(weights.hiphelp_L||0)+(weights.hiphelp_R||0)+(weights.pelvis||0);
 if(lower<.01)continue;
 const bag=smooth(.12,.18,x)*smooth(.10,.15,z);
 let wp=smooth(.00,.18,y),r=smooth(-.045,.045,x);
 wp=wp+(1-wp)*bag;
 const helper=process.argv.includes('--helper'),a1=1-wp;
 const entries=helper?[[byName.pelvis,lower*Math.max(0,1-2*a1)],[byName.hiphelp_L,lower*(1-Math.abs(2*a1-1))*(1-r)],[byName.hiphelp_R,lower*(1-Math.abs(2*a1-1))*r],[byName.thigh_L,lower*Math.max(0,2*a1-1)*(1-r)],[byName.thigh_R,lower*Math.max(0,2*a1-1)*r]]:[[byName.pelvis,lower*wp],[byName.thigh_L,lower*(1-wp)*(1-r)],[byName.thigh_R,lower*(1-wp)*r]];
 for(const [n,w] of Object.entries(weights))if(!['pelvis','hiphelp_L','hiphelp_R','thigh_L','thigh_R'].includes(n))entries.push([byName[n],w]);
 entries.sort((a,b)=>b[1]-a[1]);const a=entries.slice(0,4),sum=a.reduce((s,v)=>s+v[1],0);while(a.length<4)a.push([0,0]);ji.set(i,a.map(v=>v[0]));we.set(i,a.map(v=>v[1]/sum));edited++;
}
// Smooth the newly painted transition on the welded surface, including UV seams.
const unique=[],weld=[],groups=new Map;for(let i=0;i<p.array.length;i++){const key=p.array[i].map(x=>x.toFixed(5)).join(',');if(!groups.has(key)){groups.set(key,unique.length);unique.push([]);}const k=groups.get(key);unique[k].push(i);weld[i]=k;}
const neighbors=unique.map(()=>new Set);for(let i=0;i<idx.length;i+=3)for(let k=0;k<3;k++){const a=weld[idx[i+k]],b=weld[idx[i+(k+1)%3]];if(a!==b){neighbors[a].add(b);neighbors[b].add(a);}}
const nowJ=g.accessor(pr.attributes.JOINTS_0).array,nowW=g.accessor(pr.attributes.WEIGHTS_0).array;
let ww=unique.map(ids=>{const a=Array(names.length).fill(0);for(const i of ids)for(let k=0;k<4;k++)a[nowJ[i][k]]+=nowW[i][k]/ids.length;return a;});
for(let step=0;step<12;step++)ww=ww.map((weights,k)=>{const [x,y,z]=p.array[unique[k][0]],mask=smooth(-.05,.015,y)*(1-smooth(.13,.19,y));if(mask<=0||!neighbors[k].size)return weights;const avg=Array(names.length).fill(0);const factors=[...neighbors[k]].map(n=>[n,1/Math.max(1e-8,p.array[unique[k][0]].reduce((s,v,c)=>s+(v-p.array[unique[n][0]][c])**2,0))]);const total=factors.reduce((s,v)=>s+v[1],0);for(const [n,f] of factors)for(let b=0;b<names.length;b++)avg[b]+=ww[n][b]*f/total;return weights.map((v,b)=>v+(avg[b]-v)*.4*mask);});
for(let k=0;k<unique.length;k++){const entries=ww[k].map((w,id)=>[id,w]).sort((a,b)=>b[1]-a[1]).slice(0,4),sum=entries.reduce((s,v)=>s+v[1],0);for(const i of unique[k]){ji.set(i,entries.map(v=>v[1]>0?v[0]:0));we.set(i,entries.map(v=>v[1]/sum));}}
g.j.asset.extras={...g.j.asset.extras,repair:'hip-transition-v1'};g.save(new URL(process.argv.includes('--helper')?'repaired-helper.glb':'repaired.glb',root));console.log({edited});
