const __vite__mapDeps=(i,m=__vite__mapDeps,d=(m.f||(m.f=["assets/vendor-DivU4Fss.js","assets/react-core-CGxiiNc9.js"])))=>i.map(i=>d[i]);
import{j as a,r as b,u as gd}from"./react-core-CGxiiNc9.js";import{u as B,a as re,b as P}from"./tanstack-9glGrma2.js";import{L as hr,X as He,P as Td,A as Nd,a as hd,S as Gt,b as xr,c as Qe,d as st,G as Ps,C as Te,e as ye,f as oe,g as Bt,h as xd,i as bd,F as fd,j as kt,T as Re,k as ja,l as Oe,B as Be,m as Aa,n as Ia,Q as vd,o as Nt,p as pe,q as De,r as br,s as We,t as Ke,u as Et,U as Rd,v as Ta,w as fr,x as ka,y as Ms,z as Ue,R as wd,D as Ld,E as Ct,H as Sd,I as Cd,J as Od,K as Xs,M as qs,N as vr,O as jd,V as Gs,W as Ad,Y as Rr,Z as Na,_ as Xe,$ as ut,a0 as Da,a1 as Fa,a2 as Id,a3 as Ot,a4 as wr,a5 as kd,a6 as Dd,a7 as Fd,a8 as Ua,a9 as Lr,aa as Sr,ab as Ud,ac as Bs,ad as Pd,ae as Md,af as Xd,ag as qd,ah as Gd}from"./icons-Dj0IuHRJ.js";import{a as Bd,c as Cr,t as $d,b as Hd}from"./vendor-DivU4Fss.js";let $s="__toast-container";function Wd(){let e=document.getElementById($s);return e||(e=document.createElement("div"),e.id=$s,Object.assign(e.style,{position:"fixed",top:"16px",right:"16px",zIndex:"9999",display:"flex",flexDirection:"column",gap:"8px",pointerEvents:"none"}),document.body.appendChild(e)),e}function Pa(e,t="default",s={}){const r=s.duration??3500,n=Wd(),i=document.createElement("div");i.textContent=e;const o=document.documentElement.classList.contains("dark"),d={default:{bg:o?"#1f2937":"#ffffff",text:o?"#e5e7eb":"#1f2937",border:o?"#374151":"#e5e7eb"},success:{bg:o?"#064e3b":"#ecfdf5",text:o?"#6ee7b7":"#065f46",border:o?"#065f46":"#a7f3d0"},error:{bg:o?"#7f1d1d":"#fef2f2",text:o?"#fca5a5":"#991b1b",border:o?"#991b1b":"#fecaca"}}[t];Object.assign(i.style,{background:d.bg,color:d.text,border:`1px solid ${d.border}`,borderRadius:"8px",padding:"10px 16px",fontSize:"14px",fontWeight:"500",boxShadow:"0 4px 12px rgba(0,0,0,0.15)",pointerEvents:"auto",cursor:"pointer",maxWidth:"360px",wordBreak:"break-word",opacity:"0",transform:"translateX(100%)",transition:"opacity 0.25s ease, transform 0.25s ease"}),n.appendChild(i),requestAnimationFrame(()=>{i.style.opacity="1",i.style.transform="translateX(0)"}),i.addEventListener("click",()=>Hs(i)),setTimeout(()=>Hs(i),r)}function Hs(e){e.style.opacity="0",e.style.transform="translateX(100%)",setTimeout(()=>e.remove(),300)}function H(e,t){Pa(e,"default",t)}H.success=(e,t)=>{Pa(e,"success",t)};H.error=(e,t)=>{Pa(e,"error",t)};const Kd="modulepreload",Yd=function(e){return"/"+e},Ws={},N=function(t,s,r){let n=Promise.resolve();if(s&&s.length>0){let d=function(l){return Promise.all(l.map(u=>Promise.resolve(u).then(E=>({status:"fulfilled",value:E}),E=>({status:"rejected",reason:E}))))};document.getElementsByTagName("link");const o=document.querySelector("meta[property=csp-nonce]"),c=o?.nonce||o?.getAttribute("nonce");n=d(s.map(l=>{if(l=Yd(l),l in Ws)return;Ws[l]=!0;const u=l.endsWith(".css"),E=u?'[rel="stylesheet"]':"";if(document.querySelector(`link[href="${l}"]${E}`))return;const _=document.createElement("link");if(_.rel=u?"stylesheet":Kd,u||(_.as="script"),_.crossOrigin="",_.href=l,c&&_.setAttribute("nonce",c),document.head.appendChild(_),u)return new Promise((m,y)=>{_.addEventListener("load",m),_.addEventListener("error",()=>y(new Error(`Unable to preload CSS for ${l}`)))})}))}function i(o){const c=new Event("vite:preloadError",{cancelable:!0});if(c.payload=o,window.dispatchEvent(c),!c.defaultPrevented)throw o}return n.then(o=>{for(const c of o||[])c.status==="rejected"&&i(c.reason);return t().catch(i)})},Vd="/api",Fe={EDIT_PARTS_CATALOG:"edit_parts_catalog",EDIT_PRICING:"edit_pricing",SHOW_DOLLAR_VALUES:"show_dollar_values",MOVE_STOCK_WAREHOUSE:"move_stock_warehouse",VIEW_TRUCKS:"view_trucks",MANAGE_FLEET:"manage_fleet",MANAGE_JOBS:"manage_jobs",MANAGE_ORDERS:"manage_orders",VIEW_PEOPLE:"view_people",MANAGE_PEOPLE:"manage_people",MANAGE_CUSTOMERS:"manage_customers",MANAGE_CONTRACTORS:"manage_contractors",VIEW_SCHEDULE:"view_schedule",MANAGE_SCHEDULE:"manage_schedule",REQUEST_TIME_OFF:"request_time_off",APPROVE_TIME_OFF:"approve_time_off",DISPATCH_EMPLOYEES:"dispatch_employees",MANAGE_TOOLS:"manage_tools",CHECKOUT_TOOLS:"checkout_tools",PERFORM_AUDIT:"perform_audit"},x=Bd.create({baseURL:Vd,headers:{"Content-Type":"application/json"}});x.interceptors.request.use(e=>{const t=localStorage.getItem("wiredpart_token");return t&&(e.headers.Authorization=`Bearer ${t}`),e});x.interceptors.response.use(e=>e,e=>{e.response?.status===401&&(localStorage.removeItem("wiredpart_token"),window.dispatchEvent(new CustomEvent("auth:expired")));const t=e.response?.headers?.["x-device-override"];if(t){const s=e.response?.headers?.["x-override-reason"]??"";window.dispatchEvent(new CustomEvent("device:override",{detail:{action:t,reason:s}}))}return Promise.reject(e)});function ce(){return typeof window<"u"&&"__TAURI__"in window}function Se(){return ce()}function Or(){if(!ce())return!1;const e=Ma();return e==="macos"||e==="windows"}function Ma(){if(ce()){const e=window.__TAURI_ENV_PLATFORM__;return e==="macos"||e==="darwin"?"macos":e==="windows"?"windows":e==="ios"?"ios":e==="android"?"android":navigator.userAgent.includes("Macintosh")?"macos":navigator.userAgent.includes("Windows")?"windows":"macos"}return"web"}const Jd=Object.freeze(Object.defineProperty({__proto__:null,getPlatform:Ma,isDesktop:Or,isNativeApp:Se,isTauri:ce},Symbol.toStringTag,{value:"Module"}));async function R(e,t){return Se()&&t?t():e()}async function qp(e,t){return R(async()=>{const{data:s}=await x.post("/auth/device-login",{device_fingerprint:e,device_name:t});return s.data},async()=>({auto_login:!1,token:null,requires_user_selection:!0,is_public_device:!0,device_id:null}))}async function Gp(){return R(async()=>{const{data:e}=await x.get("/auth/users");return e.data??[]},async()=>{const{getActiveUsers:e,getUserHatNames:t}=await N(async()=>{const{getActiveUsers:n,getUserHatNames:i}=await Promise.resolve().then(()=>Ja);return{getActiveUsers:n,getUserHatNames:i}},void 0),s=await e(),r=[];for(const n of s){const i=await t(n.id);r.push({id:n.id,display_name:n.display_name,avatar_url:n.avatar_url,hats:i})}return r})}async function Bp(e,t,s,r){return R(async()=>{const{data:n}=await x.post("/auth/pin-login",{user_id:e,pin:t,device_fingerprint:s,device_name:r});return n.data},async()=>{const{authenticateByPin:n}=await N(async()=>{const{authenticateByPin:o}=await Promise.resolve().then(()=>Ja);return{authenticateByPin:o}},void 0),i=await n(e,t);if(!i.success||!i.token){const o=new Error(i.message);throw o.response={data:{detail:i.message}},o}return{access_token:i.token,token_type:"bearer",expires_in:86400}})}async function Ks(){return R(async()=>{const{data:e}=await x.get("/auth/me");return e.data},async()=>{const{getLocalUserProfile:e}=await N(async()=>{const{getLocalUserProfile:s}=await Promise.resolve().then(()=>Ja);return{getLocalUserProfile:s}},void 0),t=localStorage.getItem("wiredpart_token");if(!t)throw new Error("No token");return e(t)})}async function Ys(){return R(async()=>{const{data:e}=await x.get("/settings/theme");return e.data},async()=>{const{getTheme:e}=await N(async()=>{const{getTheme:t}=await Promise.resolve().then(()=>ne);return{getTheme:t}},void 0);return e()})}async function $p(e){return R(async()=>{const{data:t}=await x.put("/settings/theme",e);return t.data},async()=>{const{updateTheme:t}=await N(async()=>{const{updateTheme:s}=await Promise.resolve().then(()=>ne);return{updateTheme:s}},void 0);return t(e)})}async function Hp(){return R(async()=>{const{data:e}=await x.get("/settings");return e.data??{}},async()=>{const{getAllSettings:e}=await N(async()=>{const{getAllSettings:t}=await Promise.resolve().then(()=>ne);return{getAllSettings:t}},void 0);return e()})}async function Wp(e){return R(async()=>{try{const{data:t}=await x.get(`/settings/${e}`);return t.data?.value??null}catch{return null}},async()=>{const{getSetting:t}=await N(async()=>{const{getSetting:s}=await Promise.resolve().then(()=>ne);return{getSetting:s}},void 0);return t(e)})}async function Kp(e,t,s="general"){return R(async()=>{await x.put(`/settings/${e}`,{value:t,category:s})},async()=>{const{updateSetting:r}=await N(async()=>{const{updateSetting:n}=await Promise.resolve().then(()=>ne);return{updateSetting:n}},void 0);await r(e,t,s)})}async function Yp(){return R(async()=>{const{data:e}=await x.get("/settings/warranty_length_days");return e.data?.value?parseInt(e.data.value,10):365},async()=>{const{getWarrantyLengthDays:e}=await N(async()=>{const{getWarrantyLengthDays:t}=await Promise.resolve().then(()=>ne);return{getWarrantyLengthDays:t}},void 0);return e()})}async function Vp(e){return R(async()=>{await x.put("/settings/warranty_length_days",{value:String(e)})},async()=>{const{updateWarrantyLengthDays:t}=await N(async()=>{const{updateWarrantyLengthDays:s}=await Promise.resolve().then(()=>ne);return{updateWarrantyLengthDays:s}},void 0);await t(e)})}async function Jp(){return R(async()=>{const{data:e}=await x.get("/settings/company-profiles");return e.data??[]},async()=>{const{listCompanyProfiles:e}=await N(async()=>{const{listCompanyProfiles:t}=await Promise.resolve().then(()=>ne);return{listCompanyProfiles:t}},void 0);return e()})}async function Qp(e){return R(async()=>{const{data:t}=await x.post("/settings/company-profiles",e);return t.data},async()=>{const{createCompanyProfile:t}=await N(async()=>{const{createCompanyProfile:s}=await Promise.resolve().then(()=>ne);return{createCompanyProfile:s}},void 0);return t(e)})}async function zp(e,t){return R(async()=>{const{data:s}=await x.put(`/settings/company-profiles/${e}`,t);return s.data},async()=>{const{updateCompanyProfile:s}=await N(async()=>{const{updateCompanyProfile:r}=await Promise.resolve().then(()=>ne);return{updateCompanyProfile:r}},void 0);return s(e,t)})}async function Zp(e){return R(async()=>{const{data:t}=await x.delete(`/settings/company-profiles/${e}`);return t.data},async()=>{const{deleteCompanyProfile:t}=await N(async()=>{const{deleteCompanyProfile:s}=await Promise.resolve().then(()=>ne);return{deleteCompanyProfile:s}},void 0);return t(e)})}async function em(){return R(async()=>{const{data:e}=await x.get("/settings/pdf");return e.data},async()=>{const{getPDFSettings:e}=await N(async()=>{const{getPDFSettings:t}=await Promise.resolve().then(()=>ne);return{getPDFSettings:t}},void 0);return e()})}async function tm(e){return R(async()=>{const{data:t}=await x.put("/settings/pdf",e);return t.data},async()=>{const{updatePDFSettings:t}=await N(async()=>{const{updatePDFSettings:s}=await Promise.resolve().then(()=>ne);return{updatePDFSettings:s}},void 0);return t(e)})}async function am(e){return R(async()=>{const t=new FormData;t.append("file",e);const{data:s}=await x.post("/settings/company-logo",t,{headers:{"Content-Type":"multipart/form-data"}});return s.data},async()=>{const{uploadCompanyLogo:t}=await N(async()=>{const{uploadCompanyLogo:s}=await Promise.resolve().then(()=>ne);return{uploadCompanyLogo:s}},void 0);return t(e.name)})}async function sm(){return R(async()=>{const{data:e}=await x.get("/settings/billing-cycle");return e.data},async()=>{const{getBillingCycle:e}=await N(async()=>{const{getBillingCycle:t}=await Promise.resolve().then(()=>ne);return{getBillingCycle:t}},void 0);return e()})}async function rm(e){return R(async()=>{const{data:t}=await x.put("/settings/billing-cycle",e);return t.data},async()=>{const{updateBillingCycle:t}=await N(async()=>{const{updateBillingCycle:s}=await Promise.resolve().then(()=>ne);return{updateBillingCycle:s}},void 0);return t(e)})}async function nm(){return R(async()=>{const{data:e}=await x.get("/settings/pay-period");return e.data},async()=>{const{getPayPeriod:e}=await N(async()=>{const{getPayPeriod:t}=await Promise.resolve().then(()=>ne);return{getPayPeriod:t}},void 0);return e()})}async function im(e){return R(async()=>{const{data:t}=await x.put("/settings/pay-period",e);return t.data},async()=>{const{updatePayPeriod:t}=await N(async()=>{const{updatePayPeriod:s}=await Promise.resolve().then(()=>ne);return{updatePayPeriod:s}},void 0);return t(e)})}async function om(){return R(async()=>{const{data:e}=await x.get("/settings/payroll-columns");return e.data},async()=>{const{getPayrollColumns:e}=await N(async()=>{const{getPayrollColumns:t}=await Promise.resolve().then(()=>ne);return{getPayrollColumns:t}},void 0);return e()})}async function cm(e){return R(async()=>{const{data:t}=await x.put("/settings/payroll-columns",e);return t.data},async()=>{const{updatePayrollColumns:t}=await N(async()=>{const{updatePayrollColumns:s}=await Promise.resolve().then(()=>ne);return{updatePayrollColumns:s}},void 0);return t(e)})}function Qd(e){const t=parseInt(e.slice(1,3),16)/255,s=parseInt(e.slice(3,5),16)/255,r=parseInt(e.slice(5,7),16)/255,n=Math.max(t,s,r),i=Math.min(t,s,r);let o=0,c=0;const d=(n+i)/2;if(n!==i){const l=n-i;switch(c=d>.5?l/(2-n-i):l/(n+i),n){case t:o=((s-r)/l+(s<r?6:0))/6;break;case s:o=((r-t)/l+2)/6;break;case r:o=((t-s)/l+4)/6;break}}return[Math.round(o*360),Math.round(c*100),Math.round(d*100)]}function zd(e,t,s){return`hsl(${e} ${t}% ${Math.max(5,Math.min(97,s))}%)`}function Zd(e){if(!e||!e.startsWith("#")||e.length<7)return{};try{const[t,s,r]=Qd(e),n={50:r+44,100:r+36,200:r+26,300:r+16,400:r+8,500:r,600:r-8,700:r-18,800:r-28,900:r-38};return Object.fromEntries(Object.entries(n).map(([i,o])=>[i,zd(t,s,o)]))}catch{return{}}}const Vs="#3B82F6",ua="Inter";function Dt(e){return e==="dark"?!0:e==="light"?!1:window.matchMedia("(prefers-color-scheme: dark)").matches}const jr=typeof window<"u"?localStorage.getItem("wiredpart_theme")??"system":"system",eu=Dt(jr),be=Cr((e,t)=>({mode:jr,isDark:eu,primaryColor:Vs,fontFamily:ua,initialize:s=>{const r=s?.theme_mode??localStorage.getItem("wiredpart_theme")??"system",n=s?.primary_color??Vs,i=s?.font_family??ua,o=Dt(r);e({mode:r,isDark:o,primaryColor:n,fontFamily:i}),t().applyTheme()},setMode:s=>{const r=Dt(s);localStorage.setItem("wiredpart_theme",s),e({mode:s,isDark:r}),t().applyTheme()},setPrimaryColor:s=>{e({primaryColor:s}),t().applyTheme()},setFontFamily:s=>{e({fontFamily:s}),t().applyTheme()},applyTheme:()=>{const{isDark:s,primaryColor:r,fontFamily:n}=t(),i=document.documentElement;s?i.classList.add("dark"):i.classList.remove("dark");const o=Zd(r);Object.entries(o).forEach(([c,d])=>{i.style.setProperty(`--color-primary-${c}`,d)}),n&&n!==ua?i.style.setProperty("--font-sans",`'${n}', ui-sans-serif, system-ui, sans-serif`):i.style.removeProperty("--font-sans")}}));typeof window<"u"&&be.getState().applyTheme();typeof window<"u"&&window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change",()=>{const{mode:e}=be.getState();if(e==="system"){const t=Dt("system");be.setState({isDark:t}),be.getState().applyTheme()}});const Ar="db-config.json",_a={mode:"private"},Js={macos:"/Users/Shared/WiredPart/wiredpart.db",windows:"C:\\Users\\Public\\WiredPart\\wiredpart.db"};let Le=null;async function tu(){if(Le)return Le;if(!ce())return Le=_a,Le;try{const{readTextFile:e,BaseDirectory:t}=await N(async()=>{const{readTextFile:n,BaseDirectory:i}=await import("@tauri-apps/plugin-fs");return{readTextFile:n,BaseDirectory:i}},[]),s=await e(Ar,{baseDir:t.AppData}),r=JSON.parse(s);r.mode==="public"&&typeof r.customPath=="string"?Le={mode:"public",customPath:r.customPath}:Le=_a}catch{Le=_a}return Le}async function lm(e){if(!ce()){console.warn("[db-config] Cannot save config outside Tauri");return}try{const{writeTextFile:t,BaseDirectory:s}=await N(async()=>{const{writeTextFile:n,BaseDirectory:i}=await import("@tauri-apps/plugin-fs");return{writeTextFile:n,BaseDirectory:i}},[]),r=JSON.stringify(e,null,2);await t(Ar,r,{baseDir:s.AppData}),Le=e,console.log("[db-config] Saved:",e)}catch(t){throw console.error("[db-config] Failed to save config:",t),t}}function dm(){if(!Or())return null;const e=Ma();return e==="macos"?Js.macos:e==="windows"?Js.windows:null}async function au(){const e=await tu();return e.mode==="public"&&e.customPath?`sqlite:${e.customPath}`:"sqlite:wiredpart.db"}let dt=null;async function p(){if(dt)return dt;if(!ce())throw new Error("Local database is only available in Tauri native mode. Browser mode should use the HTTP API client.");return dt=await su(),dt}async function Ir(){const e=await p();await nu(e)}async function su(){const e=(await N(async()=>{const{default:r}=await import("@tauri-apps/plugin-sql");return{default:r}},[])).default,t=await au();console.log(`[db] Opening database: ${t}`);const s=await e.load(t);return{async query(r,n=[]){return{values:await s.select(r,n)}},async run(r,n=[]){const i=await s.execute(r,n);return{changes:{changes:i.rowsAffected,lastId:i.lastInsertId??0}}},async execute(r){const n=ru(r);for(const i of n)try{await s.execute(i,[])}catch(o){const c=String(o?.message||o||"");if(/duplicate column name/i.test(c)&&/ALTER\s+TABLE/i.test(i)){console.warn(`[db] Skipping duplicate column: ${i.slice(0,80)}…`);continue}throw o}},async close(){await s.close(),dt=null}}}function ru(e){const t=[];let s="",r=!1,n=!1,i=!1;for(let c=0;c<e.length;c++){const d=e[c];if(i){s+=d,i=!1;continue}if(d==="\\"){s+=d,i=!0;continue}if(d==="'"&&!n){if(r&&c+1<e.length&&e[c+1]==="'"){s+="''",c++;continue}r=!r,s+=d;continue}if(d==='"'&&!r){n=!n,s+=d;continue}if(d===";"&&!r&&!n){const l=s.trim();l.length>0&&t.push(l),s="";continue}s+=d}const o=s.trim();return o.length>0&&t.push(o),t}async function nu(e){await e.execute(`
    CREATE TABLE IF NOT EXISTS _migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      applied_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  `);const{migrations:t}=await N(async()=>{const{migrations:s}=await Promise.resolve().then(()=>JE);return{migrations:s}},void 0);for(const s of t)(await e.query("SELECT 1 FROM _migrations WHERE name = ?",[s.name])).values.length||(console.log(`[db] Running migration: ${s.name}`),await e.execute(s.sql),await e.run("INSERT INTO _migrations (name) VALUES (?)",[s.name]),console.log(`[db] Migration complete: ${s.name}`))}const kr=Object.freeze(Object.defineProperty({__proto__:null,getDb:p,initLocalDb:Ir},Symbol.toStringTag,{value:"Module"})),Qs="wiredpart_device_id";function iu(){return typeof crypto<"u"&&crypto.randomUUID?crypto.randomUUID():"xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g,e=>{const t=Math.random()*16|0;return(e==="x"?t:t&3|8).toString(16)})}async function rt(){let e=localStorage.getItem(Qs);return e||(e=iu(),localStorage.setItem(Qs,e)),e}const ou=Object.freeze(Object.defineProperty({__proto__:null,getDeviceId:rt},Symbol.toStringTag,{value:"Module"}));async function X(e,t,s,r,n){const i=await p(),o=await rt();await i.run(`INSERT INTO _change_log
       (device_id, table_name, record_id, operation, changed_fields, old_values)
     VALUES (?, ?, ?, ?, ?, ?)`,[o,e,t,s,r?JSON.stringify(r):null,n?JSON.stringify(n):null])}async function Dr(){return(await(await p()).query("SELECT * FROM _change_log WHERE synced = 0 ORDER BY timestamp ASC")).values}async function Xa(){return(await(await p()).query("SELECT COUNT(*) as cnt FROM _change_log WHERE synced = 0")).values[0]?.cnt??0}async function Fr(e,t){if(e.length===0)return;const s=await p(),r=e.map(()=>"?").join(",");await s.run(`UPDATE _change_log SET synced = 1, sync_batch_id = ?
     WHERE id IN (${r})`,[t,...e])}async function cu(){const e=await p(),t=await rt(),s=await e.query("SELECT peer_id, last_sequence FROM _vector_clock WHERE device_id = ?",[t]),r={};for(const n of s.values)r[n.peer_id]=n.last_sequence;return r}async function lu(e,t){const s=await p(),r=await rt();await s.run(`INSERT INTO _vector_clock (device_id, peer_id, last_sequence, updated_at)
     VALUES (?, ?, ?, datetime('now'))
     ON CONFLICT(device_id, peer_id)
     DO UPDATE SET last_sequence = MAX(last_sequence, ?), updated_at = datetime('now')`,[r,e,t,t])}async function du(e,t,s){await(await p()).run(`INSERT INTO _device_registry (device_id, device_name, platform, last_seen_at, is_trusted)
     VALUES (?, ?, ?, datetime('now'), 1)
     ON CONFLICT(device_id)
     DO UPDATE SET device_name = ?, last_seen_at = datetime('now')`,[e,t,s??null,t])}async function uu(e){await(await p()).run(`UPDATE _device_registry SET last_sync_at = datetime('now'), last_seen_at = datetime('now')
     WHERE device_id = ?`,[e])}const Ur=Object.freeze(Object.defineProperty({__proto__:null,getPendingChangeCount:Xa,getPendingChanges:Dr,getVectorClock:cu,markSynced:Fr,registerPeerDevice:du,trackChange:X,updatePeerSyncTime:uu,updateVectorClock:lu},Symbol.toStringTag,{value:"Module"})),Pr="shop_url";async function ht(){return localStorage.getItem(Pr)}async function _u(e){const t=e.replace(/\/$/,"");localStorage.setItem(Pr,t)}async function Mr(){const e=await ht();if(!e)return!1;try{return(await fetch(`${e}/api/health`,{signal:AbortSignal.timeout(3e3)})).ok}catch{return!1}}async function Eu(){const e=await ht();if(!e)return null;try{const t=await fetch(`${e}/api/server-info`,{signal:AbortSignal.timeout(3e3)});return t.ok?t.json():null}catch{return null}}const um=Object.freeze(Object.defineProperty({__proto__:null,getShopInfo:Eu,getShopUrl:ht,isShopReachable:Mr,setShopUrl:_u},Symbol.toStringTag,{value:"Module"}));let _e={status:"idle",lastSyncAt:null,pendingCount:0,error:null,consecutiveFailures:0,lastAttemptAt:null};const ha=new Set;function _m(){return{..._e}}function Em(e){return ha.add(e),()=>ha.delete(e)}function ue(e){_e={..._e,...e};for(const t of ha)try{t(_e)}catch{}}const Xr=300*1e3,pu=30*1e3,mu=300*1e3,yu=10;function gu(){if(_e.consecutiveFailures===0)return Xr;const e=pu*Math.pow(2,_e.consecutiveFailures-1);return Math.min(e,mu)}let Ea=!1;async function nt(e){if(Ea)return!1;Ea=!0;try{if(ue({status:"syncing",error:null,lastAttemptAt:new Date().toISOString()}),!await Mr()){const u=await Xa();return ue({status:"offline",pendingCount:u,consecutiveFailures:_e.consecutiveFailures+1}),pa(e),!1}const s=await ht();if(!s)return ue({status:"error",error:"Shop URL not configured"}),!1;const r=localStorage.getItem("wiredpart_token"),n={"Content-Type":"application/json"};r&&(n.Authorization=`Bearer ${r}`);const i=await Dr();ue({pendingCount:i.length});const o=await fetch(`${s}/api/sync/push`,{method:"POST",headers:n,body:JSON.stringify({device_id:e,last_sync_at:_e.lastSyncAt||"1970-01-01",changes:i}),signal:AbortSignal.timeout(3e4)});if(!o.ok)return await o.text(),ue({status:"error",error:`Push failed: ${o.status}`,consecutiveFailures:_e.consecutiveFailures+1}),pa(e),!1;const d=(await o.json()).data;if(d.shop_changes?.length&&await Tu(d.shop_changes),i.length>0&&d.sync_batch_id){const u=i.map(E=>E.id);await Fr(u,d.sync_batch_id)}try{await fetch(`${s}/api/sync/ack`,{method:"POST",headers:n,body:JSON.stringify({device_id:e,sync_batch_id:d.sync_batch_id}),signal:AbortSignal.timeout(1e4)})}catch{}const l=new Date().toISOString();return ue({status:"synced",lastSyncAt:l,pendingCount:0,error:null,consecutiveFailures:0}),localStorage.setItem("last_sync_at",l),!0}catch(t){return ue({status:"error",error:t instanceof Error?t.message:"Sync failed",consecutiveFailures:_e.consecutiveFailures+1}),pa(e),!1}finally{Ea=!1}}async function Tu(e){const t=await p();for(const s of e){const{table_name:r,record_id:n,operation:i,record_data:o}=s;try{if(i==="DELETE")await t.run(`DELETE FROM [${r}] WHERE id = ?`,[n]);else if(o){const c=Object.keys(o),d=c.map(()=>"?").join(", "),l=c.map(u=>o[u]);await t.run(`INSERT OR REPLACE INTO [${r}] (${c.join(", ")}) VALUES (${d})`,l)}}catch(c){console.error(`Failed to apply sync change: ${r}.${n}`,c)}}}async function pm(e){try{ue({status:"syncing",error:null});const t=await ht();if(!t)return ue({status:"error",error:"Shop URL not configured"}),!1;const s=localStorage.getItem("wiredpart_token"),r={"Content-Type":"application/json"};s&&(r.Authorization=`Bearer ${s}`);const n=await fetch(`${t}/api/sync/initial`,{method:"POST",headers:r,body:JSON.stringify({device_id:e}),signal:AbortSignal.timeout(12e4)});if(!n.ok)return ue({status:"error",error:"Initial sync failed"}),!1;const o=(await n.json()).data?.tables||{},c=await p();for(const[l,u]of Object.entries(o))if(!(!Array.isArray(u)||u.length===0))for(const E of u){const _=Object.keys(E),m=_.map(()=>"?").join(", "),y=_.map(f=>E[f]);try{await c.run(`INSERT OR REPLACE INTO [${l}] (${_.join(", ")}) VALUES (${m})`,y)}catch{}}const d=new Date().toISOString();return ue({status:"synced",lastSyncAt:d,pendingCount:0,consecutiveFailures:0}),localStorage.setItem("last_sync_at",d),!0}catch(t){return ue({status:"error",error:t instanceof Error?t.message:"Initial sync failed"}),!1}}let Ae=null;function pa(e){if(Ae&&clearTimeout(Ae),_e.consecutiveFailures>=yu){ue({error:"Too many failures. Tap to retry."});return}const t=gu();Ae=setTimeout(()=>{Ae=null,nt(e).catch(console.error)},t)}function qa(){Ae&&(clearTimeout(Ae),Ae=null)}let _t=null;function Nu(e){_t||(_t=setInterval(()=>{!Ae&&_e.consecutiveFailures===0&&nt(e).catch(console.error)},Xr))}function hu(){_t&&(clearInterval(_t),_t=null),qa()}async function mm(e){return qa(),ue({consecutiveFailures:0}),nt(e)}let zs=!1;async function xu(e){zs||(zs=!0,window.addEventListener("online",()=>{setTimeout(()=>{qa(),ue({consecutiveFailures:0}),nt(e).catch(console.error)},2e3)}),window.addEventListener("offline",()=>{ue({status:"offline"})}))}async function bu(e){document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible"){const t=_e.lastAttemptAt,s=Date.now();(t?s-new Date(t).getTime():1/0)>3e4&&nt(e).catch(console.error)}})}async function qr(){const e=localStorage.getItem("last_sync_at");e&&(_e.lastSyncAt=e);try{const t=await Xa();_e.pendingCount=t}catch{}}async function fu(e){await qr(),await xu(e),await bu(e),Nu(e),nt(e).catch(console.error);const{isTauri:t}=await N(async()=>{const{isTauri:s}=await Promise.resolve().then(()=>Jd);return{isTauri:s}},void 0);if(t())try{const{startPeerSync:s,refreshOutbox:r}=await N(async()=>{const{startPeerSync:o,refreshOutbox:c}=await Promise.resolve().then(()=>Xu);return{startPeerSync:o,refreshOutbox:c}},void 0),n=localStorage.getItem("device_name")||"WiredPart Device",i=localStorage.getItem("company_id")||"default";await s(e,n,i),setInterval(()=>{r().catch(console.error)},3e4),r().catch(console.error)}catch(s){console.error("[sync] P2P peer sync failed to start:",s)}}const Pe=Cr((e,t)=>({user:null,isLoading:!1,isAuthenticated:!1,login:async s=>{localStorage.setItem("wiredpart_token",s),e({isLoading:!0});try{const r=await Ks();e({user:r,isAuthenticated:!0,isLoading:!1});try{if(Se())be.getState().initialize();else{const n=await Ys();be.getState().initialize(n)}}catch{be.getState().initialize()}Se()&&rt().then(n=>fu(n)).catch(console.error)}catch{localStorage.removeItem("wiredpart_token"),e({user:null,isAuthenticated:!1,isLoading:!1})}},logout:()=>{if(localStorage.removeItem("wiredpart_token"),e({user:null,isAuthenticated:!1,isLoading:!1}),Se())try{hu()}catch{}},checkAuth:async()=>{if(!localStorage.getItem("wiredpart_token")){e({user:null,isAuthenticated:!1,isLoading:!1});return}e({isLoading:!0});try{const r=await Ks();e({user:r,isAuthenticated:!0,isLoading:!1});try{if(Se())be.getState().initialize();else{const n=await Ys();be.getState().initialize(n)}}catch{be.getState().initialize()}}catch{localStorage.removeItem("wiredpart_token"),e({user:null,isAuthenticated:!1,isLoading:!1})}},hasPermission:s=>{const{user:r}=t();return r?.permissions?.includes(s)??!1},hasAllPermissions:(...s)=>{const{user:r}=t();return r?.permissions?s.every(n=>r.permissions.includes(n)):!1},hasAnyPermission:(...s)=>{const{user:r}=t();return r?.permissions?s.some(n=>r.permissions.includes(n)):!1}}));typeof window<"u"&&window.addEventListener("auth:expired",()=>{Pe.getState().logout()});function we(...e){return $d(Hd(e))}function vu(){const t=[navigator.userAgent,navigator.language,screen.width+"x"+screen.height,screen.colorDepth.toString(),Intl.DateTimeFormat().resolvedOptions().timeZone,navigator.hardwareConcurrency?.toString()??"0"].join("|");let s=0;for(let n=0;n<t.length;n++){const i=t.charCodeAt(n);s=(s<<5)-s+i,s|=0}let r=localStorage.getItem("wiredpart_device_id");return r||(r=Math.random().toString(36).substring(2,15),localStorage.setItem("wiredpart_device_id",r)),`wp-${Math.abs(s).toString(36)}-${r}`}function Ru(){const e=navigator.userAgent;return e.includes("Chrome")&&!e.includes("Edg")?"Chrome":e.includes("Edg")?"Edge":e.includes("Firefox")?"Firefox":e.includes("Safari")&&!e.includes("Chrome")?"Safari":"Browser"}function wu(e){if(!e)return"—";try{return new Date(e).toLocaleString()}catch{return e}}function Lu(e){if(!e)return"—";const t=typeof e=="string"?new Date(e):e,r=new Date().getTime()-t.getTime(),n=Math.floor(r/6e4);if(n<1)return"Just now";if(n<60)return`${n}m ago`;const i=Math.floor(n/60);if(i<24)return`${i}h ago`;const o=Math.floor(i/24);return o<7?`${o}d ago`:t.toLocaleDateString()}const ym=Object.freeze(Object.defineProperty({__proto__:null,cn:we,formatDateTime:wu,formatRelativeTime:Lu,generateDeviceFingerprint:vu,getDeviceName:Ru},Symbol.toStringTag,{value:"Module"})),Su={default:"bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300",primary:"bg-primary-100 text-primary-700 dark:bg-primary-900 dark:text-primary-300",success:"bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300",warning:"bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300",danger:"bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300",info:"bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300",neutral:"bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300",secondary:"bg-gray-200 text-gray-600 dark:bg-gray-600 dark:text-gray-300"};function G({variant:e="default",className:t,children:s,...r}){return a.jsx("span",{className:we("inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",Su[e],t),...r,children:s})}const Cu={sm:"h-4 w-4",md:"h-6 w-6",lg:"h-10 w-10"};function z({size:e="md",className:t,label:s}){return a.jsxs("div",{className:we("flex items-center justify-center gap-2",t),children:[a.jsx(hr,{className:we("animate-spin text-primary-500",Cu[e])}),s&&a.jsx("span",{className:"text-sm text-gray-500 dark:text-gray-400",children:s})]})}function gm({label:e="Loading..."}){return a.jsx("div",{className:"flex items-center justify-center min-h-[400px]",children:a.jsx(z,{size:"lg",label:e})})}const Ou={primary:"bg-primary-500 text-white hover:bg-primary-600 active:bg-primary-700 shadow-sm",secondary:"bg-white text-gray-700 border border-gray-300 hover:bg-gray-50 active:bg-gray-100 dark:bg-gray-800 dark:text-gray-200 dark:border-gray-600 dark:hover:bg-gray-700",ghost:"text-gray-600 hover:bg-gray-100 active:bg-gray-200 dark:text-gray-300 dark:hover:bg-gray-800",danger:"bg-red-500 text-white hover:bg-red-600 active:bg-red-700 shadow-sm",success:"bg-green-600 text-white hover:bg-green-700 active:bg-green-800 shadow-sm",warning:"bg-amber-500 text-white hover:bg-amber-600 active:bg-amber-700 shadow-sm"},ju={sm:"h-8 px-3 text-sm gap-1.5",md:"h-10 px-4 text-sm gap-2",lg:"h-12 px-6 text-base gap-2.5"},F=b.forwardRef(({variant:e="primary",size:t="md",icon:s,iconRight:r,isLoading:n,fullWidth:i,className:o,disabled:c,children:d,...l},u)=>a.jsxs("button",{ref:u,disabled:c||n,className:we("inline-flex items-center justify-center font-medium rounded-lg","transition-colors duration-150 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:ring-offset-2","disabled:opacity-50 disabled:cursor-not-allowed",Ou[e],ju[t],i&&"w-full",o),...l,children:[n?a.jsx(hr,{className:"h-4 w-4 animate-spin"}):s,d,r]}));F.displayName="Button";let Ee={running:!1,sync_port:0,peers:[],last_peer_syncs:{},syncing_with:null};const xa=new Set;let jt=null,At=null;function Au(){return{...Ee}}function Iu(e){return xa.add(e),()=>xa.delete(e)}function ze(e){Ee={...Ee,...e};for(const t of xa)try{t(Ee)}catch{}}async function $e(e,t){const{invoke:s}=await N(async()=>{const{invoke:r}=await import("./vendor-DivU4Fss.js").then(n=>n.i);return{invoke:r}},__vite__mapDeps([0,1]));return s(e,t)}async function ku(e,t,s){if(!(!ce()||Ee.running))try{const r=await $e("start_p2p_sync",{device_id:e,device_name:t,company_id:s});ze({running:!0,sync_port:r}),console.log(`[peer-manager] P2P sync active on port ${r}`);try{const{getDevicePublicKey:n}=await N(async()=>{const{getDevicePublicKey:o}=await Promise.resolve().then(()=>oi);return{getDevicePublicKey:o}},void 0),i=localStorage.getItem("wp_security_company_public_key");i&&(await $e("set_company_public_key",{public_key_b64:i}),console.log("[peer-manager] Company public key set for Ed25519 verification"))}catch(n){console.warn("[peer-manager] Could not set company public key:",n)}try{const{btService:n}=await N(async()=>{const{btService:i}=await Promise.resolve().then(()=>zt);return{btService:i}},void 0);await n.start(e,t,s)}catch(n){console.warn("[peer-manager] Multipeer not available:",n)}jt=setInterval(async()=>{try{await Zs()}catch(n){console.error("[peer-manager] Peer poll error:",n)}},1e4),At=setInterval(async()=>{try{await Uu()}catch(n){console.error("[peer-manager] Inbox processing error:",n)}},5e3),await Zs()}catch(r){console.error("[peer-manager] Failed to start P2P sync:",r)}}async function Du(){jt&&(clearInterval(jt),jt=null),At&&(clearInterval(At),At=null);try{const{btService:e}=await N(async()=>{const{btService:t}=await Promise.resolve().then(()=>zt);return{btService:t}},void 0);await e.stop()}catch{}ze({running:!1,sync_port:0,peers:[],syncing_with:null})}async function Zs(){const e=[],t=new Set;try{const s=await $e("get_discovered_peers");for(const r of s)t.add(r.device_id),e.push({...r,transport:"lan"})}catch(s){console.error("[peer-manager] mDNS peer poll error:",s)}try{const{btService:s}=await N(async()=>{const{btService:r}=await Promise.resolve().then(()=>zt);return{btService:r}},void 0);if(s.status==="running")for(const r of s.nearbyDevices)t.has(r.deviceId)||(t.add(r.deviceId),e.push({device_id:r.deviceId,device_name:r.name??"Unknown Device",company_id:r.companyId,host:"",port:0,version:"",discovered_at:new Date().toISOString(),transport:"multipeer",multipeer_state:r.state}))}catch{}ze({peers:e})}async function Gr(e){const{getPendingChanges:t,markSynced:s,getVectorClock:r,updateVectorClock:n,registerPeerDevice:i,updatePeerSyncTime:o}=await N(async()=>{const{getPendingChanges:u,markSynced:E,getVectorClock:_,updateVectorClock:m,registerPeerDevice:y,updatePeerSyncTime:f}=await Promise.resolve().then(()=>Ur);return{getPendingChanges:u,markSynced:E,getVectorClock:_,updateVectorClock:m,registerPeerDevice:y,updatePeerSyncTime:f}},void 0),{getDeviceId:c}=await N(async()=>{const{getDeviceId:u}=await Promise.resolve().then(()=>ou);return{getDeviceId:u}},void 0),d=await c(),l=new Date().toISOString();ze({syncing_with:e.device_id});try{await i(e.device_id,e.device_name);const u=await t(),E=await $r(u);let _=0,m=0;if(e.transport==="multipeer"&&e.multipeer_state==="connected"){const{btService:f}=await N(async()=>{const{btService:v}=await Promise.resolve().then(()=>zt);return{btService:v}},void 0);if(E.length>0){const v=JSON.stringify(E);if(await f.sendToPeer(e.device_id,v)){_=E.length;const T=u.map(g=>g.id);await s(T,`mp-${Date.now()}`)}}}else{let f={};try{const{getSyncAuthFields:T}=await N(async()=>{const{getSyncAuthFields:L}=await Promise.resolve().then(()=>oi);return{getSyncAuthFields:L}},void 0),g=await T();g&&(f={certificate_data:g.certificate_data,certificate_signature:g.signature})}catch{}if(E.length>0){const T=await fetch(`http://${e.host}:${e.port}/sync/push`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({device_id:d,company_id:e.company_id,last_sync_at:Ee.last_peer_syncs[e.device_id]?.synced_at??null,changes:E,auth:f}),signal:AbortSignal.timeout(3e4)});if(T.ok){const g=await T.json();if(_=g.accepted??0,_>0&&g.sync_batch_id){const L=u.map(w=>w.id);await s(L,g.sync_batch_id)}}}const v=await r(),h=await fetch(`http://${e.host}:${e.port}/sync/pull`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({device_id:d,company_id:e.company_id,vector_clock:v,last_sync_at:Ee.last_peer_syncs[e.device_id]?.synced_at??null,auth:f}),signal:AbortSignal.timeout(3e4)});if(h.ok){const T=await h.json(),g=T.changes??[],L=T.server_device_id;if(m=g.length,g.length>0){await Br(g);const w=Math.max(...g.map(O=>O.id??0));w>0&&L&&await n(L,w)}}}await o(e.device_id);const y={peer_device_id:e.device_id,peer_name:e.device_name,pushed:_,pulled:m,success:!0,synced_at:l};return ze({syncing_with:null,last_peer_syncs:{...Ee.last_peer_syncs,[e.device_id]:y}}),await $e("update_sync_timestamp",{timestamp:l}),console.log(`[peer-manager] Synced with ${e.device_name}: pushed ${_}, pulled ${m}`),y}catch(u){const E={peer_device_id:e.device_id,peer_name:e.device_name,pushed:0,pulled:0,success:!1,error:u instanceof Error?u.message:"Sync failed",synced_at:l};return ze({syncing_with:null,last_peer_syncs:{...Ee.last_peer_syncs,[e.device_id]:E}}),console.error(`[peer-manager] Sync with ${e.device_name} failed:`,u),E}}async function Fu(){const e=[],t=[...Ee.peers].sort((s,r)=>{const n=er(s),i=er(r);if(n&&!i)return-1;if(!n&&i)return 1;const o=Ee.last_peer_syncs[s.device_id]?.synced_at??"",c=Ee.last_peer_syncs[r.device_id]?.synced_at??"";return o.localeCompare(c)});for(const s of t){if(s.transport==="multipeer"&&s.multipeer_state!=="connected")continue;const r=await Gr(s);e.push(r)}return e}function er(e){const t=e.device_name.toLowerCase();return t.includes("office")||t.includes("shop")||t.includes("server")||t.includes("main")}async function Uu(){if(!Ee.running)return;const e=await $e("get_sync_inbox");!e||e.length===0||(await Br(e),await $e("clear_sync_inbox"),console.log(`[peer-manager] Processed ${e.length} inbox changes`))}async function Br(e){try{const{resolveAndApplyChanges:t}=await N(async()=>{const{resolveAndApplyChanges:n}=await Promise.resolve().then(()=>bp);return{resolveAndApplyChanges:n}},void 0),s=e.map(n=>({id:n.id,device_id:n.device_id??"unknown",table_name:n.table_name,record_id:String(n.record_id),operation:n.operation,changed_fields:n.changed_fields??null,old_values:n.old_values??null,record_data:n.record_data??null,timestamp:n.timestamp??new Date().toISOString()})),r=await t(s);console.log(`[peer-manager] Conflict resolver: applied=${r.applied}, conflicts=${r.conflicts}, skipped=${r.skipped}, errors=${r.errors}`)}catch(t){console.error("[peer-manager] Conflict resolver failed, falling back to naive apply:",t),await Pu(e)}}async function Pu(e){const{getDb:t}=await N(async()=>{const{getDb:r}=await Promise.resolve().then(()=>kr);return{getDb:r}},void 0),s=await t();for(const r of e){const{table_name:n,record_id:i,operation:o,record_data:c,changed_fields:d}=r;try{if(o==="DELETE")try{await s.run(`UPDATE [${n}] SET deleted_at = datetime('now') WHERE id = ?`,[i])}catch{await s.run(`DELETE FROM [${n}] WHERE id = ?`,[i])}else if(c){const l=typeof c=="string"?JSON.parse(c):c,u=Object.keys(l),E=u.map(()=>"?").join(", "),_=u.map(m=>l[m]);await s.run(`INSERT OR REPLACE INTO [${n}] (${u.join(", ")}) VALUES (${E})`,_)}else if(d&&o==="UPDATE"){const l=typeof d=="string"?JSON.parse(d):d,u=Object.keys(l);if(u.length===0)continue;const E=u.map(m=>`${m} = ?`).join(", "),_=u.map(m=>l[m]);await s.run(`UPDATE [${n}] SET ${E} WHERE id = ?`,[..._,i])}}catch(l){console.error(`[peer-manager] Naive apply failed: ${n}.${i}`,l)}}}async function $r(e){const{getDb:t}=await N(async()=>{const{getDb:n}=await Promise.resolve().then(()=>kr);return{getDb:n}},void 0),s=await t(),r=[];for(const n of e){const i={...n};if(n.operation!=="DELETE")try{const o=await s.query(`SELECT * FROM [${n.table_name}] WHERE id = ?`,[n.record_id]);o.values&&o.values.length>0&&(i.record_data=JSON.stringify(o.values[0]))}catch{}r.push(i)}return r}async function Mu(){if(!ce()||!Ee.running)return;const{getPendingChanges:e}=await N(async()=>{const{getPendingChanges:r}=await Promise.resolve().then(()=>Ur);return{getPendingChanges:r}},void 0),t=await e(),s=await $r(t);await $e("set_sync_outbox",{changes:s})}const Xu=Object.freeze(Object.defineProperty({__proto__:null,getPeerManagerState:Au,onPeerManagerStateChange:Iu,refreshOutbox:Mu,startPeerSync:ku,stopPeerSync:Du,syncWithAllPeers:Fu,syncWithPeer:Gr},Symbol.toStringTag,{value:"Module"}));function Ce({className:e,noPadding:t,children:s,...r}){return a.jsx("div",{className:we("bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm",!t&&"p-6",e),...r,children:s})}function ma({title:e,subtitle:t,action:s,className:r,...n}){return a.jsxs("div",{className:we("flex items-center justify-between mb-4",r),...n,children:[a.jsxs("div",{children:[a.jsx("h3",{className:"text-lg font-semibold text-gray-900 dark:text-gray-100",children:e}),t&&a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400 mt-0.5",children:t})]}),s]})}function qu(e){return e?b.isValidElement(e)?e:typeof e=="function"||typeof e=="object"&&e!==null&&"$$typeof"in e?b.createElement(e,{className:"h-12 w-12"}):e:null}function le({icon:e,title:t,description:s,action:r,className:n}){const i=qu(e);return a.jsxs("div",{className:we("flex flex-col items-center justify-center py-16 px-6 text-center",n),children:[i&&a.jsx("div",{className:"mb-4 text-gray-400 dark:text-gray-500",children:i}),a.jsx("h3",{className:"text-lg font-semibold text-gray-900 dark:text-gray-100 mb-1",children:t}),s&&a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400 max-w-md mb-6",children:s}),r]})}async function Tm(){return R(async()=>{const{data:e}=await x.get("/costs/settings");return e.data},async()=>{const{getCompanySettings:e}=await N(async()=>{const{getCompanySettings:t}=await Promise.resolve().then(()=>de);return{getCompanySettings:t}},void 0);return e()})}async function Gu(e){return R(async()=>{const{data:t}=await x.get(`/costs/part/${e}/layers`);return t.data},async()=>{const{getCostLayers:t}=await N(async()=>{const{getCostLayers:s}=await Promise.resolve().then(()=>de);return{getCostLayers:s}},void 0);return t(e)})}async function Bu(e,t=90){return R(async()=>{const{data:s}=await x.get(`/costs/part/${e}/history`,{params:{days:t}});return s.data},async()=>{const{getCostHistory:s}=await N(async()=>{const{getCostHistory:r}=await Promise.resolve().then(()=>de);return{getCostHistory:r}},void 0);return s(e,t)})}async function $u(e){return R(async()=>{const{data:t}=await x.get(`/costs/part/${e}/summary`);return t.data},async()=>{const{getPartCostSummary:t}=await N(async()=>{const{getPartCostSummary:s}=await Promise.resolve().then(()=>de);return{getPartCostSummary:s}},void 0);return t(e)})}async function Hu(e,t){return R(async()=>{const{data:s}=await x.put(`/costs/part/${e}/margin`,{margin_percent:t});return s.data},async()=>{const{setCustomMargin:s}=await N(async()=>{const{setCustomMargin:r}=await Promise.resolve().then(()=>de);return{setCustomMargin:r}},void 0);return s(e,t)})}async function Wu(e){return R(async()=>{const{data:t}=await x.delete(`/costs/part/${e}/margin`);return t.data},async()=>{const{clearCustomMargin:t}=await N(async()=>{const{clearCustomMargin:s}=await Promise.resolve().then(()=>de);return{clearCustomMargin:s}},void 0);return t(e)})}async function Nm(){return R(async()=>{const{data:e}=await x.post("/costs/enforce-default-margin");return e.data},async()=>{const{enforceDefaultMargin:e}=await N(async()=>{const{enforceDefaultMargin:t}=await Promise.resolve().then(()=>de);return{enforceDefaultMargin:t}},void 0);return e()})}async function hm(e){return R(async()=>{const{data:t}=await x.get("/costs/dashboard",{params:e});return t.data},async()=>{const{getSpendingSummary:t}=await N(async()=>{const{getSpendingSummary:s}=await Promise.resolve().then(()=>de);return{getSpendingSummary:s}},void 0);return t(e)})}async function xm(e){return R(async()=>{const{data:t}=await x.get("/costs/spending/by-supplier",{params:e});return t.data},async()=>{const{getSpendingBySupplier:t}=await N(async()=>{const{getSpendingBySupplier:s}=await Promise.resolve().then(()=>de);return{getSpendingBySupplier:s}},void 0);return t(e)})}async function bm(e){return R(async()=>{const{data:t}=await x.get("/costs/spending/by-category",{params:e});return t.data},async()=>{const{getSpendingByCategory:t}=await N(async()=>{const{getSpendingByCategory:s}=await Promise.resolve().then(()=>de);return{getSpendingByCategory:s}},void 0);return t(e)})}async function fm(e){return R(async()=>{const{data:t}=await x.get("/costs/spending/by-job",{params:e});return t.data},async()=>{const{getSpendingByJob:t}=await N(async()=>{const{getSpendingByJob:s}=await Promise.resolve().then(()=>de);return{getSpendingByJob:s}},void 0);return t(e)})}async function vm(e){return R(async()=>{const{data:t}=await x.get("/costs/spending/trend",{params:e});return t.data},async()=>{const{getSpendingTrend:t}=await N(async()=>{const{getSpendingTrend:s}=await Promise.resolve().then(()=>de);return{getSpendingTrend:s}},void 0);return t(e)})}async function Rm(e){return R(async()=>{const{data:t}=await x.get(`/costs/job/${e}/rollup`);return t.data},async()=>{const{getJobCostRollup:t}=await N(async()=>{const{getJobCostRollup:s}=await Promise.resolve().then(()=>de);return{getJobCostRollup:s}},void 0);return t(e)})}async function wm(e){return R(async()=>{const{data:t}=await x.get(`/costs/job/${e}/budget-status`);return t.data},async()=>{const{getJobBudgetStatus:t}=await N(async()=>{const{getJobBudgetStatus:s}=await Promise.resolve().then(()=>de);return{getJobBudgetStatus:s}},void 0);return t(e)})}async function Lm(e){return R(async()=>{const{data:t}=await x.get("/costs/variance-report",{params:e});return t.data},async()=>{const{getPriceVarianceReport:t}=await N(async()=>{const{getPriceVarianceReport:s}=await Promise.resolve().then(()=>de);return{getPriceVarianceReport:s}},void 0);return t(e)})}async function Sm(){return R(async()=>{const{data:e}=await x.get("/costs/budget-alerts");return e.data},async()=>{const{getBudgetAlerts:e}=await N(async()=>{const{getBudgetAlerts:t}=await Promise.resolve().then(()=>de);return{getBudgetAlerts:t}},void 0);return e()})}async function Cm(){return R(async()=>{const{data:e}=await x.get("/costs/daily-report");return e.data},async()=>{const{getDailyReport:e}=await N(async()=>{const{getDailyReport:t}=await Promise.resolve().then(()=>de);return{getDailyReport:t}},void 0);return e()})}const q=b.forwardRef(({label:e,error:t,hint:s,icon:r,iconRight:n,className:i,id:o,...c},d)=>{const l=o??e?.toLowerCase().replace(/\s+/g,"-");return a.jsxs("div",{className:"space-y-1.5",children:[e&&a.jsx("label",{htmlFor:l,className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:e}),a.jsxs("div",{className:"relative",children:[r&&a.jsx("div",{className:"absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-gray-400",children:r}),a.jsx("input",{ref:d,id:l,className:we("block w-full rounded-lg border bg-white dark:bg-gray-800","px-3 py-2 text-sm text-gray-900 dark:text-gray-100","placeholder:text-gray-400 dark:placeholder:text-gray-500","focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500","transition-colors duration-150",t?"border-red-300 focus:border-red-500 focus:ring-red-200":"border-gray-300 dark:border-gray-600",r&&"pl-10",n&&"pr-10",i),...c}),n&&a.jsx("div",{className:"absolute inset-y-0 right-0 pr-3 flex items-center text-gray-400",children:n})]}),t&&a.jsx("p",{className:"text-sm text-red-500",children:t}),s&&!t&&a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400",children:s})]})});q.displayName="Input";const Ku={sm:"max-w-md",md:"max-w-lg",lg:"max-w-2xl",xl:"max-w-4xl",full:"max-w-[95vw]"};function Ne({isOpen:e,onClose:t,title:s,size:r="md",children:n,persistent:i=!1}){return b.useEffect(()=>{if(!e)return;const o=c=>{c.key==="Escape"&&!i&&t()};return document.addEventListener("keydown",o),document.body.style.overflow="hidden",()=>{document.removeEventListener("keydown",o),document.body.style.overflow=""}},[e,t,i]),e?a.jsxs("div",{className:"fixed inset-0 z-50 flex items-center justify-center p-4",children:[a.jsx("div",{className:"absolute inset-0 bg-black/50 backdrop-blur-sm",onClick:i?void 0:t}),a.jsxs("div",{className:we("relative w-full bg-white dark:bg-gray-800 rounded-2xl shadow-2xl","max-h-[90vh] flex flex-col","animate-in fade-in zoom-in-95 duration-200",Ku[r]),children:[s&&a.jsxs("div",{className:"flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-700",children:[a.jsx("h2",{className:"text-lg font-semibold text-gray-900 dark:text-gray-100",children:s}),a.jsx("button",{onClick:t,className:"p-2 rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:text-gray-300 dark:hover:bg-gray-700 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center",children:a.jsx(He,{className:"h-5 w-5"})})]}),a.jsx("div",{className:"flex-1 overflow-y-auto px-6 py-4",children:n})]})]}):null}async function Ga(){return R(async()=>{const{data:e}=await x.get("/parts/hierarchy");return e.data},async()=>{const{getHierarchy:e}=await N(async()=>{const{getHierarchy:t}=await Promise.resolve().then(()=>U);return{getHierarchy:t}},void 0);return await e()})}async function Ba(e){return R(async()=>{const{data:t}=await x.get("/parts/categories",{params:e});return t.data??[]},async()=>{const{getCategories:t}=await N(async()=>{const{getCategories:s}=await Promise.resolve().then(()=>U);return{getCategories:s}},void 0);return await t(e)})}async function Yu(e){return R(async()=>{const{data:t}=await x.post("/parts/categories",e);return t.data},async()=>{const{createCategory:t}=await N(async()=>{const{createCategory:s}=await Promise.resolve().then(()=>U);return{createCategory:s}},void 0);return await t(e)})}async function tr(e,t){return R(async()=>{const{data:s}=await x.put(`/parts/categories/${e}`,t);return s.data},async()=>{const{updateCategory:s}=await N(async()=>{const{updateCategory:r}=await Promise.resolve().then(()=>U);return{updateCategory:r}},void 0);return await s(e,t)})}async function Vu(e){return R(async()=>{await x.delete(`/parts/categories/${e}`)},async()=>{const{deleteCategory:t}=await N(async()=>{const{deleteCategory:s}=await Promise.resolve().then(()=>U);return{deleteCategory:s}},void 0);await t(e)})}async function Ft(e,t){return R(async()=>{const{data:s}=await x.get(`/parts/categories/${e}/styles`,{params:t});return s.data??[]},async()=>{const{listStylesByCategory:s}=await N(async()=>{const{listStylesByCategory:r}=await Promise.resolve().then(()=>U);return{listStylesByCategory:r}},void 0);return await s(e,t)})}async function Hr(e){return R(async()=>{const{data:t}=await x.post("/parts/styles",e);return t.data},async()=>{const{createStyle:t}=await N(async()=>{const{createStyle:s}=await Promise.resolve().then(()=>U);return{createStyle:s}},void 0);return await t(e)})}async function ar(e,t){return R(async()=>{const{data:s}=await x.put(`/parts/styles/${e}`,t);return s.data},async()=>{const{updateStyle:s}=await N(async()=>{const{updateStyle:r}=await Promise.resolve().then(()=>U);return{updateStyle:r}},void 0);return await s(e,t)})}async function Wr(e){return R(async()=>{await x.delete(`/parts/styles/${e}`)},async()=>{const{deleteStyle:t}=await N(async()=>{const{deleteStyle:s}=await Promise.resolve().then(()=>U);return{deleteStyle:s}},void 0);await t(e)})}async function Kr(e,t){return R(async()=>{const{data:s}=await x.get(`/parts/styles/${e}/types`,{params:t});return s.data??[]},async()=>{const{listTypesByStyle:s}=await N(async()=>{const{listTypesByStyle:r}=await Promise.resolve().then(()=>U);return{listTypesByStyle:r}},void 0);return await s(e,t)})}async function Ju(e){return R(async()=>{const{data:t}=await x.get(`/parts/types/${e}`);return t.data},async()=>{const{getType:t}=await N(async()=>{const{getType:s}=await Promise.resolve().then(()=>U);return{getType:s}},void 0);return await t(e)})}async function Yr(e){return R(async()=>{const{data:t}=await x.post("/parts/types",e);return t.data},async()=>{const{createType:t}=await N(async()=>{const{createType:s}=await Promise.resolve().then(()=>U);return{createType:s}},void 0);return await t(e)})}async function sr(e,t){return R(async()=>{const{data:s}=await x.put(`/parts/types/${e}`,t);return s.data},async()=>{const{updateType:s}=await N(async()=>{const{updateType:r}=await Promise.resolve().then(()=>U);return{updateType:r}},void 0);return await s(e,t)})}async function Vr(e){return R(async()=>{await x.delete(`/parts/types/${e}`)},async()=>{const{deleteType:t}=await N(async()=>{const{deleteType:s}=await Promise.resolve().then(()=>U);return{deleteType:s}},void 0);await t(e)})}async function Qu(e){return R(async()=>{const{data:t}=await x.get(`/parts/types/${e}/colors`);return t.data??[]},async()=>{const{listTypeColors:t}=await N(async()=>{const{listTypeColors:s}=await Promise.resolve().then(()=>U);return{listTypeColors:s}},void 0);return await t(e)})}async function zu(e,t){return R(async()=>{const{data:s}=await x.post(`/parts/types/${e}/colors`,t);return s.data??[]},async()=>{const{linkColorsToType:s}=await N(async()=>{const{linkColorsToType:r}=await Promise.resolve().then(()=>U);return{linkColorsToType:r}},void 0);return await s(e,t)})}async function Zu(e,t){return R(async()=>{await x.delete(`/parts/types/${e}/colors/${t}`)},async()=>{const{unlinkColorFromType:s}=await N(async()=>{const{unlinkColorFromType:r}=await Promise.resolve().then(()=>U);return{unlinkColorFromType:r}},void 0);await s(e,t)})}async function Jr(e){return R(async()=>{const{data:t}=await x.get(`/parts/types/${e}/brands`);return t.data??[]},async()=>{const{listTypeBrands:t}=await N(async()=>{const{listTypeBrands:s}=await Promise.resolve().then(()=>U);return{listTypeBrands:s}},void 0);return await t(e)})}async function e_(e,t){return R(async()=>{const{data:s}=await x.post(`/parts/types/${e}/brands`,{type_id:e,brand_id:t});return s.data},async()=>{const{linkBrandToType:s}=await N(async()=>{const{linkBrandToType:r}=await Promise.resolve().then(()=>U);return{linkBrandToType:r}},void 0);return await s(e,t)})}async function t_(e,t){return R(async()=>{const s=t===null?0:t;await x.delete(`/parts/types/${e}/brands/${s}`)},async()=>{const{unlinkBrandFromType:s}=await N(async()=>{const{unlinkBrandFromType:r}=await Promise.resolve().then(()=>U);return{unlinkBrandFromType:r}},void 0);await s(e,t)})}async function Qr(e,t){return R(async()=>{const s=t===null?0:t,{data:r}=await x.get(`/parts/types/${e}/brands/${s}/parts`);return r.data??[]},async()=>{const{listPartsForTypeBrand:s}=await N(async()=>{const{listPartsForTypeBrand:r}=await Promise.resolve().then(()=>U);return{listPartsForTypeBrand:r}},void 0);return await s(e,t)})}async function a_(e,t,s){return R(async()=>{const r=t===null?0:t,{data:n}=await x.post(`/parts/types/${e}/brands/${r}/parts`,{color_id:s});return n.data},async()=>{const{quickCreatePart:r}=await N(async()=>{const{quickCreatePart:n}=await Promise.resolve().then(()=>U);return{quickCreatePart:n}},void 0);return await r(e,t,s)})}async function $a(e){return R(async()=>{const{data:t}=await x.get("/parts/colors",{params:e});return t.data??[]},async()=>{const{listColors:t}=await N(async()=>{const{listColors:s}=await Promise.resolve().then(()=>U);return{listColors:s}},void 0);return await t(e)})}async function zr(e){return R(async()=>{const{data:t}=await x.post("/parts/colors",e);return t.data},async()=>{const{createColor:t}=await N(async()=>{const{createColor:s}=await Promise.resolve().then(()=>U);return{createColor:s}},void 0);return await t(e)})}async function rr(e,t){return R(async()=>{const{data:s}=await x.put(`/parts/colors/${e}`,t);return s.data},async()=>{const{updateColor:s}=await N(async()=>{const{updateColor:r}=await Promise.resolve().then(()=>U);return{updateColor:r}},void 0);return await s(e,t)})}async function s_(e){return R(async()=>{await x.delete(`/parts/colors/${e}`)},async()=>{const{deleteColor:t}=await N(async()=>{const{deleteColor:s}=await Promise.resolve().then(()=>U);return{deleteColor:s}},void 0);await t(e)})}async function Ha(e={}){return R(async()=>{const{data:t}=await x.get("/parts/catalog",{params:e});return t.data},async()=>{const{listParts:t}=await N(async()=>{const{listParts:r}=await Promise.resolve().then(()=>U);return{listParts:r}},void 0);return await t(e)})}async function r_(e){return R(async()=>{const{data:t}=await x.get(`/parts/catalog/${e}`);return t.data},async()=>{const{getPart:t}=await N(async()=>{const{getPart:r}=await Promise.resolve().then(()=>U);return{getPart:r}},void 0),s=await t(e);if(!s)throw new Error("Part not found");return s})}async function ba(e,t){return R(async()=>{const{data:s}=await x.put(`/parts/catalog/${e}`,t);return s.data},async()=>{const{updatePart:s}=await N(async()=>{const{updatePart:r}=await Promise.resolve().then(()=>U);return{updatePart:r}},void 0);return await s(e,t)})}async function Zr(e){return R(async()=>{await x.delete(`/parts/catalog/${e}`)},async()=>{const{deletePart:t}=await N(async()=>{const{deletePart:s}=await Promise.resolve().then(()=>U);return{deletePart:s}},void 0);await t(e)})}async function n_(e){return R(async()=>{const{data:t}=await x.get("/parts/catalog/groups",{params:e});return t.data??[]},async()=>{const{getCatalogGroups:t}=await N(async()=>{const{getCatalogGroups:s}=await Promise.resolve().then(()=>U);return{getCatalogGroups:s}},void 0);return await t(e)})}async function i_(){return R(async()=>{const{data:e}=await x.get("/parts/pending-part-numbers/count");return e.data.count},async()=>{const{getPendingPartNumbersCount:e}=await N(async()=>{const{getPendingPartNumbersCount:t}=await Promise.resolve().then(()=>U);return{getPendingPartNumbersCount:t}},void 0);return await e()})}async function o_(e,t){return R(async()=>{await x.put(`/parts/catalog/${e}/pricing`,t)},async()=>{const{updatePartPricing:s}=await N(async()=>{const{updatePartPricing:r}=await Promise.resolve().then(()=>U);return{updatePartPricing:r}},void 0);await s(e,t)})}async function Wa(e){return R(async()=>{const{data:t}=await x.get("/parts/brands",{params:e});return t.data??[]},async()=>{const{listBrands:t}=await N(async()=>{const{listBrands:s}=await Promise.resolve().then(()=>U);return{listBrands:s}},void 0);return await t(e)})}async function c_(e){return R(async()=>{const{data:t}=await x.post("/parts/brands",e);return t.data},async()=>{const{createBrand:t}=await N(async()=>{const{createBrand:s}=await Promise.resolve().then(()=>U);return{createBrand:s}},void 0);return await t(e)})}async function nr(e,t){return R(async()=>{const{data:s}=await x.put(`/parts/brands/${e}`,t);return s.data},async()=>{const{updateBrand:s}=await N(async()=>{const{updateBrand:r}=await Promise.resolve().then(()=>U);return{updateBrand:r}},void 0);return await s(e,t)})}async function l_(e){return R(async()=>{await x.delete(`/parts/brands/${e}`)},async()=>{const{deleteBrand:t}=await N(async()=>{const{deleteBrand:s}=await Promise.resolve().then(()=>U);return{deleteBrand:s}},void 0);await t(e)})}async function en(e){return R(async()=>{const{data:t}=await x.get(`/parts/brands/${e}/suppliers`);return t.data??[]},async()=>{const{getBrandSuppliers:t}=await N(async()=>{const{getBrandSuppliers:s}=await Promise.resolve().then(()=>U);return{getBrandSuppliers:s}},void 0);return await t(e)})}async function d_(e){return R(async()=>{const{data:t}=await x.get(`/parts/suppliers/${e}/brands`);return t.data??[]},async()=>{const{getSupplierBrands:t}=await N(async()=>{const{getSupplierBrands:s}=await Promise.resolve().then(()=>U);return{getSupplierBrands:s}},void 0);return await t(e)})}async function tn(e){return R(async()=>{const{data:t}=await x.post("/parts/brand-supplier-links",e);return t.data},async()=>{const{createBrandSupplierLink:t}=await N(async()=>{const{createBrandSupplierLink:s}=await Promise.resolve().then(()=>U);return{createBrandSupplierLink:s}},void 0);return await t(e)})}async function an(e){return R(async()=>{await x.delete(`/parts/brand-supplier-links/${e}`)},async()=>{const{deleteBrandSupplierLink:t}=await N(async()=>{const{deleteBrandSupplierLink:s}=await Promise.resolve().then(()=>U);return{deleteBrandSupplierLink:s}},void 0);await t(e)})}async function Ka(e){return R(async()=>{const{data:t}=await x.get("/parts/suppliers",{params:e});return t.data??[]},async()=>{const{listSuppliers:t}=await N(async()=>{const{listSuppliers:s}=await Promise.resolve().then(()=>U);return{listSuppliers:s}},void 0);return await t(e)})}async function u_(e){return R(async()=>{const{data:t}=await x.post("/parts/suppliers",e);return t.data},async()=>{const{createSupplier:t}=await N(async()=>{const{createSupplier:s}=await Promise.resolve().then(()=>U);return{createSupplier:s}},void 0);return await t(e)})}async function ir(e,t){return R(async()=>{const{data:s}=await x.put(`/parts/suppliers/${e}`,t);return s.data},async()=>{const{updateSupplier:s}=await N(async()=>{const{updateSupplier:r}=await Promise.resolve().then(()=>U);return{updateSupplier:r}},void 0);return await s(e,t)})}async function __(e){return R(async()=>{await x.delete(`/parts/suppliers/${e}`)},async()=>{const{deleteSupplier:t}=await N(async()=>{const{deleteSupplier:s}=await Promise.resolve().then(()=>U);return{deleteSupplier:s}},void 0);await t(e)})}async function E_(e){return R(async()=>{const{data:t}=await x.get("/parts/forecasting",{params:e});return t.data},async()=>{const{getForecasting:t}=await N(async()=>{const{getForecasting:s}=await Promise.resolve().then(()=>U);return{getForecasting:s}},void 0);return await t(e)})}async function p_(){return R(async()=>{const{data:e}=await x.post("/parts/forecasting/recalculate");return e.data},async()=>{const{recalculateForecasts:e}=await N(async()=>{const{recalculateForecasts:t}=await Promise.resolve().then(()=>U);return{recalculateForecasts:t}},void 0);return await e()})}async function m_(){return R(async()=>{const{data:e}=await x.get("/parts/export",{responseType:"blob"});return e},async()=>{const{exportPartsCsv:e}=await N(async()=>{const{exportPartsCsv:t}=await Promise.resolve().then(()=>U);return{exportPartsCsv:t}},void 0);return await e()})}async function y_(e){return R(async()=>{const t=new FormData;t.append("file",e);const{data:s}=await x.post("/parts/import",t,{headers:{"Content-Type":"multipart/form-data"}});return s.data},async()=>{const{importPartsCsv:t}=await N(async()=>{const{importPartsCsv:s}=await Promise.resolve().then(()=>U);return{importPartsCsv:s}},void 0);return await t(e)})}async function g_(){return R(async()=>{const{data:e}=await x.get("/parts/companions/rules");return e.data??[]},async()=>{const{listCompanionRules:e}=await N(async()=>{const{listCompanionRules:t}=await Promise.resolve().then(()=>U);return{listCompanionRules:t}},void 0);return await e()})}async function T_(e){return R(async()=>{const{data:t}=await x.post("/parts/companions/rules",e);return t.data},async()=>{const{createCompanionRule:t}=await N(async()=>{const{createCompanionRule:s}=await Promise.resolve().then(()=>U);return{createCompanionRule:s}},void 0);return await t(e)})}async function N_(e,t){return R(async()=>{const{data:s}=await x.put(`/parts/companions/rules/${e}`,t);return s.data},async()=>{const{updateCompanionRule:s}=await N(async()=>{const{updateCompanionRule:r}=await Promise.resolve().then(()=>U);return{updateCompanionRule:r}},void 0);return await s(e,t)})}async function h_(e){return R(async()=>{await x.delete(`/parts/companions/rules/${e}`)},async()=>{const{deleteCompanionRule:t}=await N(async()=>{const{deleteCompanionRule:s}=await Promise.resolve().then(()=>U);return{deleteCompanionRule:s}},void 0);await t(e)})}async function x_(e){return R(async()=>{const{data:t}=await x.post("/parts/companions/generate",e);return t.data??[]},async()=>{const{generateCompanionSuggestions:t}=await N(async()=>{const{generateCompanionSuggestions:s}=await Promise.resolve().then(()=>U);return{generateCompanionSuggestions:s}},void 0);return await t(e)})}async function or(e){return R(async()=>{const{data:t}=await x.get("/parts/companions/suggestions",{params:e});return t.data??[]},async()=>{const{listCompanionSuggestions:t}=await N(async()=>{const{listCompanionSuggestions:s}=await Promise.resolve().then(()=>U);return{listCompanionSuggestions:s}},void 0);return await t(e)})}async function b_(e,t){return R(async()=>{const{data:s}=await x.post(`/parts/companions/suggestions/${e}/decide`,t);return s.data},async()=>{const{decideCompanionSuggestion:s}=await N(async()=>{const{decideCompanionSuggestion:r}=await Promise.resolve().then(()=>U);return{decideCompanionSuggestion:r}},void 0);return await s(e,t)})}async function f_(){return R(async()=>{const{data:e}=await x.get("/parts/companions/stats");return e.data},async()=>{const{getCompanionStats:e}=await N(async()=>{const{getCompanionStats:t}=await Promise.resolve().then(()=>U);return{getCompanionStats:t}},void 0);return await e()})}async function v_(e){return R(async()=>{const{data:t}=await x.get(`/parts/catalog/${e}/alternatives`);return t.data??[]},async()=>{const{listPartAlternatives:t}=await N(async()=>{const{listPartAlternatives:s}=await Promise.resolve().then(()=>U);return{listPartAlternatives:s}},void 0);return await t(e)})}async function R_(e,t){return R(async()=>{const{data:s}=await x.post(`/parts/catalog/${e}/alternatives`,t);return s.data},async()=>{const{linkPartAlternative:s}=await N(async()=>{const{linkPartAlternative:r}=await Promise.resolve().then(()=>U);return{linkPartAlternative:r}},void 0);return await s(e,t)})}async function w_(e,t){return R(async()=>{const{data:s}=await x.put(`/parts/alternatives/${e}`,t);return s.data},async()=>{const{updatePartAlternative:s}=await N(async()=>{const{updatePartAlternative:r}=await Promise.resolve().then(()=>U);return{updatePartAlternative:r}},void 0);return await s(e,t)})}async function L_(e){return R(async()=>{await x.delete(`/parts/alternatives/${e}`)},async()=>{const{unlinkPartAlternative:t}=await N(async()=>{const{unlinkPartAlternative:s}=await Promise.resolve().then(()=>U);return{unlinkPartAlternative:s}},void 0);await t(e)})}const cr={substitute:{icon:hd,label:"Substitute",variant:"default"},upgrade:{icon:Nd,label:"Upgrade",variant:"primary"},compatible:{icon:Td,label:"Compatible",variant:"success"}};function S_({alt:e,viewingPartId:t,readOnly:s=!1,onEdit:r,onUnlink:n}){const i=e.part_id===t,o=i?e.alternative_name:e.part_name,c=i?e.alternative_code:e.part_code,d=e.alternative_brand_name,l=cr[e.relationship]??cr.substitute,u=l.icon;return a.jsxs("div",{className:"flex items-center gap-3 py-2.5 px-3 rounded-lg bg-gray-50 dark:bg-gray-800/50 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors group",children:[a.jsx("div",{className:"flex-shrink-0 w-5",children:e.preference>0?a.jsx(Gt,{className:"h-4 w-4 text-amber-500 fill-amber-500"}):a.jsx("span",{className:"h-4 w-4"})}),a.jsxs("div",{className:"flex-1 min-w-0",children:[a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx("span",{className:"text-sm font-medium text-gray-900 dark:text-gray-100 truncate",children:o??"Unknown Part"}),c&&a.jsx("span",{className:"text-xs text-gray-500 dark:text-gray-400 font-mono",children:c})]}),(d||e.notes)&&a.jsxs("div",{className:"flex items-center gap-2 mt-0.5",children:[d&&a.jsx("span",{className:"text-xs text-gray-500 dark:text-gray-400",children:d}),e.notes&&a.jsxs("span",{className:"text-xs text-gray-400 dark:text-gray-500 italic truncate",children:["— ",e.notes]})]})]}),a.jsxs(G,{variant:l.variant,children:[a.jsx(u,{className:"h-3 w-3 mr-1 inline"}),l.label]}),e.preference>0&&a.jsx(G,{variant:"warning",children:"Preferred"}),!s&&a.jsxs("div",{className:"flex items-center gap-1 shrink-0",children:[r&&a.jsx("button",{className:"p-2 rounded text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors",onClick:()=>r(e),title:"Edit link",children:a.jsx(xr,{className:"h-4 w-4"})}),n&&a.jsx("button",{className:"p-2 rounded text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors",onClick:()=>n(e),title:"Remove link",children:a.jsx(He,{className:"h-4 w-4"})})]})]})}const C_=[{value:"substitute",label:"Substitute",description:"Does the same job"},{value:"upgrade",label:"Upgrade",description:"Better/newer version"},{value:"compatible",label:"Compatible",description:"Works alongside"}];function O_({isOpen:e,onClose:t,partId:s,editingLink:r=null,onSave:n,isLoading:i=!1}){const[o,c]=b.useState(""),[d,l]=b.useState(""),[u,E]=b.useState(null),[_,m]=b.useState(""),[y,f]=b.useState("substitute"),[v,h]=b.useState(!1),[T,g]=b.useState("");b.useEffect(()=>{const M=setTimeout(()=>l(o),300);return()=>clearTimeout(M)},[o]),b.useEffect(()=>{if(r){f(r.relationship),h(r.preference>0),g(r.notes??"");const M=r.part_id===s?r.alternative_name:r.part_name;m(M??"Linked Part")}else c(""),l(""),E(null),m(""),f("substitute"),h(!1),g("")},[r,s,e]);const{data:L,isLoading:w}=B({queryKey:["catalog-search-alt",d],queryFn:()=>Ha({search:d,page:1,page_size:10,sort_by:"name",sort_dir:"asc"}),enabled:!r&&d.length>=2}),O=(L?.items??[]).filter(M=>M.id!==s),C=b.useCallback((M,te)=>{E(M),m(te),c(""),l("")},[]),W=()=>{if(r)n({relationship:y,preference:v?1:0,notes:T||void 0});else{if(!u)return;n({alternative_part_id:u,relationship:y,preference:v?1:0,notes:T||void 0})}},Q=r?!0:u!==null;return a.jsxs(Ne,{isOpen:e,onClose:t,title:r?"Edit Alternative Link":"Link Alternative Part",size:"md",children:[a.jsxs("div",{className:"space-y-4 max-h-[70vh] overflow-y-auto",children:[r?a.jsxs("div",{className:"flex items-center gap-2 p-3 rounded-lg bg-gray-50 dark:bg-gray-800/50 border border-gray-200 dark:border-gray-700",children:[a.jsx(Qe,{className:"h-4 w-4 text-gray-500 dark:text-gray-400"}),a.jsx("span",{className:"text-sm font-medium text-gray-700 dark:text-gray-300",children:_}),a.jsx(G,{variant:"default",children:"Linked"})]}):a.jsx("div",{children:u?a.jsxs("div",{className:"flex items-center gap-2 p-3 rounded-lg bg-primary-50 dark:bg-primary-900/20 border border-primary-200 dark:border-primary-800",children:[a.jsx(Qe,{className:"h-4 w-4 text-primary-600 dark:text-primary-400"}),a.jsx("span",{className:"text-sm font-medium text-primary-700 dark:text-primary-300",children:_}),a.jsx("button",{className:"ml-auto text-xs text-primary-500 hover:underline",onClick:()=>{E(null),m("")},children:"Change"})]}):a.jsxs("div",{className:"relative",children:[a.jsx(q,{label:"Search for a part",value:o,onChange:M=>c(M.target.value),placeholder:"Search by name, code, or MPN...",icon:a.jsx(st,{className:"h-4 w-4"})}),d.length>=2&&a.jsx("div",{className:"absolute z-10 left-0 right-0 top-full mt-1 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg shadow-lg max-h-48 overflow-y-auto",children:w?a.jsx("div",{className:"flex justify-center py-3",children:a.jsx(z,{size:"sm"})}):O.length===0?a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400 p-3 text-center",children:"No parts found"}):O.map(M=>a.jsxs("button",{className:"w-full text-left px-3 py-2 hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors border-b border-gray-100 dark:border-gray-700/50 last:border-b-0",onClick:()=>C(M.id,M.name),children:[a.jsxs("div",{className:"flex items-center justify-between",children:[a.jsx("span",{className:"text-sm font-medium text-gray-900 dark:text-gray-100",children:M.name}),M.code&&a.jsx("span",{className:"text-xs text-gray-500 font-mono",children:M.code})]}),a.jsxs("div",{className:"flex items-center gap-2 mt-0.5",children:[M.brand_name&&a.jsx("span",{className:"text-xs text-gray-500 dark:text-gray-400",children:M.brand_name}),M.category_name&&a.jsx("span",{className:"text-xs text-gray-400 dark:text-gray-500",children:M.category_name})]})]},M.id))})]})}),a.jsxs("div",{className:"space-y-2",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Relationship"}),a.jsx("div",{className:"grid grid-cols-3 gap-2",children:C_.map(M=>a.jsxs("button",{type:"button",onClick:()=>f(M.value),className:`
                  p-3 rounded-lg border text-center transition-colors
                  ${y===M.value?"border-primary-500 bg-primary-50 dark:bg-primary-900/20 text-primary-700 dark:text-primary-300":"border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 text-gray-700 dark:text-gray-300"}
                `,children:[a.jsx("div",{className:"text-sm font-medium",children:M.label}),a.jsx("div",{className:"text-xs text-gray-500 dark:text-gray-400 mt-0.5",children:M.description})]},M.value))})]}),a.jsxs("label",{className:"flex items-center gap-2 cursor-pointer select-none",children:[a.jsx("input",{type:"checkbox",checked:v,onChange:M=>h(M.target.checked),className:"rounded border-gray-300 dark:border-gray-600 text-primary-600 focus:ring-primary-500"}),a.jsx(Gt,{className:`h-4 w-4 ${v?"text-amber-500 fill-amber-500":"text-gray-400"}`}),a.jsx("span",{className:"text-sm text-gray-700 dark:text-gray-300",children:"Mark as preferred alternative"})]}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Notes"}),a.jsx("textarea",{value:T,onChange:M=>g(M.target.value),className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px]",placeholder:"e.g. Better quality, more customizable..."})]})]}),a.jsxs("div",{className:"flex justify-end gap-2 mt-4 pt-4 border-t border-gray-200 dark:border-gray-700",children:[a.jsx(F,{variant:"secondary",onClick:t,children:"Cancel"}),a.jsx(F,{variant:"primary",onClick:W,disabled:!Q,isLoading:i,children:r?"Update Link":"Link Part"})]})]})}function sn({partId:e,readOnly:t=!1}){const s=re(),[r,n]=b.useState(!0),[i,o]=b.useState(!1),[c,d]=b.useState(null),{data:l=[],isLoading:u}=B({queryKey:["part-alternatives",e],queryFn:()=>v_(e)}),E=P({mutationFn:g=>R_(e,{alternative_part_id:g.alternative_part_id,relationship:g.relationship,preference:g.preference,notes:g.notes}),onSuccess:()=>{s.invalidateQueries({queryKey:["part-alternatives",e]}),o(!1)}}),_=P({mutationFn:({linkId:g,data:L})=>w_(g,L),onSuccess:()=>{s.invalidateQueries({queryKey:["part-alternatives",e]}),d(null),o(!1)}}),m=P({mutationFn:L_,onSuccess:()=>{s.invalidateQueries({queryKey:["part-alternatives",e]})}}),y=g=>{d(g),o(!0)},f=g=>{confirm("Remove alternative link? This won't delete either part.")&&m.mutate(g.id)},v=g=>{c?_.mutate({linkId:c.id,data:{relationship:g.relationship,preference:g.preference,notes:g.notes}}):g.alternative_part_id&&E.mutate({alternative_part_id:g.alternative_part_id,relationship:g.relationship,preference:g.preference,notes:g.notes})},h=()=>{d(null),o(!0)},T=[...l].sort((g,L)=>{if(g.preference!==L.preference)return L.preference-g.preference;const w=(g.part_id===e?g.alternative_name:g.part_name)??"",O=(L.part_id===e?L.alternative_name:L.part_name)??"";return w.localeCompare(O)});return t?u||l.length===0?null:a.jsxs("div",{className:"space-y-2",children:[a.jsxs("h4",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1",children:[a.jsx(Ps,{className:"h-3.5 w-3.5"}),"Alternatives"]}),a.jsx("div",{className:"space-y-1",children:T.map(g=>{const L=g.part_id===e?g.alternative_name:g.part_name;return a.jsxs("div",{className:"flex items-center gap-2 text-sm",children:[g.preference>0&&a.jsx("span",{className:"text-amber-500",title:"Preferred",children:"★"}),a.jsx("span",{className:"text-gray-700 dark:text-gray-300",children:L??"Unknown"}),a.jsx(G,{variant:g.relationship==="upgrade"?"primary":g.relationship==="compatible"?"success":"default",children:g.relationship})]},g.id)})}),a.jsx("p",{className:"text-xs text-gray-400 dark:text-gray-500 italic",children:"Full edit in Categories →"})]}):a.jsxs("div",{className:"space-y-3 border-t border-gray-200 dark:border-gray-700 pt-4",children:[a.jsxs("div",{className:"flex items-center justify-between",children:[a.jsxs("button",{onClick:()=>n(!r),className:"flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 transition-colors",children:[r?a.jsx(Te,{className:"h-3.5 w-3.5"}):a.jsx(ye,{className:"h-3.5 w-3.5"}),a.jsx(Ps,{className:"h-3.5 w-3.5"}),"Alternatives",l.length>0&&a.jsxs("span",{className:"text-gray-400 dark:text-gray-500 font-normal normal-case",children:["(",l.length,")"]})]}),a.jsxs("button",{onClick:h,className:"text-xs text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1",title:"Link alternative part",children:[a.jsx(oe,{className:"h-3.5 w-3.5"}),"Link Part"]})]}),r&&a.jsx("div",{children:u?a.jsx("div",{className:"flex justify-center py-3",children:a.jsx(z,{size:"sm"})}):T.length===0?a.jsxs("div",{className:"text-center py-4",children:[a.jsx(Qe,{className:"h-8 w-8 text-gray-300 dark:text-gray-600 mx-auto mb-2"}),a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400",children:"No alternatives linked."}),a.jsx("button",{onClick:h,className:"text-xs text-primary-600 dark:text-primary-400 hover:underline mt-1",children:"+ Link a part"})]}):a.jsx("div",{className:"space-y-1",children:T.map(g=>a.jsx(S_,{alt:g,viewingPartId:e,onEdit:y,onUnlink:f},g.id))})}),a.jsx(O_,{isOpen:i,onClose:()=>{o(!1),d(null)},partId:e,editingLink:c,onSave:v,isLoading:E.isPending||_.isPending})]})}function Om(){const e=re(),t=gd(),{hasPermission:s}=Pe(),r=s(Fe.EDIT_PARTS_CATALOG),n=s(Fe.SHOW_DOLLAR_VALUES),[i,o]=b.useState("cards"),[c,d]=b.useState(""),[l,u]=b.useState({page:1,page_size:25,sort_by:"name",sort_dir:"asc"}),[E,_]=b.useState(!1),[m,y]=b.useState(null),[f,v]=b.useState(null),{data:h}=B({queryKey:["hierarchy"],queryFn:Ga,staleTime:300*1e3}),{data:T}=B({queryKey:["brands"],queryFn:()=>Wa()}),{data:g}=B({queryKey:["pendingPartNumbersCount"],queryFn:i_,staleTime:3e4}),L={...l,search:c||void 0},{data:w,isLoading:O,error:C}=B({queryKey:["parts",L],queryFn:()=>Ha(L),enabled:i==="table"}),{data:W,isLoading:Q,error:M}=B({queryKey:["catalogGroups",{search:c||void 0,category_id:l.category_id,is_deprecated:l.is_deprecated}],queryFn:()=>n_({search:c||void 0,category_id:l.category_id,is_deprecated:l.is_deprecated}),enabled:i==="cards"}),te=h?.categories??[],S=b.useMemo(()=>!l.category_id||!h?[]:h.categories.find(I=>I.id===l.category_id)?.styles??[],[l.category_id,h]),j=b.useMemo(()=>{if(!l.style_id||!h)return[];for(const I of h.categories){const ee=I.styles.find(yd=>yd.id===l.style_id);if(ee)return ee.types}return[]},[l.style_id,h]),K=h?.colors??[],ae=P({mutationFn:({id:I,data:ee})=>ba(I,ee),onSuccess:()=>{e.invalidateQueries({queryKey:["parts"]}),e.invalidateQueries({queryKey:["catalogGroups"]}),e.invalidateQueries({queryKey:["pendingPartNumbersCount"]}),y(null)}}),k=P({mutationFn:Zr,onSuccess:()=>{e.invalidateQueries({queryKey:["parts"]}),e.invalidateQueries({queryKey:["catalogGroups"]}),e.invalidateQueries({queryKey:["pendingPartNumbersCount"]}),e.invalidateQueries({queryKey:["hierarchy"]}),v(null)}}),A=b.useCallback(I=>{u(ee=>({...ee,sort_by:I,sort_dir:ee.sort_by===I&&ee.sort_dir==="asc"?"desc":"asc",page:1}))},[]),Z=({column:I})=>l.sort_by!==I?null:l.sort_dir==="asc"?a.jsx(Aa,{className:"inline h-3.5 w-3.5 ml-0.5"}):a.jsx(Te,{className:"inline h-3.5 w-3.5 ml-0.5"}),D=I=>I!=null?`$${I.toFixed(2)}`:"---",se=w?.items??[],ie=w?.total??0,$=w?.total_pages??0,V=l.page??1,Ve="rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm",md=i==="cards"?Q:O,Us=i==="cards"?M:C;return a.jsxs("div",{className:"space-y-4",children:[a.jsxs("div",{className:"flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between",children:[a.jsx("div",{className:"flex-1 w-full sm:max-w-md",children:a.jsx(q,{placeholder:"Search parts by code, name, or description...",icon:a.jsx(st,{className:"h-4 w-4"}),value:c,onChange:I=>{d(I.target.value),u(ee=>({...ee,page:1}))}})}),a.jsxs("div",{className:"flex gap-2 items-center",children:[(g??0)>0&&a.jsxs("button",{className:`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${l.has_pending_pn?"bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300 ring-1 ring-amber-300 dark:ring-amber-700":"bg-amber-50 text-amber-700 dark:bg-amber-900/20 dark:text-amber-400 hover:bg-amber-100 dark:hover:bg-amber-900/30"}`,onClick:()=>{o("table"),u(I=>({...I,has_pending_pn:I.has_pending_pn?void 0:!0,page:1}))},title:"Click to filter parts with pending part numbers",children:[a.jsx(Bt,{className:"h-4 w-4"}),g," Pending PN",g!==1?"s":""]}),a.jsxs("div",{className:"flex rounded-lg border border-gray-300 dark:border-gray-600 overflow-hidden",children:[a.jsx("button",{className:`p-1.5 transition-colors ${i==="cards"?"bg-primary-500 text-white":"bg-white dark:bg-gray-800 text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700"}`,onClick:()=>o("cards"),title:"Card grid view",children:a.jsx(xd,{className:"h-4 w-4"})}),a.jsx("button",{className:`p-1.5 transition-colors ${i==="table"?"bg-primary-500 text-white":"bg-white dark:bg-gray-800 text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700"}`,onClick:()=>o("table"),title:"Table view",children:a.jsx(bd,{className:"h-4 w-4"})})]}),a.jsx(F,{variant:"secondary",size:"sm",icon:a.jsx(fd,{className:"h-4 w-4"}),onClick:()=>_(!E),children:"Filters"}),r&&a.jsx(F,{variant:"secondary",size:"sm",icon:a.jsx(kt,{className:"h-4 w-4"}),onClick:()=>t("/parts/categories"),title:"Create and manage parts via the category tree",children:"Edit in Categories"})]})]}),E&&a.jsxs("div",{className:"flex flex-wrap gap-3 p-3 bg-gray-50 dark:bg-gray-800/50 rounded-lg border border-gray-200 dark:border-gray-700",children:[a.jsxs("select",{className:Ve,value:l.category_id??"",onChange:I=>u(ee=>({...ee,category_id:I.target.value?Number(I.target.value):void 0,style_id:void 0,type_id:void 0,page:1})),children:[a.jsx("option",{value:"",children:"All Categories"}),te.map(I=>a.jsx("option",{value:I.id,children:I.name},I.id))]}),i==="table"&&a.jsxs(a.Fragment,{children:[a.jsxs("select",{className:Ve,value:l.style_id??"",disabled:!l.category_id,onChange:I=>u(ee=>({...ee,style_id:I.target.value?Number(I.target.value):void 0,type_id:void 0,page:1})),children:[a.jsx("option",{value:"",children:"All Styles"}),S.map(I=>a.jsx("option",{value:I.id,children:I.name},I.id))]}),a.jsxs("select",{className:Ve,value:l.type_id??"",disabled:!l.style_id,onChange:I=>u(ee=>({...ee,type_id:I.target.value?Number(I.target.value):void 0,page:1})),children:[a.jsx("option",{value:"",children:"All Types"}),j.map(I=>a.jsx("option",{value:I.id,children:I.name},I.id))]}),a.jsxs("select",{className:Ve,value:l.color_id??"",onChange:I=>u(ee=>({...ee,color_id:I.target.value?Number(I.target.value):void 0,page:1})),children:[a.jsx("option",{value:"",children:"All Colors"}),K.map(I=>a.jsx("option",{value:I.id,children:I.name},I.id))]}),a.jsx("div",{className:"w-px bg-gray-300 dark:bg-gray-600 self-stretch"}),a.jsxs("select",{className:Ve,value:l.part_type??"",onChange:I=>u(ee=>({...ee,part_type:I.target.value||void 0,page:1})),children:[a.jsx("option",{value:"",children:"General + Specific"}),a.jsx("option",{value:"general",children:"General Only"}),a.jsx("option",{value:"specific",children:"Specific Only"})]}),a.jsxs("select",{className:Ve,value:l.brand_id??"",onChange:I=>u(ee=>({...ee,brand_id:I.target.value?Number(I.target.value):void 0,page:1})),children:[a.jsx("option",{value:"",children:"All Brands"}),T?.map(I=>a.jsx("option",{value:I.id,children:I.name},I.id))]}),a.jsx("div",{className:"w-px bg-gray-300 dark:bg-gray-600 self-stretch"}),a.jsxs("label",{className:"flex items-center gap-1.5 text-sm text-gray-600 dark:text-gray-400",children:[a.jsx("input",{type:"checkbox",className:"rounded",checked:l.low_stock??!1,onChange:I=>u(ee=>({...ee,low_stock:I.target.checked||void 0,page:1}))}),"Low Stock"]})]}),a.jsxs("label",{className:"flex items-center gap-1.5 text-sm text-gray-600 dark:text-gray-400",children:[a.jsx("input",{type:"checkbox",className:"rounded",checked:l.is_deprecated===!0,onChange:I=>u(ee=>({...ee,is_deprecated:I.target.checked||void 0,page:1}))}),"Deprecated"]}),a.jsx(F,{variant:"ghost",size:"sm",onClick:()=>{u({page:1,page_size:25,sort_by:"name",sort_dir:"asc"}),d("")},children:"Clear All"})]}),md?a.jsx("div",{className:"flex justify-center py-12",children:a.jsx(z,{size:"lg"})}):Us?a.jsx(le,{icon:a.jsx(Re,{className:"h-12 w-12 text-red-400"}),title:"Error loading parts",description:String(Us)}):i==="cards"?a.jsx(j_,{groups:W??[],canSeePricing:n,searchText:c}):a.jsxs(a.Fragment,{children:[a.jsx("div",{className:"text-sm text-gray-500 dark:text-gray-400",children:ie>0?a.jsxs(a.Fragment,{children:["Showing ",(V-1)*(l.page_size??25)+1,"–",Math.min(V*(l.page_size??25),ie)," of ",ie," parts"]}):"No parts found"}),a.jsx(A_,{items:se,canEdit:r,canSeePricing:n,handleSort:A,SortIcon:Z,formatDollars:D,onEdit:y,onDelete:v,searchText:c}),$>1&&a.jsxs("div",{className:"flex items-center justify-between",children:[a.jsx(F,{variant:"secondary",size:"sm",icon:a.jsx(ja,{className:"h-4 w-4"}),disabled:V<=1,onClick:()=>u(I=>({...I,page:(I.page??1)-1})),children:"Previous"}),a.jsxs("span",{className:"text-sm text-gray-500",children:["Page ",V," of ",$]}),a.jsx(F,{variant:"secondary",size:"sm",iconRight:a.jsx(ye,{className:"h-4 w-4"}),disabled:V>=$,onClick:()=>u(I=>({...I,page:(I.page??1)+1})),children:"Next"})]})]}),m&&a.jsx(I_,{part:m,onClose:()=>y(null),onSave:I=>ae.mutate({id:m.id,data:I}),isLoading:ae.isPending,error:ae.isError?ae.error?.response?.data?.detail:null,canEdit:r,canSeePricing:n,onNavigateToCategories:()=>t("/parts/categories")}),f&&a.jsxs(Ne,{isOpen:!0,onClose:()=>v(null),title:"Delete Part?",size:"sm",children:[a.jsxs("p",{className:"text-gray-600 dark:text-gray-300 mb-4",children:["Are you sure you want to delete ",a.jsx("strong",{children:f.name}),"? This cannot be undone."]}),k.isError&&a.jsx("p",{className:"text-red-500 text-sm mb-4",children:k.error?.response?.data?.detail??"Failed to delete part."}),a.jsxs("div",{className:"flex justify-end gap-2",children:[a.jsx(F,{variant:"secondary",onClick:()=>v(null),children:"Cancel"}),a.jsx(F,{variant:"danger",isLoading:k.isPending,onClick:()=>k.mutate(f.id),children:"Delete"})]})]})]})}function j_({groups:e,canSeePricing:t,searchText:s}){const[r,n]=b.useState(null);if(e.length===0)return a.jsx(le,{icon:a.jsx(Oe,{className:"h-12 w-12"}),title:"No parts found",description:s?"Try adjusting your search or filters.":"No parts in the catalog yet. Use the Categories page to create parts."});const i=o=>`${o.category_id}-${o.brand_id??"general"}`;return a.jsxs("div",{children:[a.jsxs("div",{className:"text-sm text-gray-500 dark:text-gray-400 mb-3",children:[e.length," group",e.length!==1?"s":""," ·"," ",e.reduce((o,c)=>o+c.variant_count,0)," total variants"]}),a.jsx("div",{className:"grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4",children:e.map(o=>{const c=i(o),d=r===c;return a.jsxs("div",{className:`border rounded-xl transition-all ${d?"border-primary-300 dark:border-primary-700 shadow-md col-span-full":"border-gray-200 dark:border-gray-700 hover:shadow-md hover:border-gray-300 dark:hover:border-gray-600"} bg-white dark:bg-gray-800 overflow-hidden`,children:[a.jsxs("button",{className:"w-full flex items-start gap-3 p-4 text-left",onClick:()=>n(d?null:c),children:[a.jsx("div",{className:"w-14 h-14 rounded-lg bg-gray-100 dark:bg-gray-700 flex items-center justify-center flex-shrink-0",children:o.image_url?a.jsx("img",{src:o.image_url,alt:"",className:"w-full h-full object-cover rounded-lg"}):a.jsx(Be,{className:"h-6 w-6 text-gray-400"})}),a.jsxs("div",{className:"flex-1 min-w-0",children:[a.jsxs("div",{className:"flex items-center gap-2 mb-0.5",children:[a.jsx("h3",{className:"text-sm font-semibold text-gray-900 dark:text-gray-100 truncate",children:o.category_name}),o.brand_name?a.jsx(G,{variant:"primary",children:o.brand_name}):a.jsx(G,{variant:"default",children:"General"})]}),a.jsxs("div",{className:"flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400",children:[a.jsxs("span",{children:[o.variant_count," variant",o.variant_count!==1?"s":""]}),a.jsxs("span",{children:[o.total_stock," in stock"]}),t&&o.price_range_low!=null&&a.jsxs("span",{children:["$",o.price_range_low.toFixed(2),o.price_range_high!=null&&o.price_range_high!==o.price_range_low&&a.jsxs(a.Fragment,{children:["–$",o.price_range_high.toFixed(2)]})]})]})]}),a.jsx("div",{className:"flex-shrink-0 pt-1",children:d?a.jsx(Aa,{className:"h-4 w-4 text-gray-400"}):a.jsx(Te,{className:"h-4 w-4 text-gray-400"})})]}),d&&a.jsx("div",{className:"border-t border-gray-200 dark:border-gray-700",children:a.jsx("div",{className:"overflow-x-auto",children:a.jsxs("table",{className:"w-full text-sm",children:[a.jsx("thead",{children:a.jsxs("tr",{className:"bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700",children:[a.jsx("th",{className:"text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs",children:"Style"}),a.jsx("th",{className:"text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs",children:"Type"}),a.jsx("th",{className:"text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs",children:"Color"}),a.jsx("th",{className:"text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs",children:"Name"}),a.jsx("th",{className:"text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs",children:"Code"}),a.jsx("th",{className:"text-right px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs",children:"Stock"}),t&&a.jsxs(a.Fragment,{children:[a.jsx("th",{className:"text-right px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs",children:"Cost"}),a.jsx("th",{className:"text-right px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs",children:"Sell"})]}),a.jsx("th",{className:"px-3 py-2 text-center text-xs font-medium text-gray-500 dark:text-gray-400",children:"Status"})]})}),a.jsx("tbody",{children:o.variants.map(l=>a.jsxs("tr",{className:"border-b border-gray-100 dark:border-gray-700/50 hover:bg-gray-50 dark:hover:bg-gray-700/30 transition-colors",children:[a.jsx("td",{className:"px-3 py-2 text-xs text-gray-600 dark:text-gray-400",children:l.style_name??"—"}),a.jsx("td",{className:"px-3 py-2 text-xs text-gray-600 dark:text-gray-400",children:l.type_name??"—"}),a.jsx("td",{className:"px-3 py-2 text-xs text-gray-600 dark:text-gray-400",children:l.color_name??"—"}),a.jsx("td",{className:"px-3 py-2 font-medium text-gray-900 dark:text-gray-100",children:l.name}),a.jsx("td",{className:"px-3 py-2 font-mono text-xs text-primary-600 dark:text-primary-400",children:l.code??a.jsx("span",{className:"text-gray-400",children:"—"})}),a.jsx("td",{className:"px-3 py-2 text-right font-medium",children:a.jsx("span",{className:l.total_stock<=0?"text-red-500":"text-gray-900 dark:text-gray-100",children:l.total_stock})}),t&&a.jsxs(a.Fragment,{children:[a.jsx("td",{className:"px-3 py-2 text-right text-xs text-gray-600 dark:text-gray-400",children:l.company_cost_price!=null?`$${l.company_cost_price.toFixed(2)}`:"---"}),a.jsx("td",{className:"px-3 py-2 text-right text-xs text-gray-600 dark:text-gray-400",children:l.company_sell_price!=null?`$${l.company_sell_price.toFixed(2)}`:"---"})]}),a.jsx("td",{className:"px-3 py-2 text-center",children:a.jsxs("div",{className:"flex justify-center gap-1",children:[l.has_pending_part_number&&a.jsx("span",{title:"Missing manufacturer part number",children:a.jsx(Ia,{className:"h-3.5 w-3.5 text-amber-500"})}),l.is_deprecated&&a.jsx(G,{variant:"warning",className:"text-[10px]",children:"depr"})]})})]},l.id))})]})})})]},c)})})]})}function A_({items:e,canEdit:t,canSeePricing:s,handleSort:r,SortIcon:n,formatDollars:i,onEdit:o,onDelete:c,searchText:d}){return e.length===0?a.jsx(le,{icon:a.jsx(Oe,{className:"h-12 w-12"}),title:"No parts found",description:d?"Try adjusting your search or filters.":"No parts in the catalog yet. Use the Categories page to create parts."}):a.jsx("div",{className:"overflow-x-auto border border-gray-200 dark:border-gray-700 rounded-xl",children:a.jsxs("table",{className:"w-full text-sm",children:[a.jsx("thead",{children:a.jsxs("tr",{className:"bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700",children:[a.jsxs("th",{className:"text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>r("category_name"),children:["Category ",a.jsx(n,{column:"category_name"})]}),a.jsxs("th",{className:"text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>r("style_name"),children:["Style ",a.jsx(n,{column:"style_name"})]}),a.jsxs("th",{className:"text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>r("type_name"),children:["Type ",a.jsx(n,{column:"type_name"})]}),a.jsxs("th",{className:"text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>r("color_name"),children:["Color ",a.jsx(n,{column:"color_name"})]}),a.jsxs("th",{className:"text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>r("name"),children:["Name ",a.jsx(n,{column:"name"})]}),a.jsxs("th",{className:"text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>r("code"),children:["Code ",a.jsx(n,{column:"code"})]}),a.jsxs("th",{className:"text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>r("brand_name"),children:["Brand ",a.jsx(n,{column:"brand_name"})]}),a.jsxs("th",{className:"text-right px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>r("total_stock"),children:["Stock ",a.jsx(n,{column:"total_stock"})]}),s&&a.jsxs(a.Fragment,{children:[a.jsxs("th",{className:"text-right px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>r("company_cost_price"),children:["Cost ",a.jsx(n,{column:"company_cost_price"})]}),a.jsxs("th",{className:"text-right px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>r("company_sell_price"),children:["Sell ",a.jsx(n,{column:"company_sell_price"})]})]}),a.jsx("th",{className:"px-3 py-3 font-medium text-gray-600 dark:text-gray-400 text-center",children:"Status"}),t&&a.jsx("th",{className:"px-3 py-3 font-medium text-gray-600 dark:text-gray-400 text-right",children:"Actions"})]})}),a.jsx("tbody",{children:e.map(l=>a.jsxs("tr",{className:"border-b border-gray-100 dark:border-gray-700/50 hover:bg-primary-50/50 dark:hover:bg-primary-900/10 transition-colors",children:[a.jsx("td",{className:"px-3 py-2.5 text-gray-600 dark:text-gray-400 text-xs",children:l.category_name??"—"}),a.jsx("td",{className:"px-3 py-2.5 text-gray-600 dark:text-gray-400 text-xs",children:l.style_name??"—"}),a.jsx("td",{className:"px-3 py-2.5 text-gray-600 dark:text-gray-400 text-xs",children:l.type_name??"—"}),a.jsx("td",{className:"px-3 py-2.5 text-gray-600 dark:text-gray-400 text-xs",children:l.color_name??"—"}),a.jsx("td",{className:"px-3 py-2.5 font-medium text-gray-900 dark:text-gray-100",children:l.name}),a.jsx("td",{className:"px-3 py-2.5 font-mono text-xs text-primary-600 dark:text-primary-400",children:l.code??a.jsx("span",{className:"text-gray-400",children:"—"})}),a.jsx("td",{className:"px-3 py-2.5 text-gray-600 dark:text-gray-400 text-xs",children:l.brand_name??"—"}),a.jsx("td",{className:"px-3 py-2.5 text-right font-medium",children:a.jsx("span",{className:l.total_stock<=0?"text-red-500":"text-gray-900 dark:text-gray-100",children:l.total_stock})}),s&&a.jsxs(a.Fragment,{children:[a.jsx("td",{className:"px-3 py-2.5 text-right text-gray-600 dark:text-gray-400 text-xs",children:i(l.company_cost_price)}),a.jsx("td",{className:"px-3 py-2.5 text-right text-gray-600 dark:text-gray-400 text-xs",children:i(l.company_sell_price)})]}),a.jsx("td",{className:"px-3 py-2.5 text-center",children:a.jsxs("div",{className:"flex justify-center gap-1",children:[l.has_pending_part_number&&a.jsx("span",{title:"Missing manufacturer part number",children:a.jsx(Ia,{className:"h-4 w-4 text-amber-500"})}),l.is_deprecated&&a.jsx(G,{variant:"warning",children:"depr"}),l.is_qr_tagged&&a.jsx(vd,{className:"h-4 w-4 text-green-500"})]})}),t&&a.jsx("td",{className:"px-3 py-2.5 text-right",children:a.jsxs("div",{className:"flex justify-end gap-1",children:[a.jsx("button",{className:"p-2 rounded text-gray-500 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors",onClick:()=>o(l),title:"Edit",children:a.jsx(Nt,{className:"h-4 w-4"})}),a.jsx("button",{className:"p-2 rounded text-red-400 hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors",onClick:()=>c(l),title:"Delete",children:a.jsx(pe,{className:"h-4 w-4"})})]})})]},l.id))})]})})}function I_({part:e,onClose:t,onSave:s,isLoading:r,error:n,canEdit:i,canSeePricing:o,onNavigateToCategories:c}){const[d,l]=b.useState(e.name),[u,E]=b.useState(e.code??""),[_,m]=b.useState(e.manufacturer_part_number??""),[y,f]=b.useState(e.company_cost_price!=null?String(e.company_cost_price):""),[v,h]=b.useState(e.company_markup_percent!=null?String(e.company_markup_percent):""),T=e.part_type==="specific",g=y&&v?(parseFloat(y)*(1+parseFloat(v)/100)).toFixed(2):e.company_sell_price?.toFixed(2)??"—",L=w=>{w.preventDefault(),s({name:d,code:u||void 0,manufacturer_part_number:_||void 0,company_cost_price:y?parseFloat(y):void 0,company_markup_percent:v?parseFloat(v):void 0})};return a.jsx(Ne,{isOpen:!0,onClose:t,title:`${i?"Edit":"View"}: ${e.name}`,size:"md",children:a.jsxs("form",{onSubmit:L,className:"space-y-4",children:[a.jsxs("div",{className:"flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400 bg-gray-50 dark:bg-gray-800/50 rounded-lg px-3 py-2",children:[a.jsx("span",{children:e.category_name}),e.style_name&&a.jsxs(a.Fragment,{children:[a.jsx("span",{children:"→"}),a.jsx("span",{children:e.style_name})]}),e.type_name&&a.jsxs(a.Fragment,{children:[a.jsx("span",{children:"→"}),a.jsx("span",{children:e.type_name})]}),e.color_name&&a.jsxs(a.Fragment,{children:[a.jsx("span",{children:"·"}),a.jsx("span",{children:e.color_name})]}),e.brand_name&&a.jsx(G,{variant:"primary",className:"ml-auto text-xs",children:e.brand_name}),!e.brand_name&&a.jsx(G,{variant:"default",className:"ml-auto text-xs",children:"General"})]}),a.jsx(q,{label:"Name",value:d,onChange:w=>l(w.target.value),disabled:!i,required:!0}),a.jsx(q,{label:"Code / SKU",value:u,onChange:w=>E(w.target.value),disabled:!i,placeholder:"Optional"}),T&&a.jsx(q,{label:"Manufacturer Part Number (MPN)",value:_,onChange:w=>m(w.target.value),disabled:!i,placeholder:e.has_pending_part_number?"Pending — add MPN":"MPN"}),o&&a.jsxs("div",{className:"grid grid-cols-3 gap-3",children:[a.jsx(q,{label:"Cost",value:y,onChange:w=>f(w.target.value),disabled:!i,type:"number",step:"0.01",min:"0"}),a.jsx(q,{label:"Markup %",value:v,onChange:w=>h(w.target.value),disabled:!i,type:"number",step:"0.1",min:"0"}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Sell"}),a.jsxs("div",{className:"px-3 py-2 rounded-lg bg-gray-100 dark:bg-gray-700 text-sm font-medium",children:["$",g]})]})]}),a.jsxs("div",{className:"flex items-center gap-4 text-sm text-gray-600 dark:text-gray-400 border-t border-gray-200 dark:border-gray-700 pt-3",children:[a.jsxs("span",{children:["Stock: ",a.jsx("strong",{className:e.total_stock<=0?"text-red-500":"",children:e.total_stock})]}),e.is_deprecated&&a.jsx(G,{variant:"danger",children:"Deprecated"}),e.has_pending_part_number&&a.jsxs("span",{className:"flex items-center gap-1 text-amber-500",children:[a.jsx(Ia,{className:"h-3.5 w-3.5"})," MPN needed"]})]}),a.jsx("div",{className:"border-t border-gray-200 dark:border-gray-700 pt-3",children:a.jsx(sn,{partId:e.id,readOnly:!0})}),n&&a.jsx("div",{className:"p-3 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800",children:a.jsx("p",{className:"text-sm text-red-600 dark:text-red-400",children:n})}),a.jsxs("div",{className:"flex items-center justify-between pt-2 border-t border-gray-200 dark:border-gray-700",children:[a.jsxs("button",{type:"button",className:"text-sm text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1",onClick:c,children:[a.jsx(kt,{className:"h-3.5 w-3.5"}),"Full edit in Categories"]}),a.jsxs("div",{className:"flex gap-2",children:[a.jsx(F,{variant:"secondary",type:"button",onClick:t,children:i?"Cancel":"Close"}),i&&a.jsx(F,{type:"submit",isLoading:r,children:"Save Changes"})]})]})]})})}function jm(){const e=re(),{hasPermission:t}=Pe(),s=t(Fe.EDIT_PARTS_CATALOG),[r,n]=b.useState(""),[i,o]=b.useState(null),[c,d]=b.useState(!1),[l,u]=b.useState(null),[E,_]=b.useState(null),{data:m,isLoading:y,error:f}=B({queryKey:["brands",{search:r||void 0}],queryFn:()=>Wa({search:r||void 0})}),v=P({mutationFn:c_,onSuccess:()=>{e.invalidateQueries({queryKey:["brands"]}),d(!1)}}),h=P({mutationFn:({id:w,data:O})=>nr(w,O),onSuccess:()=>{e.invalidateQueries({queryKey:["brands"]}),u(null)}}),T=P({mutationFn:l_,onSuccess:()=>{e.invalidateQueries({queryKey:["brands"]}),_(null)}}),g=P({mutationFn:({id:w,is_active:O})=>nr(w,{is_active:O}),onSuccess:()=>e.invalidateQueries({queryKey:["brands"]})}),L=m??[];return a.jsxs("div",{className:"space-y-4",children:[a.jsxs("div",{className:"flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between",children:[a.jsx("div",{className:"flex-1 w-full sm:max-w-md",children:a.jsx(q,{placeholder:"Search brands...",icon:a.jsx(st,{className:"h-4 w-4"}),value:r,onChange:w=>n(w.target.value)})}),s&&a.jsx(F,{size:"sm",icon:a.jsx(oe,{className:"h-4 w-4"}),onClick:()=>d(!0),children:"Add Brand"})]}),a.jsx("div",{className:"text-sm text-gray-500 dark:text-gray-400",children:y?"Loading...":`${L.length} brand${L.length!==1?"s":""}`}),y?a.jsx("div",{className:"flex justify-center py-12",children:a.jsx(z,{size:"lg"})}):f?a.jsx(le,{icon:a.jsx(Re,{className:"h-12 w-12 text-red-400"}),title:"Error loading brands",description:String(f)}):L.length===0?a.jsx(le,{icon:a.jsx(De,{className:"h-12 w-12"}),title:"No brands found",description:r?"Try a different search term.":"Add your first brand to get started."}):a.jsx("div",{className:"overflow-x-auto border border-gray-200 dark:border-gray-700 rounded-xl",children:a.jsxs("table",{className:"w-full text-sm",children:[a.jsx("thead",{children:a.jsxs("tr",{className:"bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700",children:[a.jsx("th",{className:"w-8 px-3 py-3"}),a.jsx("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Brand"}),a.jsx("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Website"}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Parts"}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Suppliers"}),a.jsx("th",{className:"text-center px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Status"}),a.jsx("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400 hidden lg:table-cell",children:"Notes"}),s&&a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Actions"})]})}),a.jsx("tbody",{children:L.map(w=>{const O=i===w.id;return a.jsx(k_,{brand:w,isExpanded:O,onToggleExpand:()=>o(O?null:w.id),canEdit:s,onEdit:()=>u(w),onDelete:()=>_(w),onToggleActive:()=>g.mutate({id:w.id,is_active:!w.is_active})},w.id)})})]})}),a.jsx(lr,{isOpen:c,onClose:()=>d(!1),onSubmit:w=>v.mutate(w),isLoading:v.isPending,title:"Add Brand"}),l&&a.jsx(lr,{isOpen:!0,onClose:()=>u(null),onSubmit:w=>h.mutate({id:l.id,data:w}),isLoading:h.isPending,title:`Edit: ${l.name}`,initial:l}),E&&a.jsxs(Ne,{isOpen:!0,onClose:()=>_(null),title:"Delete Brand?",size:"sm",children:[a.jsxs("p",{className:"text-gray-600 dark:text-gray-300 mb-2",children:["Are you sure you want to delete ",a.jsx("strong",{children:E.name}),"?"]}),E.part_count>0&&a.jsxs("p",{className:"text-amber-600 dark:text-amber-400 text-sm mb-4",children:["This brand has ",E.part_count," part",E.part_count!==1?"s":""," linked to it. You must reassign or remove those parts before deleting."]}),T.isError&&a.jsx("p",{className:"text-red-500 text-sm mb-4",children:T.error?.response?.data?.detail??"Failed to delete brand."}),a.jsxs("div",{className:"flex justify-end gap-2",children:[a.jsx(F,{variant:"secondary",onClick:()=>_(null),children:"Cancel"}),a.jsx(F,{variant:"danger",isLoading:T.isPending,onClick:()=>T.mutate(E.id),children:"Delete"})]})]})]})}function k_({brand:e,isExpanded:t,onToggleExpand:s,canEdit:r,onEdit:n,onDelete:i,onToggleActive:o}){return a.jsxs(a.Fragment,{children:[a.jsxs("tr",{className:"border-b border-gray-100 dark:border-gray-700/50 hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors cursor-pointer",onClick:s,children:[a.jsx("td",{className:"px-3 py-3 text-gray-400",children:t?a.jsx(Te,{className:"h-4 w-4"}):a.jsx(ye,{className:"h-4 w-4"})}),a.jsx("td",{className:"px-4 py-3 font-medium text-gray-900 dark:text-gray-100",children:e.name}),a.jsx("td",{className:"px-4 py-3",children:e.website?a.jsxs("a",{href:e.website,target:"_blank",rel:"noopener noreferrer",className:"inline-flex items-center gap-1 text-primary-500 hover:text-primary-600 hover:underline",onClick:c=>c.stopPropagation(),children:[a.jsx(br,{className:"h-3.5 w-3.5"}),a.jsx("span",{className:"truncate max-w-[200px]",children:e.website.replace(/^https?:\/\/(www\.)?/,"")})]}):a.jsx("span",{className:"text-gray-400",children:"—"})}),a.jsx("td",{className:"px-4 py-3 text-right font-medium text-gray-700 dark:text-gray-300",children:e.part_count}),a.jsx("td",{className:"px-4 py-3 text-right font-medium text-gray-700 dark:text-gray-300",children:e.supplier_count}),a.jsx("td",{className:"px-4 py-3 text-center",onClick:c=>c.stopPropagation(),children:r?a.jsx("button",{className:"inline-flex items-center gap-1 text-sm transition-colors",onClick:o,title:e.is_active?"Click to deactivate":"Click to activate",children:e.is_active?a.jsx(We,{className:"h-5 w-5 text-green-500"}):a.jsx(Ke,{className:"h-5 w-5 text-gray-400"})}):a.jsx(G,{variant:e.is_active?"success":"default",children:e.is_active?"Active":"Inactive"})}),a.jsx("td",{className:"px-4 py-3 text-gray-500 dark:text-gray-400 truncate max-w-[250px] hidden lg:table-cell",children:e.notes??"—"}),r&&a.jsx("td",{className:"px-4 py-3 text-right",onClick:c=>c.stopPropagation(),children:a.jsxs("div",{className:"flex justify-end gap-1",children:[a.jsx("button",{className:"p-2 rounded text-gray-500 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors",onClick:n,title:"Edit",children:a.jsx(Nt,{className:"h-4 w-4"})}),a.jsx("button",{className:"p-2 rounded text-red-400 hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors",onClick:i,title:"Delete",children:a.jsx(pe,{className:"h-4 w-4"})})]})})]}),t&&a.jsx("tr",{children:a.jsx("td",{colSpan:r?8:7,className:"px-0 py-0",children:a.jsx(D_,{brandId:e.id,brandName:e.name,canEdit:r})})})]})}function D_({brandId:e,brandName:t,canEdit:s}){const r=re(),[n,i]=b.useState(!1),[o,c]=b.useState(null),[d,l]=b.useState(""),[u,E]=b.useState(""),{data:_,isLoading:m}=B({queryKey:["brand-suppliers",e],queryFn:()=>en(e)}),{data:y}=B({queryKey:["suppliers"],queryFn:()=>Ka(),enabled:n}),f=new Set((_??[]).map(L=>L.supplier_id)),v=(y??[]).filter(L=>!f.has(L.id)&&L.is_active),h=P({mutationFn:tn,onSuccess:()=>{r.invalidateQueries({queryKey:["brand-suppliers",e]}),r.invalidateQueries({queryKey:["brands"]}),i(!1),c(null),l(""),E("")}}),T=P({mutationFn:an,onSuccess:()=>{r.invalidateQueries({queryKey:["brand-suppliers",e]}),r.invalidateQueries({queryKey:["brands"]})}}),g=()=>{o&&h.mutate({brand_id:e,supplier_id:o,account_number:d||void 0,notes:u||void 0})};return a.jsxs("div",{className:"bg-gray-50 dark:bg-gray-800/30 border-t border-gray-200 dark:border-gray-700 px-6 py-4",children:[a.jsxs("div",{className:"flex items-center justify-between mb-3",children:[a.jsxs("h4",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5",children:[a.jsx(Et,{className:"h-3.5 w-3.5"}),"Suppliers carrying ",t]}),s&&!n&&a.jsx(F,{size:"sm",variant:"secondary",icon:a.jsx(Qe,{className:"h-3.5 w-3.5"}),onClick:()=>i(!0),children:"Link Supplier"})]}),m?a.jsxs("div",{className:"flex items-center gap-2 py-2 text-sm text-gray-500",children:[a.jsx(z,{size:"sm"})," Loading suppliers..."]}):(_??[]).length===0&&!n?a.jsxs("p",{className:"text-sm text-gray-400 italic py-1",children:["No suppliers linked yet."," ",s&&a.jsx("button",{className:"text-primary-500 hover:text-primary-600 hover:underline not-italic",onClick:()=>i(!0),children:"Link one now"})]}):a.jsx("div",{className:"space-y-2",children:(_??[]).map(L=>a.jsxs("div",{className:"flex items-center justify-between py-2 px-3 bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700",children:[a.jsxs("div",{className:"flex items-center gap-3",children:[a.jsx(Et,{className:"h-4 w-4 text-gray-400"}),a.jsxs("div",{children:[a.jsx("span",{className:"text-sm font-medium text-gray-900 dark:text-gray-100",children:L.supplier_name}),L.account_number&&a.jsxs("span",{className:"ml-2 text-xs text-gray-500 dark:text-gray-400",children:["Acct: ",L.account_number]}),L.notes&&a.jsxs("span",{className:"ml-2 text-xs text-gray-400 italic",children:["— ",L.notes]})]})]}),s&&a.jsx("button",{className:"p-2 rounded text-red-400 hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors",onClick:()=>T.mutate(L.id),title:"Remove supplier link",children:a.jsx(Rd,{className:"h-4 w-4"})})]},L.id))}),n&&a.jsxs("div",{className:"mt-3 p-3 bg-white dark:bg-gray-800 rounded-lg border border-primary-200 dark:border-primary-800 space-y-3",children:[a.jsxs("div",{className:"flex items-center justify-between",children:[a.jsxs("span",{className:"text-sm font-medium text-gray-700 dark:text-gray-300 flex items-center gap-1.5",children:[a.jsx(Qe,{className:"h-3.5 w-3.5 text-primary-500"}),"Link a supplier to ",t]}),a.jsx("button",{className:"p-2 rounded text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors",onClick:()=>i(!1),children:a.jsx(He,{className:"h-4 w-4"})})]}),a.jsxs("div",{className:"grid grid-cols-1 sm:grid-cols-3 gap-3",children:[a.jsxs("div",{className:"space-y-1",children:[a.jsx("label",{className:"block text-xs font-medium text-gray-600 dark:text-gray-400",children:"Supplier *"}),a.jsxs("select",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm",value:o??"",onChange:L=>c(L.target.value?Number(L.target.value):null),children:[a.jsx("option",{value:"",children:"Select supplier..."}),v.map(L=>a.jsx("option",{value:L.id,children:L.name},L.id))]}),v.length===0&&a.jsx("p",{className:"text-xs text-gray-400 italic",children:"All active suppliers are already linked"})]}),a.jsxs("div",{className:"space-y-1",children:[a.jsx("label",{className:"block text-xs font-medium text-gray-600 dark:text-gray-400",children:"Account Number"}),a.jsx("input",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm",value:d,onChange:L=>l(L.target.value),placeholder:"e.g. CED-12345"})]}),a.jsxs("div",{className:"space-y-1",children:[a.jsx("label",{className:"block text-xs font-medium text-gray-600 dark:text-gray-400",children:"Notes"}),a.jsx("input",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm",value:u,onChange:L=>E(L.target.value),placeholder:"Optional notes..."})]})]}),a.jsxs("div",{className:"flex justify-end gap-2",children:[a.jsx(F,{variant:"secondary",size:"sm",onClick:()=>i(!1),children:"Cancel"}),a.jsx(F,{size:"sm",disabled:!o,isLoading:h.isPending,onClick:g,icon:a.jsx(Qe,{className:"h-3.5 w-3.5"}),children:"Link Supplier"})]}),h.isError&&a.jsx("p",{className:"text-red-500 text-sm",children:h.error?.response?.data?.detail??"Failed to create link."})]})]})}function lr({isOpen:e,onClose:t,onSubmit:s,isLoading:r,title:n,initial:i}){const[o,c]=b.useState({name:i?.name??"",website:i?.website??"",notes:i?.notes??""}),d=u=>{u.preventDefault(),s({name:o.name,website:o.website||void 0,notes:o.notes||void 0})},l=(u,E)=>c(_=>({..._,[u]:E}));return a.jsx(Ne,{isOpen:e,onClose:t,title:n,size:"md",children:a.jsxs("form",{onSubmit:d,className:"space-y-4",children:[a.jsx(q,{label:"Brand Name *",value:o.name,onChange:u=>l("name",u.target.value),placeholder:"e.g. Southwire",required:!0}),a.jsx(q,{label:"Website",value:o.website,onChange:u=>l("website",u.target.value),placeholder:"https://www.southwire.com",type:"url"}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Notes"}),a.jsx("textarea",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[80px]",value:o.notes,onChange:u=>l("notes",u.target.value),placeholder:"Optional notes about this brand..."})]}),i&&a.jsx(F_,{brandId:i.id,brandName:i.name}),a.jsxs("div",{className:"flex justify-end gap-2 pt-2 border-t border-gray-200 dark:border-gray-700",children:[a.jsx(F,{variant:"secondary",type:"button",onClick:t,children:"Cancel"}),a.jsx(F,{type:"submit",isLoading:r,children:i?"Save Changes":"Create Brand"})]})]})})}function F_({brandId:e,brandName:t}){const s=re(),{data:r,isLoading:n}=B({queryKey:["brand-suppliers",e],queryFn:()=>en(e)}),{data:i}=B({queryKey:["suppliers"],queryFn:()=>Ka()}),o=new Set((r??[]).map(u=>u.supplier_id)),c=(i??[]).filter(u=>!o.has(u.id)&&u.is_active),d=P({mutationFn:u=>tn({brand_id:e,supplier_id:u}),onSuccess:()=>{s.invalidateQueries({queryKey:["brand-suppliers",e]}),s.invalidateQueries({queryKey:["brands"]})}}),l=P({mutationFn:an,onSuccess:()=>{s.invalidateQueries({queryKey:["brand-suppliers",e]}),s.invalidateQueries({queryKey:["brands"]})}});return a.jsxs("div",{className:"space-y-2",children:[a.jsxs("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300 flex items-center gap-1.5",children:[a.jsx(Et,{className:"h-4 w-4 text-gray-400"}),"Suppliers"]}),a.jsxs("p",{className:"text-xs text-gray-500 dark:text-gray-400",children:["Which suppliers carry ",t," products?"]}),a.jsx("div",{className:"flex flex-wrap gap-2",children:n?a.jsxs("div",{className:"flex items-center gap-1.5 text-xs text-gray-400",children:[a.jsx(z,{size:"sm"})," Loading..."]}):(r??[]).length===0?a.jsx("p",{className:"text-sm text-gray-400 italic",children:"No suppliers linked yet."}):(r??[]).map(u=>a.jsxs("span",{className:"inline-flex items-center gap-1.5 text-sm px-2.5 py-1 rounded-full border border-gray-200 dark:border-gray-600 bg-gray-50 dark:bg-gray-700",children:[a.jsx(Et,{className:"h-3 w-3 text-gray-400"}),u.supplier_name,u.account_number&&a.jsxs("span",{className:"text-xs text-gray-400",children:["(",u.account_number,")"]}),a.jsx("button",{type:"button",className:"ml-0.5 p-1 rounded-full text-red-400 hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors",onClick:()=>l.mutate(u.id),title:`Remove ${u.supplier_name}`,children:a.jsx(He,{className:"h-3.5 w-3.5"})})]},u.id))}),c.length>0&&a.jsxs("select",{className:"w-full rounded-lg border border-dashed border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-500",value:"",onChange:u=>{u.target.value&&d.mutate(Number(u.target.value))},children:[a.jsx("option",{value:"",children:"+ Add a supplier..."}),c.map(u=>a.jsx("option",{value:u.id,children:u.name},u.id))]}),(d.isError||l.isError)&&a.jsx("p",{className:"text-red-500 text-xs",children:"Failed to update supplier link."})]})}function U_({partId:e,partName:t,canEdit:s}){const r=re(),{data:n,isLoading:i}=B({queryKey:["part-cost-summary",e],queryFn:()=>$u(e),staleTime:3e4}),{data:o}=B({queryKey:["cost-history",e],queryFn:()=>Bu(e,90),staleTime:6e4}),{data:c}=B({queryKey:["cost-layers",e],queryFn:()=>Gu(e),staleTime:3e4}),[d,l]=b.useState(!1),[u,E]=b.useState(""),_=P({mutationFn:h=>Hu(e,h),onSuccess:()=>{r.invalidateQueries({queryKey:["part-cost-summary",e]}),l(!1)}}),m=P({mutationFn:()=>Wu(e),onSuccess:()=>{r.invalidateQueries({queryKey:["part-cost-summary",e]})}}),y=()=>{E(String(n?.custom_margin_percent??n?.effective_margin_percent??25)),l(!0)},f=()=>{const h=parseFloat(u);!isNaN(h)&&h>=0&&h<=100&&_.mutate(h)},v=h=>`$${h.toFixed(2)}`;return i?a.jsx("div",{className:"flex items-center justify-center py-6",children:a.jsx(z,{size:"md"})}):n?a.jsxs("div",{className:"bg-gray-50 dark:bg-gray-800/50 rounded-lg p-4 space-y-4 border border-gray-200 dark:border-gray-700",children:[a.jsxs("div",{className:"flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300",children:[a.jsx(Ta,{className:"h-4 w-4 text-primary-500"}),"Cost Details — ",t]}),a.jsxs("div",{className:"grid grid-cols-2 sm:grid-cols-4 gap-3",children:[a.jsx(wt,{label:"Weighted Avg Cost",value:v(n.weighted_avg_cost),icon:a.jsx(fr,{className:"h-3.5 w-3.5"})}),a.jsx(wt,{label:"Active Layers",value:String(n.active_layers),icon:a.jsx(ka,{className:"h-3.5 w-3.5"})}),a.jsx(wt,{label:"Effective Margin",value:`${n.effective_margin_percent.toFixed(1)}%`,icon:a.jsx(Ms,{className:"h-3.5 w-3.5"}),badge:n.custom_margin_percent!=null?a.jsx(G,{variant:"warning",children:"Custom"}):a.jsx(G,{variant:"default",children:"Default"})}),a.jsx(wt,{label:"Sell Price",value:v(n.calculated_sell_price),icon:a.jsx(Ta,{className:"h-3.5 w-3.5"}),highlight:!0})]}),o&&o.length>1&&a.jsxs("div",{children:[a.jsx("p",{className:"text-xs text-gray-500 dark:text-gray-400 mb-1",children:"Cost trend (90 days)"}),a.jsx(P_,{data:o})]}),s&&a.jsx("div",{className:"flex items-center gap-2 flex-wrap",children:d?a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx("input",{type:"number",min:"0",max:"100",step:"0.5",className:"w-20 text-right rounded border border-primary-300 dark:border-primary-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm",value:u,onChange:h=>E(h.target.value),autoFocus:!0}),a.jsx("span",{className:"text-sm text-gray-500",children:"%"}),a.jsx("button",{className:"p-1.5 rounded text-green-600 hover:bg-green-100 dark:hover:bg-green-900/30",onClick:f,title:"Save margin",children:a.jsx(Ue,{className:"h-4 w-4"})}),a.jsx("button",{className:"p-1.5 rounded text-gray-500 hover:bg-gray-200 dark:hover:bg-gray-700",onClick:()=>l(!1),title:"Cancel",children:a.jsx(He,{className:"h-4 w-4"})})]}):a.jsxs(a.Fragment,{children:[a.jsxs(F,{variant:"secondary",size:"sm",onClick:y,children:[a.jsx(Ms,{className:"h-3.5 w-3.5 mr-1"}),"Set Custom Margin"]}),n.custom_margin_percent!=null&&a.jsxs(F,{variant:"secondary",size:"sm",onClick:()=>m.mutate(),isLoading:m.isPending,children:[a.jsx(wd,{className:"h-3.5 w-3.5 mr-1"}),"Revert to Default"]})]})}),c&&c.length>0&&a.jsxs("div",{children:[a.jsx("p",{className:"text-xs font-medium text-gray-600 dark:text-gray-400 mb-2",children:"Active Cost Layers (FIFO order)"}),a.jsx("div",{className:"overflow-x-auto",children:a.jsxs("table",{className:"w-full text-xs",children:[a.jsx("thead",{children:a.jsxs("tr",{className:"border-b border-gray-200 dark:border-gray-600 text-gray-500 dark:text-gray-400",children:[a.jsx("th",{className:"text-left py-1.5 pr-3 font-medium",children:"Date"}),a.jsx("th",{className:"text-left py-1.5 pr-3 font-medium",children:"PO"}),a.jsx("th",{className:"text-right py-1.5 pr-3 font-medium",children:"Original"}),a.jsx("th",{className:"text-right py-1.5 pr-3 font-medium",children:"Remaining"}),a.jsx("th",{className:"text-right py-1.5 font-medium",children:"Unit Cost"})]})}),a.jsx("tbody",{className:"divide-y divide-gray-100 dark:divide-gray-700/50",children:c.map(h=>a.jsxs("tr",{className:"text-gray-700 dark:text-gray-300",children:[a.jsx("td",{className:"py-1.5 pr-3",children:h.purchase_date}),a.jsx("td",{className:"py-1.5 pr-3 text-primary-600 dark:text-primary-400",children:h.po_number??"—"}),a.jsx("td",{className:"py-1.5 pr-3 text-right",children:h.original_qty}),a.jsx("td",{className:"py-1.5 pr-3 text-right font-medium",children:h.remaining_qty}),a.jsx("td",{className:"py-1.5 text-right",children:v(h.unit_cost)})]},h.id))})]})})]}),n.cost_last_updated&&a.jsxs("p",{className:"text-xs text-gray-400 dark:text-gray-500",children:["Cost last updated: ",new Date(n.cost_last_updated).toLocaleDateString()]})]}):null}function wt({label:e,value:t,icon:s,badge:r,highlight:n}){return a.jsxs("div",{className:"bg-white dark:bg-gray-800 rounded-lg p-3 border border-gray-200 dark:border-gray-700",children:[a.jsxs("div",{className:"flex items-center gap-1.5 mb-1",children:[a.jsx("span",{className:"text-gray-400 dark:text-gray-500",children:s}),a.jsx("span",{className:"text-xs text-gray-500 dark:text-gray-400",children:e}),r]}),a.jsx("p",{className:`text-lg font-bold ${n?"text-primary-600 dark:text-primary-400":"text-gray-900 dark:text-gray-100"}`,children:t})]})}function P_({data:e}){if(e.length<2)return null;const t=200,s=40,r=2,n=e.map(m=>m.weighted_avg_cost),i=Math.min(...n),c=Math.max(...n)-i||1,d=n.map((m,y)=>{const f=r+y/(n.length-1)*(t-r*2),v=s-r-(m-i)/c*(s-r*2);return`${f},${v}`}).join(" "),l=n[0],u=n[n.length-1],E=u-l,_=E>l*.05?"#ef4444":E<-l*.05?"#22c55e":"#f59e0b";return a.jsxs("svg",{width:t,height:s,viewBox:`0 0 ${t} ${s}`,className:"block",children:[a.jsx("polyline",{points:d,fill:"none",stroke:_,strokeWidth:"2",strokeLinecap:"round",strokeLinejoin:"round"}),n.length>0&&a.jsx("circle",{cx:r+(n.length-1)/(n.length-1)*(t-r*2),cy:s-r-(u-i)/c*(s-r*2),r:"3",fill:_})]})}function Am(){const{hasPermission:e}=Pe(),t=e(Fe.SHOW_DOLLAR_VALUES),s=e(Fe.EDIT_PRICING);return t?a.jsx(M_,{canEdit:s}):a.jsx(le,{icon:a.jsx(Ld,{className:"h-12 w-12"}),title:"Permission Required",description:"You need the 'Show Dollar Values' permission to view pricing information. Ask an admin for access."})}function M_({canEdit:e}){const t=re(),[s,r]=b.useState(""),[n,i]=b.useState({page:1,page_size:25,sort_by:"name",sort_dir:"asc"}),[o,c]=b.useState(null),d=k=>{c(A=>A===k?null:k)},[l,u]=b.useState(null),[E,_]=b.useState(""),[m,y]=b.useState(""),f={...n,search:s||void 0},{data:v,isLoading:h,error:T}=B({queryKey:["parts",f],queryFn:()=>Ha(f)}),g=P({mutationFn:({id:k,cost:A,markup:Z})=>o_(k,{company_cost_price:A,company_markup_percent:Z}),onSuccess:()=>{t.invalidateQueries({queryKey:["parts"]}),u(null)}}),L=b.useCallback(k=>{i(A=>({...A,sort_by:k,sort_dir:A.sort_by===k&&A.sort_dir==="asc"?"desc":"asc",page:1}))},[]),w=({column:k})=>n.sort_by!==k?null:n.sort_dir==="asc"?a.jsx(Aa,{className:"inline h-3.5 w-3.5 ml-0.5"}):a.jsx(Te,{className:"inline h-3.5 w-3.5 ml-0.5"}),O=k=>{u(k.id),_(String(k.company_cost_price??0)),y(String(k.company_markup_percent??0))},C=()=>{u(null),_(""),y("")},W=()=>{if(l==null)return;const k=parseFloat(E)||0,A=parseFloat(m)||0;g.mutate({id:l,cost:k,markup:A})},Q=(parseFloat(E)||0)*(1+(parseFloat(m)||0)/100),M=k=>k!=null?`$${k.toFixed(2)}`:"—",te=k=>k!=null?`${k.toFixed(1)}%`:"—",S=v?.items??[],j=v?.total??0,K=v?.total_pages??0,ae=n.page??1;return a.jsxs("div",{className:"space-y-4",children:[a.jsxs("div",{className:"flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between",children:[a.jsx("div",{className:"flex-1 w-full sm:max-w-md",children:a.jsx(q,{placeholder:"Search parts to view pricing...",icon:a.jsx(st,{className:"h-4 w-4"}),value:s,onChange:k=>{r(k.target.value),i(A=>({...A,page:1}))}})}),e&&a.jsxs(G,{variant:"success",children:[a.jsx(Ct,{className:"h-3 w-3 mr-0.5"}),"Inline edit enabled"]})]}),a.jsx("div",{className:"text-sm text-gray-500 dark:text-gray-400",children:j>0?a.jsxs(a.Fragment,{children:["Showing ",(ae-1)*(n.page_size??25)+1,"–",Math.min(ae*(n.page_size??25),j)," of ",j," parts"]}):h?"Loading...":"No parts found"}),h?a.jsx("div",{className:"flex justify-center py-12",children:a.jsx(z,{size:"lg"})}):T?a.jsx(le,{icon:a.jsx(Re,{className:"h-12 w-12 text-red-400"}),title:"Error loading pricing",description:String(T)}):S.length===0?a.jsx(le,{icon:a.jsx(Ct,{className:"h-12 w-12"}),title:"No parts found",description:"Add parts in the Catalog tab to manage pricing."}):a.jsx("div",{className:"overflow-x-auto border border-gray-200 dark:border-gray-700 rounded-xl",children:a.jsxs("table",{className:"w-full text-sm",children:[a.jsx("thead",{children:a.jsxs("tr",{className:"bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700",children:[a.jsx("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Category"}),a.jsxs("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>L("code"),children:["Code ",a.jsx(w,{column:"code"})]}),a.jsxs("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>L("name"),children:["Part Name ",a.jsx(w,{column:"name"})]}),a.jsx("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Brand"}),a.jsx("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"UoM"}),a.jsxs("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>L("company_cost_price"),children:["Cost ",a.jsx(w,{column:"company_cost_price"})]}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Markup"}),a.jsxs("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200",onClick:()=>L("company_sell_price"),children:["Sell ",a.jsx(w,{column:"company_sell_price"})]}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Margin"}),e&&a.jsx("th",{className:"text-center px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Actions"})]})}),a.jsx("tbody",{children:S.map(k=>{const A=l===k.id,Z=o===k.id,D=k.company_cost_price??0,se=k.company_sell_price??0,ie=se>0?(se-D)/se*100:0,$=e?10:9;return a.jsxs(b.Fragment,{children:[a.jsxs("tr",{className:`border-b border-gray-100 dark:border-gray-700/50 transition-colors ${A?"bg-primary-50/50 dark:bg-primary-900/10":Z?"bg-gray-50/80 dark:bg-gray-800/40":"hover:bg-gray-50 dark:hover:bg-gray-800/30"} cursor-pointer`,onClick:()=>{A||d(k.id)},children:[a.jsx("td",{className:"px-4 py-3 text-gray-600 dark:text-gray-400",children:k.category_name??"—"}),a.jsx("td",{className:"px-4 py-3 font-mono text-xs text-primary-600 dark:text-primary-400",children:k.code??"—"}),a.jsx("td",{className:"px-4 py-3 font-medium text-gray-900 dark:text-gray-100",children:a.jsxs("div",{className:"flex items-center gap-1.5",children:[k.name,Z&&a.jsx(Ta,{className:"h-3.5 w-3.5 text-primary-500 shrink-0"})]})}),a.jsx("td",{className:"px-4 py-3 text-gray-600 dark:text-gray-400",children:k.brand_name??"—"}),a.jsx("td",{className:"px-4 py-3 text-gray-500 dark:text-gray-400",children:k.unit_of_measure}),a.jsx("td",{className:"px-4 py-3 text-right",onClick:V=>A&&V.stopPropagation(),children:A?a.jsx("input",{type:"number",min:"0",step:"0.01",className:"w-24 text-right rounded border border-primary-300 dark:border-primary-600 bg-white dark:bg-gray-800 px-2 py-1 text-sm",value:E,onChange:V=>_(V.target.value),autoFocus:!0}):a.jsx("span",{className:"text-gray-700 dark:text-gray-300",children:M(k.company_cost_price)})}),a.jsx("td",{className:"px-4 py-3 text-right",onClick:V=>A&&V.stopPropagation(),children:A?a.jsxs("div",{className:"inline-flex items-center gap-0.5",children:[a.jsx("input",{type:"number",min:"0",step:"0.1",className:"w-20 text-right rounded border border-primary-300 dark:border-primary-600 bg-white dark:bg-gray-800 px-2 py-1 text-sm",value:m,onChange:V=>y(V.target.value)}),a.jsx("span",{className:"text-gray-400 text-xs",children:"%"})]}):a.jsx("span",{className:"text-gray-600 dark:text-gray-400",children:te(k.company_markup_percent)})}),a.jsx("td",{className:"px-4 py-3 text-right font-medium",children:A?a.jsxs("span",{className:"text-primary-600 dark:text-primary-400",children:["$",Q.toFixed(2)]}):a.jsx("span",{className:"text-gray-900 dark:text-gray-100",children:M(k.company_sell_price)})}),a.jsx("td",{className:"px-4 py-3 text-right",children:a.jsxs(G,{variant:ie>=30?"success":ie>=15?"warning":"danger",children:[ie.toFixed(1),"%"]})}),e&&a.jsx("td",{className:"px-4 py-3 text-center",onClick:V=>V.stopPropagation(),children:A?a.jsxs("div",{className:"flex justify-center gap-1",children:[a.jsx("button",{className:"p-2 rounded text-green-600 hover:bg-green-100 dark:hover:bg-green-900/30 transition-colors",onClick:W,title:"Save",children:a.jsx(Ue,{className:"h-4 w-4"})}),a.jsx("button",{className:"p-2 rounded text-gray-500 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors",onClick:C,title:"Cancel",children:a.jsx(He,{className:"h-4 w-4"})})]}):a.jsx("button",{className:"p-2 rounded text-gray-500 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors",onClick:()=>O(k),title:"Edit pricing",children:a.jsx(Ct,{className:"h-4 w-4"})})})]}),Z&&a.jsx("tr",{className:"border-b border-gray-200 dark:border-gray-700",children:a.jsx("td",{colSpan:$,className:"px-4 py-3",children:a.jsx(U_,{partId:k.id,partName:k.name,canEdit:e})})})]},k.id)})})]})}),K>1&&a.jsxs("div",{className:"flex items-center justify-between",children:[a.jsx(F,{variant:"secondary",size:"sm",icon:a.jsx(ja,{className:"h-4 w-4"}),disabled:ae<=1,onClick:()=>i(k=>({...k,page:(k.page??1)-1})),children:"Previous"}),a.jsxs("span",{className:"text-sm text-gray-500",children:["Page ",ae," of ",K]}),a.jsx(F,{variant:"secondary",size:"sm",iconRight:a.jsx(ye,{className:"h-4 w-4"}),disabled:ae>=K,onClick:()=>i(k=>({...k,page:(k.page??1)+1})),children:"Next"})]}),g.isError&&a.jsxs("div",{className:"p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400",children:["Failed to update pricing: ",g.error?.response?.data?.detail??"Unknown error"]})]})}function Im(){const[e,t]=b.useState(""),[s,r]=b.useState(1),n=25,i=re(),{data:o,isLoading:c,error:d}=B({queryKey:["forecasting",{page:s,page_size:n}],queryFn:()=>E_({page:s,page_size:n})}),l=P({mutationFn:p_,onSuccess:T=>{H.success(`Recalculated ${T.recalculated} parts`+(T.errors>0?` (${T.errors} errors)`:"")),i.invalidateQueries({queryKey:["forecasting"]})},onError:()=>{H.error("Failed to recalculate forecasts")}}),u=b.useMemo(()=>{const T=o?.items??[];if(!e)return T;const g=e.toLowerCase();return T.filter(L=>(L.code??"").toLowerCase().includes(g)||L.name.toLowerCase().includes(g)||(L.category_name??"").toLowerCase().includes(g)||(L.brand_name??"").toLowerCase().includes(g))},[o,e]),E=o?.total??0,_=o?.total_pages??0,m=o?.items??[],y=m.filter(T=>T.forecast_days_until_low<7).length,f=m.filter(T=>T.forecast_suggested_order>0).length,v=m.length>0?m.reduce((T,g)=>T+(g.forecast_adu_30??0),0)/m.length:0,h=T=>T<0?a.jsx(G,{variant:"danger",children:"BELOW MIN"}):T<7?a.jsxs(G,{variant:"danger",children:[T,"d"]}):T<14?a.jsxs(G,{variant:"warning",children:[T,"d"]}):T<30?a.jsxs(G,{variant:"default",children:[T,"d"]}):a.jsxs("span",{className:"text-green-600 dark:text-green-400 font-medium",children:[T,"d"]});return a.jsxs("div",{className:"space-y-4",children:[a.jsxs("div",{className:"grid grid-cols-1 sm:grid-cols-3 gap-4",children:[a.jsxs(Ce,{className:"flex items-center gap-3",children:[a.jsx("div",{className:"p-2 rounded-lg bg-red-100 dark:bg-red-900/30",children:a.jsx(Re,{className:"h-5 w-5 text-red-500"})}),a.jsxs("div",{children:[a.jsx("p",{className:"text-2xl font-bold text-gray-900 dark:text-gray-100",children:y}),a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400",children:"Critical (<7 days)"})]})]}),a.jsxs(Ce,{className:"flex items-center gap-3",children:[a.jsx("div",{className:"p-2 rounded-lg bg-amber-100 dark:bg-amber-900/30",children:a.jsx(Sd,{className:"h-5 w-5 text-amber-500"})}),a.jsxs("div",{children:[a.jsx("p",{className:"text-2xl font-bold text-gray-900 dark:text-gray-100",children:f}),a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400",children:"Suggested Orders"})]})]}),a.jsxs(Ce,{className:"flex items-center gap-3",children:[a.jsx("div",{className:"p-2 rounded-lg bg-blue-100 dark:bg-blue-900/30",children:a.jsx(Cd,{className:"h-5 w-5 text-blue-500"})}),a.jsxs("div",{children:[a.jsx("p",{className:"text-2xl font-bold text-gray-900 dark:text-gray-100",children:v.toFixed(1)}),a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400",children:"Avg Daily Usage (30d)"})]})]})]}),a.jsxs("div",{className:"flex flex-wrap gap-3 items-start sm:items-center justify-between",children:[a.jsx("div",{className:"flex-1 w-full sm:max-w-md",children:a.jsx(q,{placeholder:"Search by code or name...",icon:a.jsx(st,{className:"h-4 w-4"}),value:e,onChange:T=>t(T.target.value)})}),a.jsxs("div",{className:"flex items-center gap-3",children:[a.jsx(F,{variant:"secondary",size:"sm",icon:a.jsx(Od,{className:`h-4 w-4 ${l.isPending?"animate-spin":""}`}),onClick:()=>l.mutate(),isLoading:l.isPending,children:a.jsx("span",{className:"hidden sm:inline",children:"Recalculate All"})}),a.jsxs("div",{className:"flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400",children:[a.jsx(Bt,{className:"h-4 w-4"}),a.jsx("span",{className:"hidden md:inline",children:"Sorted by urgency"})]})]})]}),c?a.jsx("div",{className:"flex justify-center py-12",children:a.jsx(z,{size:"lg"})}):d?a.jsx(le,{icon:a.jsx(Re,{className:"h-12 w-12 text-red-400"}),title:"Error loading forecast data",description:String(d)}):u.length===0?a.jsx(le,{icon:a.jsx(fr,{className:"h-12 w-12"}),title:"No forecast data",description:"Forecast data will appear once the forecast service has run and parts have usage history."}):a.jsx("div",{className:"overflow-x-auto border border-gray-200 dark:border-gray-700 rounded-xl",children:a.jsxs("table",{className:"w-full text-sm",children:[a.jsx("thead",{children:a.jsxs("tr",{className:"bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700",children:[a.jsx("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Category"}),a.jsx("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Code"}),a.jsx("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Part Name"}),a.jsx("th",{className:"text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Brand"}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Current Stock"}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Min Level"}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"ADU (30d)"}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"ADU (90d)"}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Reorder Point"}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Target Qty"}),a.jsx("th",{className:"text-center px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Days Until Low"}),a.jsx("th",{className:"text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400",children:"Suggested Order"})]})}),a.jsx("tbody",{children:u.map(T=>a.jsxs("tr",{className:`border-b border-gray-100 dark:border-gray-700/50 transition-colors ${T.forecast_days_until_low<7?"bg-red-50/50 dark:bg-red-900/10":"hover:bg-gray-50 dark:hover:bg-gray-800/30"}`,children:[a.jsx("td",{className:"px-4 py-3 text-gray-600 dark:text-gray-400",children:T.category_name??"—"}),a.jsx("td",{className:"px-4 py-3 font-mono text-xs text-primary-600 dark:text-primary-400",children:T.code??"—"}),a.jsx("td",{className:"px-4 py-3 font-medium text-gray-900 dark:text-gray-100",children:T.name}),a.jsx("td",{className:"px-4 py-3 text-gray-600 dark:text-gray-400",children:T.brand_name??"—"}),a.jsx("td",{className:"px-4 py-3 text-right",children:a.jsx("span",{className:T.total_stock<=T.min_stock_level?"text-red-500 font-medium":"text-gray-700 dark:text-gray-300",children:T.total_stock})}),a.jsx("td",{className:"px-4 py-3 text-right text-gray-600 dark:text-gray-400",children:T.min_stock_level}),a.jsx("td",{className:"px-4 py-3 text-right text-gray-700 dark:text-gray-300",children:T.forecast_adu_30.toFixed(2)}),a.jsx("td",{className:"px-4 py-3 text-right text-gray-700 dark:text-gray-300",children:T.forecast_adu_90.toFixed(2)}),a.jsx("td",{className:"px-4 py-3 text-right text-gray-600 dark:text-gray-400",children:T.forecast_reorder_point}),a.jsx("td",{className:"px-4 py-3 text-right text-gray-600 dark:text-gray-400",children:T.forecast_target_qty}),a.jsx("td",{className:"px-4 py-3 text-center",children:h(T.forecast_days_until_low)}),a.jsx("td",{className:"px-4 py-3 text-right",children:T.forecast_suggested_order>0?a.jsx("span",{className:"font-semibold text-amber-600 dark:text-amber-400",children:T.forecast_suggested_order}):a.jsx("span",{className:"text-gray-400",children:"—"})})]},T.id))})]})}),_>1&&a.jsxs("div",{className:"flex items-center justify-between",children:[a.jsx(F,{variant:"secondary",size:"sm",icon:a.jsx(ja,{className:"h-4 w-4"}),disabled:s<=1,onClick:()=>r(T=>T-1),children:"Previous"}),a.jsxs("span",{className:"text-sm text-gray-500",children:["Page ",s," of ",_," (",E," parts)"]}),a.jsx(F,{variant:"secondary",size:"sm",iconRight:a.jsx(ye,{className:"h-4 w-4"}),disabled:s>=_,onClick:()=>r(T=>T+1),children:"Next"})]})]})}const X_=`category_name,style_name,type_name,color_name,brand_name,name,description,part_type,code,manufacturer_part_number,unit_of_measure,company_cost_price,company_markup_percent,min_stock_level,max_stock_level,target_stock_level,notes
Wire,"12/2 NM",,White,,12/2 Romex 250ft,Non-metallic sheathed cable,general,WR-12-2-250,,ft,89.99,35.0,5,20,10,
Breakers,"Square D",20A,,,Square D 20A Breaker,Single-pole circuit breaker,specific,BR-SQD-20A,QO120,each,12.50,40.0,10,50,25,`;function km(){const{hasPermission:e}=Pe(),t=e(Fe.SHOW_DOLLAR_VALUES),s=b.useRef(null),[r,n]=b.useState(null),[i,o]=b.useState(null),c=P({mutationFn:m_,onSuccess:async _=>{const{exportFile:m}=await N(async()=>{const{exportFile:y}=await Promise.resolve().then(()=>Tr);return{exportFile:y}},void 0);await m(_,`parts-export-${new Date().toISOString().slice(0,10)}.csv`)}}),d=P({mutationFn:y_,onSuccess:_=>{n(_),o(null),s.current&&(s.current.value="")}}),l=async()=>{const{exportFile:_}=await N(async()=>{const{exportFile:m}=await Promise.resolve().then(()=>Tr);return{exportFile:m}},void 0);await _(X_,"parts-import-template.csv")},u=_=>{const m=_.target.files?.[0]??null;o(m),n(null)},E=()=>{i&&d.mutate(i)};return a.jsxs("div",{className:"space-y-6",children:[a.jsxs("div",{className:"grid grid-cols-1 lg:grid-cols-2 gap-6",children:[a.jsxs(Ce,{children:[a.jsx(ma,{title:"Export Parts",subtitle:"Download your parts catalog as a CSV file."}),a.jsxs("div",{className:"space-y-4",children:[a.jsx("div",{className:"p-4 rounded-lg bg-gray-50 dark:bg-gray-700/30 border border-gray-200 dark:border-gray-600",children:a.jsxs("div",{className:"flex items-start gap-3",children:[a.jsx(Xs,{className:"h-8 w-8 text-primary-500 mt-0.5 shrink-0"}),a.jsxs("div",{className:"text-sm text-gray-600 dark:text-gray-300 space-y-1",children:[a.jsx("p",{children:"Exports all parts including hierarchy (category, style, type, color), code, name, brand, unit of measure, stock levels, and notes."}),t?a.jsxs("p",{className:"text-green-600 dark:text-green-400",children:[a.jsx(qs,{className:"inline h-3.5 w-3.5 mr-1"}),"Pricing columns (cost, markup, sell) will be included."]}):a.jsxs("p",{className:"text-amber-600 dark:text-amber-400",children:[a.jsx(vr,{className:"inline h-3.5 w-3.5 mr-1"}),"Pricing columns are hidden based on your permissions."]})]})]})}),a.jsx(F,{icon:a.jsx(jd,{className:"h-4 w-4"}),onClick:()=>c.mutate(),isLoading:c.isPending,fullWidth:!0,children:"Export Catalog CSV"}),c.isError&&a.jsxs("div",{className:"p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400",children:["Export failed: ",c.error?.message??"Unknown error"]})]})]}),a.jsxs(Ce,{children:[a.jsx(ma,{title:"Import Parts",subtitle:"Upload a CSV file to create or update parts."}),a.jsxs("div",{className:"space-y-4",children:[a.jsx("div",{className:"p-4 rounded-lg bg-gray-50 dark:bg-gray-700/30 border border-gray-200 dark:border-gray-600",children:a.jsxs("div",{className:"flex items-start gap-3",children:[a.jsx(Gs,{className:"h-8 w-8 text-primary-500 mt-0.5 shrink-0"}),a.jsxs("div",{className:"text-sm text-gray-600 dark:text-gray-300 space-y-1",children:[a.jsxs("p",{children:["Upload a CSV with part data. Each row requires a ",a.jsx("strong",{children:"name"})," and either ",a.jsx("strong",{children:"category_id"})," or ",a.jsx("strong",{children:"category_name"}),":"]}),a.jsxs("ul",{className:"list-disc list-inside ml-1 text-gray-500 dark:text-gray-400",children:[a.jsxs("li",{children:["Use hierarchy ",a.jsx("strong",{children:"names"})," (category_name, style_name, type_name, color_name, brand_name) or IDs"]}),a.jsxs("li",{children:["Parts with a matching ",a.jsx("strong",{children:"code"})," are ",a.jsx("strong",{children:"updated"})]}),a.jsxs("li",{children:["Non-matching rows are ",a.jsx("strong",{children:"created"})]}),a.jsx("li",{children:"Code is optional for general parts"})]})]})]})}),a.jsxs("button",{onClick:l,className:"flex items-center gap-2 text-sm text-primary-500 hover:text-primary-600 hover:underline",children:[a.jsx(Ad,{className:"h-4 w-4"}),"Download CSV template with example data"]}),a.jsxs("div",{className:"space-y-2",children:[a.jsx("input",{ref:s,type:"file",accept:".csv,text/csv",onChange:u,className:`block w-full text-sm text-gray-500 dark:text-gray-400
                  file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0
                  file:text-sm file:font-medium
                  file:bg-primary-50 file:text-primary-600
                  dark:file:bg-primary-900/30 dark:file:text-primary-400
                  hover:file:bg-primary-100 dark:hover:file:bg-primary-900/50
                  cursor-pointer`}),i&&a.jsxs("p",{className:"text-sm text-gray-500 dark:text-gray-400",children:["Selected: ",a.jsx("strong",{children:i.name})," (",(i.size/1024).toFixed(1)," KB)"]})]}),a.jsx(F,{icon:a.jsx(Gs,{className:"h-4 w-4"}),onClick:E,isLoading:d.isPending,disabled:!i,fullWidth:!0,children:"Import CSV"}),d.isError&&a.jsxs("div",{className:"p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400",children:["Import failed: ",d.error?.message??"Unknown error"]})]})]})]}),r&&a.jsxs(Ce,{children:[a.jsx(ma,{title:"Import Results",subtitle:`Processed on ${new Date().toLocaleString()}`}),a.jsxs("div",{className:"flex flex-wrap gap-3 mb-4",children:[a.jsxs(G,{variant:"success",children:[a.jsx(qs,{className:"h-3.5 w-3.5 mr-1"}),r.created," created"]}),a.jsxs(G,{variant:"primary",children:[a.jsx(Xs,{className:"h-3.5 w-3.5 mr-1"}),r.updated," updated"]}),r.total_errors>0&&a.jsxs(G,{variant:"danger",children:[a.jsx(Re,{className:"h-3.5 w-3.5 mr-1"}),r.total_errors," error",r.total_errors!==1?"s":""]})]}),r.created+r.updated>0&&r.total_errors===0&&a.jsx("div",{className:"p-3 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg text-sm text-green-600 dark:text-green-400 mb-4",children:"All rows imported successfully!"}),r.errors.length>0&&a.jsxs("div",{className:"space-y-2",children:[a.jsx("h4",{className:"text-sm font-medium text-red-600 dark:text-red-400",children:"Errors:"}),a.jsx("div",{className:"max-h-60 overflow-y-auto space-y-1.5",children:r.errors.map((_,m)=>a.jsx("div",{className:"p-2 bg-red-50 dark:bg-red-900/10 border border-red-100 dark:border-red-900/30 rounded text-sm text-red-600 dark:text-red-400 font-mono",children:_},m))})]})]})]})}async function Dm(e={}){return R(async()=>{const{data:t}=await x.get("/contacts/customers",{params:e});return t.data},async()=>{const{getCustomers:t}=await N(async()=>{const{getCustomers:s}=await Promise.resolve().then(()=>J);return{getCustomers:s}},void 0);return t(e)})}async function Fm(e,t=20){return R(async()=>{const{data:s}=await x.get("/contacts/customers/search",{params:{q:e,limit:t}});return s.data},async()=>{const{searchCustomers:s}=await N(async()=>{const{searchCustomers:r}=await Promise.resolve().then(()=>J);return{searchCustomers:r}},void 0);return s(e,t)})}async function Um(e){return R(async()=>{const{data:t}=await x.get(`/contacts/customers/${e}`);return t.data},async()=>{const{getCustomer:t}=await N(async()=>{const{getCustomer:s}=await Promise.resolve().then(()=>J);return{getCustomer:s}},void 0);return t(e)})}async function Pm(e){return R(async()=>{const{data:t}=await x.post("/contacts/customers",e);return t.data},async()=>{const{createCustomer:t}=await N(async()=>{const{createCustomer:s}=await Promise.resolve().then(()=>J);return{createCustomer:s}},void 0);return t(e)})}async function Mm(e,t){return R(async()=>{const{data:s}=await x.put(`/contacts/customers/${e}`,t);return s.data},async()=>{const{updateCustomer:s}=await N(async()=>{const{updateCustomer:r}=await Promise.resolve().then(()=>J);return{updateCustomer:r}},void 0);return s(e,t)})}async function Xm(e,t){return R(async()=>{await x.patch(`/contacts/customers/${e}/toggle-active`,null,{params:{is_active:t}})},async()=>{const{toggleCustomerActive:s}=await N(async()=>{const{toggleCustomerActive:r}=await Promise.resolve().then(()=>J);return{toggleCustomerActive:r}},void 0);await s(e,t)})}async function qm(e,t=!1){return R(async()=>{const{data:s}=await x.get(`/contacts/customers/${e}/contacts`,{params:{include_inactive:t}});return s.data},async()=>{const{getCustomerContacts:s}=await N(async()=>{const{getCustomerContacts:r}=await Promise.resolve().then(()=>J);return{getCustomerContacts:r}},void 0);return s(e,t)})}async function Gm(e,t){return R(async()=>{const{data:s}=await x.post(`/contacts/customers/${e}/contacts`,t);return s.data},async()=>{const{addCustomerContact:s}=await N(async()=>{const{addCustomerContact:r}=await Promise.resolve().then(()=>J);return{addCustomerContact:r}},void 0);return s(e,t)})}async function Bm(e){return R(async()=>{const{data:t}=await x.get(`/contacts/customers/${e}/jobs`);return t.data},async()=>{const{getCustomerJobs:t}=await N(async()=>{const{getCustomerJobs:s}=await Promise.resolve().then(()=>J);return{getCustomerJobs:s}},void 0);return t(e)})}async function $m(e={}){return R(async()=>{const{data:t}=await x.get("/contacts/general-contractors",{params:e});return t.data},async()=>{const{getGCs:t}=await N(async()=>{const{getGCs:s}=await Promise.resolve().then(()=>J);return{getGCs:s}},void 0);return t(e)})}async function Hm(e,t=20){return R(async()=>{const{data:s}=await x.get("/contacts/general-contractors/search",{params:{q:e,limit:t}});return s.data},async()=>{const{searchGCs:s}=await N(async()=>{const{searchGCs:r}=await Promise.resolve().then(()=>J);return{searchGCs:r}},void 0);return s(e,t)})}async function Wm(e){return R(async()=>{const{data:t}=await x.get(`/contacts/general-contractors/${e}`);return t.data},async()=>{const{getGC:t}=await N(async()=>{const{getGC:s}=await Promise.resolve().then(()=>J);return{getGC:s}},void 0);return t(e)})}async function Km(e){return R(async()=>{const{data:t}=await x.post("/contacts/general-contractors",e);return t.data},async()=>{const{createGC:t}=await N(async()=>{const{createGC:s}=await Promise.resolve().then(()=>J);return{createGC:s}},void 0);return t(e)})}async function Ym(e,t){return R(async()=>{const{data:s}=await x.put(`/contacts/general-contractors/${e}`,t);return s.data},async()=>{const{updateGC:s}=await N(async()=>{const{updateGC:r}=await Promise.resolve().then(()=>J);return{updateGC:r}},void 0);return s(e,t)})}async function Vm(e,t){return R(async()=>{await x.patch(`/contacts/general-contractors/${e}/toggle-active`,null,{params:{is_active:t}})},async()=>{const{toggleGCActive:s}=await N(async()=>{const{toggleGCActive:r}=await Promise.resolve().then(()=>J);return{toggleGCActive:r}},void 0);await s(e,t)})}async function Jm(e,t=!1){return R(async()=>{const{data:s}=await x.get(`/contacts/general-contractors/${e}/contacts`,{params:{include_inactive:t}});return s.data},async()=>{const{getGCContacts:s}=await N(async()=>{const{getGCContacts:r}=await Promise.resolve().then(()=>J);return{getGCContacts:r}},void 0);return s(e,t)})}async function Qm(e,t){return R(async()=>{const{data:s}=await x.post(`/contacts/general-contractors/${e}/contacts`,t);return s.data},async()=>{const{addGCContact:s}=await N(async()=>{const{addGCContact:r}=await Promise.resolve().then(()=>J);return{addGCContact:r}},void 0);return s(e,t)})}async function zm(e){return R(async()=>{const{data:t}=await x.get(`/contacts/general-contractors/${e}/jobs`);return t.data},async()=>{const{getGCJobs:t}=await N(async()=>{const{getGCJobs:s}=await Promise.resolve().then(()=>J);return{getGCJobs:s}},void 0);return t(e)})}async function q_(e,t=!1){return R(async()=>{const{data:s}=await x.get(`/contacts/suppliers/${e}/contacts`,{params:{include_inactive:t}});return s.data},async()=>{const{getSupplierContacts:s}=await N(async()=>{const{getSupplierContacts:r}=await Promise.resolve().then(()=>J);return{getSupplierContacts:r}},void 0);return s(e,t)})}async function G_(e,t){return R(async()=>{const{data:s}=await x.post(`/contacts/suppliers/${e}/contacts`,t);return s.data},async()=>{const{addSupplierContact:s}=await N(async()=>{const{addSupplierContact:r}=await Promise.resolve().then(()=>J);return{addSupplierContact:r}},void 0);return s(e,t)})}async function Zm(e,t=50){return R(async()=>{const{data:s}=await x.get("/contacts/directory",{params:{q:e,limit:t}});return s.data},async()=>{const{searchDirectory:s}=await N(async()=>{const{searchDirectory:r}=await Promise.resolve().then(()=>J);return{searchDirectory:r}},void 0);return s(e,t)})}async function B_(e,t){return R(async()=>{const{data:s}=await x.put(`/contacts/entity-contacts/${e}`,t);return s.data},async()=>{const{updateEntityContact:s}=await N(async()=>{const{updateEntityContact:r}=await Promise.resolve().then(()=>J);return{updateEntityContact:r}},void 0);return s(e,t)})}async function $_(e){return R(async()=>{const{data:t}=await x.delete(`/contacts/entity-contacts/${e}`);return t.data},async()=>{const{deleteEntityContact:t}=await N(async()=>{const{deleteEntityContact:s}=await Promise.resolve().then(()=>J);return{deleteEntityContact:s}},void 0);return t(e)})}async function ey(e){return R(async()=>{const{data:t}=await x.get(`/jobs/${e}/customers`);return t.data},async()=>{const{getJobCustomers:t}=await N(async()=>{const{getJobCustomers:s}=await Promise.resolve().then(()=>J);return{getJobCustomers:s}},void 0);return t(e)})}async function ty(e,t){return R(async()=>{const{data:s}=await x.post(`/jobs/${e}/customers`,t);return s.data},async()=>{const{linkCustomerToJob:s}=await N(async()=>{const{linkCustomerToJob:r}=await Promise.resolve().then(()=>J);return{linkCustomerToJob:r}},void 0);return s(e,t)})}async function ay(e,t){return R(async()=>{await x.delete(`/jobs/${e}/customers/${t}`)},async()=>{const{unlinkCustomerFromJob:s}=await N(async()=>{const{unlinkCustomerFromJob:r}=await Promise.resolve().then(()=>J);return{unlinkCustomerFromJob:r}},void 0);await s(e,t)})}async function sy(e){return R(async()=>{const{data:t}=await x.get(`/jobs/${e}/general-contractors`);return t.data},async()=>{const{getJobGCs:t}=await N(async()=>{const{getJobGCs:s}=await Promise.resolve().then(()=>J);return{getJobGCs:s}},void 0);return t(e)})}async function ry(e,t){return R(async()=>{const{data:s}=await x.post(`/jobs/${e}/general-contractors`,t);return s.data},async()=>{const{linkGCToJob:s}=await N(async()=>{const{linkGCToJob:r}=await Promise.resolve().then(()=>J);return{linkGCToJob:r}},void 0);return s(e,t)})}async function ny(e,t){return R(async()=>{await x.delete(`/jobs/${e}/general-contractors/${t}`)},async()=>{const{unlinkGCFromJob:s}=await N(async()=>{const{unlinkGCFromJob:r}=await Promise.resolve().then(()=>J);return{unlinkGCFromJob:r}},void 0);await s(e,t)})}async function iy(e){return R(async()=>{const t=new FormData;t.append("file",e);const{data:s}=await x.post("/contacts/import/customers",t,{headers:{"Content-Type":"multipart/form-data"}});return s.data},async()=>{const{importCustomersCSV:t}=await N(async()=>{const{importCustomersCSV:s}=await Promise.resolve().then(()=>J);return{importCustomersCSV:s}},void 0);return t(e)})}async function oy(e){return R(async()=>{const t=new FormData;t.append("file",e);const{data:s}=await x.post("/contacts/import/contractors",t,{headers:{"Content-Type":"multipart/form-data"}});return s.data},async()=>{const{importContractorsCSV:t}=await N(async()=>{const{importContractorsCSV:s}=await Promise.resolve().then(()=>J);return{importContractorsCSV:s}},void 0);return t(e)})}async function cy(e=.8){return R(async()=>{const{data:t}=await x.get("/contacts/dedupe/customers",{params:{threshold:e}});return t.data??[]},async()=>{const{findDuplicateCustomers:t}=await N(async()=>{const{findDuplicateCustomers:s}=await Promise.resolve().then(()=>J);return{findDuplicateCustomers:s}},void 0);return t(e)})}async function ly(e,t){return R(async()=>{const{data:s}=await x.post("/contacts/merge/customers",{keep_id:e,merge_id:t});return s.data},async()=>{const{mergeCustomers:s}=await N(async()=>{const{mergeCustomers:r}=await Promise.resolve().then(()=>J);return{mergeCustomers:r}},void 0);return s(e,t)})}const Ut={standard_shipping:"Standard Shipping",scheduled_delivery:"Scheduled Delivery",in_store_pickup:"In-Store Pickup"},dr={standard_shipping:"info",scheduled_delivery:"success",in_store_pickup:"warning"},fa={standard_shipping:Xe,scheduled_delivery:Na,in_store_pickup:Rr},H_={monday:"Mon",tuesday:"Tue",wednesday:"Wed",thursday:"Thu",friday:"Fri",saturday:"Sat",sunday:"Sun"};function rn(e){if(!e)return[];try{const t=JSON.parse(e);return Array.isArray(t)?t:[]}catch{return[]}}function dy(){const e=re(),{hasPermission:t}=Pe(),s=t(Fe.EDIT_PARTS_CATALOG),[r,n]=b.useState(""),[i,o]=b.useState(null),[c,d]=b.useState(!1),[l,u]=b.useState(null),[E,_]=b.useState(null),{data:m,isLoading:y,error:f}=B({queryKey:["suppliers",{search:r||void 0}],queryFn:()=>Ka({search:r||void 0})}),v=P({mutationFn:u_,onSuccess:()=>{e.invalidateQueries({queryKey:["suppliers"]}),d(!1)}}),h=P({mutationFn:({id:w,data:O})=>ir(w,O),onSuccess:()=>{e.invalidateQueries({queryKey:["suppliers"]}),u(null)}}),T=P({mutationFn:__,onSuccess:()=>{e.invalidateQueries({queryKey:["suppliers"]}),_(null)}}),g=P({mutationFn:({id:w,is_active:O})=>ir(w,{is_active:O}),onSuccess:()=>e.invalidateQueries({queryKey:["suppliers"]})}),L=m??[];return a.jsxs("div",{className:"space-y-4",children:[a.jsxs("div",{className:"flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between",children:[a.jsx("div",{className:"flex-1 w-full sm:max-w-md",children:a.jsx(q,{placeholder:"Search suppliers, contacts, reps...",icon:a.jsx(st,{className:"h-4 w-4"}),value:r,onChange:w=>n(w.target.value)})}),s&&a.jsx(F,{size:"sm",icon:a.jsx(oe,{className:"h-4 w-4"}),onClick:()=>d(!0),children:"Add Supplier"})]}),a.jsx("div",{className:"text-sm text-gray-500 dark:text-gray-400",children:y?"Loading...":`${L.length} supplier${L.length!==1?"s":""}`}),y?a.jsx("div",{className:"flex justify-center py-12",children:a.jsx(z,{size:"lg"})}):f?a.jsx(le,{icon:a.jsx(Re,{className:"h-12 w-12 text-red-400"}),title:"Error loading suppliers",description:String(f)}):L.length===0?a.jsx(le,{icon:a.jsx(Et,{className:"h-12 w-12"}),title:"No suppliers found",description:r?"Try a different search term.":"Add your first supplier to get started."}):a.jsx("div",{className:"space-y-3",children:L.map(w=>a.jsx(W_,{supplier:w,isExpanded:i===w.id,onToggleExpand:()=>o(i===w.id?null:w.id),canEdit:s,onEdit:()=>u(w),onDelete:()=>_(w),onToggleActive:()=>g.mutate({id:w.id,is_active:!w.is_active})},w.id))}),a.jsx(_r,{isOpen:c,onClose:()=>d(!1),onSubmit:w=>v.mutate(w),isLoading:v.isPending,title:"Add Supplier"}),l&&a.jsx(_r,{isOpen:!0,onClose:()=>u(null),onSubmit:w=>h.mutate({id:l.id,data:w}),isLoading:h.isPending,title:`Edit: ${l.name}`,initial:l}),E&&a.jsxs(Ne,{isOpen:!0,onClose:()=>_(null),title:"Delete Supplier?",size:"sm",children:[a.jsxs("p",{className:"text-gray-600 dark:text-gray-300 mb-4",children:["Are you sure you want to delete ",a.jsx("strong",{children:E.name}),"? This will also remove all part-supplier links for this supplier."]}),T.isError&&a.jsx("p",{className:"text-red-500 text-sm mb-4",children:T.error?.response?.data?.detail??"Failed to delete supplier."}),a.jsxs("div",{className:"flex justify-end gap-2",children:[a.jsx(F,{variant:"secondary",onClick:()=>_(null),children:"Cancel"}),a.jsx(F,{variant:"danger",isLoading:T.isPending,onClick:()=>T.mutate(E.id),children:"Delete"})]})]})]})}function W_({supplier:e,isExpanded:t,onToggleExpand:s,canEdit:r,onEdit:n,onDelete:i,onToggleActive:o}){fa[e.primary_delivery_method]??Xe;const c=e.delivery_methods?.includes("scheduled_delivery")??!1,d=rn(e.delivery_days);return a.jsxs("div",{className:"border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800/50 overflow-hidden",children:[a.jsxs("div",{className:"flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800/80 transition-colors",onClick:s,children:[a.jsx("div",{className:"text-gray-400",children:t?a.jsx(Te,{className:"h-4 w-4"}):a.jsx(ye,{className:"h-4 w-4"})}),a.jsxs("div",{className:"flex-1 min-w-0",children:[a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx("span",{className:"font-medium text-gray-900 dark:text-gray-100 truncate",children:e.name}),!e.is_active&&a.jsx(G,{variant:"default",children:"Inactive"})]}),a.jsxs("div",{className:"flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400 mt-0.5",children:[e.phone&&a.jsxs("span",{className:"flex items-center gap-1",children:[a.jsx(ut,{className:"h-3 w-3"}),e.phone]}),e.rep_name&&a.jsxs("span",{className:"flex items-center gap-1",children:[a.jsx(Da,{className:"h-3 w-3"}),"Rep: ",e.rep_name]}),c&&e.driver_name&&a.jsxs("span",{className:"flex items-center gap-1",children:[a.jsx(Xe,{className:"h-3 w-3"}),"Driver: ",e.driver_name]}),e.brand_count>0&&a.jsxs("span",{className:"flex items-center gap-1",children:[a.jsx(De,{className:"h-3 w-3"}),e.brand_count," brand",e.brand_count!==1?"s":""]})]})]}),a.jsx("div",{className:"flex items-center gap-1",children:(e.delivery_methods??(e.primary_delivery_method?[e.primary_delivery_method]:[])).map(l=>{const u=fa[l]??Xe,E=l===e.primary_delivery_method;return a.jsxs(G,{variant:dr[l],children:[a.jsx(u,{className:"h-3 w-3 mr-1 inline"}),Ut[l],E&&(e.delivery_methods?.length??0)>1&&a.jsx(Gt,{className:"h-2.5 w-2.5 ml-0.5 inline fill-current"})]},l)})}),a.jsx("div",{className:"flex items-center gap-1",onClick:l=>l.stopPropagation(),children:r&&a.jsxs(a.Fragment,{children:[a.jsx("button",{className:"p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors",onClick:o,title:e.is_active?"Deactivate":"Activate",children:e.is_active?a.jsx(We,{className:"h-4 w-4 text-green-500"}):a.jsx(Ke,{className:"h-4 w-4 text-gray-400"})}),a.jsx("button",{className:"p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors",onClick:n,title:"Edit",children:a.jsx(Nt,{className:"h-4 w-4 text-gray-500"})}),a.jsx("button",{className:"p-1.5 rounded hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors",onClick:i,title:"Delete",children:a.jsx(pe,{className:"h-4 w-4 text-red-400"})})]})})]}),t&&a.jsxs("div",{className:"border-t border-gray-200 dark:border-gray-700 px-4 py-4",children:[a.jsx(Y_,{supplierId:e.id,canEdit:r,fallback:{contact_name:e.contact_name,phone:e.phone,email:e.email,website:e.website,address:e.address,rep_name:e.rep_name,rep_phone:e.rep_phone,rep_email:e.rep_email,driver_name:e.driver_name,driver_phone:e.driver_phone,driver_email:e.driver_email}}),a.jsx("div",{className:"grid grid-cols-1 gap-6 md:grid-cols-2 mt-6",children:a.jsxs("div",{className:"space-y-2",children:[a.jsxs("h4",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5",children:[a.jsx(Na,{className:"h-3.5 w-3.5"}),"Delivery Info"]}),a.jsxs("div",{className:"space-y-1.5 text-sm",children:[a.jsx("div",{className:"flex flex-wrap gap-1",children:(e.delivery_methods??(e.primary_delivery_method?[e.primary_delivery_method]:[])).map(l=>{const u=l===e.primary_delivery_method;return a.jsxs(G,{variant:dr[l],children:[Ut[l],u&&(e.delivery_methods?.length??0)>1&&a.jsx("span",{className:"ml-1 text-[10px] opacity-75",children:"(primary)"})]},l)})}),c&&d.length>0&&a.jsxs("div",{className:"flex items-center gap-1 flex-wrap mt-1",children:[a.jsx(Na,{className:"h-3.5 w-3.5 text-gray-500 shrink-0"}),d.map(l=>a.jsx("span",{className:"px-2 py-0.5 text-xs rounded-full bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300",children:H_[l]??l},l))]}),e.special_order_lead_days!=null&&e.special_order_lead_days>0&&a.jsxs("div",{className:"flex items-center gap-1.5 text-amber-600 dark:text-amber-400",children:[a.jsx(Bt,{className:"h-3.5 w-3.5"}),"Special orders: +",e.special_order_lead_days," day",e.special_order_lead_days!==1?"s":""]}),e.delivery_notes&&a.jsx("div",{className:"text-gray-500 dark:text-gray-400 text-xs italic mt-1",children:e.delivery_notes})]})]})}),a.jsx("div",{className:"mt-4 pt-3 border-t border-gray-100 dark:border-gray-700/50",children:a.jsxs("div",{className:"flex flex-wrap gap-4 text-xs",children:[a.jsx(Lt,{label:"On-Time",value:e.on_time_rate,format:"percent"}),a.jsx(Lt,{label:"Quality",value:e.quality_score,format:"percent"}),a.jsx(Lt,{label:"Avg Lead",value:e.avg_lead_days,format:"days"}),a.jsx(Lt,{label:"Reliability",value:e.reliability_score,format:"percent"})]})}),e.notes&&a.jsxs("div",{className:"mt-3 pt-3 border-t border-gray-100 dark:border-gray-700/50 text-sm text-gray-600 dark:text-gray-400",children:[a.jsx("span",{className:"font-medium text-gray-700 dark:text-gray-300",children:"Notes: "}),e.notes]}),a.jsx(K_,{supplierId:e.id,supplierName:e.name})]})]})}function K_({supplierId:e,supplierName:t}){const{data:s,isLoading:r}=B({queryKey:["supplier-brands",e],queryFn:()=>d_(e)});return a.jsxs("div",{className:"mt-3 pt-3 border-t border-gray-100 dark:border-gray-700/50",children:[a.jsxs("h4",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5 mb-2",children:[a.jsx(De,{className:"h-3.5 w-3.5"}),"Brands Carried"]}),r?a.jsxs("div",{className:"flex items-center gap-2 text-sm text-gray-500",children:[a.jsx(z,{size:"sm"})," Loading..."]}):(s??[]).length===0?a.jsx("p",{className:"text-sm text-gray-400 italic",children:"No brands linked. Link brands from the Brands tab."}):a.jsx("div",{className:"flex flex-wrap gap-2",children:(s??[]).map(n=>a.jsxs("div",{className:"inline-flex items-center gap-1.5 px-3 py-1.5 bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 text-sm",children:[a.jsx(De,{className:"h-3.5 w-3.5 text-primary-500"}),a.jsx("span",{className:"font-medium text-gray-900 dark:text-gray-100",children:n.brand_name}),n.account_number&&a.jsxs("span",{className:"text-xs text-gray-500 dark:text-gray-400",children:["(",n.account_number,")"]})]},n.id))})]})}function Lt({label:e,value:t,format:s}){let r,n;if(s==="percent"){const i=Math.round(t*100);r=`${i}%`,n=i>=90?"text-green-600 dark:text-green-400":i>=75?"text-amber-600 dark:text-amber-400":"text-red-600 dark:text-red-400"}else r=`${t}d`,n=t<=3?"text-green-600 dark:text-green-400":t<=7?"text-amber-600 dark:text-amber-400":"text-red-600 dark:text-red-400";return a.jsxs("div",{className:"flex items-center gap-1",children:[a.jsxs("span",{className:"text-gray-500 dark:text-gray-400",children:[e,":"]}),a.jsx("span",{className:`font-semibold ${n}`,children:r})]})}function Y_({supplierId:e,canEdit:t,fallback:s}){const r=re(),[n,i]=b.useState(!1),[o,c]=b.useState(null),{data:d,isLoading:l}=B({queryKey:["supplier-contacts",e],queryFn:()=>q_(e)}),u=P({mutationFn:y=>G_(e,y),onSuccess:()=>{r.invalidateQueries({queryKey:["supplier-contacts",e]}),i(!1)}}),E=P({mutationFn:({id:y,data:f})=>B_(y,f),onSuccess:()=>{r.invalidateQueries({queryKey:["supplier-contacts",e]}),c(null)}}),_=P({mutationFn:$_,onSuccess:()=>{r.invalidateQueries({queryKey:["supplier-contacts",e]})}}),m=(d??[]).length>0;return a.jsxs("div",{className:"space-y-3",children:[a.jsxs("div",{className:"flex items-center justify-between",children:[a.jsxs("h4",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5",children:[a.jsx(Fa,{className:"h-3.5 w-3.5"}),"Contacts"]}),t&&!n&&a.jsxs("button",{onClick:()=>i(!0),className:"flex items-center gap-1 text-xs text-primary-500 hover:text-primary-600 font-medium",children:[a.jsx(Id,{className:"h-3.5 w-3.5"}),"Add Contact"]})]}),n&&a.jsx(ur,{onSubmit:y=>u.mutate(y),onCancel:()=>i(!1),isLoading:u.isPending}),l?a.jsxs("div",{className:"flex items-center gap-2 text-sm text-gray-500",children:[a.jsx(z,{size:"sm"})," Loading contacts..."]}):m?a.jsx("div",{className:"grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3",children:(d??[]).map(y=>a.jsx("div",{className:"p-3 rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800/50 space-y-1.5",children:o?.id===y.id?a.jsx(ur,{initial:y,onSubmit:f=>E.mutate({id:y.id,data:f}),onCancel:()=>c(null),isLoading:E.isPending}):a.jsxs(a.Fragment,{children:[a.jsxs("div",{className:"flex items-center justify-between",children:[a.jsxs("div",{className:"flex items-center gap-2 min-w-0",children:[a.jsxs("span",{className:"font-medium text-sm text-gray-900 dark:text-gray-100 truncate",children:[y.first_name," ",y.last_name]}),a.jsx(G,{variant:"info",className:"text-[10px] flex-shrink-0",children:y.role}),y.is_primary&&a.jsx(G,{variant:"success",className:"text-[10px] flex-shrink-0",children:"Primary"})]}),t&&a.jsxs("div",{className:"flex items-center gap-0.5 ml-1 flex-shrink-0",children:[a.jsx("button",{onClick:()=>c(y),className:"p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700",title:"Edit",children:a.jsx(Nt,{className:"h-3 w-3 text-gray-400"})}),a.jsx("button",{onClick:()=>_.mutate(y.id),className:"p-1 rounded hover:bg-red-100 dark:hover:bg-red-900/30",title:"Remove",children:a.jsx(pe,{className:"h-3 w-3 text-red-400"})})]})]}),a.jsxs("div",{className:"space-y-0.5 text-sm",children:[y.phone&&a.jsxs("a",{href:`tel:${y.phone}`,className:"flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline",children:[a.jsx(ut,{className:"h-3 w-3"}),y.phone]}),y.email&&a.jsxs("a",{href:`mailto:${y.email}`,className:"flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline",children:[a.jsx(Ot,{className:"h-3 w-3"}),y.email]})]})]})},y.id))}):a.jsx(V_,{fallback:s})]})}function V_({fallback:e}){const t=e.contact_name||e.phone||e.email,s=e.rep_name||e.rep_phone||e.rep_email,r=e.driver_name||e.driver_phone||e.driver_email;return!t&&!s&&!r?a.jsx("p",{className:"text-sm text-gray-400 dark:text-gray-500 italic",children:'No contacts on file. Click "Add Contact" to add one.'}):a.jsxs("div",{className:"grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3",children:[t&&a.jsxs("div",{className:"space-y-1.5 text-sm",children:[a.jsxs("div",{className:"flex items-center gap-1 text-xs font-medium text-gray-500 dark:text-gray-400",children:[a.jsx(Fa,{className:"h-3 w-3"})," Business Contact"]}),e.contact_name&&a.jsx("div",{className:"text-gray-900 dark:text-gray-100 font-medium",children:e.contact_name}),e.phone&&a.jsxs("a",{href:`tel:${e.phone}`,className:"flex items-center gap-1.5 text-primary-500 hover:underline",children:[a.jsx(ut,{className:"h-3 w-3"})," ",e.phone]}),e.email&&a.jsxs("a",{href:`mailto:${e.email}`,className:"flex items-center gap-1.5 text-primary-500 hover:underline",children:[a.jsx(Ot,{className:"h-3 w-3"})," ",e.email]}),e.website&&a.jsxs("a",{href:e.website,target:"_blank",rel:"noopener noreferrer",className:"flex items-center gap-1.5 text-primary-500 hover:underline",children:[a.jsx(br,{className:"h-3 w-3"}),a.jsx("span",{className:"truncate",children:e.website.replace(/^https?:\/\/(www\.)?/,"")})]}),e.address&&a.jsxs("div",{className:"flex items-start gap-1.5 text-gray-600 dark:text-gray-400",children:[a.jsx(Rr,{className:"h-3 w-3 mt-0.5 shrink-0"})," ",e.address]})]}),s&&a.jsxs("div",{className:"space-y-1.5 text-sm",children:[a.jsxs("div",{className:"flex items-center gap-1 text-xs font-medium text-gray-500 dark:text-gray-400",children:[a.jsx(Da,{className:"h-3 w-3"})," Sales Rep"]}),e.rep_name&&a.jsx("div",{className:"text-gray-900 dark:text-gray-100 font-medium",children:e.rep_name}),e.rep_phone&&a.jsxs("a",{href:`tel:${e.rep_phone}`,className:"flex items-center gap-1.5 text-primary-500 hover:underline",children:[a.jsx(ut,{className:"h-3 w-3"})," ",e.rep_phone]}),e.rep_email&&a.jsxs("a",{href:`mailto:${e.rep_email}`,className:"flex items-center gap-1.5 text-primary-500 hover:underline",children:[a.jsx(Ot,{className:"h-3 w-3"})," ",e.rep_email]})]}),r&&a.jsxs("div",{className:"space-y-1.5 text-sm",children:[a.jsxs("div",{className:"flex items-center gap-1 text-xs font-medium text-gray-500 dark:text-gray-400",children:[a.jsx(Xe,{className:"h-3 w-3"})," Delivery Driver"]}),e.driver_name&&a.jsx("div",{className:"text-gray-900 dark:text-gray-100 font-medium",children:e.driver_name}),e.driver_phone&&a.jsxs("a",{href:`tel:${e.driver_phone}`,className:"flex items-center gap-1.5 text-primary-500 hover:underline",children:[a.jsx(ut,{className:"h-3 w-3"})," ",e.driver_phone]}),e.driver_email&&a.jsxs("a",{href:`mailto:${e.driver_email}`,className:"flex items-center gap-1.5 text-primary-500 hover:underline",children:[a.jsx(Ot,{className:"h-3 w-3"})," ",e.driver_email]})]})]})}function ur({initial:e,onSubmit:t,onCancel:s,isLoading:r}){const[n,i]=b.useState({first_name:e?.first_name??"",last_name:e?.last_name??"",role:e?.role??"",phone:e?.phone??"",email:e?.email??"",is_primary:e?.is_primary??!1}),o=c=>{c.preventDefault(),t({first_name:n.first_name,last_name:n.last_name,role:n.role,phone:n.phone,email:n.email||void 0,is_primary:!!n.is_primary})};return a.jsxs("form",{onSubmit:o,className:"p-3 rounded-lg border border-primary-200 dark:border-primary-800 bg-primary-50/50 dark:bg-primary-900/10 space-y-2",children:[a.jsxs("div",{className:"grid grid-cols-2 gap-2",children:[a.jsx("input",{className:"rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm",placeholder:"First name *",value:n.first_name,onChange:c=>i(d=>({...d,first_name:c.target.value})),required:!0}),a.jsx("input",{className:"rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm",placeholder:"Last name *",value:n.last_name,onChange:c=>i(d=>({...d,last_name:c.target.value})),required:!0})]}),a.jsxs("div",{className:"grid grid-cols-2 gap-2",children:[a.jsx("input",{className:"rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm",placeholder:"Role * (e.g. Sales Rep)",value:n.role,onChange:c=>i(d=>({...d,role:c.target.value})),required:!0}),a.jsx("input",{className:"rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm",placeholder:"Phone *",value:n.phone,onChange:c=>i(d=>({...d,phone:c.target.value})),required:!0,type:"tel"})]}),a.jsxs("div",{className:"grid grid-cols-2 gap-2",children:[a.jsx("input",{className:"rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm",placeholder:"Email",value:n.email,onChange:c=>i(d=>({...d,email:c.target.value})),type:"email"}),a.jsxs("label",{className:"flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400 cursor-pointer",children:[a.jsx("input",{type:"checkbox",className:"rounded",checked:!!n.is_primary,onChange:c=>i(d=>({...d,is_primary:c.target.checked}))}),"Primary contact"]})]}),a.jsxs("div",{className:"flex items-center gap-2 pt-1",children:[a.jsx("button",{type:"submit",disabled:r,className:"px-3 py-1 rounded bg-primary-500 text-white text-xs font-medium hover:bg-primary-600 disabled:opacity-50",children:r?"Saving...":e?"Update":"Add"}),a.jsx("button",{type:"button",onClick:s,className:"px-3 py-1 rounded border border-gray-300 dark:border-gray-600 text-xs font-medium text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800",children:"Cancel"})]})]})}const J_=[{value:"monday",label:"Mon"},{value:"tuesday",label:"Tue"},{value:"wednesday",label:"Wed"},{value:"thursday",label:"Thu"},{value:"friday",label:"Fri"},{value:"saturday",label:"Sat"},{value:"sunday",label:"Sun"}];function _r({isOpen:e,onClose:t,onSubmit:s,isLoading:r,title:n,initial:i}){const[o,c]=b.useState({name:i?.name??"",contact_name:i?.contact_name??"",email:i?.email??"",phone:i?.phone??"",address:i?.address??"",website:i?.website??"",rep_name:i?.rep_name??"",rep_email:i?.rep_email??"",rep_phone:i?.rep_phone??"",delivery_methods:i?.delivery_methods??["standard_shipping"],primary_delivery_method:i?.primary_delivery_method??"standard_shipping",delivery_days:rn(i?.delivery_days??null),special_order_lead_days:i?.special_order_lead_days?.toString()??"",delivery_notes:i?.delivery_notes??"",driver_name:i?.driver_name??"",driver_phone:i?.driver_phone??"",driver_email:i?.driver_email??"",notes:i?.notes??""}),d=_=>{_.preventDefault();const m={name:o.name,contact_name:o.contact_name||void 0,email:o.email||void 0,phone:o.phone||void 0,address:o.address||void 0,website:o.website||void 0,rep_name:o.rep_name||void 0,rep_email:o.rep_email||void 0,rep_phone:o.rep_phone||void 0,delivery_methods:o.delivery_methods,primary_delivery_method:o.primary_delivery_method,delivery_days:o.delivery_methods.includes("scheduled_delivery")&&o.delivery_days.length>0?JSON.stringify(o.delivery_days):void 0,special_order_lead_days:o.special_order_lead_days?parseInt(o.special_order_lead_days,10):void 0,delivery_notes:o.delivery_notes||void 0,driver_name:o.driver_name||void 0,driver_phone:o.driver_phone||void 0,driver_email:o.driver_email||void 0,notes:o.notes||void 0};s(m)},l=(_,m)=>c(y=>({...y,[_]:m})),u=_=>{c(m=>{const y=m.delivery_methods.includes(_);let f;if(y){if(m.delivery_methods.length<=1)return m;f=m.delivery_methods.filter(h=>h!==_)}else f=[...m.delivery_methods,_];const v=f.includes(m.primary_delivery_method)?m.primary_delivery_method:f[0];return{...m,delivery_methods:f,primary_delivery_method:v}})},E=_=>{c(m=>({...m,delivery_days:m.delivery_days.includes(_)?m.delivery_days.filter(y=>y!==_):[...m.delivery_days,_]}))};return a.jsx(Ne,{isOpen:e,onClose:t,title:n,size:"lg",children:a.jsxs("form",{onSubmit:d,className:"space-y-5 max-h-[70vh] overflow-y-auto pr-1",children:[a.jsx(q,{label:"Supplier Name *",value:o.name,onChange:_=>l("name",_.target.value),placeholder:"e.g. CED Irving",required:!0}),a.jsxs("fieldset",{className:"space-y-3 border border-gray-200 dark:border-gray-700 rounded-lg p-3",children:[a.jsxs("legend",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 px-1 flex items-center gap-1",children:[a.jsx(Fa,{className:"h-3.5 w-3.5"}),"Business Contact"]}),a.jsx(q,{label:"Contact Name",value:o.contact_name,onChange:_=>l("contact_name",_.target.value),placeholder:"e.g. Front Desk, Customer Service"}),a.jsxs("div",{className:"grid grid-cols-1 sm:grid-cols-2 gap-3",children:[a.jsx(q,{label:"Phone",value:o.phone,onChange:_=>l("phone",_.target.value),placeholder:"972-555-0100",type:"tel"}),a.jsx(q,{label:"Email",value:o.email,onChange:_=>l("email",_.target.value),placeholder:"info@supplier.com",type:"email"})]}),a.jsx(q,{label:"Address",value:o.address,onChange:_=>l("address",_.target.value),placeholder:"123 Supply Rd, Irving TX 75061"}),a.jsx(q,{label:"Website",value:o.website,onChange:_=>l("website",_.target.value),placeholder:"https://www.supplier.com",type:"url"})]}),a.jsxs("fieldset",{className:"space-y-3 border border-gray-200 dark:border-gray-700 rounded-lg p-3",children:[a.jsxs("legend",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 px-1 flex items-center gap-1",children:[a.jsx(Da,{className:"h-3.5 w-3.5"}),"Sales Rep"]}),a.jsx(q,{label:"Rep Name",value:o.rep_name,onChange:_=>l("rep_name",_.target.value),placeholder:"e.g. Mike Johnson"}),a.jsxs("div",{className:"grid grid-cols-1 sm:grid-cols-2 gap-3",children:[a.jsx(q,{label:"Rep Phone",value:o.rep_phone,onChange:_=>l("rep_phone",_.target.value),placeholder:"972-555-0101",type:"tel"}),a.jsx(q,{label:"Rep Email",value:o.rep_email,onChange:_=>l("rep_email",_.target.value),placeholder:"rep@supplier.com",type:"email"})]})]}),a.jsxs("fieldset",{className:"space-y-3 border border-gray-200 dark:border-gray-700 rounded-lg p-3",children:[a.jsxs("legend",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 px-1 flex items-center gap-1",children:[a.jsx(Xe,{className:"h-3.5 w-3.5"}),"Delivery"]}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Delivery Methods"}),a.jsx("p",{className:"text-xs text-gray-500 dark:text-gray-400",children:"Select all that apply"}),a.jsx("div",{className:"flex flex-wrap gap-2",children:["standard_shipping","scheduled_delivery","in_store_pickup"].map(_=>{const m=fa[_],y=o.delivery_methods.includes(_);return a.jsxs("button",{type:"button",className:`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm border transition-colors ${y?"border-primary-500 bg-primary-50 dark:bg-primary-900/20 text-primary-700 dark:text-primary-300":"border-gray-200 dark:border-gray-600 hover:border-gray-300 dark:hover:border-gray-500"}`,onClick:()=>u(_),children:[a.jsx(m,{className:"h-3.5 w-3.5"}),Ut[_]]},_)})})]}),o.delivery_methods.length>1&&a.jsxs("div",{className:"space-y-1.5",children:[a.jsxs("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300 flex items-center gap-1.5",children:[a.jsx(Gt,{className:"h-3.5 w-3.5 text-amber-500"}),"Primary Method"]}),a.jsx("p",{className:"text-xs text-gray-500 dark:text-gray-400",children:"Which method do you use most often?"}),a.jsx("select",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm",value:o.primary_delivery_method,onChange:_=>l("primary_delivery_method",_.target.value),children:o.delivery_methods.map(_=>a.jsx("option",{value:_,children:Ut[_]},_))})]}),o.delivery_methods.includes("scheduled_delivery")&&a.jsxs("div",{className:"space-y-3 mt-2 p-2.5 rounded-lg bg-gray-50 dark:bg-gray-900/40",children:[a.jsxs("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300 flex items-center gap-1.5",children:[a.jsx(Xe,{className:"h-3.5 w-3.5"}),"Delivery Driver"]}),a.jsx(q,{label:"Driver Name",value:o.driver_name,onChange:_=>l("driver_name",_.target.value),placeholder:"e.g. Carlos"}),a.jsxs("div",{className:"grid grid-cols-1 sm:grid-cols-2 gap-3",children:[a.jsx(q,{label:"Driver Phone",value:o.driver_phone,onChange:_=>l("driver_phone",_.target.value),placeholder:"972-555-0102",type:"tel"}),a.jsx(q,{label:"Driver Email",value:o.driver_email,onChange:_=>l("driver_email",_.target.value),placeholder:"driver@supplier.com",type:"email"})]})]}),o.delivery_methods.includes("scheduled_delivery")&&a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Delivery Days"}),a.jsx("div",{className:"flex flex-wrap gap-1.5",children:J_.map(({value:_,label:m})=>a.jsx("button",{type:"button",className:`px-3 py-1 rounded-full text-xs font-medium border transition-colors ${o.delivery_days.includes(_)?"border-green-500 bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300":"border-gray-200 dark:border-gray-600 text-gray-500 hover:border-gray-300"}`,onClick:()=>E(_),children:m},_))})]}),a.jsxs("div",{className:"grid grid-cols-1 sm:grid-cols-2 gap-3",children:[a.jsx(q,{label:"Special Order Lead Days",value:o.special_order_lead_days,onChange:_=>l("special_order_lead_days",_.target.value),placeholder:"e.g. 3",type:"number",min:"0",hint:"Extra days for items not in local warehouse"}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Delivery Notes"}),a.jsx("input",{className:"block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm",value:o.delivery_notes,onChange:_=>l("delivery_notes",_.target.value),placeholder:"e.g. Delivers 7am-noon only"})]})]})]}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Notes"}),a.jsx("textarea",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[80px]",value:o.notes,onChange:_=>l("notes",_.target.value),placeholder:"Any additional notes about this supplier..."})]}),a.jsxs("div",{className:"flex justify-end gap-2 pt-2 border-t border-gray-200 dark:border-gray-700",children:[a.jsx(F,{variant:"secondary",type:"button",onClick:t,children:"Cancel"}),a.jsx(F,{type:"submit",isLoading:r,children:i?"Save Changes":"Create Supplier"})]})]})})}function Q_({part:e,typeId:t,styleId:s,categoryId:r,brandId:n,selected:i,onSelect:o}){const c=i?.type==="part"&&i.partId===e.id;return a.jsxs("button",{className:`flex items-center gap-1.5 w-full px-2 py-1 rounded-lg text-left transition-colors ${c?"bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300":"hover:bg-gray-100 dark:hover:bg-gray-700/50"}`,onClick:()=>o({type:"part",id:e.id,partId:e.id,typeId:t,styleId:s,categoryId:r,brandId:n,colorId:e.color_id??void 0}),children:[a.jsx("span",{className:"inline-block w-3 h-3 rounded-full border border-gray-300 dark:border-gray-500 flex-shrink-0",style:{backgroundColor:e.color_hex??"#ccc"}}),a.jsx("span",{className:"text-xs truncate flex-1",children:e.color_name??e.name}),e.is_deprecated&&a.jsx("span",{className:"text-[9px] text-red-400 font-medium",children:"DEP"}),e.brand_id!==null&&!e.manufacturer_part_number&&a.jsx("span",{className:"text-[9px] text-amber-500 font-medium",title:"MPN needed",children:"!"})]})}function z_({link:e,typeId:t,styleId:s,categoryId:r,selected:n,onSelect:i,canEdit:o}){const[c,d]=b.useState(!1),l=e.brand_id===null,u=l?"General":e.brand_name??"Unknown",E=n?.type==="brand"&&n.typeId===t&&n.brandId===e.brand_id,{data:_,isLoading:m}=B({queryKey:["type-brand-parts",t,e.brand_id??0],queryFn:()=>Qr(t,e.brand_id),enabled:c});return a.jsxs("div",{children:[a.jsxs("div",{className:`flex items-center gap-1 px-2 py-1.5 rounded-lg cursor-pointer transition-colors group ${E?"bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300":"hover:bg-gray-100 dark:hover:bg-gray-700/50"}`,children:[a.jsx("button",{className:"p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-600 flex-shrink-0 transition-colors",onClick:y=>{y.stopPropagation(),d(!c)},children:c?a.jsx(Te,{className:"h-4 w-4 text-gray-500"}):a.jsx(ye,{className:"h-4 w-4 text-gray-500"})}),l?a.jsx(Oe,{className:"h-3.5 w-3.5 text-gray-500 flex-shrink-0"}):a.jsx(De,{className:"h-3.5 w-3.5 text-amber-500 flex-shrink-0"}),a.jsx("button",{className:"flex-1 text-left text-sm truncate",onClick:()=>{d(!0),i({type:"brand",id:e.id,typeId:t,styleId:s,categoryId:r,brandId:e.brand_id,brandName:u})},children:u}),e.part_count>0&&a.jsx(G,{variant:"default",className:"text-[10px] px-1.5 py-0",children:e.part_count})]}),c&&a.jsx("div",{className:"ml-4 pl-2 border-l border-gray-200 dark:border-gray-700",children:m?a.jsxs("div",{className:"flex items-center gap-2 py-1 pl-2 text-xs text-gray-400",children:[a.jsx(z,{size:"sm"})," Loading parts..."]}):!_||_.length===0?a.jsx("p",{className:"text-xs text-gray-400 italic py-1 pl-2",children:"No parts yet — select to add colors"}):_.map(y=>a.jsx(Q_,{part:y,typeId:t,styleId:s,categoryId:r,brandId:e.brand_id,selected:n,onSelect:i},y.id))})]})}function Z_({type:e,styleId:t,categoryId:s,isExpanded:r,onToggle:n,selected:i,onSelect:o,canEdit:c}){const d=i?.type==="type"&&i.id===e.id,{data:l,isLoading:u}=B({queryKey:["type-brands",e.id],queryFn:()=>Jr(e.id),enabled:r});return a.jsxs("div",{children:[a.jsxs("div",{className:`flex items-center gap-1 px-2 py-1.5 rounded-lg cursor-pointer transition-colors group ${d?"bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300":"hover:bg-gray-100 dark:hover:bg-gray-700/50"}`,children:[a.jsx("button",{className:"p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-600 flex-shrink-0 transition-colors",onClick:E=>{E.stopPropagation(),n()},children:r?a.jsx(Te,{className:"h-4 w-4 text-gray-500"}):a.jsx(ye,{className:"h-4 w-4 text-gray-500"})}),a.jsx(Be,{className:"h-3 w-3 text-teal-500 flex-shrink-0"}),a.jsx("button",{className:"flex-1 text-left text-sm truncate",onClick:()=>o({type:"type",id:e.id,styleId:t,categoryId:s}),children:e.name}),!e.is_active&&a.jsx(G,{variant:"default",className:"text-[10px] px-1.5 py-0",children:"Off"}),e.part_count>0&&a.jsxs("span",{className:"text-[10px] text-gray-400 mr-1",children:[e.part_count,"p"]})]}),r&&a.jsx("div",{className:"ml-4 pl-2 border-l border-gray-200 dark:border-gray-700",children:u?a.jsxs("div",{className:"flex items-center gap-2 py-2 pl-2 text-xs text-gray-400",children:[a.jsx(z,{size:"sm"})," Loading brands..."]}):!l||l.length===0?a.jsx("p",{className:"text-xs text-gray-400 italic py-1.5 pl-2",children:"No brands enabled — select this type to configure"}):l.map(E=>a.jsx(z_,{link:E,typeId:e.id,styleId:t,categoryId:s,selected:i,onSelect:o,canEdit:c},E.id))})]})}function eE({style:e,categoryId:t,isExpanded:s,onToggle:r,selected:n,onSelect:i,canEdit:o,expandedTypes:c,onToggleType:d,onCreateType:l}){const u=n?.type==="style"&&n.id===e.id,{data:E,isLoading:_}=B({queryKey:["types",e.id],queryFn:()=>Kr(e.id),enabled:s});return a.jsxs("div",{children:[a.jsxs("div",{className:`flex items-center gap-1 px-2 py-1.5 rounded-lg cursor-pointer transition-colors group ${u?"bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300":"hover:bg-gray-100 dark:hover:bg-gray-700/50"}`,children:[a.jsx("button",{className:"p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-600 flex-shrink-0 transition-colors",onClick:m=>{m.stopPropagation(),r()},children:s?a.jsx(Te,{className:"h-4 w-4 text-gray-500"}):a.jsx(ye,{className:"h-4 w-4 text-gray-500"})}),a.jsx(Be,{className:"h-3.5 w-3.5 text-indigo-500 flex-shrink-0"}),a.jsx("button",{className:"flex-1 text-left text-sm truncate min-h-[28px] flex items-center",onClick:()=>i({type:"style",id:e.id,categoryId:t}),children:e.name}),!e.is_active&&a.jsx(G,{variant:"default",className:"text-[10px] px-1.5 py-0",children:"Off"}),a.jsxs("span",{className:"text-[10px] text-gray-400 mr-1",children:[e.type_count,"t / ",e.part_count,"p"]}),o&&a.jsx("button",{className:"p-1.5 rounded text-gray-400 hover:text-gray-600 hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors shrink-0",onClick:m=>{m.stopPropagation(),l(e.id)},title:"Add Type",children:a.jsx(oe,{className:"h-4 w-4"})})]}),s&&a.jsx("div",{className:"ml-4 pl-2 border-l border-gray-200 dark:border-gray-700",children:_?a.jsxs("div",{className:"flex items-center gap-2 py-2 pl-2 text-xs text-gray-400",children:[a.jsx(z,{size:"sm"})," Loading types..."]}):!E||E.length===0?a.jsx("p",{className:"text-xs text-gray-400 italic py-1.5 pl-2",children:"No types yet"}):E.map(m=>a.jsx(Z_,{type:m,styleId:e.id,categoryId:t,isExpanded:c.has(m.id),onToggle:()=>d(m.id),selected:n,onSelect:i,canEdit:o},m.id))})]})}function tE({category:e,isExpanded:t,onToggle:s,selected:r,onSelect:n,canEdit:i,onCreateChild:o,expandedStyles:c,onToggleStyle:d,expandedTypes:l,onToggleType:u,onCreateType:E}){const _=r?.type==="category"&&r.id===e.id,{data:m,isLoading:y}=B({queryKey:["styles",e.id],queryFn:()=>Ft(e.id),enabled:t});return a.jsxs("div",{children:[a.jsxs("div",{className:`flex items-center gap-1 px-2 py-1.5 rounded-lg cursor-pointer transition-colors group ${_?"bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300":"hover:bg-gray-100 dark:hover:bg-gray-700/50"}`,children:[a.jsx("button",{className:"p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-600 flex-shrink-0 transition-colors",onClick:f=>{f.stopPropagation(),s()},children:t?a.jsx(Te,{className:"h-4 w-4 text-gray-500"}):a.jsx(ye,{className:"h-4 w-4 text-gray-500"})}),a.jsx(ka,{className:"h-4 w-4 text-primary-500 flex-shrink-0"}),a.jsx("button",{className:"flex-1 text-left text-sm font-medium truncate min-h-[28px] flex items-center",onClick:()=>n({type:"category",id:e.id}),children:e.name}),!e.is_active&&a.jsx(G,{variant:"default",className:"text-[10px] px-1.5 py-0",children:"Off"}),a.jsxs("span",{className:"text-[10px] text-gray-400 mr-1",children:[e.style_count,"s / ",e.part_count,"p"]}),i&&a.jsx("button",{className:"p-1.5 rounded text-gray-400 hover:text-gray-600 hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors shrink-0",onClick:f=>{f.stopPropagation(),o(e.id)},title:"Add Style",children:a.jsx(oe,{className:"h-4 w-4"})})]}),t&&a.jsx("div",{className:"ml-4 pl-2 border-l border-gray-200 dark:border-gray-700",children:y?a.jsxs("div",{className:"flex items-center gap-2 py-2 pl-2 text-xs text-gray-400",children:[a.jsx(z,{size:"sm"})," Loading styles..."]}):!m||m.length===0?a.jsx("p",{className:"text-xs text-gray-400 italic py-1.5 pl-2",children:"No styles yet"}):m.map(f=>a.jsx(eE,{style:f,categoryId:e.id,isExpanded:c.has(f.id),onToggle:()=>d(f.id),selected:r,onSelect:n,canEdit:i,expandedTypes:l,onToggleType:u,onCreateType:v=>E(v,e.id)},f.id))})]})}function aE({target:e,allColors:t,onCancel:s,onCreated:r}){const n=re(),[i,o]=b.useState(""),[c,d]=b.useState(""),[l,u]=b.useState(""),[E,_]=b.useState("#FFFFFF"),m=e.type==="category"?"Category":e.type==="style"?"Style":e.type==="type"?"Type":"Color",y=P({mutationFn:Yu,onSuccess:w=>{n.invalidateQueries({queryKey:["categories"]}),r("category",w.id),H.success("Category created")},onError:()=>H.error("Failed to create category")}),f=P({mutationFn:Hr,onSuccess:w=>{n.invalidateQueries({queryKey:["styles",e.parentId]}),n.invalidateQueries({queryKey:["categories"]}),r("style",w.id,e.parentId),H.success("Style created")},onError:()=>H.error("Failed to create style")}),v=P({mutationFn:Yr,onSuccess:w=>{n.invalidateQueries({queryKey:["types",e.parentId]}),n.invalidateQueries({queryKey:["styles"]}),r("type",w.id,e.parentId),H.success("Type created")},onError:()=>H.error("Failed to create type")}),h=P({mutationFn:zr,onSuccess:w=>{n.invalidateQueries({queryKey:["colors"]}),r("color",w.id),H.success("Color created")},onError:()=>H.error("Failed to create color")}),T=y.isPending||f.isPending||v.isPending||h.isPending,g=y.error||f.error||v.error||h.error,L=w=>{w.preventDefault();const O={name:i,description:c||void 0,image_url:l||void 0};switch(e.type){case"category":y.mutate(O);break;case"style":f.mutate({...O,category_id:e.parentId});break;case"type":v.mutate({...O,style_id:e.parentId});break;case"color":h.mutate({name:i,hex_code:E||void 0});break}};return a.jsxs("div",{className:"flex flex-col h-full",children:[a.jsxs("div",{className:"px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80",children:[a.jsxs("h3",{className:"text-lg font-semibold text-gray-900 dark:text-gray-100",children:["New ",m]}),e.type==="style"&&a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400 mt-0.5",children:"Adding to category"}),e.type==="type"&&a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400 mt-0.5",children:"Adding to style"})]}),a.jsxs("form",{onSubmit:L,className:"flex-1 overflow-y-auto p-6 space-y-4",children:[a.jsx(q,{label:`${m} Name *`,value:i,onChange:w=>o(w.target.value),placeholder:`e.g. ${e.type==="category"?"Outlet":e.type==="style"?"Decora":e.type==="type"?"GFI":"White"}`,required:!0,autoFocus:!0}),e.type!=="color"&&a.jsxs(a.Fragment,{children:[a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Description"}),a.jsx("textarea",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px]",value:c,onChange:w=>d(w.target.value),placeholder:"Optional description..."})]}),a.jsx(q,{label:"Image URL",value:l,onChange:w=>u(w.target.value),placeholder:"https://...",type:"url",hint:"Optional — add product images later"})]}),e.type==="color"&&a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Hex Color Code"}),a.jsxs("div",{className:"flex items-center gap-3",children:[a.jsx("input",{type:"color",value:E,onChange:w=>_(w.target.value),className:"w-10 h-10 rounded-lg border border-gray-300 dark:border-gray-600 cursor-pointer"}),a.jsx(q,{value:E,onChange:w=>_(w.target.value),placeholder:"#FFFFFF",className:"font-mono"})]})]}),g&&a.jsx("p",{className:"text-red-500 text-sm",children:g?.response?.data?.detail??`Failed to create ${m.toLowerCase()}.`}),a.jsxs("div",{className:"flex justify-end gap-2 pt-4 border-t border-gray-200 dark:border-gray-700",children:[a.jsx(F,{variant:"secondary",type:"button",onClick:s,children:"Cancel"}),a.jsxs(F,{type:"submit",isLoading:T,icon:a.jsx(oe,{className:"h-4 w-4"}),children:["Create ",m]})]})]})]})}function sE({categoryId:e,canEdit:t,onDelete:s,onSelectChild:r}){const n=re(),{data:i}=B({queryKey:["categories"],queryFn:()=>Ba()}),o=i?.find(j=>j.id===e),[c,d]=b.useState(""),[l,u]=b.useState(""),[E,_]=b.useState(""),[m,y]=b.useState(!1),[f,v]=b.useState(e),[h,T]=b.useState(!1),[g,L]=b.useState("");o&&(!m||e!==f)&&(d(o.name),u(o.description??""),_(o.image_url??""),y(!0),v(e));const{data:w,isLoading:O}=B({queryKey:["styles",e],queryFn:()=>Ft(e),enabled:!!o}),C=P({mutationFn:j=>tr(e,j),onSuccess:()=>{n.invalidateQueries({queryKey:["categories"]}),H.success("Category updated")},onError:()=>H.error("Failed to update category")}),W=P({mutationFn:j=>tr(e,{is_active:j}),onSuccess:()=>{n.invalidateQueries({queryKey:["categories"]}),H.success("Category status updated")},onError:()=>H.error("Failed to update status")}),Q=P({mutationFn:j=>Hr({category_id:e,name:j}),onSuccess:j=>{n.invalidateQueries({queryKey:["styles",e]}),n.invalidateQueries({queryKey:["categories"]}),L(""),T(!1),r({type:"style",id:j.id,categoryId:e}),H.success("Style created")},onError:()=>H.error("Failed to create style")}),M=P({mutationFn:Wr,onSuccess:()=>{n.invalidateQueries({queryKey:["styles",e]}),n.invalidateQueries({queryKey:["categories"]}),H.success("Style deleted")},onError:()=>H.error("Failed to delete style")});if(!o)return a.jsx("div",{className:"flex-1 flex items-center justify-center",children:a.jsx(z,{size:"lg"})});const te=j=>{j.preventDefault(),C.mutate({name:c,description:l||void 0,image_url:E||void 0})},S=j=>{j.preventDefault(),g.trim()&&Q.mutate(g.trim())};return a.jsxs("div",{className:"flex flex-col h-full",children:[a.jsxs("div",{className:"px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80 flex items-center justify-between",children:[a.jsxs("div",{children:[a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx(ka,{className:"h-5 w-5 text-primary-500"}),a.jsx("h3",{className:"text-lg font-semibold text-gray-900 dark:text-gray-100",children:o.name}),a.jsx(G,{variant:o.is_active?"success":"default",children:o.is_active?"Active":"Inactive"})]}),a.jsxs("p",{className:"text-sm text-gray-500 dark:text-gray-400 mt-0.5",children:["Category · ",o.style_count," styles · ",o.part_count," parts"]})]}),t&&a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx("button",{className:"p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors",onClick:()=>W.mutate(!o.is_active),title:o.is_active?"Deactivate":"Activate",children:o.is_active?a.jsx(We,{className:"h-5 w-5 text-green-500"}):a.jsx(Ke,{className:"h-5 w-5 text-gray-400"})}),a.jsx("button",{className:"p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors",onClick:s,title:"Delete",children:a.jsx(pe,{className:"h-4 w-4 text-red-400"})})]})]}),a.jsxs("div",{className:"flex-1 overflow-y-auto",children:[a.jsxs("form",{onSubmit:te,className:"p-6 space-y-4",children:[a.jsx(q,{label:"Name",value:c,onChange:j=>d(j.target.value),disabled:!t,required:!0}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Description"}),a.jsx("textarea",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px] disabled:opacity-50",value:l,onChange:j=>u(j.target.value),disabled:!t,placeholder:"Optional description..."})]}),a.jsx(q,{label:"Image URL",value:E,onChange:j=>_(j.target.value),disabled:!t,placeholder:"https://...",type:"url"}),C.isSuccess&&a.jsxs("p",{className:"text-green-600 text-sm flex items-center gap-1",children:[a.jsx(Ue,{className:"h-4 w-4"})," Saved successfully"]}),C.isError&&a.jsx("p",{className:"text-red-500 text-sm",children:C.error?.response?.data?.detail??"Failed to save."}),t&&a.jsx("div",{className:"flex justify-end",children:a.jsx(F,{type:"submit",isLoading:C.isPending,children:"Save Changes"})})]}),a.jsxs("div",{className:"border-t border-gray-200 dark:border-gray-700 p-6",children:[a.jsxs("div",{className:"flex items-center justify-between mb-3",children:[a.jsxs("h4",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2",children:[a.jsx(Be,{className:"h-4 w-4 text-indigo-500"}),"Styles",w&&a.jsxs("span",{className:"text-xs text-gray-400 font-normal",children:["(",w.length,")"]})]}),t&&a.jsxs("button",{className:"flex items-center gap-1 text-xs text-primary-600 hover:text-primary-700 dark:text-primary-400 font-medium",onClick:()=>T(!h),children:[a.jsx(oe,{className:"h-3.5 w-3.5"}),"Add Style"]})]}),h&&a.jsxs("form",{onSubmit:S,className:"flex items-center gap-2 mb-3",children:[a.jsx("input",{className:"flex-1 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm focus:ring-2 focus:ring-primary-500 focus:border-primary-500",placeholder:"New style name...",value:g,onChange:j=>L(j.target.value),autoFocus:!0}),a.jsx(F,{type:"submit",size:"sm",isLoading:Q.isPending,disabled:!g.trim(),children:"Add"}),a.jsx(F,{type:"button",size:"sm",variant:"ghost",onClick:()=>{T(!1),L("")},children:"Cancel"})]}),Q.isError&&a.jsx("p",{className:"text-red-500 text-xs mb-2",children:Q.error?.response?.data?.detail??"Failed to create style."}),O?a.jsxs("div",{className:"flex items-center gap-2 py-3 text-sm text-gray-400",children:[a.jsx(z,{size:"sm"})," Loading styles..."]}):!w||w.length===0?a.jsx("p",{className:"text-sm text-gray-400 italic py-2",children:t?'No styles yet. Click "Add Style" to create one.':"No styles in this category."}):a.jsx("div",{className:"space-y-1",children:w.map(j=>a.jsxs("div",{className:"flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer group transition-colors",onClick:()=>r({type:"style",id:j.id,categoryId:e}),children:[a.jsx(Be,{className:"h-3.5 w-3.5 text-indigo-400 flex-shrink-0"}),a.jsx("span",{className:"flex-1 text-sm text-gray-700 dark:text-gray-300 truncate",children:j.name}),!j.is_active&&a.jsx(G,{variant:"default",className:"text-[10px] px-1.5 py-0",children:"Off"}),a.jsxs("span",{className:"text-[10px] text-gray-400",children:[j.type_count,"t · ",j.part_count,"p"]}),t&&a.jsx("button",{className:"p-2 rounded text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors shrink-0",onClick:K=>{K.stopPropagation(),confirm(`Delete style "${j.name}"?`)&&M.mutate(j.id)},title:"Delete style",children:a.jsx(pe,{className:"h-3.5 w-3.5"})}),a.jsx(ye,{className:"h-3.5 w-3.5 text-gray-400 dark:text-gray-500 flex-shrink-0"})]},j.id))})]})]})]})}function rE({styleId:e,categoryId:t,canEdit:s,onDelete:r,onSelectChild:n}){const i=re(),{data:o}=B({queryKey:["categories"],queryFn:()=>Ba()}),[c,d]=b.useState(null),[l,u]=b.useState(""),[E,_]=b.useState(""),[m,y]=b.useState(""),[f,v]=b.useState(!1),[h,T]=b.useState(e),[g,L]=b.useState(!1),[w,O]=b.useState(""),C=t??void 0,W=B({queryKey:["styles",C],queryFn:()=>Ft(C),enabled:!!C,select:D=>D.find(se=>se.id===e)??null}),Q=B({queryKey:["style-lookup-fallback",e],queryFn:async()=>{if(!o)return null;for(const D of o){const ie=(await Ft(D.id)).find($=>$.id===e);if(ie)return ie}return null},enabled:!C&&!!o&&o.length>0}),M=W.data??Q.data??null;M&&(!f||e!==h)&&(d(M),u(M.name),_(M.description??""),y(M.image_url??""),v(!0),T(e));const{data:te,isLoading:S}=B({queryKey:["types",e],queryFn:()=>Kr(e),enabled:!!c}),j=P({mutationFn:D=>ar(e,D),onSuccess:()=>{i.invalidateQueries({queryKey:["styles"]}),i.invalidateQueries({queryKey:["style-lookup-fallback",e]}),i.invalidateQueries({queryKey:["categories"]}),H.success("Style updated")},onError:()=>H.error("Failed to update style")}),K=P({mutationFn:D=>ar(e,{is_active:D}),onSuccess:()=>{i.invalidateQueries({queryKey:["styles"]}),i.invalidateQueries({queryKey:["style-lookup-fallback",e]}),H.success("Style status updated")},onError:()=>H.error("Failed to update status")}),ae=P({mutationFn:D=>Yr({style_id:e,name:D}),onSuccess:D=>{i.invalidateQueries({queryKey:["types",e]}),i.invalidateQueries({queryKey:["styles"]}),i.invalidateQueries({queryKey:["style-lookup-fallback",e]}),i.invalidateQueries({queryKey:["categories"]}),O(""),L(!1),n({type:"type",id:D.id,styleId:e,categoryId:c?.category_id}),H.success("Type created")},onError:()=>H.error("Failed to create type")}),k=P({mutationFn:Vr,onSuccess:()=>{i.invalidateQueries({queryKey:["types",e]}),i.invalidateQueries({queryKey:["styles"]}),i.invalidateQueries({queryKey:["style-lookup-fallback",e]}),i.invalidateQueries({queryKey:["categories"]}),H.success("Type deleted")},onError:()=>H.error("Failed to delete type")});if(!c)return a.jsx("div",{className:"flex-1 flex items-center justify-center",children:a.jsx(z,{size:"lg"})});const A=D=>{D.preventDefault(),j.mutate({name:l,description:E||void 0,image_url:m||void 0})},Z=D=>{D.preventDefault(),w.trim()&&ae.mutate(w.trim())};return a.jsxs("div",{className:"flex flex-col h-full",children:[a.jsxs("div",{className:"px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80 flex items-center justify-between",children:[a.jsxs("div",{children:[a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx(Be,{className:"h-5 w-5 text-indigo-500"}),a.jsx("h3",{className:"text-lg font-semibold text-gray-900 dark:text-gray-100",children:c.name}),a.jsx(G,{variant:c.is_active?"success":"default",children:c.is_active?"Active":"Inactive"})]}),a.jsxs("p",{className:"text-sm text-gray-500 dark:text-gray-400 mt-0.5",children:["Style in ",c.category_name," · ",c.type_count," types · ",c.part_count," parts"]})]}),s&&a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx("button",{className:"p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors",onClick:()=>K.mutate(!c.is_active),title:c.is_active?"Deactivate":"Activate",children:c.is_active?a.jsx(We,{className:"h-5 w-5 text-green-500"}):a.jsx(Ke,{className:"h-5 w-5 text-gray-400"})}),a.jsx("button",{className:"p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors",onClick:r,title:"Delete",children:a.jsx(pe,{className:"h-4 w-4 text-red-400"})})]})]}),a.jsxs("div",{className:"flex-1 overflow-y-auto",children:[a.jsxs("form",{onSubmit:A,className:"p-6 space-y-4",children:[a.jsx(q,{label:"Name",value:l,onChange:D=>u(D.target.value),disabled:!s,required:!0}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Description"}),a.jsx("textarea",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px] disabled:opacity-50",value:E,onChange:D=>_(D.target.value),disabled:!s})]}),a.jsx(q,{label:"Image URL",value:m,onChange:D=>y(D.target.value),disabled:!s,type:"url"}),j.isSuccess&&a.jsxs("p",{className:"text-green-600 text-sm flex items-center gap-1",children:[a.jsx(Ue,{className:"h-4 w-4"})," Saved"]}),j.isError&&a.jsx("p",{className:"text-red-500 text-sm",children:j.error?.response?.data?.detail??"Failed to save."}),s&&a.jsx("div",{className:"flex justify-end",children:a.jsx(F,{type:"submit",isLoading:j.isPending,children:"Save Changes"})})]}),a.jsxs("div",{className:"border-t border-gray-200 dark:border-gray-700 p-6",children:[a.jsxs("div",{className:"flex items-center justify-between mb-3",children:[a.jsxs("h4",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2",children:[a.jsx(Oe,{className:"h-4 w-4 text-teal-500"}),"Types",te&&a.jsxs("span",{className:"text-xs text-gray-400 font-normal",children:["(",te.length,")"]})]}),s&&a.jsxs("button",{className:"flex items-center gap-1 text-xs text-primary-600 hover:text-primary-700 dark:text-primary-400 font-medium",onClick:()=>L(!g),children:[a.jsx(oe,{className:"h-3.5 w-3.5"}),"Add Type"]})]}),g&&a.jsxs("form",{onSubmit:Z,className:"flex items-center gap-2 mb-3",children:[a.jsx("input",{className:"flex-1 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm focus:ring-2 focus:ring-primary-500 focus:border-primary-500",placeholder:"New type name...",value:w,onChange:D=>O(D.target.value),autoFocus:!0}),a.jsx(F,{type:"submit",size:"sm",isLoading:ae.isPending,disabled:!w.trim(),children:"Add"}),a.jsx(F,{type:"button",size:"sm",variant:"ghost",onClick:()=>{L(!1),O("")},children:"Cancel"})]}),ae.isError&&a.jsx("p",{className:"text-red-500 text-xs mb-2",children:ae.error?.response?.data?.detail??"Failed to create type."}),S?a.jsxs("div",{className:"flex items-center gap-2 py-3 text-sm text-gray-400",children:[a.jsx(z,{size:"sm"})," Loading types..."]}):!te||te.length===0?a.jsx("p",{className:"text-sm text-gray-400 italic py-2",children:s?'No types yet. Click "Add Type" to create one.':"No types in this style."}):a.jsx("div",{className:"space-y-1",children:te.map(D=>a.jsxs("div",{className:"flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer group transition-colors",onClick:()=>n({type:"type",id:D.id,styleId:e,categoryId:c.category_id}),children:[a.jsx(Oe,{className:"h-3.5 w-3.5 text-teal-400 flex-shrink-0"}),a.jsx("span",{className:"flex-1 text-sm text-gray-700 dark:text-gray-300 truncate",children:D.name}),!D.is_active&&a.jsx(G,{variant:"default",className:"text-[10px] px-1.5 py-0",children:"Off"}),a.jsxs("span",{className:"text-[10px] text-gray-400",children:[D.color_count,"c · ",D.part_count,"p"]}),s&&a.jsx("button",{className:"p-2 rounded text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors shrink-0",onClick:se=>{se.stopPropagation(),confirm(`Delete type "${D.name}"?`)&&k.mutate(D.id)},title:"Delete type",children:a.jsx(pe,{className:"h-3.5 w-3.5"})}),a.jsx(ye,{className:"h-3.5 w-3.5 text-gray-400 dark:text-gray-500 flex-shrink-0"})]},D.id))})]})]})]})}function nE({typeId:e,canEdit:t,onDelete:s}){const r=re(),[n,i]=b.useState(""),[o,c]=b.useState(""),[d,l]=b.useState(""),{data:u}=B({queryKey:["type-detail",e],queryFn:()=>Ju(e),staleTime:3e4});b.useEffect(()=>{u&&(i(u.name),c(u.description??""),l(u.image_url??""))},[u,e]);const{data:E,isLoading:_}=B({queryKey:["type-brands",e],queryFn:()=>Jr(e)}),{data:m}=B({queryKey:["brands"],queryFn:()=>Wa()}),y=P({mutationFn:O=>e_(e,O),onSuccess:()=>{r.invalidateQueries({queryKey:["type-brands",e]}),r.invalidateQueries({queryKey:["types"]}),r.invalidateQueries({queryKey:["type-detail",e]}),H.success("Brand linked")},onError:()=>H.error("Failed to link brand")}),f=P({mutationFn:O=>t_(e,O),onSuccess:()=>{r.invalidateQueries({queryKey:["type-brands",e]}),r.invalidateQueries({queryKey:["types"]}),r.invalidateQueries({queryKey:["type-detail",e]}),H.success("Brand unlinked")},onError:()=>H.error("Failed to unlink brand")}),v=P({mutationFn:O=>sr(e,O),onSuccess:()=>{r.invalidateQueries({queryKey:["types"]}),r.invalidateQueries({queryKey:["type-detail",e]}),H.success("Type updated")},onError:()=>H.error("Failed to update type")}),h=P({mutationFn:O=>sr(e,{is_active:O}),onSuccess:()=>{r.invalidateQueries({queryKey:["types"]}),r.invalidateQueries({queryKey:["type-detail",e]}),H.success("Type status updated")},onError:()=>H.error("Failed to update status")}),T=b.useMemo(()=>{const O=new Set;return(E??[]).forEach(C=>O.add(C.brand_id)),O},[E]),g=T.has(null);if(!u)return a.jsx("div",{className:"flex-1 flex items-center justify-center",children:a.jsx(z,{size:"lg"})});const L=O=>{O.preventDefault(),v.mutate({name:n,description:o||void 0,image_url:d||void 0})},w=(O,C)=>{C?f.mutate(O):y.mutate(O)};return a.jsxs("div",{className:"flex flex-col h-full",children:[a.jsxs("div",{className:"px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80 flex items-center justify-between",children:[a.jsxs("div",{children:[a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx(Be,{className:"h-5 w-5 text-teal-500"}),a.jsx("h3",{className:"text-lg font-semibold text-gray-900 dark:text-gray-100",children:u.name}),a.jsx(G,{variant:u.is_active?"success":"default",children:u.is_active?"Active":"Inactive"})]}),a.jsxs("p",{className:"text-sm text-gray-500 dark:text-gray-400 mt-0.5",children:["Type in ",u.category_name," → ",u.style_name," · ",u.color_count," colors · ",u.part_count," parts"]})]}),t&&a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx("button",{className:"p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors",onClick:()=>h.mutate(!u.is_active),children:u.is_active?a.jsx(We,{className:"h-5 w-5 text-green-500"}):a.jsx(Ke,{className:"h-5 w-5 text-gray-400"})}),a.jsx("button",{className:"p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors",onClick:s,children:a.jsx(pe,{className:"h-4 w-4 text-red-400"})})]})]}),a.jsxs("div",{className:"flex-1 overflow-y-auto",children:[a.jsxs("form",{onSubmit:L,className:"p-6 space-y-4",children:[a.jsx(q,{label:"Name",value:n,onChange:O=>i(O.target.value),disabled:!t,required:!0}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Description"}),a.jsx("textarea",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px] disabled:opacity-50",value:o,onChange:O=>c(O.target.value),disabled:!t})]}),a.jsx(q,{label:"Image URL",value:d,onChange:O=>l(O.target.value),disabled:!t,type:"url"}),v.isSuccess&&a.jsxs("p",{className:"text-green-600 text-sm flex items-center gap-1",children:[a.jsx(Ue,{className:"h-4 w-4"})," Saved"]}),v.isError&&a.jsx("p",{className:"text-red-500 text-sm",children:v.error?.response?.data?.detail??"Failed to save."}),t&&a.jsx("div",{className:"flex justify-end",children:a.jsx(F,{type:"submit",isLoading:v.isPending,children:"Save Changes"})})]}),a.jsxs("div",{className:"border-t border-gray-200 dark:border-gray-700 p-6",children:[a.jsxs("h4",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2 mb-3",children:[a.jsx(De,{className:"h-4 w-4 text-amber-500"}),"Brands & General"]}),a.jsx("p",{className:"text-xs text-gray-500 dark:text-gray-400 mb-3",children:'Enable brands that manufacture this type of part. "General" is for unbranded commodity items. Click a brand in the tree to select colors and create parts.'}),_?a.jsxs("div",{className:"flex items-center gap-2 py-2 text-sm text-gray-500",children:[a.jsx(z,{size:"sm"})," Loading brands..."]}):a.jsxs("div",{className:"space-y-1.5",children:[a.jsxs("label",{className:`flex items-center gap-3 px-3 py-2 rounded-lg border transition-colors cursor-pointer ${g?"border-primary-300 bg-primary-50 dark:border-primary-700 dark:bg-primary-900/20":"border-gray-200 dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-700/50"}`,children:[a.jsx("input",{type:"checkbox",checked:g,onChange:()=>w(null,g),disabled:!t||y.isPending||f.isPending,className:"w-4 h-4 rounded border-gray-300 text-primary-600 focus:ring-primary-500"}),a.jsx(Oe,{className:"h-4 w-4 text-gray-500 flex-shrink-0"}),a.jsx("span",{className:"text-sm font-medium flex-1",children:"General"}),a.jsx("span",{className:"text-xs text-gray-400",children:"Unbranded / commodity"})]}),(m??[]).filter(O=>O.is_active).map(O=>{const C=T.has(O.id);return a.jsxs("label",{className:`flex items-center gap-3 px-3 py-2 rounded-lg border transition-colors cursor-pointer ${C?"border-amber-300 bg-amber-50 dark:border-amber-700 dark:bg-amber-900/20":"border-gray-200 dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-700/50"}`,children:[a.jsx("input",{type:"checkbox",checked:C,onChange:()=>w(O.id,C),disabled:!t||y.isPending||f.isPending,className:"w-4 h-4 rounded border-gray-300 text-amber-600 focus:ring-amber-500"}),a.jsx(De,{className:"h-4 w-4 text-amber-500 flex-shrink-0"}),a.jsx("span",{className:"text-sm flex-1",children:O.name}),C&&a.jsxs("span",{className:"text-xs text-gray-400",children:[E?.find(W=>W.brand_id===O.id)?.part_count??0," parts"]})]},O.id)}),f.isError&&a.jsx("p",{className:"text-red-500 text-sm mt-2",children:f.error?.response?.data?.detail??"Cannot unlink — parts may exist under this brand."})]})]})]})]})}function Er(e){return e.name==="[NULL]"}function iE({isOpen:e,onClose:t,canEdit:s}){const r=re(),[n,i]=b.useState(null),[o,c]=b.useState(!1),[d,l]=b.useState(""),[u,E]=b.useState("#FFFFFF"),[_,m]=b.useState(""),[y,f]=b.useState("#4F46E5"),{data:v=[],isLoading:h}=B({queryKey:["colors"],queryFn:()=>$a(),enabled:e}),T=[...v].sort((S,j)=>S.sort_order!==j.sort_order?S.sort_order-j.sort_order:S.name.localeCompare(j.name)),g=v.find(S=>S.id===n)??null,L=g?Er(g):!1;b.useEffect(()=>{g&&(l(g.name),E(g.hex_code??"#FFFFFF"))},[g?.id,g?.name,g?.hex_code]),b.useEffect(()=>{e||(i(null),c(!1),m(""),f("#4F46E5"))},[e]);const w=P({mutationFn:S=>rr(n,S),onSuccess:()=>r.invalidateQueries({queryKey:["colors"]})}),O=P({mutationFn:({id:S,is_active:j})=>rr(S,{is_active:j}),onSuccess:()=>r.invalidateQueries({queryKey:["colors"]})}),C=P({mutationFn:S=>zr(S),onSuccess:S=>{r.invalidateQueries({queryKey:["colors"]}),c(!1),m(""),f("#4F46E5"),S?.id&&i(S.id)}}),W=P({mutationFn:s_,onSuccess:()=>{r.invalidateQueries({queryKey:["colors"]}),i(null)}}),Q=S=>{S.preventDefault(),!(!n||L)&&w.mutate({name:d,hex_code:u||void 0})},M=S=>{S.preventDefault(),_.trim()&&C.mutate({name:_.trim(),hex_code:y||void 0})},te=()=>{!n||L||window.confirm(`Delete color "${g?.name}"? This cannot be undone.`)&&W.mutate(n)};return a.jsx(Ne,{isOpen:e,onClose:t,title:"Global Colors",size:"lg",children:a.jsxs("div",{className:"flex flex-col sm:flex-row gap-4 min-h-[340px]",children:[a.jsxs("div",{className:"sm:w-56 flex-shrink-0 flex flex-col",children:[s&&a.jsxs("button",{className:"flex items-center gap-2 w-full px-3 py-2 mb-2 rounded-lg border border-dashed border-gray-300 dark:border-gray-600 text-sm text-primary-600 dark:text-primary-400 hover:bg-primary-50 dark:hover:bg-primary-900/20 transition-colors min-h-[44px]",onClick:()=>{c(!0),i(null)},children:[a.jsx(oe,{className:"h-4 w-4"}),"Add Color"]}),a.jsx("div",{className:"flex-1 overflow-y-auto space-y-0.5 max-h-[50vh]",children:h?a.jsx("div",{className:"flex justify-center py-8",children:a.jsx(z,{size:"md"})}):T.length===0?a.jsx("p",{className:"text-sm text-gray-400 italic text-center py-4",children:"No colors defined"}):T.map(S=>{const j=n===S.id&&!o,K=Er(S);return a.jsxs("button",{className:`flex items-center gap-2 w-full px-2.5 py-2 rounded-lg text-left transition-colors min-h-[44px] ${j?"bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300":"hover:bg-gray-100 dark:hover:bg-gray-700/50"}`,onClick:()=>{i(S.id),c(!1)},children:[K?a.jsx("span",{className:"inline-flex items-center justify-center w-5 h-5 rounded-full bg-black border border-gray-500 flex-shrink-0",children:a.jsx("span",{className:"text-white text-[7px] font-bold leading-none",children:"NULL"})}):a.jsx("span",{className:"inline-block w-5 h-5 rounded-full border border-gray-300 dark:border-gray-500 flex-shrink-0",style:{backgroundColor:S.hex_code??"#ccc"}}),a.jsx("span",{className:"text-sm truncate flex-1",children:S.name}),!S.is_active&&a.jsx(G,{variant:"default",className:"text-[10px] px-1.5 py-0",children:"Off"}),a.jsxs("span",{className:"text-[10px] text-gray-400 flex-shrink-0",children:[S.part_count,"p"]})]},S.id)})})]}),a.jsx("div",{className:"flex-1 min-w-0 border-l border-gray-200 dark:border-gray-700 pl-4",children:o?a.jsxs("form",{onSubmit:M,className:"space-y-4",children:[a.jsxs("h4",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2",children:[a.jsx(oe,{className:"h-4 w-4"}),"New Color"]}),a.jsx(q,{label:"Color Name",value:_,onChange:S=>m(S.target.value),placeholder:"e.g. Navy Blue",required:!0,maxLength:50}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Hex Color"}),a.jsxs("div",{className:"flex items-center gap-3",children:[a.jsx("input",{type:"color",value:y,onChange:S=>f(S.target.value),className:"w-10 h-10 rounded-lg border border-gray-300 dark:border-gray-600 cursor-pointer"}),a.jsx(q,{value:y,onChange:S=>f(S.target.value),className:"font-mono",placeholder:"#000000"})]})]}),C.isError&&a.jsx("p",{className:"text-red-500 text-sm",children:C.error?.response?.data?.detail??"Failed to create color."}),a.jsxs("div",{className:"flex gap-2 pt-2",children:[a.jsx(F,{type:"submit",isLoading:C.isPending,children:"Create Color"}),a.jsx(F,{type:"button",variant:"ghost",onClick:()=>{c(!1),m(""),f("#4F46E5")},children:"Cancel"})]})]}):g?a.jsxs("div",{className:"space-y-4",children:[a.jsxs("div",{className:"flex items-center justify-between",children:[a.jsxs("div",{className:"flex items-center gap-2",children:[L?a.jsx("span",{className:"inline-flex items-center justify-center w-6 h-6 rounded-full bg-black border-2 border-gray-500",children:a.jsx("span",{className:"text-white text-[8px] font-bold leading-none",children:"NULL"})}):a.jsx("span",{className:"inline-block w-6 h-6 rounded-full border-2 border-gray-300 dark:border-gray-500",style:{backgroundColor:g.hex_code??"#ccc"}}),a.jsx("h4",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300",children:g.name}),a.jsx(G,{variant:g.is_active?"success":"default",children:g.is_active?"Active":"Inactive"})]}),s&&!L&&a.jsxs("div",{className:"flex items-center gap-1",children:[a.jsx("button",{className:"p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center",onClick:()=>O.mutate({id:g.id,is_active:!g.is_active}),title:g.is_active?"Deactivate":"Activate",children:g.is_active?a.jsx(We,{className:"h-5 w-5 text-green-500"}):a.jsx(Ke,{className:"h-5 w-5 text-gray-400"})}),a.jsx("button",{className:"p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center",onClick:te,title:"Delete color",children:a.jsx(pe,{className:"h-4 w-4 text-red-400"})})]})]}),a.jsxs("p",{className:"text-xs text-gray-500 dark:text-gray-400",children:[g.part_count," part",g.part_count!==1?"s":""," using this color",L&&" · System color (read-only)"]}),L?a.jsxs("div",{className:"rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-4 text-sm text-gray-500 dark:text-gray-400",children:["The ",a.jsx("span",{className:"font-mono font-medium",children:"[NULL]"})," color is a system default for parts where color is unknown or unimportant. It cannot be edited or deleted."]}):a.jsxs("form",{onSubmit:Q,className:"space-y-4",children:[a.jsx(q,{label:"Name",value:d,onChange:S=>l(S.target.value),disabled:!s,required:!0,maxLength:50}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Hex Color Code"}),a.jsxs("div",{className:"flex items-center gap-3",children:[a.jsx("input",{type:"color",value:u,onChange:S=>E(S.target.value),disabled:!s,className:"w-10 h-10 rounded-lg border border-gray-300 dark:border-gray-600 cursor-pointer disabled:opacity-50"}),a.jsx(q,{value:u,onChange:S=>E(S.target.value),disabled:!s,className:"font-mono"})]})]}),w.isSuccess&&a.jsxs("p",{className:"text-green-600 text-sm flex items-center gap-1",children:[a.jsx(Ue,{className:"h-4 w-4"})," Saved"]}),w.isError&&a.jsx("p",{className:"text-red-500 text-sm",children:w.error?.response?.data?.detail??"Failed to save."}),s&&a.jsx("div",{className:"pt-2",children:a.jsx(F,{type:"submit",isLoading:w.isPending,children:"Save Changes"})})]})]}):a.jsxs("div",{className:"flex flex-col items-center justify-center h-full text-center py-8",children:[a.jsx(wr,{className:"h-10 w-10 text-gray-300 dark:text-gray-600 mb-3"}),a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400",children:"Select a color to view or edit"}),a.jsxs("p",{className:"text-xs text-gray-400 dark:text-gray-500 mt-1",children:[T.length," color",T.length!==1?"s":""," defined"]})]})})]})})}function oE({typeId:e,brandId:t,brandName:s,categoryId:r,styleId:n,canEdit:i,onSelectPart:o}){const c=re(),d=t===null,[l,u]=b.useState(!1),{data:E}=B({queryKey:["colors"],queryFn:()=>$a()}),{data:_,isLoading:m}=B({queryKey:["type-colors",e],queryFn:()=>Qu(e)}),{data:y,isLoading:f}=B({queryKey:["type-brand-parts",e,t??0],queryFn:()=>Qr(e,t)}),v=P({mutationFn:C=>zu(e,C),onSuccess:()=>{c.invalidateQueries({queryKey:["type-colors",e]}),c.invalidateQueries({queryKey:["types"]}),c.invalidateQueries({queryKey:["type-lookup",e]})}}),h=P({mutationFn:C=>Zu(e,C),onSuccess:()=>{c.invalidateQueries({queryKey:["type-colors",e]}),c.invalidateQueries({queryKey:["types"]}),c.invalidateQueries({queryKey:["type-lookup",e]})}}),T=P({mutationFn:C=>a_(e,t,C),onSuccess:()=>{c.invalidateQueries({queryKey:["type-brand-parts",e,t??0]}),c.invalidateQueries({queryKey:["type-brands",e]}),c.invalidateQueries({queryKey:["types"]})}}),g=b.useMemo(()=>new Set((_??[]).map(C=>C.color_id)),[_]),L=(E??[]).filter(C=>!g.has(C.id)&&C.is_active),w=b.useMemo(()=>{const C=new Map;return(y??[]).forEach(W=>{W.color_id!=null&&C.set(W.color_id,W)}),C},[y]),O=m||f;return a.jsxs("div",{className:"flex flex-col h-full",children:[a.jsxs("div",{className:"px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80",children:[a.jsxs("div",{className:"flex items-center justify-between",children:[a.jsxs("div",{className:"flex items-center gap-2",children:[d?a.jsx(Oe,{className:"h-5 w-5 text-gray-500"}):a.jsx(De,{className:"h-5 w-5 text-amber-500"}),a.jsx("h3",{className:"text-lg font-semibold text-gray-900 dark:text-gray-100",children:s}),a.jsx(G,{variant:d?"default":"warning",children:d?"General":"Branded"})]}),a.jsxs("button",{className:"inline-flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors min-h-[44px]",onClick:()=>u(!0),title:"Manage global color palette",children:[a.jsx(wr,{className:"h-4 w-4"}),"Global Colors"]})]}),a.jsxs("p",{className:"text-sm text-gray-500 dark:text-gray-400 mt-0.5",children:[d?"Unbranded commodity parts":`Parts manufactured by ${s}`," ","· ",y?.length??0," parts created"]}),!d&&a.jsxs("p",{className:"text-xs text-amber-600 dark:text-amber-400 mt-1 flex items-center gap-1",children:[a.jsx(Re,{className:"h-3 w-3"}),"Branded parts need a Manufacturer Part Number (MPN)"]})]}),a.jsx("div",{className:"flex-1 overflow-y-auto",children:O?a.jsx("div",{className:"flex items-center justify-center py-8",children:a.jsx(z,{size:"lg"})}):a.jsxs(a.Fragment,{children:[a.jsxs("div",{className:"p-6 border-b border-gray-200 dark:border-gray-700",children:[a.jsxs("h4",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2 mb-3",children:[a.jsx(kd,{className:"h-4 w-4 text-primary-500"}),"Available Colors (",_?.length??0,")"]}),a.jsx("p",{className:"text-xs text-gray-500 dark:text-gray-400 mb-3",children:"Select which colors are available for this type. Each linked color becomes a device you can create below."}),a.jsxs("div",{className:"flex flex-wrap gap-2 mb-3",children:[(_??[]).map(C=>a.jsxs("span",{className:"inline-flex items-center gap-1.5 text-sm px-2.5 py-1 rounded-full border border-gray-200 dark:border-gray-600 bg-gray-50 dark:bg-gray-700",children:[C.hex_code&&a.jsx("span",{className:"inline-block w-3 h-3 rounded-full border border-gray-300 dark:border-gray-500",style:{backgroundColor:C.hex_code}}),C.color_name,i&&a.jsx("button",{className:"ml-1 p-1 rounded-full text-red-400 hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors",onClick:()=>h.mutate(C.color_id),title:`Remove ${C.color_name}`,children:a.jsx(He,{className:"h-3.5 w-3.5"})})]},C.id)),(_??[]).length===0&&a.jsx("p",{className:"text-sm text-gray-400 italic",children:"No colors linked yet — add colors below to start creating parts."})]}),i&&L.length>0&&a.jsxs("div",{children:[a.jsx("p",{className:"text-xs text-gray-500 dark:text-gray-400 mb-2",children:"Click to add a color:"}),a.jsx("div",{className:"flex flex-wrap gap-1.5",children:L.map(C=>a.jsxs("button",{className:"inline-flex items-center gap-1 text-xs px-2 py-1 rounded-full border border-dashed border-gray-300 dark:border-gray-600 hover:border-primary-400 hover:bg-primary-50 dark:hover:bg-primary-900/20 transition-colors",onClick:()=>v.mutate([C.id]),title:`Add ${C.name}`,children:[C.hex_code&&a.jsx("span",{className:"inline-block w-2.5 h-2.5 rounded-full border border-gray-300 dark:border-gray-500",style:{backgroundColor:C.hex_code}}),a.jsx(oe,{className:"h-2.5 w-2.5"}),C.name]},C.id))})]}),(v.isError||h.isError)&&a.jsx("p",{className:"text-red-500 text-xs mt-2",children:"Failed to update colors. A color may have parts linked to it."})]}),a.jsxs("div",{className:"p-6",children:[a.jsxs("h4",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2 mb-3",children:[a.jsx(Oe,{className:"h-4 w-4 text-teal-500"}),"Devices (",y?.length??0,")"]}),!_||_.length===0?a.jsx("p",{className:"text-sm text-gray-400 italic py-2",children:"Add colors above first, then create devices for each color."}):a.jsxs(a.Fragment,{children:[a.jsx("p",{className:"text-xs text-gray-500 dark:text-gray-400 mb-3",children:"Click a color to create a part, or click an existing part to edit it."}),a.jsx("div",{className:"grid grid-cols-1 sm:grid-cols-2 gap-2",children:_.map(C=>{const W=w.get(C.color_id),Q=!!W;return a.jsxs("button",{className:`flex items-center gap-3 px-3 py-2.5 rounded-lg border text-left transition-all ${Q?"border-green-200 bg-green-50 dark:border-green-800 dark:bg-green-900/20 hover:bg-green-100 dark:hover:bg-green-900/30":"border-dashed border-gray-300 dark:border-gray-600 hover:border-primary-400 hover:bg-primary-50 dark:hover:bg-primary-900/20"}`,onClick:()=>{Q?o({type:"part",id:W.id,partId:W.id,typeId:e,styleId:n,categoryId:r,brandId:t,colorId:C.color_id}):i&&T.mutate(C.color_id)},disabled:!Q&&!i,children:[a.jsx("span",{className:"w-6 h-6 rounded-full border-2 flex-shrink-0",style:{backgroundColor:C.hex_code??"#ccc",borderColor:Q?"#22c55e":"#d1d5db"},children:Q&&a.jsx(Ue,{className:"h-4 w-4 text-white m-0.5",style:{filter:"drop-shadow(0 0 1px rgba(0,0,0,0.5))"}})}),a.jsxs("div",{className:"flex-1 min-w-0",children:[a.jsx("div",{className:"text-sm font-medium truncate",children:C.color_name??"Unknown"}),Q?a.jsx("div",{className:"text-xs text-gray-500 dark:text-gray-400 truncate",children:W.manufacturer_part_number?`MPN: ${W.manufacturer_part_number}`:d?"Created":"MPN needed"}):a.jsx("div",{className:"text-xs text-gray-500 dark:text-gray-400",children:"Click to create"})]}),Q?W.is_deprecated?a.jsx(G,{variant:"danger",className:"text-[10px]",children:"DEP"}):!d&&!W.manufacturer_part_number?a.jsx(Re,{className:"h-4 w-4 text-amber-400 flex-shrink-0"}):null:a.jsx(oe,{className:"h-4 w-4 text-gray-400 flex-shrink-0"})]},C.color_id)})}),T.isError&&a.jsx("p",{className:"text-red-500 text-sm mt-3",children:T.error?.response?.data?.detail??"Failed to create part."})]})]})]})}),a.jsx(iE,{isOpen:l,onClose:()=>u(!1),canEdit:i})]})}function cE({partId:e,canEdit:t,onDeleted:s}){const r=re(),{user:n}=Pe(),i=n?.permissions.includes("show_dollar_values")??!1,{data:o,isLoading:c}=B({queryKey:["part-detail",e],queryFn:()=>r_(e)}),[d,l]=b.useState(""),[u,E]=b.useState(""),[_,m]=b.useState(""),[y,f]=b.useState(""),[v,h]=b.useState(""),[T,g]=b.useState(""),[L,w]=b.useState(""),[O,C]=b.useState(""),[W,Q]=b.useState(""),[M,te]=b.useState(""),[S,j]=b.useState(""),[K,ae]=b.useState(!1);b.useEffect(()=>{o&&(l(o.name),E(o.code??""),m(o.manufacturer_part_number??""),f(o.company_cost_price!=null?String(o.company_cost_price):""),h(o.company_markup_percent!=null?String(o.company_markup_percent):""),g(o.notes??""),w(o.image_url??""),C(o.unit_of_measure??"each"),Q(String(o.min_stock_level??0)),te(String(o.max_stock_level??0)),j(String(o.target_stock_level??0)))},[o]);const k=P({mutationFn:$=>ba(e,$),onSuccess:()=>{r.invalidateQueries({queryKey:["part-detail",e]}),r.invalidateQueries({queryKey:["type-brand-parts"]}),r.invalidateQueries({queryKey:["types"]})}}),A=P({mutationFn:()=>Zr(e),onSuccess:()=>{r.invalidateQueries({queryKey:["type-brand-parts"]}),r.invalidateQueries({queryKey:["type-brands"]}),r.invalidateQueries({queryKey:["types"]}),ae(!1),s()}}),Z=P({mutationFn:$=>ba(e,{is_deprecated:$}),onSuccess:()=>{r.invalidateQueries({queryKey:["part-detail",e]}),r.invalidateQueries({queryKey:["type-brand-parts"]})}});if(c||!o)return a.jsx("div",{className:"flex-1 flex items-center justify-center",children:a.jsx(z,{size:"lg"})});const D=o.part_type==="general",se=y&&v?(parseFloat(y)*(1+parseFloat(v)/100)).toFixed(2):o.company_sell_price?.toFixed(2)??"—",ie=$=>{$.preventDefault();const V={name:d,code:u||void 0,manufacturer_part_number:_||void 0,notes:T||void 0,image_url:L||void 0,unit_of_measure:O||void 0,min_stock_level:W?parseInt(W,10):0,max_stock_level:M?parseInt(M,10):0,target_stock_level:S?parseInt(S,10):0};i&&(V.company_cost_price=y?parseFloat(y):void 0,V.company_markup_percent=v?parseFloat(v):void 0),k.mutate(V)};return a.jsxs("div",{className:"flex flex-col h-full",children:[a.jsxs("div",{className:"px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80 flex items-center justify-between",children:[a.jsxs("div",{children:[a.jsxs("div",{className:"flex items-center gap-2",children:[o.color_hex&&a.jsx("span",{className:"inline-block w-5 h-5 rounded-full border-2 border-gray-300 dark:border-gray-500",style:{backgroundColor:o.color_hex}}),a.jsx("h3",{className:"text-lg font-semibold text-gray-900 dark:text-gray-100 truncate",children:o.name}),a.jsx(G,{variant:D?"default":"warning",children:D?"General":"Branded"}),o.is_deprecated&&a.jsx(G,{variant:"danger",children:"Deprecated"})]}),a.jsxs("p",{className:"text-sm text-gray-500 dark:text-gray-400 mt-0.5",children:[o.category_name," → ",o.style_name," → ",o.type_name,o.brand_name&&` &rarr; ${o.brand_name}`,o.color_name&&` &middot; ${o.color_name}`]})]}),t&&a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx("button",{className:"p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors",onClick:()=>Z.mutate(!o.is_deprecated),title:o.is_deprecated?"Restore":"Deprecate",children:o.is_deprecated?a.jsx(Ke,{className:"h-5 w-5 text-gray-400"}):a.jsx(We,{className:"h-5 w-5 text-green-500"})}),a.jsx("button",{className:"p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors",onClick:()=>ae(!0),title:"Delete Part",children:a.jsx(pe,{className:"h-4 w-4 text-red-400"})})]})]}),a.jsxs("form",{onSubmit:ie,className:"flex-1 overflow-y-auto p-6 space-y-5",children:[a.jsxs("div",{className:"space-y-3",children:[a.jsx("h4",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400",children:"Identity"}),a.jsx(q,{label:"Part Name",value:d,onChange:$=>l($.target.value),disabled:!t,required:!0}),a.jsx(q,{label:"Code / SKU",value:u,onChange:$=>E($.target.value),disabled:!t,placeholder:"Optional internal code"}),!D&&a.jsxs("div",{children:[a.jsx(q,{label:"Manufacturer Part Number (MPN)",value:_,onChange:$=>m($.target.value),disabled:!t,placeholder:"e.g. GFNT1-0GW"}),!_&&a.jsxs("p",{className:"text-xs text-amber-500 mt-1 flex items-center gap-1",children:[a.jsx(Re,{className:"h-3 w-3"}),"This branded part needs an MPN"]})]})]}),i&&a.jsxs("div",{className:"space-y-3 border-t border-gray-200 dark:border-gray-700 pt-4",children:[a.jsxs("h4",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1",children:[a.jsx(Ct,{className:"h-3.5 w-3.5"}),"Pricing"]}),a.jsxs("div",{className:"grid grid-cols-3 gap-3",children:[a.jsx(q,{label:"Cost",value:y,onChange:$=>f($.target.value),disabled:!t,type:"number",step:"0.01",min:"0",placeholder:"0.00"}),a.jsx(q,{label:"Markup %",value:v,onChange:$=>h($.target.value),disabled:!t,type:"number",step:"0.1",min:"0",placeholder:"0"}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Sell"}),a.jsxs("div",{className:"px-3 py-2 rounded-lg bg-gray-100 dark:bg-gray-700 text-sm font-medium text-gray-700 dark:text-gray-300",children:["$",se]})]})]})]}),a.jsx("div",{className:"space-y-3 border-t border-gray-200 dark:border-gray-700 pt-4",children:a.jsx(q,{label:"Unit of Measure",value:O,onChange:$=>C($.target.value),disabled:!t,placeholder:"each"})}),a.jsxs("div",{className:"space-y-3 border-t border-gray-200 dark:border-gray-700 pt-4",children:[a.jsxs("h4",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1",children:[a.jsx(Dd,{className:"h-3.5 w-3.5"}),"Stock Levels"]}),a.jsxs("div",{className:"grid grid-cols-2 gap-3",children:[a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Warehouse"}),a.jsx("div",{className:"px-3 py-2 rounded-lg bg-gray-100 dark:bg-gray-700 text-sm font-medium text-gray-700 dark:text-gray-300",children:o.warehouse_stock??0})]}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Total (all locations)"}),a.jsx("div",{className:"px-3 py-2 rounded-lg bg-gray-100 dark:bg-gray-700 text-sm font-medium text-gray-700 dark:text-gray-300",children:o.total_stock??0})]})]}),(o.pulled_stock>0||o.truck_stock>0||o.job_stock>0)&&a.jsxs("div",{className:"flex flex-wrap gap-2",children:[o.pulled_stock>0&&a.jsxs(G,{variant:"warning",children:[o.pulled_stock," pulled"]}),o.truck_stock>0&&a.jsxs(G,{variant:"info",children:[o.truck_stock," on trucks"]}),o.job_stock>0&&a.jsxs(G,{variant:"default",children:[o.job_stock," on jobs"]})]})]}),a.jsxs("div",{className:"space-y-3 border-t border-gray-200 dark:border-gray-700 pt-4",children:[a.jsxs("h4",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1",children:[a.jsx(Fd,{className:"h-3.5 w-3.5"}),"Inventory Targets"]}),a.jsxs("div",{className:"grid grid-cols-3 gap-3",children:[a.jsx(q,{label:"Min",value:W,onChange:$=>Q($.target.value),disabled:!t,type:"number",min:"0",placeholder:"0"}),a.jsx(q,{label:"Target",value:S,onChange:$=>j($.target.value),disabled:!t,type:"number",min:"0",placeholder:"0"}),a.jsx(q,{label:"Max",value:M,onChange:$=>te($.target.value),disabled:!t,type:"number",min:"0",placeholder:"0"})]})]}),a.jsxs("div",{className:"space-y-3 border-t border-gray-200 dark:border-gray-700 pt-4",children:[a.jsx("h4",{className:"text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400",children:"Details"}),a.jsx(q,{label:"Image URL",value:L,onChange:$=>w($.target.value),disabled:!t,placeholder:"https://...",type:"url"}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Notes"}),a.jsx("textarea",{className:"w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px] disabled:opacity-50",value:T,onChange:$=>g($.target.value),disabled:!t,placeholder:"Optional notes..."})]})]}),a.jsx(sn,{partId:e,readOnly:!t}),k.isSuccess&&a.jsxs("p",{className:"text-green-600 text-sm flex items-center gap-1",children:[a.jsx(Ue,{className:"h-4 w-4"})," Saved"]}),k.isError&&a.jsx("p",{className:"text-red-500 text-sm",children:k.error?.response?.data?.detail??"Failed to save."}),t&&a.jsx("div",{className:"flex justify-end pt-4 border-t border-gray-200 dark:border-gray-700",children:a.jsx(F,{type:"submit",isLoading:k.isPending,children:"Save Changes"})})]}),K&&a.jsxs(Ne,{isOpen:!0,onClose:()=>ae(!1),title:"Delete Part?",size:"sm",children:[a.jsxs("p",{className:"text-gray-600 dark:text-gray-300 mb-4",children:["Are you sure you want to delete ",a.jsx("strong",{children:o.name}),"? This cannot be undone."]}),A.isError&&a.jsx("p",{className:"text-red-500 text-sm mb-4",children:A.error?.response?.data?.detail??"Failed to delete. Stock may exist for this part."}),a.jsxs("div",{className:"flex justify-end gap-2",children:[a.jsx(F,{variant:"secondary",onClick:()=>ae(!1),children:"Cancel"}),a.jsx(F,{variant:"danger",isLoading:A.isPending,onClick:()=>A.mutate(),children:"Delete Part"})]})]})]})}function uy(){const e=re(),{hasPermission:t}=Pe(),s=t(Fe.EDIT_PARTS_CATALOG),[r,n]=b.useState(null),[i,o]=b.useState(null),[c,d]=b.useState(new Set),[l,u]=b.useState(new Set),[E,_]=b.useState(new Set),[m,y]=b.useState(null),{data:f,isLoading:v}=B({queryKey:["categories"],queryFn:()=>Ba()}),{data:h}=B({queryKey:["colors"],queryFn:()=>$a()}),T=S=>{d(j=>{const K=new Set(j);return K.has(S)?K.delete(S):K.add(S),K})},g=S=>{u(j=>{const K=new Set(j);return K.has(S)?K.delete(S):K.add(S),K})},L=S=>{_(j=>{const K=new Set(j);return K.has(S)?K.delete(S):K.add(S),K})},w=S=>{n(S),S.type==="category"?d(j=>new Set([...j,S.id])):S.type==="style"?(u(j=>new Set([...j,S.id])),S.categoryId&&d(j=>new Set([...j,S.categoryId]))):S.type==="type"?(_(j=>new Set([...j,S.id])),S.styleId&&u(j=>new Set([...j,S.styleId])),S.categoryId&&d(j=>new Set([...j,S.categoryId]))):(S.type==="brand"||S.type==="part")&&(S.typeId&&_(j=>new Set([...j,S.typeId])),S.styleId&&u(j=>new Set([...j,S.styleId])),S.categoryId&&d(j=>new Set([...j,S.categoryId])))},O=P({mutationFn:Vu,onSuccess:()=>{e.invalidateQueries({queryKey:["categories"]}),n(null),y(null),H.success("Category deleted")},onError:()=>H.error("Failed to delete category")}),C=P({mutationFn:Wr,onSuccess:()=>{e.invalidateQueries({queryKey:["styles"]}),e.invalidateQueries({queryKey:["categories"]}),n(null),y(null),H.success("Style deleted")},onError:()=>H.error("Failed to delete style")}),W=P({mutationFn:Vr,onSuccess:()=>{e.invalidateQueries({queryKey:["types"]}),e.invalidateQueries({queryKey:["styles"]}),n(null),y(null),H.success("Type deleted")},onError:()=>H.error("Failed to delete type")}),Q=()=>{if(m)switch(m.type){case"category":O.mutate(m.id);break;case"style":C.mutate(m.id);break;case"type":W.mutate(m.id);break}},M=O.isPending||C.isPending||W.isPending,te=()=>{if(i)return a.jsx(aE,{target:i,allColors:h??[],onCancel:()=>o(null),onCreated:(S,j,K)=>{o(null),n({type:S,id:j}),S==="style"&&K&&T(K),S==="type"&&K&&g(K)}});if(!r)return a.jsx("div",{className:"flex-1 flex items-center justify-center p-8",children:a.jsx(le,{icon:a.jsx(Nt,{className:"h-10 w-10"}),title:"Select a node to edit",description:"Click any item in the tree to view or edit its details. Use the + buttons to create new items."})});switch(r.type){case"category":return a.jsx(sE,{categoryId:r.id,canEdit:s,onDelete:()=>y(r),onSelectChild:S=>{w(S)}});case"style":return a.jsx(rE,{styleId:r.id,categoryId:r.categoryId,canEdit:s,onDelete:()=>y(r),onSelectChild:S=>{w(S)}});case"type":return a.jsx(nE,{typeId:r.id,canEdit:s,onDelete:()=>y(r)});case"brand":return a.jsx(oE,{typeId:r.typeId,brandId:r.brandId??null,brandName:r.brandId===null?"General":r.brandName??"Brand",categoryId:r.categoryId,styleId:r.styleId,canEdit:s,onSelectPart:w});case"part":return a.jsx(cE,{partId:r.partId??r.id,canEdit:s,onDeleted:()=>n(null)});default:return null}};return a.jsxs("div",{className:"flex flex-col lg:flex-row gap-4 h-[calc(100vh-10rem)]",children:[a.jsxs("div",{className:"w-full lg:w-[380px] xl:w-[420px] flex-shrink-0 flex flex-col border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 overflow-hidden",children:[a.jsxs("div",{className:"flex items-center justify-between px-4 py-3 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80",children:[a.jsxs("h3",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2",children:[a.jsx(kt,{className:"h-4 w-4"}),"Part Hierarchy"]}),s&&a.jsx(F,{size:"sm",variant:"ghost",icon:a.jsx(oe,{className:"h-3.5 w-3.5"}),onClick:()=>{o({type:"category"}),n(null)},title:"Add Category",children:"Category"})]}),a.jsx("div",{className:"flex-1 overflow-y-auto px-2 py-2",children:v?a.jsx("div",{className:"flex justify-center py-8",children:a.jsx(z,{size:"lg"})}):!f||f.length===0?a.jsx(le,{icon:a.jsx(kt,{className:"h-10 w-10"}),title:"No categories yet",description:s?'Click "+ Category" to create one.':"No categories have been created."}):a.jsx("div",{className:"space-y-0.5",children:f.map(S=>a.jsx(tE,{category:S,isExpanded:c.has(S.id),onToggle:()=>T(S.id),selected:r,onSelect:w,canEdit:s,onCreateChild:j=>{o({type:"style",parentId:j}),n(null)},expandedStyles:l,onToggleStyle:g,expandedTypes:E,onToggleType:L,onCreateType:(j,K)=>{o({type:"type",parentId:j,grandparentId:K}),n(null)}},S.id))})})]}),a.jsx("div",{className:"flex-1 min-w-0 border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 overflow-hidden flex flex-col",children:te()}),m&&a.jsxs(Ne,{isOpen:!0,onClose:()=>y(null),title:`Delete ${m.type}?`,size:"sm",children:[a.jsxs("p",{className:"text-gray-600 dark:text-gray-300 mb-4",children:["Are you sure you want to delete this ",m.type,"? This cannot be undone."]}),(O.isError||C.isError||W.isError)&&a.jsx("p",{className:"text-red-500 text-sm mb-4",children:"Failed to delete. This item may have child items or parts linked to it."}),a.jsxs("div",{className:"flex justify-end gap-2",children:[a.jsx(F,{variant:"secondary",onClick:()=>y(null),children:"Cancel"}),a.jsx(F,{variant:"danger",isLoading:M,onClick:Q,children:"Delete"})]})]})]})}function lE(){const{data:e,isLoading:t}=B({queryKey:["companion-stats"],queryFn:f_,staleTime:15e3});if(t)return a.jsx("div",{className:"flex items-center justify-center py-6",children:a.jsx(z,{})});const s=[{label:"Active Rules",value:e?.active_rules??0,total:e?.total_rules,icon:Ua,color:"text-blue-600 dark:text-blue-400",bg:"bg-blue-50 dark:bg-blue-900/30"},{label:"Pending",value:e?.pending_suggestions??0,icon:Bt,color:"text-amber-600 dark:text-amber-400",bg:"bg-amber-50 dark:bg-amber-900/30"},{label:"Approved",value:e?.approved_count??0,icon:Lr,color:"text-green-600 dark:text-green-400",bg:"bg-green-50 dark:bg-green-900/30"},{label:"Discarded",value:e?.discarded_count??0,icon:Sr,color:"text-red-600 dark:text-red-400",bg:"bg-red-50 dark:bg-red-900/30"},{label:"Learned Pairs",value:e?.co_occurrence_pairs??0,icon:Ud,color:"text-purple-600 dark:text-purple-400",bg:"bg-purple-50 dark:bg-purple-900/30"}];return a.jsx("div",{className:"grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3",children:s.map(r=>a.jsx(Ce,{className:"p-4",children:a.jsxs("div",{className:"flex items-center gap-3",children:[a.jsx("div",{className:`p-2 rounded-lg ${r.bg}`,children:a.jsx(r.icon,{className:`h-5 w-5 ${r.color}`})}),a.jsxs("div",{children:[a.jsxs("p",{className:"text-2xl font-bold text-gray-900 dark:text-gray-100",children:[r.value,r.total!==void 0&&a.jsxs("span",{className:"text-sm font-normal text-gray-400 ml-1",children:["/",r.total]})]}),a.jsx("p",{className:"text-xs text-gray-500 dark:text-gray-400",children:r.label})]})]})},r.label))})}function va({suggestion:e,onDecide:t,isDeciding:s}){const[r,n]=b.useState(e.suggested_qty),[i,o]=b.useState(""),c=e.status==="pending",d={pending:"warning",approved:"success",discarded:"danger"}[e.status];return a.jsxs(Ce,{className:"p-4",children:[a.jsx("div",{className:"flex items-start justify-between gap-3 mb-3",children:a.jsx("div",{className:"min-w-0 flex-1",children:a.jsxs("div",{className:"flex items-center gap-2 flex-wrap",children:[a.jsxs("h4",{className:"font-semibold text-gray-900 dark:text-gray-100",children:[e.suggested_qty,"× ",e.target_description]}),a.jsx(G,{variant:d,children:e.status})]})})}),a.jsxs("div",{className:"mb-3",children:[a.jsx("p",{className:"text-xs font-medium text-gray-500 dark:text-gray-400 mb-1",children:"Triggered by:"}),a.jsx("div",{className:"flex flex-wrap gap-1.5",children:e.sources.map(l=>a.jsxs(G,{variant:"default",children:[l.qty,"× ",l.category_name,l.style_name&&` (${l.style_name})`]},l.id))})]}),a.jsxs("div",{className:"flex items-start gap-2 mb-3 p-2.5 rounded-lg bg-blue-50 dark:bg-blue-900/20 border border-blue-100 dark:border-blue-800",children:[a.jsx(vr,{className:"h-4 w-4 text-blue-500 dark:text-blue-400 mt-0.5 shrink-0"}),a.jsx("p",{className:"text-xs text-blue-700 dark:text-blue-300",children:e.reason_text})]}),c&&a.jsxs("div",{className:"flex flex-col sm:flex-row items-stretch sm:items-center gap-2 pt-2 border-t border-gray-100 dark:border-gray-700",children:[a.jsxs("div",{className:"flex items-center gap-2",children:[a.jsx("label",{className:"text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap",children:"Qty:"}),a.jsx("input",{type:"number",min:1,value:r,onChange:l=>n(Math.max(1,parseInt(l.target.value)||1)),className:"w-20 h-8 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"})]}),a.jsx("input",{type:"text",placeholder:"Notes (optional)",value:i,onChange:l=>o(l.target.value),className:"flex-1 h-8 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-300"}),a.jsxs("div",{className:"flex gap-2",children:[a.jsx(F,{variant:"primary",size:"sm",icon:a.jsx(Lr,{className:"h-4 w-4"}),isLoading:s,onClick:()=>t(e.id,"approved",r,i||void 0),children:"Approve"}),a.jsx(F,{variant:"ghost",size:"sm",icon:a.jsx(Sr,{className:"h-4 w-4"}),isLoading:s,onClick:()=>t(e.id,"discarded",void 0,i||void 0),children:"Discard"})]})]}),!c&&e.decided_at&&a.jsx("div",{className:"pt-2 border-t border-gray-100 dark:border-gray-700",children:a.jsxs("p",{className:"text-xs text-gray-500 dark:text-gray-400",children:[e.status==="approved"?"Approved":"Discarded",e.approved_qty&&e.approved_qty!==e.suggested_qty&&a.jsxs(a.Fragment,{children:[" (qty adjusted: ",e.suggested_qty," → ",e.approved_qty,")"]}),e.notes&&a.jsxs(a.Fragment,{children:[" — ",e.notes]})]})})]})}function dE(){const e=re(),[t,s]=b.useState(!1),[r,n]=b.useState(null),{data:i=[],isLoading:o}=B({queryKey:["companion-suggestions","pending"],queryFn:()=>or({status:"pending"})}),{data:c=[],isLoading:d}=B({queryKey:["companion-suggestions","decided"],queryFn:()=>or({status:void 0,page_size:100}),enabled:t,select:E=>E.filter(_=>_.status!=="pending")}),l=P({mutationFn:({id:E,action:_,qty:m,notes:y})=>b_(E,{action:_,approved_qty:m,notes:y}),onSuccess:()=>{e.invalidateQueries({queryKey:["companion-suggestions"]}),e.invalidateQueries({queryKey:["companion-stats"]}),n(null)}}),u=(E,_,m,y)=>{n(E),l.mutate({id:E,action:_,qty:m,notes:y})};return a.jsxs("div",{className:"space-y-4",children:[a.jsxs("div",{children:[a.jsxs("h3",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3 flex items-center gap-2",children:[a.jsx(Bs,{className:"h-4 w-4"}),"Pending Suggestions",i.length>0&&a.jsxs("span",{className:"text-xs font-normal text-gray-500 dark:text-gray-400",children:["(",i.length,")"]})]}),o?a.jsx("div",{className:"flex justify-center py-8",children:a.jsx(z,{})}):i.length===0?a.jsx(le,{icon:a.jsx(Bs,{className:"h-12 w-12"}),title:"No pending suggestions",description:"Generate suggestions using the 'What Should I Also Order?' tab, or create rules in the 'Link Rules' tab.",className:"py-8"}):a.jsx("div",{className:"space-y-3",children:i.map(E=>a.jsx(va,{suggestion:E,onDecide:u,isDeciding:r===E.id&&l.isPending},E.id))})]}),a.jsxs("div",{className:"border-t border-gray-200 dark:border-gray-700 pt-3",children:[a.jsxs("button",{onClick:()=>s(!t),className:"flex items-center gap-2 text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 transition-colors",children:[t?a.jsx(Te,{className:"h-4 w-4"}):a.jsx(ye,{className:"h-4 w-4"}),a.jsx(Pd,{className:"h-4 w-4"}),"History"]}),t&&a.jsx("div",{className:"mt-3",children:d?a.jsx("div",{className:"flex justify-center py-4",children:a.jsx(z,{})}):c.length===0?a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400 py-4 text-center",children:"No past decisions yet."}):a.jsx("div",{className:"space-y-2",children:c.map(E=>a.jsx(va,{suggestion:E,onDecide:u},E.id))})})]})]})}function uE({rule:e,onEdit:t,onDelete:s}){const r={auto:"Auto-match style",any:"Any style",explicit:"Explicit style"}[e.style_match],n={sum:"Sum qty",max:"Max qty",ratio:`Ratio ${e.qty_ratio}x`}[e.qty_mode];return a.jsxs(Ce,{className:"p-4",children:[a.jsxs("div",{className:"flex items-start justify-between gap-3 mb-3",children:[a.jsxs("div",{className:"min-w-0 flex-1",children:[a.jsxs("div",{className:"flex items-center gap-2 flex-wrap",children:[a.jsx("h4",{className:"font-semibold text-gray-900 dark:text-gray-100",children:e.name}),a.jsx(G,{variant:e.is_active?"success":"default",children:e.is_active?"Active":"Inactive"})]}),e.description&&a.jsx("p",{className:"text-sm text-gray-500 dark:text-gray-400 mt-1",children:e.description})]}),a.jsxs("div",{className:"flex items-center gap-1 shrink-0",children:[a.jsx(F,{variant:"ghost",size:"sm",icon:a.jsx(xr,{className:"h-3.5 w-3.5"}),onClick:()=>t(e)}),a.jsx(F,{variant:"ghost",size:"sm",icon:a.jsx(pe,{className:"h-3.5 w-3.5 text-red-500"}),onClick:()=>s(e)})]})]}),a.jsxs("div",{className:"flex flex-col sm:flex-row items-start sm:items-center gap-2 mb-3",children:[a.jsx("div",{className:"flex flex-wrap gap-1.5",children:e.sources.map(i=>a.jsxs(G,{variant:"primary",children:[i.category_name,i.style_name&&` (${i.style_name})`]},i.id))}),a.jsx(Md,{className:"h-4 w-4 text-gray-400 dark:text-gray-500 shrink-0 rotate-90 sm:rotate-0"}),a.jsx("div",{className:"flex flex-wrap gap-1.5",children:e.targets.map(i=>a.jsxs(G,{variant:"success",children:[i.category_name,i.style_name&&` (${i.style_name})`]},i.id))})]}),a.jsxs("div",{className:"flex flex-wrap gap-2 text-xs text-gray-500 dark:text-gray-400",children:[a.jsx("span",{className:"px-2 py-0.5 rounded bg-gray-100 dark:bg-gray-700",children:r}),a.jsx("span",{className:"px-2 py-0.5 rounded bg-gray-100 dark:bg-gray-700",children:n})]})]})}function _E({isOpen:e,onClose:t,onSave:s,isLoading:r,rule:n}){const i=!!n,[o,c]=b.useState(""),[d,l]=b.useState(""),[u,E]=b.useState("auto"),[_,m]=b.useState("sum"),[y,f]=b.useState(1),[v,h]=b.useState(!0),[T,g]=b.useState([{category_id:"",style_id:null}]),[L,w]=b.useState([{category_id:"",style_id:null}]),{data:O}=B({queryKey:["hierarchy"],queryFn:Ga,staleTime:300*1e3}),C=O?.categories??[];b.useEffect(()=>{n?(c(n.name),l(n.description??""),E(n.style_match),m(n.qty_mode),f(n.qty_ratio),h(n.is_active),g(n.sources.map(A=>({category_id:A.category_id,style_id:A.style_id??null}))),w(n.targets.map(A=>({category_id:A.category_id,style_id:A.style_id??null})))):(c(""),l(""),E("auto"),m("sum"),f(1),h(!0),g([{category_id:"",style_id:null}]),w([{category_id:"",style_id:null}]))},[n,e]);const W=A=>!A||!O?[]:C.find(D=>D.id===A)?.styles??[],Q=(A,Z)=>{Z([...A,{category_id:"",style_id:null}])},M=(A,Z,D)=>{A.length<=1||Z(A.filter((se,ie)=>ie!==D))},te=(A,Z,D,se,ie)=>{const $=[...A];$[D]={...$[D],[se]:ie},se==="category_id"&&($[D].style_id=null),Z($)},S=T.filter(A=>A.category_id!==""),j=L.filter(A=>A.category_id!==""),K=o.trim().length>0&&S.length>0&&j.length>0,ae=()=>{const A=S.map(D=>({category_id:D.category_id,style_id:D.style_id||void 0})),Z=j.map(D=>({category_id:D.category_id,style_id:D.style_id||void 0}));s(i?{name:o,description:d||void 0,style_match:u,qty_mode:_,qty_ratio:_==="ratio"?y:void 0,is_active:v,sources:A,targets:Z}:{name:o,description:d||void 0,style_match:u,qty_mode:_,qty_ratio:_==="ratio"?y:1,is_active:v,sources:A,targets:Z})},k=(A,Z,D,se,ie)=>{const $=W(se.category_id);return a.jsxs("div",{className:"flex flex-col sm:flex-row gap-2 items-start sm:items-end",children:[a.jsxs("div",{className:"flex-1 min-w-0 w-full sm:w-auto",children:[D===0&&a.jsxs("label",{className:"block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1",children:[ie," Category"]}),a.jsxs("select",{value:se.category_id,onChange:V=>te(A,Z,D,"category_id",V.target.value?Number(V.target.value):""),className:"w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300",children:[a.jsx("option",{value:"",children:"Select category..."}),C.map(V=>a.jsx("option",{value:V.id,children:V.name},V.id))]})]}),a.jsxs("div",{className:"flex-1 min-w-0 w-full sm:w-auto",children:[D===0&&a.jsx("label",{className:"block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1",children:"Style (optional)"}),a.jsxs("select",{value:se.style_id??"",onChange:V=>te(A,Z,D,"style_id",V.target.value?Number(V.target.value):null),disabled:!se.category_id||$.length===0,className:"w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 disabled:opacity-50 focus:outline-none focus:ring-2 focus:ring-primary-300",children:[a.jsx("option",{value:"",children:"Any style"}),$.map(V=>a.jsx("option",{value:V.id,children:V.name},V.id))]})]}),a.jsx("button",{onClick:()=>M(A,Z,D),disabled:A.length<=1,className:"p-2 text-gray-400 hover:text-red-500 disabled:opacity-30 transition-colors shrink-0",children:a.jsx(pe,{className:"h-4 w-4"})})]},D)};return a.jsxs(Ne,{isOpen:e,onClose:t,title:i?"Edit Rule":"New Companion Rule",size:"lg",children:[a.jsxs("div",{className:"space-y-5 max-h-[70vh] overflow-y-auto",children:[a.jsx(q,{label:"Rule Name",value:o,onChange:A=>c(A.target.value),placeholder:"e.g., Cover Plates for Devices"}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Description"}),a.jsx("textarea",{value:d,onChange:A=>l(A.target.value),placeholder:"Optional description...",rows:2,className:"block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-300"})]}),a.jsxs("div",{className:"grid grid-cols-1 sm:grid-cols-3 gap-3",children:[a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Style Matching"}),a.jsxs("select",{value:u,onChange:A=>E(A.target.value),className:"w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300",children:[a.jsx("option",{value:"auto",children:"Auto (match by name)"}),a.jsx("option",{value:"any",children:"Any style"}),a.jsx("option",{value:"explicit",children:"Explicit only"})]})]}),a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Quantity Mode"}),a.jsxs("select",{value:_,onChange:A=>m(A.target.value),className:"w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300",children:[a.jsx("option",{value:"sum",children:"Sum of sources"}),a.jsx("option",{value:"max",children:"Max of sources"}),a.jsx("option",{value:"ratio",children:"Ratio"})]})]}),_==="ratio"&&a.jsxs("div",{className:"space-y-1.5",children:[a.jsx("label",{className:"block text-sm font-medium text-gray-700 dark:text-gray-300",children:"Ratio"}),a.jsx("input",{type:"number",min:.01,step:.1,value:y,onChange:A=>f(parseFloat(A.target.value)||1),className:"w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"})]})]}),a.jsxs("label",{className:"flex items-center gap-2 cursor-pointer",children:[a.jsx("input",{type:"checkbox",checked:v,onChange:A=>h(A.target.checked),className:"rounded border-gray-300 dark:border-gray-600 text-primary-500 focus:ring-primary-300"}),a.jsx("span",{className:"text-sm text-gray-700 dark:text-gray-300",children:"Active"})]}),a.jsxs("div",{children:[a.jsxs("div",{className:"flex items-center justify-between mb-2",children:[a.jsx("h4",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300",children:"Source Categories (triggers)"}),a.jsxs("button",{onClick:()=>Q(T,g),className:"text-xs text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1",children:[a.jsx(oe,{className:"h-3 w-3"})," Add"]})]}),a.jsx("div",{className:"space-y-2",children:T.map((A,Z)=>k(T,g,Z,A,"Source"))})]}),a.jsxs("div",{children:[a.jsxs("div",{className:"flex items-center justify-between mb-2",children:[a.jsx("h4",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300",children:"Target Categories (suggested)"}),a.jsxs("button",{onClick:()=>Q(L,w),className:"text-xs text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1",children:[a.jsx(oe,{className:"h-3 w-3"})," Add"]})]}),a.jsx("div",{className:"space-y-2",children:L.map((A,Z)=>k(L,w,Z,A,"Target"))})]})]}),a.jsxs("div",{className:"flex justify-end gap-3 mt-6 pt-4 border-t border-gray-200 dark:border-gray-700",children:[a.jsx(F,{variant:"secondary",onClick:t,children:"Cancel"}),a.jsx(F,{variant:"primary",onClick:ae,disabled:!K,isLoading:r,children:i?"Update Rule":"Create Rule"})]})]})}function EE(){const e=re(),[t,s]=b.useState(!1),[r,n]=b.useState(null),{data:i=[],isLoading:o}=B({queryKey:["companion-rules"],queryFn:g_}),c=P({mutationFn:T_,onSuccess:()=>{e.invalidateQueries({queryKey:["companion-rules"]}),e.invalidateQueries({queryKey:["companion-stats"]}),s(!1)}}),d=P({mutationFn:({id:y,data:f})=>N_(y,f),onSuccess:()=>{e.invalidateQueries({queryKey:["companion-rules"]}),e.invalidateQueries({queryKey:["companion-stats"]}),n(null),s(!1)}}),l=P({mutationFn:h_,onSuccess:()=>{e.invalidateQueries({queryKey:["companion-rules"]}),e.invalidateQueries({queryKey:["companion-stats"]})}}),u=y=>{n(y),s(!0)},E=y=>{confirm(`Delete rule "${y.name}"? This cannot be undone.`)&&l.mutate(y.id)},_=y=>{r?d.mutate({id:r.id,data:y}):c.mutate(y)},m=()=>{n(null),s(!0)};return o?a.jsx("div",{className:"flex justify-center py-12",children:a.jsx(z,{})}):a.jsxs("div",{children:[a.jsxs("div",{className:"flex items-center justify-between mb-4",children:[a.jsxs("h3",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300",children:[i.length," rule",i.length!==1?"s":""," defined"]}),a.jsx(F,{variant:"primary",size:"sm",icon:a.jsx(oe,{className:"h-4 w-4"}),onClick:m,children:"New Rule"})]}),i.length===0?a.jsx(le,{icon:a.jsx(Ua,{className:"h-12 w-12"}),title:"No companion rules",description:"Create a rule to define which categories should be suggested together.",action:a.jsx(F,{variant:"primary",size:"sm",icon:a.jsx(oe,{className:"h-4 w-4"}),onClick:m,children:"Create First Rule"})}):a.jsx("div",{className:"space-y-3",children:i.map(y=>a.jsx(uE,{rule:y,onEdit:u,onDelete:E},y.id))}),a.jsx(_E,{isOpen:t,onClose:()=>{s(!1),n(null)},onSave:_,isLoading:c.isPending||d.isPending,rule:r})]})}function pE({index:e,categoryId:t,styleId:s,qty:r,categories:n,styles:i,canRemove:o,onChange:c,onRemove:d}){return a.jsxs("div",{className:"flex flex-col sm:flex-row gap-2 items-start sm:items-end",children:[a.jsxs("div",{className:"flex-1 min-w-0 w-full sm:w-auto",children:[e===0&&a.jsx("label",{className:"block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1",children:"Category"}),a.jsxs("select",{value:t,onChange:l=>c(e,"category_id",l.target.value?Number(l.target.value):""),className:"w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300",children:[a.jsx("option",{value:"",children:"Select category..."}),n.map(l=>a.jsx("option",{value:l.id,children:l.name},l.id))]})]}),a.jsxs("div",{className:"flex-1 min-w-0 w-full sm:w-auto",children:[e===0&&a.jsx("label",{className:"block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1",children:"Style (optional)"}),a.jsxs("select",{value:s??"",onChange:l=>c(e,"style_id",l.target.value?Number(l.target.value):null),disabled:!t||i.length===0,className:"w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 disabled:opacity-50 focus:outline-none focus:ring-2 focus:ring-primary-300",children:[a.jsx("option",{value:"",children:"Any style"}),i.map(l=>a.jsx("option",{value:l.id,children:l.name},l.id))]})]}),a.jsxs("div",{className:"w-full sm:w-24",children:[e===0&&a.jsx("label",{className:"block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1",children:"Qty"}),a.jsx("input",{type:"number",min:1,value:r,onChange:l=>c(e,"qty",Math.max(1,parseInt(l.target.value)||1)),className:"w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"})]}),a.jsx("button",{onClick:()=>d(e),disabled:!o,className:"p-2 text-gray-400 hover:text-red-500 disabled:opacity-30 transition-colors shrink-0",children:a.jsx(pe,{className:"h-4 w-4"})})]})}function mE(){const e=re(),[t,s]=b.useState([{category_id:"",style_id:null,qty:1},{category_id:"",style_id:null,qty:1}]),[r,n]=b.useState([]),[i,o]=b.useState(!1),{data:c}=B({queryKey:["hierarchy"],queryFn:Ga,staleTime:300*1e3}),d=c?.categories??[],l=v=>v?d.find(T=>T.id===v)?.styles??[]:[],u=P({mutationFn:x_,onSuccess:v=>{n(v),o(!0),e.invalidateQueries({queryKey:["companion-suggestions"]}),e.invalidateQueries({queryKey:["companion-stats"]})}}),E=(v,h,T)=>{const g=[...t];g[v]={...g[v],[h]:T},h==="category_id"&&(g[v].style_id=null),s(g)},_=v=>{t.length<=1||s(t.filter((h,T)=>T!==v))},m=()=>{s([...t,{category_id:"",style_id:null,qty:1}])},y=()=>{const v=t.filter(h=>h.category_id!=="").map(h=>({category_id:h.category_id,style_id:h.style_id?h.style_id:void 0,qty:h.qty}));v.length!==0&&u.mutate({items:v})},f=t.filter(v=>v.category_id!=="").length;return a.jsxs("div",{className:"space-y-6",children:[a.jsxs("div",{children:[a.jsx("p",{className:"text-sm text-gray-600 dark:text-gray-400 mb-4",children:"Enter the parts you're ordering, and the system will suggest companion items you might also need based on your defined rules."}),a.jsx("div",{className:"space-y-2 mb-4",children:t.map((v,h)=>a.jsx(pE,{index:h,categoryId:v.category_id,styleId:v.style_id,qty:v.qty,categories:d,styles:l(v.category_id),canRemove:t.length>1,onChange:E,onRemove:_},h))}),a.jsxs("div",{className:"flex flex-col sm:flex-row items-stretch sm:items-center gap-3",children:[a.jsxs("button",{onClick:m,className:"text-sm text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1",children:[a.jsx(oe,{className:"h-3.5 w-3.5"})," Add another item"]}),a.jsx("div",{className:"flex-1"}),a.jsx(F,{variant:"primary",icon:a.jsx(Xd,{className:"h-4 w-4"}),onClick:y,disabled:f===0,isLoading:u.isPending,children:"Generate Suggestions"})]})]}),i&&a.jsxs("div",{className:"border-t border-gray-200 dark:border-gray-700 pt-4",children:[a.jsx("h3",{className:"text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3",children:"Results"}),r.length===0?a.jsx(le,{icon:a.jsx(Oe,{className:"h-10 w-10"}),title:"No suggestions found",description:"No companion rules matched the categories you entered. Try adding rules in the 'Link Rules' tab.",className:"py-6"}):a.jsxs("div",{className:"space-y-3",children:[r.map(v=>a.jsx(va,{suggestion:v,onDecide:()=>{}},v.id)),a.jsx("p",{className:"text-xs text-gray-500 dark:text-gray-400 text-center mt-2",children:"Suggestions are now pending on the Suggestions tab."})]})]})]})}const yE=[{id:"suggestions",label:"Suggestions",icon:qd},{id:"rules",label:"Link Rules",icon:Ua},{id:"trigger",label:"What Should I Also Order?",icon:Gd}];function _y(){const[e,t]=b.useState("suggestions");return a.jsxs("div",{className:"flex flex-col h-full overflow-hidden",children:[a.jsx("div",{className:"px-4 sm:px-6 pt-4 pb-2 flex-shrink-0",children:a.jsx(lE,{})}),a.jsx("div",{className:"px-4 sm:px-6 flex-shrink-0",children:a.jsx("div",{className:"border-b border-gray-200 dark:border-gray-700",children:a.jsx("nav",{className:"-mb-px flex gap-4 overflow-x-auto","aria-label":"Companion tabs",children:yE.map(s=>{const r=e===s.id,n=s.icon;return a.jsxs("button",{onClick:()=>t(s.id),className:`
                    flex items-center gap-1.5 whitespace-nowrap pb-3 pt-2 px-1
                    text-sm font-medium border-b-2 transition-colors
                    ${r?"border-primary-500 text-primary-600 dark:text-primary-400":"border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 hover:border-gray-300 dark:hover:border-gray-600"}
                  `,children:[a.jsx(n,{className:"h-4 w-4"}),a.jsx("span",{className:"hidden sm:inline",children:s.label}),a.jsx("span",{className:"sm:hidden",children:s.id==="trigger"?"Order?":s.label})]},s.id)})})})}),a.jsxs("div",{className:"flex-1 overflow-y-auto px-4 sm:px-6 py-4",children:[e==="suggestions"&&a.jsx(dE,{}),e==="rules"&&a.jsx(EE,{}),e==="trigger"&&a.jsx(mE,{})]})]})}async function Ey(e){const{data:t}=await x.post("/bootstrap/pairing-codes",e);return t.data}async function py(e=100){const{data:t}=await x.get("/bootstrap/pairing-codes",{params:{limit:e}});return t.data??[]}async function my(e){const{data:t}=await x.post("/bootstrap/artifacts",e);return t.data}async function yy(e,t=50){const{data:s}=await x.get("/bootstrap/artifacts",{params:{platform:void 0,limit:t}});return s.data??[]}async function gy(e){const{data:t}=await x.post("/bootstrap/handshake",e);return t.data}async function gE(e){const{data:t}=await x.post("/bootstrap/install-events",e);return t.data}async function Ty(e,t=100){const{data:s}=await x.get("/bootstrap/install-events",{params:{device_id:e||void 0,limit:t}});return s.data??[]}async function TE(e){const{data:t}=await x.get(`/bootstrap/artifacts/active/${e}`);return t.data}async function NE(e){const{data:t}=await x.post("/bootstrap/artifacts/verify",e);return t.data}async function Ny(e){const{data:t}=await x.post(`/bootstrap/artifacts/${e}/sign`);return t.data}const hE="wp_bootstrap_",xE=`${hE}download_state`;function bE(e,t){localStorage.setItem(e,t)}async function nn(e){const t=await crypto.subtle.digest("SHA-256",e.buffer);return Array.from(new Uint8Array(t)).map(s=>s.toString(16).padStart(2,"0")).join("")}class fE{chunks=[];totalSize=0;append(t){this.chunks.push(t),this.totalSize+=t.length}async finalise(){const t=new Uint8Array(this.totalSize);let s=0;for(const r of this.chunks)t.set(r,s),s+=r.length;return nn(t)}getMergedBytes(){const t=new Uint8Array(this.totalSize);let s=0;for(const r of this.chunks)t.set(r,s),s+=r.length;return t}get size(){return this.totalSize}}async function je(e){await bE(xE,JSON.stringify(e))}async function he(e,t){try{await gE({pairing_code:e.pairingCode,device_id:e.deviceId,platform:e.platform,artifact_id:t.artifactId,status:t.status,error_message:t.error??void 0,progress_pct:t.progress,bytes_downloaded:t.bytesDownloaded,bytes_total:t.bytesTotal,checksum_computed:t.computedChecksum??void 0,checksum_verified:t.checksumVerified,signature_verified:t.signatureVerified,metadata:{source:"bootstrap-client",version:t.version}})}catch(s){console.warn("[bootstrap-client] Failed to report install event:",s)}}async function vE(e,t,s,r){const n=await fetch(e);if(!n.ok)throw new Error(`Download failed: HTTP ${n.status} ${n.statusText}`);const i=parseInt(n.headers.get("content-length")||"0",10);if(s.bytesTotal=i,!n.body){const E=await n.arrayBuffer(),_=new Uint8Array(E),m=await nn(_);return s.bytesDownloaded=_.length,s.progress=100,{bytes:_,checksum:m}}const o=n.body.getReader(),c=new fE;let d=0;for(;;){const{done:E,value:_}=await o.read();if(E)break;c.append(_),s.bytesDownloaded=c.size,i>0&&(s.progress=Math.round(c.size/i*100));const m=Date.now();m-d>200&&r&&(d=m,r({...s}))}const l=await c.finalise(),u=c.getMergedBytes();return s.bytesDownloaded=u.length,s.progress=100,{bytes:u,checksum:l}}async function RE(e,t){if(ce())try{const{writeFile:r,mkdir:n,BaseDirectory:i}=await N(async()=>{const{writeFile:o,mkdir:c,BaseDirectory:d}=await import("@tauri-apps/plugin-fs");return{writeFile:o,mkdir:c,BaseDirectory:d}},[]);return await n("bootstrap",{baseDir:i.AppData,recursive:!0}).catch(()=>{}),await r(`bootstrap/${t}`,e,{baseDir:i.AppData}),`bootstrap/${t}`}catch(r){console.warn("[bootstrap-client] Filesystem write failed, using blob URL:",r)}const s=new Blob([e],{type:"application/octet-stream"});return URL.createObjectURL(s)}async function hy(e){const{platform:t,onProgress:s}=e;let r;try{r=await TE(t)}catch{throw new Error(`No active artifact found for platform "${t}". Register one in the admin panel first.`)}const n=t==="ios"?"ipa":t==="android"?"apk":"bin",i=`weirdpart-${t}-${r.version}.${n}`,o={artifactId:r.id,platform:t,version:r.version,downloadUrl:r.download_url,expectedChecksum:r.checksum_sha256,status:"requested",progress:0,bytesDownloaded:0,bytesTotal:0,computedChecksum:null,checksumVerified:!1,signatureVerified:null,filePath:null,error:null,startedAt:new Date().toISOString(),completedAt:null};await je(o),s?.({...o}),await he(e,o);try{o.status="downloading",await je(o),s?.({...o}),await he(e,o);const{bytes:c,checksum:d}=await vE(r.download_url,e,o,s);o.status="downloaded",o.computedChecksum=d,await je(o),s?.({...o}),await he(e,o),o.status="verifying",s?.({...o}),await he(e,o);const l=d.toLowerCase()===r.checksum_sha256.toLowerCase();if(!l)return o.checksumVerified=!1,o.status="failed",o.error=`Checksum mismatch: expected ${r.checksum_sha256}, got ${d}`,o.completedAt=new Date().toISOString(),await je(o),s?.({...o}),await he(e,o),{success:!1,state:o,artifact:r};try{const E=await NE({artifact_id:r.id,client_checksum_sha256:d});if(o.checksumVerified=E.checksum_match,o.signatureVerified=E.signature_valid,!E.valid)return o.status="failed",o.error=`Server verification failed: ${E.detail}`,o.completedAt=new Date().toISOString(),await je(o),s?.({...o}),await he(e,o),{success:!1,state:o,artifact:r}}catch(E){console.warn("[bootstrap-client] Server verification unavailable, proceeding with local checksum:",E),o.checksumVerified=l,o.signatureVerified=null}o.status="verified",await je(o),s?.({...o}),await he(e,o),o.status="installing",s?.({...o}),await he(e,o);const u=await RE(c,i);return o.filePath=u,o.status="installed",o.completedAt=new Date().toISOString(),await je(o),s?.({...o}),await he(e,o),{success:!0,state:o,artifact:r}}catch(c){return o.status="failed",o.error=c instanceof Error?c.message:String(c),o.completedAt=new Date().toISOString(),await je(o),s?.({...o}),await he(e,o),{success:!1,state:o,artifact:r}}}function xy(e){switch(e){case"requested":return"Preparing download…";case"downloading":return"Downloading…";case"downloaded":return"Download complete";case"verifying":return"Verifying integrity…";case"verified":return"Verified ✓";case"installing":return"Installing…";case"installed":return"Installed ✓";case"failed":return"Failed";default:return e}}function by(e){switch(e){case"installed":case"verified":return"success";case"failed":return"danger";case"downloading":case"verifying":case"installing":return"warning";case"downloaded":return"info";default:return"neutral"}}async function on(e,t){const s=await p(),n=(await s.query("SELECT * FROM users WHERE id = ? AND is_active = 1",[e])).values[0];if(!n)return{success:!1,user:null,token:null,message:"User not found or inactive"};const o=(await s.query("SELECT pin_hash FROM users WHERE id = ?",[e])).values[0]?.pin_hash;if(!o||o==="__PLACEHOLDER_HASH__")return{success:!1,user:null,token:null,message:"PIN not configured. Sync with shop first."};if(!await CE(t,o))return{success:!1,user:null,token:null,message:"Invalid PIN"};const d=Va(e);return{success:!0,user:n,token:d,message:"Authenticated"}}async function cn(){return(await(await p()).query("SELECT id, display_name, email, phone, avatar_url, certification, hire_date, is_active, default_truck_id, created_at, updated_at FROM users WHERE is_active = 1 ORDER BY display_name ASC")).values}async function wE(e,t){const s=await p();if((await s.query("SELECT COUNT(*) AS cnt FROM users")).values[0]?.cnt>0)return{success:!1,user:null,token:null,message:"Users already exist. Seed aborted."};const n=new Date().toISOString().replace("T"," ").slice(0,19),i=await OE(t),o=[{name:"Admin",level:100,description:"Full system access"},{name:"Manager",level:80,description:"Most permissions except system settings"},{name:"Office",level:60,description:"Ordering, reports, scheduling"},{name:"Lead",level:50,description:"Field lead with scoped job management"},{name:"Worker",level:30,description:"Basic field access"},{name:"Apprentice",level:20,description:"Restricted field access"},{name:"Grunt",level:10,description:"Minimal access"}];for(const m of o)await s.query(`INSERT OR IGNORE INTO hats (name, description, level, is_builtin, created_at)
       VALUES (?, ?, ?, 1, ?)`,[m.name,m.description,m.level,n]);const c={Admin:["view_parts_catalog","edit_parts_catalog","edit_pricing","show_dollar_values","manage_deprecation","view_warehouse","manage_warehouse","move_stock_warehouse","view_trucks","manage_trucks","move_stock_truck","view_jobs","manage_jobs","clock_in_out","consume_parts_any_job","view_labor","manage_labor","view_orders","manage_orders","approve_returns","view_people","manage_people","view_reports","export_reports","manage_settings","manage_devices","manage_templates","manage_notebooks","perform_audit","manager_override","view_activity_log","view_fleet","manage_fleet","view_tools","manage_tools","view_scheduling","manage_scheduling","manage_dispatch","view_schedule","manage_schedule","dispatch_employees","manage_time_off","manage_subcontractors","view_chat","manage_chat","moderate_chat"],Manager:["view_parts_catalog","edit_parts_catalog","edit_pricing","show_dollar_values","manage_deprecation","view_warehouse","manage_warehouse","move_stock_warehouse","view_trucks","manage_trucks","move_stock_truck","view_jobs","manage_jobs","clock_in_out","consume_parts_any_job","view_labor","manage_labor","view_orders","manage_orders","approve_returns","view_people","manage_people","view_reports","export_reports","manage_templates","manage_notebooks","perform_audit","manager_override","view_activity_log","view_fleet","manage_fleet","view_tools","manage_tools","view_scheduling","manage_scheduling","manage_dispatch","view_schedule","manage_schedule","dispatch_employees"],Office:["view_parts_catalog","edit_parts_catalog","show_dollar_values","view_warehouse","view_trucks","view_jobs","manage_jobs","view_labor","manage_labor","view_orders","manage_orders","view_people","view_reports","export_reports","view_scheduling","manage_scheduling","view_schedule","dispatch_employees"],Lead:["view_parts_catalog","view_warehouse","view_trucks","move_stock_truck","view_jobs","manage_jobs","clock_in_out","consume_parts_any_job","view_labor","view_orders","view_reports","view_fleet","view_tools","view_scheduling","view_schedule"],Worker:["view_parts_catalog","view_warehouse","view_trucks","move_stock_truck","view_jobs","clock_in_out","view_labor","view_orders","view_fleet","view_tools","view_schedule"],Apprentice:["view_parts_catalog","view_trucks","view_jobs","clock_in_out","view_labor"],Grunt:["view_parts_catalog","view_trucks","view_jobs","clock_in_out"]};for(const[m,y]of Object.entries(c))for(const f of y)await s.query(`INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
         SELECT id, ? FROM hats WHERE name = ?`,[f,m]);await s.query(`INSERT INTO users (display_name, pin_hash, is_active, created_at, updated_at)
     VALUES (?, ?, 1, ?, ?)`,[e,i,n,n]);const l=(await s.query("SELECT id FROM users WHERE display_name = ? ORDER BY id DESC LIMIT 1",[e])).values[0]?.id;await s.query(`INSERT INTO user_hats (user_id, hat_id, is_active)
     SELECT ?, id, 1 FROM hats WHERE name = 'Admin'`,[l]);const u=[["company_name",e+"'s Company","general"],["auto_lock_minutes","15","security"],["stale_data_hours","4","sync"],["archive_completed_days","90","data"]];for(const[m,y,f]of u)await s.query(`INSERT OR IGNORE INTO settings (key, value, category, updated_at)
       VALUES (?, ?, ?, ?)`,[m,y,f,n]);await s.query(`INSERT INTO activity_log (user_id, action, entity_type, entity_id, details, timestamp)
     VALUES (?, 'first_admin_setup', 'user', ?, 'First device bootstrap', ?)`,[l,l,n]);const E=await $t(l),_=Va(l);return{success:!0,user:E,token:_,message:"Company database initialized. Welcome!"}}async function $t(e){return(await(await p()).query("SELECT id, display_name, email, phone, avatar_url, certification, hire_date, is_active, default_truck_id, created_at, updated_at FROM users WHERE id = ?",[e])).values[0]??null}async function Ya(e){return(await(await p()).query(`SELECT DISTINCT hp.permission_key
     FROM user_hats uh
     JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
     WHERE uh.user_id = ? AND uh.is_active = 1`,[e])).values.map(r=>r.permission_key)}async function ln(e,t){return(await(await p()).query(`SELECT 1 FROM user_hats uh
     JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
     WHERE uh.user_id = ? AND uh.is_active = 1 AND hp.permission_key = ?
     LIMIT 1`,[e,t])).values.length>0}async function LE(e){return(await(await p()).query(`SELECT h.name FROM user_hats uh
     JOIN hats h ON h.id = uh.hat_id
     WHERE uh.user_id = ? AND uh.is_active = 1
     ORDER BY h.level DESC`,[e])).values.map(r=>r.name)}async function dn(e){return(await(await p()).query(`SELECT h.id, h.name, h.level FROM user_hats uh
     JOIN hats h ON h.id = uh.hat_id
     WHERE uh.user_id = ? AND uh.is_active = 1
     ORDER BY h.level DESC`,[e])).values}async function SE(e){const t=AE(e);if(!t)throw new Error("Invalid local token");if(t.exp<Date.now())throw new Error("Token expired");const s=t.sub,r=await $t(s);if(!r)throw new Error("User not found");const n=await dn(s),i=await Ya(s);return{id:r.id,display_name:r.display_name,email:r.email,phone:r.phone,avatar_url:r.avatar_url,certification:r.certification,hire_date:r.hire_date,is_active:!!r.is_active,hats:n,permissions:i,created_at:r.created_at}}async function CE(e,t){if(t.startsWith("$2b$")||t.startsWith("$2a$"))try{const{compare:c}=await N(async()=>{const{compare:d}=await import("bcryptjs");return{compare:d}},[]);return await c(e,t)}catch{return console.warn("bcryptjs not available for offline PIN verification"),!1}const r=new TextEncoder().encode(e+":wiredpart"),n=await crypto.subtle.digest("SHA-256",r);return Array.from(new Uint8Array(n)).map(c=>c.toString(16).padStart(2,"0")).join("")===t}async function OE(e){const s=new TextEncoder().encode(e+":wiredpart"),r=await crypto.subtle.digest("SHA-256",s);return Array.from(new Uint8Array(r)).map(i=>i.toString(16).padStart(2,"0")).join("")}async function jE(e){const t=await p();let s=await t.query("SELECT * FROM users WHERE id = ? AND is_active = 1",[e]),r=s.values?.[0];if(r||(s=await t.query("SELECT * FROM users WHERE is_active = 1 ORDER BY id ASC LIMIT 1"),r=s.values?.[0]),!r)return{success:!1,user:null,token:null,message:"No active users in local DB"};const n=Va(r.id);return{success:!0,user:r,token:n,message:`DEV auto-login as ${r.display_name} (id=${r.id})`}}function Va(e){const t={sub:e,iat:Date.now(),exp:Date.now()+864e5,type:"local"};return btoa(JSON.stringify(t))}function AE(e){try{const t=atob(e),s=JSON.parse(t);return s.type!=="local"||typeof s.sub!="number"?null:s}catch{return null}}const Ja=Object.freeze(Object.defineProperty({__proto__:null,authenticateByPin:on,devAutoLogin:jE,getActiveUsers:cn,getLocalUserProfile:SE,getUser:$t,getUserHatNames:LE,getUserHats:dn,getUserPermissions:Ya,hasPermission:ln,seedFirstAdmin:wE},Symbol.toStringTag,{value:"Module"}));class Y{tableName;primaryKey;constructor(t,s="id"){this.tableName=t,this.primaryKey=s}async getById(t){return(await(await p()).query(`SELECT * FROM ${this.tableName} WHERE ${this.primaryKey} = ?`,[t])).values[0]??null}async findAll(t,s,r,n,i){const o=await p();let c=`SELECT * FROM ${this.tableName}`;return t&&(c+=` WHERE ${t}`),r&&(c+=` ORDER BY ${r}`),n&&(c+=` LIMIT ${n}`),i&&(c+=` OFFSET ${i}`),(await o.query(c,s??[])).values}async count(t,s){const r=await p();let n=`SELECT COUNT(*) as cnt FROM ${this.tableName}`;return t&&(n+=` WHERE ${t}`),(await r.query(n,s??[])).values[0]?.cnt??0}async insert(t,s=!0){const r=await p(),n=Object.keys(t),i=n.map(()=>"?").join(", "),o=n.map(l=>t[l]),d=(await r.run(`INSERT INTO ${this.tableName} (${n.join(", ")}) VALUES (${i})`,o)).changes.lastId;return s&&await X(this.tableName,d,"INSERT",t),d}async update(t,s,r=!0){const n=await p(),i=Object.keys(s);if(i.length===0)return!1;const o=i.map(u=>`${u} = ?`).join(", "),c=[...i.map(u=>s[u]),t];let d;if(r){const u=await this.getById(t);if(u){d={};for(const E of i)d[E]=u[E]}}const l=await n.run(`UPDATE ${this.tableName} SET ${o} WHERE ${this.primaryKey} = ?`,c);return l.changes.changes>0&&r&&await X(this.tableName,t,"UPDATE",s,d),l.changes.changes>0}async delete(t,s=!0){const r=await p();let n;if(s){const o=await this.getById(t);o&&(n=o)}const i=await r.run(`DELETE FROM ${this.tableName} WHERE ${this.primaryKey} = ?`,[t]);return i.changes.changes>0&&s&&await X(this.tableName,t,"DELETE",void 0,n),i.changes.changes>0}async rawQuery(t,s){return(await(await p()).query(t,s??[])).values}async rawRun(t,s){return(await p()).run(t,s??[])}}const Ht=new Y("company_profiles");async function Qa(e){return(await(await p()).query("SELECT value FROM settings WHERE key = ?",[e])).values[0]?.value??null}async function xt(e,t,s="general"){await(await p()).run(`INSERT INTO settings (key, value, category, updated_at)
     VALUES (?, ?, ?, datetime('now'))
     ON CONFLICT(key) DO UPDATE SET value = ?, category = ?, updated_at = datetime('now')`,[e,t,s,t,s])}async function Wt(e){const s=await(await p()).query("SELECT key, value FROM settings WHERE category = ?",[e]),r={};for(const n of s.values)r[n.key]=n.value;return r}async function Kt(e,t){for(const[s,r]of Object.entries(e))r!==void 0&&await xt(s,String(r),t)}const ya={theme_mode:"system",primary_color:"#2563eb",font_family:"Inter"};async function za(){const e=await Wt("theme");return{theme_mode:e.theme_mode??ya.theme_mode,primary_color:e.primary_color??ya.primary_color,font_family:e.font_family??ya.font_family}}async function un(e){return await Kt(e,"theme"),za()}async function _n(){const t=await(await p()).query("SELECT key, value, category FROM settings ORDER BY category, key"),s={};for(const r of t.values){const n=r.category??"general";s[n]||(s[n]={}),s[n][r.key]=r.value}return s}async function En(e){return Qa(e)}async function pn(e,t,s="general"){await xt(e,t,s)}async function mn(){const e=await Qa("warranty_length_days");return e?parseInt(e,10):365}async function yn(e){await xt("warranty_length_days",String(e),"general")}async function gn(){return Ht.findAll("deleted_at IS NULL",[],"name ASC")}async function Tn(e){const t=new Date().toISOString();return{id:await Ht.insert({name:e.name,address_street:e.address_street??null,address_city:e.address_city??null,address_state:e.address_state??null,address_zip:e.address_zip??null,phone:e.phone??null,email:e.email??null,website:e.website??null,contractor_license:e.contractor_license??null,insurance_info:e.insurance_info??null,tax_id:e.tax_id??null,is_primary:e.is_primary?1:0,branch_name:e.branch_name??null,notes:e.notes??null,created_at:t,updated_at:t})}}async function Nn(e,t){const s={updated_at:new Date().toISOString()};for(const[r,n]of Object.entries(t))n!==void 0&&(s[r]=r==="is_primary"?n?1:0:n);return await Ht.update(e,s),{status:"ok"}}async function hn(e){return await Ht.update(e,{deleted_at:new Date().toISOString()}),{status:"ok"}}const Je={accent_color:"#2563eb",show_unit_prices:!0,show_extended:!0,footer_text:"",payment_terms:"Net 30",delivery_notes:""};async function Za(){const e=await Wt("pdf");return{accent_color:e.accent_color??Je.accent_color,show_unit_prices:e.show_unit_prices!==void 0?e.show_unit_prices==="true":Je.show_unit_prices,show_extended:e.show_extended!==void 0?e.show_extended==="true":Je.show_extended,footer_text:e.footer_text??Je.footer_text,payment_terms:e.payment_terms??Je.payment_terms,delivery_notes:e.delivery_notes??Je.delivery_notes}}async function xn(e){return await Kt(e,"pdf"),Za()}async function bn(e){await xt("company_logo_path",e,"general");const t=e.split("/").pop()??e.split("\\").pop()??"logo";return{logo_path:e,filename:t}}async function es(){const e=await Wt("billing_cycle");return{cycle_type:e.cycle_type??"monthly",start_day:e.start_day?parseInt(e.start_day,10):1}}async function fn(e){return await Kt(e,"billing_cycle"),es()}async function ts(){const e=await Wt("pay_period");return{period_type:e.period_type??"biweekly",start_day:e.start_day?parseInt(e.start_day,10):1}}async function vn(e){return await Kt(e,"pay_period"),ts()}async function Rn(){const e=await Qa("payroll_columns");if(e)try{return JSON.parse(e)}catch{}return{columns:[]}}async function wn(e){return await xt("payroll_columns",JSON.stringify(e),"payroll"),e}const ne=Object.freeze(Object.defineProperty({__proto__:null,createCompanyProfile:Tn,deleteCompanyProfile:hn,getAllSettings:_n,getBillingCycle:es,getPDFSettings:Za,getPayPeriod:ts,getPayrollColumns:Rn,getSetting:En,getTheme:za,getWarrantyLengthDays:mn,listCompanyProfiles:gn,updateBillingCycle:fn,updateCompanyProfile:Nn,updatePDFSettings:xn,updatePayPeriod:vn,updatePayrollColumns:wn,updateSetting:pn,updateTheme:un,updateWarrantyLengthDays:yn,uploadCompanyLogo:bn},Symbol.toStringTag,{value:"Module"})),IE={name:"001_foundation",sql:`
-- ─── USERS ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    display_name            TEXT    NOT NULL,
    email                   TEXT,
    phone                   TEXT,
    pin_hash                TEXT    NOT NULL,
    default_truck_id        INTEGER,
    emergency_contact_name  TEXT,
    emergency_contact_phone TEXT,
    certification           TEXT    CHECK(certification IN ('journeyman', 'apprentice', 'master', NULL)),
    hire_date               TEXT,
    pay_rate                REAL,
    is_active               INTEGER DEFAULT 1,
    avatar_url              TEXT,
    created_at              TEXT    DEFAULT (datetime('now')),
    updated_at              TEXT    DEFAULT (datetime('now'))
);

-- ─── HATS (Roles) ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS hats (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    description TEXT,
    level       INTEGER DEFAULT 0,
    is_builtin  INTEGER DEFAULT 0,
    created_at  TEXT    DEFAULT (datetime('now'))
);

-- ─── HAT PERMISSIONS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS hat_permissions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    hat_id          INTEGER NOT NULL REFERENCES hats(id) ON DELETE CASCADE,
    permission_key  TEXT    NOT NULL,
    UNIQUE(hat_id, permission_key)
);
CREATE INDEX IF NOT EXISTS idx_hat_perms_hat ON hat_permissions(hat_id);
CREATE INDEX IF NOT EXISTS idx_hat_perms_key ON hat_permissions(permission_key);

-- ─── USER ↔ HAT JUNCTION ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_hats (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    hat_id    INTEGER NOT NULL REFERENCES hats(id) ON DELETE CASCADE,
    is_active INTEGER DEFAULT 1,
    UNIQUE(user_id, hat_id)
);
CREATE INDEX IF NOT EXISTS idx_user_hats_user ON user_hats(user_id);

-- ─── JOB LEAD ELEVATIONS ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_lead_elevations (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    job_id          INTEGER NOT NULL,
    permission_key  TEXT    NOT NULL,
    granted_by      INTEGER REFERENCES users(id),
    granted_at      TEXT    DEFAULT (datetime('now')),
    expires_at      TEXT,
    UNIQUE(user_id, job_id, permission_key)
);

-- ─── DEVICES ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS devices (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    device_name         TEXT    NOT NULL,
    device_fingerprint  TEXT    UNIQUE NOT NULL,
    assigned_user_id    INTEGER REFERENCES users(id),
    is_public           INTEGER DEFAULT 0,
    last_seen           TEXT,
    created_at          TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_devices_fp ON devices(device_fingerprint);

-- ─── SETTINGS ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS settings (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    key         TEXT    NOT NULL UNIQUE,
    value       TEXT,
    category    TEXT    DEFAULT 'general',
    updated_at  TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_settings_cat ON settings(category);

-- ─── ACTIVITY LOG ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS activity_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER REFERENCES users(id),
    action      TEXT    NOT NULL,
    entity_type TEXT,
    entity_id   INTEGER,
    details     TEXT,
    ip_address  TEXT,
    timestamp   TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_activity_ts ON activity_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_activity_entity ON activity_log(entity_type, entity_id);

-- ─── NOTIFICATIONS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER REFERENCES users(id),
    title       TEXT    NOT NULL,
    body        TEXT,
    severity    TEXT    DEFAULT 'info' CHECK(severity IN ('info','warning','error','critical')),
    source      TEXT    DEFAULT 'system',
    link        TEXT,
    is_read     INTEGER DEFAULT 0,
    type        TEXT    DEFAULT 'system',
    message     TEXT,
    entity_type TEXT,
    entity_id   INTEGER,
    created_at  TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);
CREATE INDEX IF NOT EXISTS idx_notifications_entity ON notifications(entity_type, entity_id);

-- ─── NOTIFICATION PREFERENCES ───────────────────────────────────
CREATE TABLE IF NOT EXISTS notification_preferences (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id           INTEGER NOT NULL REFERENCES users(id),
    notification_type TEXT    NOT NULL,
    is_enabled        INTEGER NOT NULL DEFAULT 0,
    UNIQUE(user_id, notification_type)
);
CREATE INDEX IF NOT EXISTS idx_notif_prefs_user ON notification_preferences(user_id);
  `},kE={name:"002_parts_inventory",sql:`
-- ─── PART CATEGORIES ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS part_categories (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    description TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now'))
);

-- ─── PART STYLES ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS part_styles (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    category_id INTEGER NOT NULL REFERENCES part_categories(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL,
    description TEXT,
    image_url   TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now')),
    UNIQUE(category_id, name)
);
CREATE INDEX IF NOT EXISTS idx_styles_category ON part_styles(category_id);

-- ─── PART TYPES ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS part_types (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    style_id    INTEGER NOT NULL REFERENCES part_styles(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL,
    description TEXT,
    color       TEXT,
    image_url   TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now')),
    UNIQUE(style_id, name)
);
CREATE INDEX IF NOT EXISTS idx_types_style ON part_types(style_id);

-- ─── PART COLORS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS part_colors (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    hex_code    TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now'))
);

-- ─── BRANDS ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS brands (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    website     TEXT,
    notes       TEXT,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now'))
);

-- ─── SUPPLIERS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS suppliers (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    name                    TEXT    NOT NULL,
    contact_name            TEXT,
    email                   TEXT,
    phone                   TEXT,
    address                 TEXT,
    website                 TEXT,
    rep_name                TEXT,
    rep_email               TEXT,
    rep_phone               TEXT,
    notes                   TEXT,
    delivery_method         TEXT    DEFAULT 'standard_shipping',
    delivery_days           TEXT,
    special_order_lead_days INTEGER,
    delivery_notes          TEXT,
    driver_name             TEXT,
    driver_phone            TEXT,
    driver_email            TEXT,
    on_time_rate            REAL    DEFAULT 0.95,
    quality_score           REAL    DEFAULT 0.90,
    avg_lead_days           INTEGER DEFAULT 5,
    reliability_score       REAL    DEFAULT 0.85,
    communication_score     REAL    DEFAULT 0.85,
    is_active               INTEGER DEFAULT 1,
    created_at              TEXT    DEFAULT (datetime('now')),
    updated_at              TEXT    DEFAULT (datetime('now'))
);

-- ─── PARTS (Orderable Variants) ────────────────────────────
CREATE TABLE IF NOT EXISTS parts (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    category_id                 INTEGER NOT NULL REFERENCES part_categories(id),
    style_id                    INTEGER REFERENCES part_styles(id),
    type_id                     INTEGER REFERENCES part_types(id),
    color_id                    INTEGER REFERENCES part_colors(id),
    part_type                   TEXT    NOT NULL DEFAULT 'general'
                                        CHECK(part_type IN ('general', 'specific')),
    code                        TEXT    UNIQUE,
    name                        TEXT    NOT NULL,
    description                 TEXT,
    brand_id                    INTEGER REFERENCES brands(id) ON DELETE SET NULL,
    manufacturer_part_number    TEXT,
    unit_of_measure             TEXT    DEFAULT 'each',
    weight_lbs                  REAL,
    company_cost_price          REAL    NOT NULL DEFAULT 0.0,
    company_markup_percent      REAL    NOT NULL DEFAULT 0.0,
    company_sell_price          REAL    GENERATED ALWAYS AS (
                                    company_cost_price * (1.0 + company_markup_percent / 100.0)
                                ) STORED,
    min_stock_level             INTEGER DEFAULT 0,
    max_stock_level             INTEGER DEFAULT 0,
    target_stock_level          INTEGER DEFAULT 0,
    reorder_point               INTEGER DEFAULT 0,
    forecast_last_run           TEXT,
    forecast_adu_30             REAL    DEFAULT 0,
    forecast_adu_90             REAL    DEFAULT 0,
    forecast_reorder_point      INTEGER DEFAULT 0,
    forecast_target_qty         INTEGER DEFAULT 0,
    forecast_suggested_order    INTEGER DEFAULT 0,
    forecast_days_until_low     INTEGER DEFAULT 999,
    is_deprecated               INTEGER DEFAULT 0,
    deprecation_reason          TEXT,
    is_qr_tagged                INTEGER DEFAULT 0,
    notes                       TEXT,
    image_url                   TEXT,
    pdf_url                     TEXT,
    shelf_location              TEXT,
    bin_location                TEXT,
    is_active                   INTEGER DEFAULT 1,
    created_at                  TEXT    DEFAULT (datetime('now')),
    updated_at                  TEXT    DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_parts_variant_unique
    ON parts(category_id, COALESCE(style_id, 0), COALESCE(type_id, 0), COALESCE(color_id, 0), COALESCE(brand_id, 0));
CREATE INDEX IF NOT EXISTS idx_parts_category ON parts(category_id);
CREATE INDEX IF NOT EXISTS idx_parts_brand ON parts(brand_id);
CREATE INDEX IF NOT EXISTS idx_parts_name ON parts(name);
CREATE INDEX IF NOT EXISTS idx_parts_code ON parts(code);

-- ─── BRAND ↔ SUPPLIER LINKS ────────────────────────────────
CREATE TABLE IF NOT EXISTS brand_supplier_links (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    brand_id        INTEGER NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
    supplier_id     INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
    account_number  TEXT,
    notes           TEXT,
    is_active       INTEGER DEFAULT 1,
    created_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(brand_id, supplier_id)
);

-- ─── PART ↔ SUPPLIER LINKS ─────────────────────────────────
CREATE TABLE IF NOT EXISTS part_supplier_links (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id              INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    supplier_id          INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
    supplier_part_number TEXT,
    supplier_cost_price  REAL,
    moq                  INTEGER DEFAULT 1,
    discount_brackets    TEXT,
    last_price_date      TEXT,
    is_preferred         INTEGER DEFAULT 0,
    created_at           TEXT    DEFAULT (datetime('now')),
    UNIQUE(part_id, supplier_id)
);

-- ─── STOCK ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS stock (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id         INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    location_type   TEXT    NOT NULL CHECK(location_type IN ('warehouse','pulled','truck','trailer','job')),
    location_id     INTEGER NOT NULL DEFAULT 1,
    qty             INTEGER NOT NULL DEFAULT 0 CHECK(qty >= 0),
    supplier_id     INTEGER REFERENCES suppliers(id),
    last_counted    TEXT,
    updated_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(part_id, location_type, location_id, supplier_id)
);
CREATE INDEX IF NOT EXISTS idx_stock_part ON stock(part_id);
CREATE INDEX IF NOT EXISTS idx_stock_location ON stock(location_type, location_id);

-- ─── STOCK MOVEMENTS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS stock_movements (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id             INTEGER NOT NULL REFERENCES parts(id),
    qty                 INTEGER NOT NULL CHECK(qty > 0),
    from_location_type  TEXT,
    from_location_id    INTEGER,
    to_location_type    TEXT,
    to_location_id      INTEGER,
    supplier_id         INTEGER REFERENCES suppliers(id),
    movement_type       TEXT    NOT NULL DEFAULT 'transfer'
                                CHECK(movement_type IN (
                                    'receive', 'transfer', 'consume',
                                    'return', 'adjust', 'write_off'
                                )),
    reason              TEXT,
    reference_number    TEXT,
    notes               TEXT,
    job_id              INTEGER,
    performed_by        INTEGER NOT NULL REFERENCES users(id),
    verified_by         INTEGER REFERENCES users(id),
    photo_path          TEXT,
    scan_confirmed      INTEGER DEFAULT 0,
    gps_lat             REAL,
    gps_lng             REAL,
    unit_cost_at_move   REAL,
    unit_sell_at_move   REAL,
    created_at          TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_movements_part ON stock_movements(part_id);
CREATE INDEX IF NOT EXISTS idx_movements_job ON stock_movements(job_id);
CREATE INDEX IF NOT EXISTS idx_movements_date ON stock_movements(created_at);

-- ─── PULLED STAGING TAGS ────────────────────────────────────
CREATE TABLE IF NOT EXISTS pulled_staging_tags (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    stock_id         INTEGER NOT NULL REFERENCES stock(id) ON DELETE CASCADE,
    destination_type TEXT,
    destination_id   INTEGER,
    destination_label TEXT,
    tagged_by        INTEGER REFERENCES users(id),
    tagged_at        TEXT    DEFAULT (datetime('now')),
    UNIQUE(stock_id)
);
  `},DE={name:"003_jobs_labor",sql:`
-- ─── BILL RATE TYPES ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bill_rate_types (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    description TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now'))
);

-- ─── JOBS ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS jobs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_number      TEXT    NOT NULL UNIQUE,
    job_name        TEXT    NOT NULL,
    customer_name   TEXT,
    address_line1   TEXT,
    address_line2   TEXT,
    city            TEXT,
    state           TEXT,
    zip             TEXT,
    gps_lat         REAL,
    gps_lng         REAL,
    status          TEXT    NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','on_hold','completed','cancelled',
                          'continuous_maintenance','on_call','pending')),
    priority        TEXT    NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low','normal','high','urgent')),
    job_type        TEXT    NOT NULL DEFAULT 'service'
        CHECK (job_type IN ('service','new_construction','remodel','maintenance','emergency')),
    bill_rate_type_id INTEGER REFERENCES bill_rate_types(id),
    billing_rate    REAL,
    estimated_hours REAL,
    lead_user_id    INTEGER REFERENCES users(id),
    on_call_type    TEXT,
    warranty_start_date TEXT,
    warranty_end_date   TEXT,
    start_date      TEXT,
    due_date        TEXT,
    completed_date  TEXT,
    notes           TEXT,
    created_by      INTEGER REFERENCES users(id),
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_number ON jobs(job_number);

-- ─── JOB PARTS (consumption tracking) ──────────────────────
CREATE TABLE IF NOT EXISTS job_parts (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id                INTEGER NOT NULL REFERENCES jobs(id),
    part_id               INTEGER NOT NULL REFERENCES parts(id),
    qty_consumed          INTEGER NOT NULL DEFAULT 0,
    qty_returned          INTEGER NOT NULL DEFAULT 0,
    unit_cost_at_consume  REAL,
    unit_sell_at_consume  REAL,
    consumed_by           INTEGER REFERENCES users(id),
    consumed_at           TEXT    NOT NULL DEFAULT (datetime('now')),
    notes                 TEXT
);
CREATE INDEX IF NOT EXISTS idx_job_parts_job ON job_parts(job_id);

-- ─── LABOR ENTRIES ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS labor_entries (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id              INTEGER NOT NULL REFERENCES users(id),
    job_id               INTEGER NOT NULL REFERENCES jobs(id),
    clock_in             TEXT    NOT NULL,
    clock_out            TEXT,
    regular_hours        REAL    DEFAULT 0,
    overtime_hours       REAL    DEFAULT 0,
    drive_time_minutes   INTEGER DEFAULT 0,
    clock_in_gps_lat     REAL,
    clock_in_gps_lng     REAL,
    clock_out_gps_lat    REAL,
    clock_out_gps_lng    REAL,
    clock_in_photo_path  TEXT,
    clock_out_photo_path TEXT,
    status               TEXT    NOT NULL DEFAULT 'clocked_in'
        CHECK (status IN ('clocked_in','clocked_out','edited','approved')),
    edited_by            INTEGER REFERENCES users(id),
    approved_by          INTEGER REFERENCES users(id),
    notes                TEXT,
    created_at           TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_labor_user ON labor_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_labor_job ON labor_entries(job_id);
CREATE INDEX IF NOT EXISTS idx_labor_status ON labor_entries(status);

-- ─── CLOCK-OUT QUESTIONS ────────────────────────────────────
CREATE TABLE IF NOT EXISTS clock_out_questions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    question_text TEXT    NOT NULL,
    answer_type   TEXT    NOT NULL DEFAULT 'text'
        CHECK (answer_type IN ('text','yes_no','photo')),
    is_required   INTEGER NOT NULL DEFAULT 1,
    sort_order    INTEGER NOT NULL DEFAULT 0,
    is_active     INTEGER NOT NULL DEFAULT 1,
    created_by    INTEGER REFERENCES users(id),
    created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ─── CLOCK-OUT RESPONSES ────────────────────────────────────
CREATE TABLE IF NOT EXISTS clock_out_responses (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    labor_entry_id  INTEGER NOT NULL REFERENCES labor_entries(id),
    question_id     INTEGER NOT NULL REFERENCES clock_out_questions(id),
    answer_text     TEXT,
    answer_bool     INTEGER,
    photo_path      TEXT,
    answered_at     TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_cor_labor ON clock_out_responses(labor_entry_id);

-- ─── ONE-TIME PER-JOB QUESTIONS ─────────────────────────────
CREATE TABLE IF NOT EXISTS one_time_questions (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id             INTEGER NOT NULL REFERENCES jobs(id),
    target_user_id     INTEGER REFERENCES users(id),
    question_text      TEXT    NOT NULL,
    answer_type        TEXT    NOT NULL DEFAULT 'text'
        CHECK (answer_type IN ('text','yes_no','photo')),
    status             TEXT    NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','answered','expired','cancelled')),
    created_by         INTEGER NOT NULL REFERENCES users(id),
    answered_by        INTEGER REFERENCES users(id),
    answer_text        TEXT,
    answer_photo_path  TEXT,
    shown_at_clock_in  INTEGER NOT NULL DEFAULT 0,
    created_at         TEXT    NOT NULL DEFAULT (datetime('now')),
    answered_at        TEXT
);
CREATE INDEX IF NOT EXISTS idx_otq_job ON one_time_questions(job_id);

-- ─── DAILY REPORTS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS daily_reports (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id         INTEGER NOT NULL REFERENCES jobs(id),
    report_date    TEXT    NOT NULL,
    report_json    TEXT    NOT NULL,
    status         TEXT    NOT NULL DEFAULT 'generated'
        CHECK (status IN ('generated','reviewed','locked')),
    generated_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    reviewed_by    INTEGER REFERENCES users(id),
    reviewed_at    TEXT,
    UNIQUE(job_id, report_date)
);
CREATE INDEX IF NOT EXISTS idx_dr_job_date ON daily_reports(job_id, report_date);
  `},FE={name:"004_notebooks",sql:`
-- ─── NOTEBOOK TEMPLATES ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS notebook_templates (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    description TEXT,
    job_type    TEXT,
    is_default  INTEGER NOT NULL DEFAULT 0,
    created_by  INTEGER REFERENCES users(id),
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS template_sections (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    template_id  INTEGER NOT NULL REFERENCES notebook_templates(id) ON DELETE CASCADE,
    name         TEXT    NOT NULL,
    section_type TEXT    NOT NULL DEFAULT 'notes'
        CHECK (section_type IN ('info','notes','tasks')),
    sort_order   INTEGER NOT NULL DEFAULT 0,
    is_locked    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS template_entries (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    section_id     INTEGER NOT NULL REFERENCES template_sections(id) ON DELETE CASCADE,
    title          TEXT    NOT NULL,
    default_content TEXT,
    entry_type     TEXT    NOT NULL DEFAULT 'note'
        CHECK (entry_type IN ('note','task','field')),
    field_type     TEXT    CHECK (field_type IN ('text','checkbox','textarea')),
    field_required INTEGER NOT NULL DEFAULT 0,
    sort_order     INTEGER NOT NULL DEFAULT 0
);

-- ─── NOTEBOOKS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notebooks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT    NOT NULL,
    description TEXT,
    job_id      INTEGER REFERENCES jobs(id),
    template_id INTEGER REFERENCES notebook_templates(id),
    created_by  INTEGER NOT NULL REFERENCES users(id),
    is_archived INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_notebooks_job ON notebooks(job_id);

-- ─── NOTEBOOK SECTIONS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS notebook_sections (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    notebook_id  INTEGER NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
    name         TEXT    NOT NULL,
    section_type TEXT    NOT NULL DEFAULT 'notes'
        CHECK (section_type IN ('info','notes','tasks')),
    sort_order   INTEGER NOT NULL DEFAULT 0,
    is_locked    INTEGER NOT NULL DEFAULT 0,
    created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_nb_sections_notebook ON notebook_sections(notebook_id);

-- ─── NOTEBOOK ENTRIES ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS notebook_entries (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    section_id       INTEGER NOT NULL REFERENCES notebook_sections(id) ON DELETE CASCADE,
    title            TEXT    NOT NULL,
    content          TEXT,
    entry_type       TEXT    NOT NULL DEFAULT 'note'
        CHECK (entry_type IN ('note','task','field')),
    field_type       TEXT    CHECK (field_type IN ('text','checkbox','textarea')),
    field_required   INTEGER NOT NULL DEFAULT 0,
    field_filled_by  INTEGER REFERENCES users(id),
    task_status      TEXT
        CHECK (task_status IN ('planned','parts_ordered','parts_delivered','in_progress','done')),
    task_due_date    TEXT,
    task_assigned_to INTEGER REFERENCES users(id),
    task_parts_note  TEXT,
    created_by       INTEGER NOT NULL REFERENCES users(id),
    updated_by       INTEGER REFERENCES users(id),
    is_deleted       INTEGER NOT NULL DEFAULT 0,
    deleted_by       INTEGER REFERENCES users(id),
    deleted_at       TEXT,
    sort_order       INTEGER NOT NULL DEFAULT 0,
    created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_nb_entries_section ON notebook_entries(section_id);
CREATE INDEX IF NOT EXISTS idx_nb_entries_task_status ON notebook_entries(task_status)
    WHERE entry_type = 'task' AND is_deleted = 0;

-- ─── ENTRY PERMISSIONS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS notebook_entry_permissions (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id   INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    user_id    INTEGER NOT NULL REFERENCES users(id),
    granted_by INTEGER NOT NULL REFERENCES users(id),
    granted_at TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(entry_id, user_id)
);

-- ─── TASK-ORDER LINKS ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS task_order_links (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id   INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    po_id      INTEGER,
    status     TEXT    DEFAULT 'linked',
    created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);
  `},UE={name:"005_orders",sql:`
-- ─── JOB PARTS ORDERS (field worker requests) ───────────────
CREATE TABLE IF NOT EXISTS job_parts_orders (
    id                        INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id                    INTEGER REFERENCES jobs(id),
    order_number              TEXT    NOT NULL UNIQUE,
    status                    TEXT    NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft','pending_approval','approved','ordering',
            'partially_ordered','ordered','partially_received',
            'received','closed'
        )),
    priority                  TEXT    DEFAULT 'normal'
        CHECK (priority IN ('normal','urgent')),
    order_type                TEXT    NOT NULL DEFAULT 'job'
        CHECK (order_type IN ('job','warehouse')),
    has_special_items         INTEGER NOT NULL DEFAULT 0,
    smart_suggestions_enabled INTEGER NOT NULL DEFAULT 1,
    requested_by              INTEGER NOT NULL REFERENCES users(id),
    approved_by               INTEGER REFERENCES users(id),
    approved_at               TEXT,
    notes                     TEXT,
    created_at                TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_jpo_job ON job_parts_orders(job_id);
CREATE INDEX IF NOT EXISTS idx_jpo_status ON job_parts_orders(status);
CREATE INDEX IF NOT EXISTS idx_jpo_requested_by ON job_parts_orders(requested_by);

-- ─── JPO LINE ITEMS ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS jpo_line_items (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    jpo_id                INTEGER NOT NULL REFERENCES job_parts_orders(id) ON DELETE CASCADE,
    part_id               INTEGER NOT NULL REFERENCES parts(id),
    qty_requested         INTEGER NOT NULL DEFAULT 1,
    qty_ordered           INTEGER NOT NULL DEFAULT 0,
    qty_received          INTEGER NOT NULL DEFAULT 0,
    priority              TEXT    DEFAULT 'normal'
        CHECK (priority IN ('normal','urgent','critical')),
    entry_id              INTEGER REFERENCES notebook_entries(id),
    suggested_supplier_id INTEGER REFERENCES suppliers(id),
    notes                 TEXT,
    created_at            TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_jpo_lines_jpo ON jpo_line_items(jpo_id);

-- ─── PURCHASE ORDERS (supplier-facing) ──────────────────────
CREATE TABLE IF NOT EXISTS purchase_orders (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    po_number              TEXT    NOT NULL UNIQUE,
    supplier_id            INTEGER NOT NULL REFERENCES suppliers(id),
    status                 TEXT    NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft','submitted','acknowledged',
            'partially_received','received','closed','cancelled'
        )),
    order_date             TEXT,
    expected_delivery      TEXT,
    actual_delivery        TEXT,
    shipping_method        TEXT,
    tracking_number        TEXT,
    subtotal               REAL    DEFAULT 0,
    tax_amount             REAL    DEFAULT 0,
    shipping_cost          REAL    DEFAULT 0,
    total_cost             REAL    DEFAULT 0,
    notes                  TEXT,
    internal_notes         TEXT,
    pdf_path               TEXT,
    pdf_generated_at       TEXT,
    confirmation_checklist TEXT,
    supplier_notes         TEXT,
    submitted_by           INTEGER REFERENCES users(id),
    created_at             TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at             TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_po_supplier ON purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_po_status ON purchase_orders(status);

-- ─── PO LINE ITEMS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS po_line_items (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id                   INTEGER NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    jpo_line_id             INTEGER REFERENCES jpo_line_items(id),
    part_id                 INTEGER NOT NULL REFERENCES parts(id),
    qty_ordered             INTEGER NOT NULL,
    qty_received            INTEGER NOT NULL DEFAULT 0,
    unit_cost               REAL,
    received_unit_cost      REAL,
    status                  TEXT    DEFAULT 'pending'
        CHECK (status IN ('pending','partial','received','backordered','cancelled')),
    backorder_expected_date TEXT,
    received_at             TEXT,
    received_by             INTEGER REFERENCES users(id),
    notes                   TEXT,
    created_at              TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_po_lines_po ON po_line_items(po_id);

-- ─── RETURNS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS returns (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    return_number   TEXT    NOT NULL UNIQUE,
    return_type     TEXT    NOT NULL
        CHECK (return_type IN ('job_to_warehouse','warehouse_to_supplier')),
    po_id           INTEGER REFERENCES purchase_orders(id),
    supplier_id     INTEGER REFERENCES suppliers(id),
    job_id          INTEGER REFERENCES jobs(id),
    status          TEXT    NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft','pending_approval','approved','shipped',
            'received_by_supplier','credited','closed'
        )),
    rma_number      TEXT,
    reason          TEXT    NOT NULL
        CHECK (reason IN ('defective','wrong_item','surplus','damaged','unused')),
    shipping_carrier TEXT,
    tracking_number TEXT,
    credit_amount   REAL    DEFAULT 0,
    notes           TEXT,
    initiated_by    INTEGER NOT NULL REFERENCES users(id),
    approved_by     INTEGER REFERENCES users(id),
    approved_at     TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ─── RETURN LINE ITEMS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS return_line_items (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    return_id   INTEGER NOT NULL REFERENCES returns(id) ON DELETE CASCADE,
    part_id     INTEGER NOT NULL REFERENCES parts(id),
    po_line_id  INTEGER REFERENCES po_line_items(id),
    qty         INTEGER NOT NULL,
    condition   TEXT    DEFAULT 'new'
        CHECK (condition IN ('new','used','damaged','defective')),
    disposition TEXT    NOT NULL
        CHECK (disposition IN ('return_to_supplier','restock','write_off')),
    unit_cost   REAL,
    notes       TEXT,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ─── ORDER STATUS HISTORY ───────────────────────────────────
CREATE TABLE IF NOT EXISTS order_status_history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT    NOT NULL
        CHECK (entity_type IN ('jpo','po','return')),
    entity_id   INTEGER NOT NULL,
    old_status  TEXT,
    new_status  TEXT    NOT NULL,
    changed_by  INTEGER NOT NULL REFERENCES users(id),
    notes       TEXT,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_order_history_entity ON order_status_history(entity_type, entity_id);

-- ─── SPECIAL ITEMS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS special_items (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    jpo_id           INTEGER NOT NULL REFERENCES job_parts_orders(id) ON DELETE CASCADE,
    description      TEXT    NOT NULL,
    part_number      TEXT,
    quantity         INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit             TEXT    NOT NULL DEFAULT 'each',
    estimated_cost   REAL,
    notes            TEXT,
    is_flagged       INTEGER NOT NULL DEFAULT 1,
    flag_resolved_by INTEGER REFERENCES users(id),
    flag_resolved_at TEXT,
    linked_part_id   INTEGER REFERENCES parts(id),
    created_at       TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_special_items_jpo ON special_items(jpo_id);

-- ─── JOB PREFERENCES ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_preferences (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id           INTEGER NOT NULL REFERENCES jobs(id),
    preference_type  TEXT    NOT NULL
        CHECK (preference_type IN ('brand','color','supplier','part')),
    entity_id        INTEGER,
    text_value       TEXT,
    category         TEXT,
    is_active        INTEGER NOT NULL DEFAULT 1,
    auto_learned     INTEGER NOT NULL DEFAULT 1,
    confidence_score REAL    NOT NULL DEFAULT 0.5,
    last_used_at     TEXT,
    created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(job_id, preference_type, entity_id, text_value, category)
);
  `},PE={name:"006_fleet_tools_scheduling",sql:`
-- ═══ FLEET ═══════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS vehicles (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_number      TEXT    NOT NULL UNIQUE,
    vehicle_name        TEXT    NOT NULL,
    vehicle_type        TEXT    NOT NULL DEFAULT 'company_truck'
        CHECK (vehicle_type IN ('company_truck','company_van','company_car','private_vehicle')),
    status              TEXT    NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','inactive','maintenance','retired')),
    make                TEXT,
    model               TEXT,
    year                INTEGER,
    color               TEXT,
    vin                 TEXT,
    license_plate       TEXT,
    insurance_policy    TEXT,
    insurance_expiry    TEXT,
    registration_expiry TEXT,
    current_odometer    INTEGER DEFAULT 0,
    owner_user_id       INTEGER REFERENCES users(id),
    notes               TEXT,
    photo_path          TEXT,
    is_active           INTEGER NOT NULL DEFAULT 1,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_vehicles_active ON vehicles(is_active);

CREATE TABLE IF NOT EXISTS vehicle_assignments (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id          INTEGER NOT NULL REFERENCES vehicles(id),
    user_id             INTEGER NOT NULL REFERENCES users(id),
    assignment_type     TEXT    NOT NULL DEFAULT 'primary'
        CHECK (assignment_type IN ('primary','authorized','temporary')),
    is_take_home        INTEGER NOT NULL DEFAULT 0,
    home_to_shop_miles  REAL,
    start_date          TEXT    NOT NULL DEFAULT (date('now')),
    end_date            TEXT,
    is_active           INTEGER NOT NULL DEFAULT 1,
    notes               TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_va_vehicle ON vehicle_assignments(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_va_user ON vehicle_assignments(user_id);

-- ═══ TOOLS ══════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS tools (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_number         TEXT    NOT NULL UNIQUE,
    name                TEXT    NOT NULL,
    category            TEXT    NOT NULL DEFAULT 'general'
        CHECK (category IN (
            'power_tool','hand_tool','meter','safety',
            'conduit','cable','lighting','general'
        )),
    brand               TEXT,
    model_number        TEXT,
    serial_number       TEXT,
    purchase_date       TEXT,
    purchase_cost       REAL,
    warranty_expiry     TEXT,
    location_type       TEXT    NOT NULL DEFAULT 'warehouse'
        CHECK (location_type IN ('warehouse','truck','job')),
    location_id         INTEGER,
    assigned_to         INTEGER REFERENCES users(id),
    status              TEXT    NOT NULL DEFAULT 'available'
        CHECK (status IN (
            'available','checked_out','in_maintenance',
            'lost','retired','damaged'
        )),
    condition_rating    INTEGER DEFAULT 5
        CHECK (condition_rating BETWEEN 1 AND 5),
    has_kit             INTEGER NOT NULL DEFAULT 0,
    notes               TEXT,
    photo_path          TEXT,
    barcode             TEXT,
    is_active           INTEGER NOT NULL DEFAULT 1,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_tools_number ON tools(tool_number);
CREATE INDEX IF NOT EXISTS idx_tools_location ON tools(location_type, location_id);
CREATE INDEX IF NOT EXISTS idx_tools_assigned ON tools(assigned_to);
CREATE INDEX IF NOT EXISTS idx_tools_status ON tools(status);
CREATE INDEX IF NOT EXISTS idx_tools_barcode ON tools(barcode);

CREATE TABLE IF NOT EXISTS kit_templates (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id         INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    component_name  TEXT    NOT NULL,
    component_type  TEXT    NOT NULL DEFAULT 'accessory'
        CHECK (component_type IN (
            'charger','battery','blade','bit_set',
            'case','accessory','cable','adapter','other'
        )),
    qty_required    INTEGER NOT NULL DEFAULT 1 CHECK (qty_required >= 1),
    brand           TEXT,
    model_number    TEXT,
    is_critical     INTEGER NOT NULL DEFAULT 0,
    sort_order      INTEGER DEFAULT 0,
    notes           TEXT
);
CREATE INDEX IF NOT EXISTS idx_kit_templates_tool ON kit_templates(tool_id);

CREATE TABLE IF NOT EXISTS tool_movements (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id),
    from_location_type  TEXT,
    from_location_id    INTEGER,
    to_location_type    TEXT,
    to_location_id      INTEGER,
    movement_type       TEXT    NOT NULL
        CHECK (movement_type IN (
            'register','checkout','return','transfer',
            'maintenance_in','maintenance_out','retire','lost'
        )),
    reason              TEXT,
    job_id              INTEGER REFERENCES jobs(id),
    performed_by        INTEGER NOT NULL REFERENCES users(id),
    verified_by         INTEGER REFERENCES users(id),
    condition_at_move   INTEGER CHECK (condition_at_move BETWEEN 1 AND 5),
    created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_tool_moves_tool ON tool_movements(tool_id);

CREATE TABLE IF NOT EXISTS kit_verification_sessions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id       INTEGER NOT NULL REFERENCES tools(id),
    movement_id   INTEGER REFERENCES tool_movements(id),
    verified_by   INTEGER NOT NULL REFERENCES users(id),
    trigger_type  TEXT    NOT NULL
        CHECK (trigger_type IN ('checkout','return','audit','manual')),
    is_complete   INTEGER NOT NULL DEFAULT 0,
    missing_count INTEGER NOT NULL DEFAULT 0,
    notes         TEXT,
    created_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS kit_verification_items (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id        INTEGER NOT NULL REFERENCES kit_verification_sessions(id) ON DELETE CASCADE,
    template_item_id  INTEGER NOT NULL REFERENCES kit_templates(id),
    is_present        INTEGER NOT NULL DEFAULT 1,
    condition_rating  INTEGER CHECK (condition_rating BETWEEN 1 AND 5),
    notes             TEXT
);

CREATE TABLE IF NOT EXISTS tool_maintenance_types (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    name                   TEXT    NOT NULL UNIQUE,
    description            TEXT,
    default_interval_days  INTEGER,
    sort_order             INTEGER DEFAULT 0,
    is_active              INTEGER NOT NULL DEFAULT 1,
    created_at             TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS tool_maintenance_schedules (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    maintenance_type_id INTEGER NOT NULL REFERENCES tool_maintenance_types(id),
    interval_days       INTEGER,
    last_performed_at   TEXT,
    next_due_date       TEXT,
    is_enabled          INTEGER NOT NULL DEFAULT 1,
    notes               TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(tool_id, maintenance_type_id)
);

CREATE TABLE IF NOT EXISTS tool_maintenance_records (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id),
    maintenance_type_id INTEGER NOT NULL REFERENCES tool_maintenance_types(id),
    service_date        TEXT    NOT NULL,
    cost                REAL,
    vendor              TEXT,
    description         TEXT,
    performed_by        INTEGER REFERENCES users(id),
    notes               TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ═══ PEOPLE / CONTACTS ══════════════════════════════════════

CREATE TABLE IF NOT EXISTS customers (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT    NOT NULL,
    company_name TEXT,
    email        TEXT,
    phone        TEXT,
    address      TEXT,
    city         TEXT,
    state        TEXT,
    zip          TEXT,
    notes        TEXT,
    is_active    INTEGER DEFAULT 1,
    created_at   TEXT    DEFAULT (datetime('now')),
    updated_at   TEXT    DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS general_contractors (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    company_name  TEXT    NOT NULL,
    contact_name  TEXT,
    email         TEXT,
    phone         TEXT,
    address       TEXT,
    city          TEXT,
    state         TEXT,
    zip           TEXT,
    relationship  TEXT    DEFAULT 'we_work_for_them'
        CHECK (relationship IN ('we_work_for_them','we_hired_them','both')),
    notes         TEXT,
    is_active     INTEGER DEFAULT 1,
    created_at    TEXT    DEFAULT (datetime('now')),
    updated_at    TEXT    DEFAULT (datetime('now'))
);

-- ═══ SCHEDULING ═════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS employee_default_schedules (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day_of_week     INTEGER NOT NULL CHECK(day_of_week BETWEEN 0 AND 6),
    start_time      TEXT    DEFAULT '07:00',
    end_time        TEXT    DEFAULT '15:30',
    lunch_start     TEXT    DEFAULT NULL,
    lunch_end       TEXT    DEFAULT NULL,
    is_working_day  INTEGER DEFAULT 1,
    notes           TEXT,
    UNIQUE(user_id, day_of_week)
);
CREATE INDEX IF NOT EXISTS idx_default_sched_user ON employee_default_schedules(user_id);

CREATE TABLE IF NOT EXISTS schedule_exceptions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    exception_date  TEXT    NOT NULL,
    exception_type  TEXT    NOT NULL
        CHECK(exception_type IN (
            'time_off','sick','vacation','holiday',
            'modified_hours','unpaid_leave','jury_duty','bereavement'
        )),
    start_time      TEXT,
    end_time        TEXT,
    lunch_start     TEXT    DEFAULT NULL,
    lunch_end       TEXT    DEFAULT NULL,
    is_approved     INTEGER DEFAULT 0,
    approved_by     INTEGER REFERENCES users(id),
    approved_at     TEXT,
    reason          TEXT,
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(user_id, exception_date)
);
CREATE INDEX IF NOT EXISTS idx_sched_exc_user ON schedule_exceptions(user_id, exception_date);

CREATE TABLE IF NOT EXISTS job_dispatch (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    dispatch_date   TEXT    NOT NULL,
    shift_start     TEXT,
    shift_end       TEXT,
    lunch_start     TEXT    DEFAULT NULL,
    lunch_end       TEXT    DEFAULT NULL,
    role_on_job     TEXT    DEFAULT 'worker'
        CHECK(role_on_job IN ('lead','worker','apprentice','helper','supervisor')),
    status          TEXT    DEFAULT 'scheduled'
        CHECK(status IN (
            'scheduled','confirmed','on_site',
            'completed','no_show','cancelled'
        )),
    dispatched_by   INTEGER REFERENCES users(id),
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(user_id, dispatch_date, job_id)
);
CREATE INDEX IF NOT EXISTS idx_dispatch_date ON job_dispatch(dispatch_date);
CREATE INDEX IF NOT EXISTS idx_dispatch_user ON job_dispatch(user_id, dispatch_date);
CREATE INDEX IF NOT EXISTS idx_dispatch_job ON job_dispatch(job_id, dispatch_date);

CREATE TABLE IF NOT EXISTS subcontractor_schedules (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    gc_id           INTEGER NOT NULL REFERENCES general_contractors(id) ON DELETE CASCADE,
    scheduled_date  TEXT    NOT NULL,
    arrival_time    TEXT,
    departure_time  TEXT,
    scope_of_work   TEXT,
    status          TEXT    DEFAULT 'scheduled'
        CHECK(status IN ('scheduled','confirmed','completed','cancelled','no_show')),
    notes           TEXT,
    created_by      INTEGER REFERENCES users(id),
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(job_id, gc_id, scheduled_date)
);
  `},ME={name:"007_chat",sql:`
-- ═══ CHAT CHANNELS ═══════════════════════════════════════════

CREATE TABLE IF NOT EXISTS chat_channels (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_type    TEXT    NOT NULL DEFAULT 'job'
        CHECK (channel_type IN ('job','dm','group')),
    job_id          INTEGER REFERENCES jobs(id),
    name            TEXT,
    created_by      INTEGER NOT NULL REFERENCES users(id),
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_chat_channels_job ON chat_channels(job_id);
CREATE INDEX IF NOT EXISTS idx_chat_channels_type ON chat_channels(channel_type);

CREATE TABLE IF NOT EXISTS chat_channel_members (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id      INTEGER NOT NULL REFERENCES chat_channels(id),
    user_id         INTEGER NOT NULL REFERENCES users(id),
    role            TEXT    NOT NULL DEFAULT 'member'
        CHECK (role IN ('admin','member','observer')),
    muted_until     TEXT,
    joined_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    left_at         TEXT,
    UNIQUE(channel_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_ccm_channel ON chat_channel_members(channel_id);
CREATE INDEX IF NOT EXISTS idx_ccm_user ON chat_channel_members(user_id);

-- ═══ Q&A THREADS ═════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS qa_threads (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id      INTEGER REFERENCES chat_channels(id),
    job_id          INTEGER NOT NULL REFERENCES jobs(id),
    asked_by        INTEGER NOT NULL REFERENCES users(id),
    subject         TEXT    NOT NULL,
    current_level   TEXT    NOT NULL DEFAULT 'worker'
        CHECK (current_level IN ('worker','lead','foreman','supervisor','office')),
    assigned_to     INTEGER REFERENCES users(id),
    status          TEXT    NOT NULL DEFAULT 'open'
        CHECK (status IN ('open','escalated','answered','closed','rfi_sent')),
    priority        TEXT    NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low','normal','high','urgent')),
    answer_text     TEXT,
    answered_by     INTEGER REFERENCES users(id),
    answered_at     TEXT,
    closed_at       TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_qa_job ON qa_threads(job_id);
CREATE INDEX IF NOT EXISTS idx_qa_status ON qa_threads(status);
CREATE INDEX IF NOT EXISTS idx_qa_assigned ON qa_threads(assigned_to);

-- ═══ CHAT MESSAGES ═══════════════════════════════════════════

CREATE TABLE IF NOT EXISTS chat_messages (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id      INTEGER NOT NULL REFERENCES chat_channels(id),
    sender_id       INTEGER NOT NULL REFERENCES users(id),
    message_type    TEXT    NOT NULL DEFAULT 'text'
        CHECK (message_type IN ('text','photo','system','qa_question','qa_answer','qa_escalation')),
    content         TEXT,
    media_path      TEXT,
    reply_to_id     INTEGER REFERENCES chat_messages(id),
    pinned_at       TEXT,
    pinned_by       INTEGER REFERENCES users(id),
    qa_thread_id    INTEGER REFERENCES qa_threads(id),
    qa_level        TEXT,
    edited_at       TEXT,
    deleted_at      TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_cm_channel ON chat_messages(channel_id, created_at);
CREATE INDEX IF NOT EXISTS idx_cm_sender ON chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_cm_qa ON chat_messages(qa_thread_id);

-- ═══ READ RECEIPTS ═══════════════════════════════════════════

CREATE TABLE IF NOT EXISTS chat_read_receipts (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id          INTEGER NOT NULL REFERENCES chat_channels(id),
    user_id             INTEGER NOT NULL REFERENCES users(id),
    last_read_message_id INTEGER NOT NULL,
    read_at             TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(channel_id, user_id)
);

-- ═══ MENTIONS ════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS chat_mentions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id          INTEGER NOT NULL REFERENCES chat_messages(id),
    mentioned_user_id   INTEGER NOT NULL REFERENCES users(id),
    acknowledged_at     TEXT
);
CREATE INDEX IF NOT EXISTS idx_mentions_user ON chat_mentions(mentioned_user_id, acknowledged_at);

-- ═══ RFI OBJECTS ═════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rfi_objects (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    qa_thread_id    INTEGER NOT NULL REFERENCES qa_threads(id),
    job_id          INTEGER NOT NULL REFERENCES jobs(id),
    gc_contact_id   INTEGER,
    subject         TEXT    NOT NULL,
    body            TEXT    NOT NULL,
    status          TEXT    NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','sent','responded','closed')),
    response_text   TEXT,
    responded_at    TEXT,
    sent_via        TEXT
        CHECK (sent_via IS NULL OR sent_via IN ('sms','email','in_person','other')),
    sent_at         TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_rfi_qa ON rfi_objects(qa_thread_id);
CREATE INDEX IF NOT EXISTS idx_rfi_job ON rfi_objects(job_id);
CREATE INDEX IF NOT EXISTS idx_rfi_status ON rfi_objects(status);
  `},XE={name:"008_soft_delete_and_sync",sql:`
-- ═══════════════════════════════════════════════════════════════════
-- PART 1: Add deleted_at to all mutable user-facing tables
-- ═══════════════════════════════════════════════════════════════════

-- Foundation
ALTER TABLE users ADD COLUMN deleted_at TEXT;
ALTER TABLE user_hats ADD COLUMN deleted_at TEXT;
ALTER TABLE devices ADD COLUMN deleted_at TEXT;
ALTER TABLE notifications ADD COLUMN deleted_at TEXT;
ALTER TABLE notification_preferences ADD COLUMN deleted_at TEXT;
ALTER TABLE job_lead_elevations ADD COLUMN deleted_at TEXT;

-- Parts & Inventory
ALTER TABLE part_categories ADD COLUMN deleted_at TEXT;
ALTER TABLE part_styles ADD COLUMN deleted_at TEXT;
ALTER TABLE part_types ADD COLUMN deleted_at TEXT;
ALTER TABLE part_colors ADD COLUMN deleted_at TEXT;
ALTER TABLE brands ADD COLUMN deleted_at TEXT;
ALTER TABLE suppliers ADD COLUMN deleted_at TEXT;
ALTER TABLE parts ADD COLUMN deleted_at TEXT;
ALTER TABLE brand_supplier_links ADD COLUMN deleted_at TEXT;
ALTER TABLE part_supplier_links ADD COLUMN deleted_at TEXT;
ALTER TABLE stock ADD COLUMN deleted_at TEXT;
ALTER TABLE stock_movements ADD COLUMN deleted_at TEXT;
ALTER TABLE pulled_staging_tags ADD COLUMN deleted_at TEXT;

-- Jobs & Labor
ALTER TABLE jobs ADD COLUMN deleted_at TEXT;
ALTER TABLE job_parts ADD COLUMN deleted_at TEXT;
ALTER TABLE labor_entries ADD COLUMN deleted_at TEXT;
ALTER TABLE clock_out_responses ADD COLUMN deleted_at TEXT;
ALTER TABLE one_time_questions ADD COLUMN deleted_at TEXT;
ALTER TABLE daily_reports ADD COLUMN deleted_at TEXT;

-- Notebooks
ALTER TABLE notebook_templates ADD COLUMN deleted_at TEXT;
ALTER TABLE template_sections ADD COLUMN deleted_at TEXT;
ALTER TABLE template_entries ADD COLUMN deleted_at TEXT;
ALTER TABLE notebooks ADD COLUMN deleted_at TEXT;
ALTER TABLE notebook_sections ADD COLUMN deleted_at TEXT;
ALTER TABLE notebook_entries ADD COLUMN deleted_at TEXT;
ALTER TABLE notebook_entry_permissions ADD COLUMN deleted_at TEXT;
ALTER TABLE task_order_links ADD COLUMN deleted_at TEXT;

-- Orders
ALTER TABLE job_parts_orders ADD COLUMN deleted_at TEXT;
ALTER TABLE jpo_line_items ADD COLUMN deleted_at TEXT;
ALTER TABLE purchase_orders ADD COLUMN deleted_at TEXT;
ALTER TABLE po_line_items ADD COLUMN deleted_at TEXT;
ALTER TABLE returns ADD COLUMN deleted_at TEXT;
ALTER TABLE return_line_items ADD COLUMN deleted_at TEXT;
ALTER TABLE special_items ADD COLUMN deleted_at TEXT;
ALTER TABLE job_preferences ADD COLUMN deleted_at TEXT;

-- Fleet, Tools & Scheduling
ALTER TABLE vehicles ADD COLUMN deleted_at TEXT;
ALTER TABLE vehicle_assignments ADD COLUMN deleted_at TEXT;
ALTER TABLE tools ADD COLUMN deleted_at TEXT;
ALTER TABLE kit_templates ADD COLUMN deleted_at TEXT;
ALTER TABLE tool_movements ADD COLUMN deleted_at TEXT;
ALTER TABLE kit_verification_sessions ADD COLUMN deleted_at TEXT;
ALTER TABLE kit_verification_items ADD COLUMN deleted_at TEXT;
ALTER TABLE tool_maintenance_types ADD COLUMN deleted_at TEXT;
ALTER TABLE tool_maintenance_schedules ADD COLUMN deleted_at TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN deleted_at TEXT;
ALTER TABLE customers ADD COLUMN deleted_at TEXT;
ALTER TABLE general_contractors ADD COLUMN deleted_at TEXT;
ALTER TABLE employee_default_schedules ADD COLUMN deleted_at TEXT;
ALTER TABLE schedule_exceptions ADD COLUMN deleted_at TEXT;
ALTER TABLE job_dispatch ADD COLUMN deleted_at TEXT;
ALTER TABLE subcontractor_schedules ADD COLUMN deleted_at TEXT;

-- Chat
ALTER TABLE chat_channels ADD COLUMN deleted_at TEXT;
ALTER TABLE chat_channel_members ADD COLUMN deleted_at TEXT;
ALTER TABLE qa_threads ADD COLUMN deleted_at TEXT;
ALTER TABLE chat_messages ADD COLUMN deleted_at TEXT;
ALTER TABLE chat_read_receipts ADD COLUMN deleted_at TEXT;
ALTER TABLE chat_mentions ADD COLUMN deleted_at TEXT;
ALTER TABLE rfi_objects ADD COLUMN deleted_at TEXT;

-- ═══════════════════════════════════════════════════════════════════
-- PART 2: Sync infrastructure tables
-- ═══════════════════════════════════════════════════════════════════

-- Conflict log — records every LWW overwrite so admins can review
CREATE TABLE IF NOT EXISTS _conflict_log (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name    TEXT    NOT NULL,
    record_id     TEXT    NOT NULL,
    field_name    TEXT    NOT NULL,
    local_value   TEXT,
    remote_value  TEXT,
    winner        TEXT    NOT NULL CHECK (winner IN ('local', 'remote')),
    local_device  TEXT    NOT NULL,
    remote_device TEXT    NOT NULL,
    local_ts      TEXT    NOT NULL,
    remote_ts     TEXT    NOT NULL,
    resolved_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    reviewed      INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_conflict_log_table ON _conflict_log(table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_conflict_log_unreviewed ON _conflict_log(reviewed) WHERE reviewed = 0;

-- Vector clock — tracks what each peer device has already seen
-- Enables efficient delta sync (only send changes the other device hasn't seen)
CREATE TABLE IF NOT EXISTS _vector_clock (
    device_id     TEXT    NOT NULL,
    peer_id       TEXT    NOT NULL,
    last_sequence INTEGER NOT NULL DEFAULT 0,
    updated_at    TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (device_id, peer_id)
);

-- Device registry — known peer devices for sync
CREATE TABLE IF NOT EXISTS _device_registry (
    device_id      TEXT PRIMARY KEY,
    device_name    TEXT,
    platform       TEXT,
    role           TEXT    CHECK (role IN ('office', 'field', 'admin')),
    certificate    TEXT,
    last_seen_at   TEXT,
    last_sync_at   TEXT,
    is_trusted     INTEGER NOT NULL DEFAULT 0,
    is_deactivated INTEGER NOT NULL DEFAULT 0,
    created_at     TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Add sequence number to change log for vector clock sync
ALTER TABLE _change_log ADD COLUMN sequence INTEGER;

-- Create auto-incrementing sequence trigger for change log
-- (sequence is device-local, monotonically increasing)
CREATE TRIGGER IF NOT EXISTS trg_change_log_sequence
    AFTER INSERT ON _change_log
    WHEN NEW.sequence IS NULL
BEGIN
    UPDATE _change_log
    SET sequence = (SELECT COALESCE(MAX(sequence), 0) + 1 FROM _change_log)
    WHERE id = NEW.id;
END;
  `},qE={name:"009_people_full",sql:`
-- ═══════════════════════════════════════════════════════════════════
-- CERTIFICATIONS — tracking with expiry dates
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS certifications (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id           INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    cert_type         TEXT    NOT NULL
                      CHECK(cert_type IN (
                          'journeyman', 'apprentice', 'master',
                          'osha_10', 'osha_30',
                          'first_aid', 'cpr',
                          'forklift', 'confined_space',
                          'custom'
                      )),
    cert_name         TEXT    NOT NULL,
    issuing_authority TEXT,
    cert_number       TEXT,
    issued_date       TEXT,
    expiry_date       TEXT,
    is_active         INTEGER DEFAULT 1,
    notes             TEXT,
    document_path     TEXT,
    deleted_at        TEXT,
    created_at        TEXT    DEFAULT (datetime('now')),
    updated_at        TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_certifications_user   ON certifications(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_certifications_expiry ON certifications(expiry_date);
CREATE INDEX IF NOT EXISTS idx_certifications_type   ON certifications(cert_type);


-- ═══════════════════════════════════════════════════════════════════
-- WAGE HISTORY — immutable pay rate audit trail
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS wage_history (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id        INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pay_rate       REAL    NOT NULL,
    effective_date TEXT    NOT NULL,
    reason         TEXT    CHECK(reason IN (
                       'hire', 'raise', 'promotion', 'demotion',
                       'adjustment', 'correction', NULL
                   )),
    changed_by     INTEGER REFERENCES users(id),
    created_at     TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_wage_history_user ON wage_history(user_id, effective_date DESC);


-- ═══════════════════════════════════════════════════════════════════
-- EMPLOYEE NOTES — HR-style record keeping
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS employee_notes (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    note_type  TEXT    DEFAULT 'general'
               CHECK(note_type IN (
                   'general', 'performance', 'incident',
                   'commendation', 'training', 'disciplinary'
               )),
    title      TEXT    NOT NULL,
    body       TEXT    NOT NULL,
    is_private INTEGER DEFAULT 0,
    created_by INTEGER REFERENCES users(id),
    deleted_at TEXT,
    created_at TEXT    DEFAULT (datetime('now')),
    updated_at TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_employee_notes_user ON employee_notes(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_employee_notes_type ON employee_notes(note_type);


-- ═══════════════════════════════════════════════════════════════════
-- USER SKILLS — proficiency tracking per employee
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS user_skills (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id          INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    skill_name       TEXT    NOT NULL,
    proficiency      TEXT    DEFAULT 'intermediate'
                     CHECK(proficiency IN (
                         'beginner', 'intermediate', 'advanced', 'expert'
                     )),
    years_experience REAL,
    verified_by      INTEGER REFERENCES users(id),
    verified_at      TEXT,
    deleted_at       TEXT,
    created_at       TEXT    DEFAULT (datetime('now')),
    UNIQUE(user_id, skill_name)
);

CREATE INDEX IF NOT EXISTS idx_user_skills_user  ON user_skills(user_id);
CREATE INDEX IF NOT EXISTS idx_user_skills_skill ON user_skills(skill_name);


-- ═══════════════════════════════════════════════════════════════════
-- EMPLOYEE TEAMS — global team definitions
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS employee_teams (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL UNIQUE,
    description  TEXT,
    lead_user_id INTEGER REFERENCES users(id),
    is_active    INTEGER NOT NULL DEFAULT 1,
    deleted_at   TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ═══════════════════════════════════════════════════════════════════
-- EMPLOYEE TEAM MEMBERS — team membership junction
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS employee_team_members (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    team_id   INTEGER NOT NULL REFERENCES employee_teams(id) ON DELETE CASCADE,
    user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role      TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('lead', 'member')),
    joined_at  TEXT NOT NULL DEFAULT (datetime('now')),
    deleted_at TEXT,
    UNIQUE(team_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_team_members_team ON employee_team_members(team_id);
CREATE INDEX IF NOT EXISTS idx_team_members_user ON employee_team_members(user_id);
  `},GE={name:"010_costs_receiving",sql:`
-- ═══════════════════════════════════════════════════════════════════
-- BILLING PERIODS — period locking
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS billing_periods (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id       INTEGER REFERENCES jobs(id),
    period_start TEXT    NOT NULL,
    period_end   TEXT    NOT NULL,
    locked_at    TEXT,
    locked_by    INTEGER REFERENCES users(id),
    notes        TEXT,
    deleted_at   TEXT,
    created_at   TEXT    DEFAULT (datetime('now')),
    updated_at   TEXT    DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_billing_periods_job_range
    ON billing_periods(COALESCE(job_id, 0), period_start, period_end);
CREATE INDEX IF NOT EXISTS idx_billing_periods_job
    ON billing_periods(job_id);


-- ═══════════════════════════════════════════════════════════════════
-- RECEIVING SESSIONS — session-based receiving workflow
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS receiving_sessions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id       INTEGER NOT NULL REFERENCES purchase_orders(id),
    started_by  INTEGER NOT NULL REFERENCES users(id),
    mode        TEXT NOT NULL DEFAULT 'packing_slip'
                CHECK (mode IN ('packing_slip', 'scan')),
    status      TEXT NOT NULL DEFAULT 'in_progress'
                CHECK (status IN ('in_progress', 'completed', 'cancelled')),
    completed_at TEXT,
    notes       TEXT,
    deleted_at  TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_recv_sessions_po ON receiving_sessions(po_id);
CREATE INDEX IF NOT EXISTS idx_recv_sessions_status ON receiving_sessions(status);


-- ═══════════════════════════════════════════════════════════════════
-- RECEIVING SESSION ITEMS — per-line receiving entries
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS receiving_session_items (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id   INTEGER NOT NULL REFERENCES receiving_sessions(id) ON DELETE CASCADE,
    po_line_id   INTEGER NOT NULL REFERENCES po_line_items(id),
    expected_qty INTEGER NOT NULL DEFAULT 0,
    received_qty INTEGER NOT NULL DEFAULT 0,
    actual_cost  REAL,
    scanned_at   TEXT,
    notes        TEXT,
    deleted_at   TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_recv_items_session ON receiving_session_items(session_id);
CREATE INDEX IF NOT EXISTS idx_recv_items_po_line ON receiving_session_items(po_line_id);


-- ═══════════════════════════════════════════════════════════════════
-- ALTER return_line_items — sorting guidance columns
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE return_line_items ADD COLUMN returnable_to_supplier INTEGER DEFAULT 1;
ALTER TABLE return_line_items ADD COLUMN non_return_reason TEXT;
ALTER TABLE return_line_items ADD COLUMN below_target_flag INTEGER DEFAULT 0;
  `},BE={name:"011_reports_pto",sql:`
-- ═══════════════════════════════════════════════════════════════════
-- REPORT ANNOTATIONS — post-generation notes on any report
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS report_annotations (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    report_type TEXT NOT NULL,
    context_key TEXT NOT NULL,
    content     TEXT NOT NULL,
    author_id   INTEGER NOT NULL REFERENCES users(id),
    deleted_at  TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_report_annotations_lookup
    ON report_annotations(report_type, context_key);


-- ═══════════════════════════════════════════════════════════════════
-- REPORT SHARE TOKENS — shareable links for external parties
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS report_share_tokens (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    token           TEXT NOT NULL UNIQUE,
    report_type     TEXT NOT NULL,
    context_params  TEXT NOT NULL DEFAULT '{}',
    label           TEXT,
    created_by      INTEGER NOT NULL REFERENCES users(id),
    expires_at      TEXT,
    last_accessed_at TEXT,
    is_active       INTEGER NOT NULL DEFAULT 1,
    deleted_at      TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_report_share_tokens_token
    ON report_share_tokens(token);


-- ═══════════════════════════════════════════════════════════════════
-- REPORT TEMPLATES — saved filter presets
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS report_templates (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    report_type TEXT NOT NULL,
    config_json TEXT NOT NULL DEFAULT '{}',
    created_by  INTEGER NOT NULL REFERENCES users(id),
    deleted_at  TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ═══════════════════════════════════════════════════════════════════
-- PTO POLICIES — per-employee PTO policy configuration
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS pto_policies (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id        INTEGER NOT NULL REFERENCES users(id),
    policy_name    TEXT NOT NULL DEFAULT 'Standard PTO',
    accrual_rate   REAL NOT NULL DEFAULT 3.33,
    accrual_period TEXT NOT NULL DEFAULT 'biweekly'
        CHECK(accrual_period IN ('weekly', 'biweekly', 'monthly')),
    max_balance     REAL,
    carryover_limit REAL,
    start_date      TEXT NOT NULL,
    is_active       INTEGER NOT NULL DEFAULT 1,
    deleted_at      TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pto_policies_user_active
    ON pto_policies(user_id) WHERE is_active = 1;


-- ═══════════════════════════════════════════════════════════════════
-- PTO TRANSACTIONS — accruals, usage, adjustments, carryover
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS pto_transactions (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id          INTEGER NOT NULL REFERENCES users(id),
    transaction_type TEXT NOT NULL
        CHECK(transaction_type IN ('accrual', 'usage', 'adjustment', 'carryover', 'forfeit')),
    hours            REAL NOT NULL,
    balance_after    REAL NOT NULL,
    reference_id     INTEGER,
    reference_type   TEXT,
    note             TEXT,
    effective_date   TEXT NOT NULL,
    created_by       INTEGER REFERENCES users(id),
    deleted_at       TEXT,
    created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_pto_transactions_user
    ON pto_transactions(user_id, effective_date);
  `},$E={name:"012_warehouse_attachments",sql:`
-- ═══════════════════════════════════════════════════════════════════
-- JOB TRAILERS — trailer master records
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS job_trailers (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    trailer_code            TEXT NOT NULL UNIQUE,
    name                    TEXT NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'active'
                            CHECK(status IN ('active', 'in_transit', 'maintenance', 'inactive')),
    current_job_id          INTEGER REFERENCES jobs(id),
    assigned_driver_user_id INTEGER REFERENCES users(id),
    notes                   TEXT,
    is_active               INTEGER NOT NULL DEFAULT 1,
    deleted_at              TEXT,
    created_at              TEXT DEFAULT (datetime('now')),
    updated_at              TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_job_trailers_code ON job_trailers(trailer_code);
CREATE INDEX IF NOT EXISTS idx_job_trailers_status ON job_trailers(status);
CREATE INDEX IF NOT EXISTS idx_job_trailers_current_job ON job_trailers(current_job_id);
CREATE INDEX IF NOT EXISTS idx_job_trailers_active ON job_trailers(is_active);


-- ═══════════════════════════════════════════════════════════════════
-- TRAILER LOCATION EVENTS — current + history location tracking
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS trailer_location_events (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    trailer_id    INTEGER NOT NULL REFERENCES job_trailers(id) ON DELETE CASCADE,
    event_type    TEXT NOT NULL DEFAULT 'manual_update'
                  CHECK(event_type IN ('check_in', 'departed', 'arrived_job', 'arrived_warehouse', 'manual_update')),
    location_kind TEXT NOT NULL DEFAULT 'other'
                  CHECK(location_kind IN ('warehouse', 'job', 'road', 'other')),
    job_id        INTEGER REFERENCES jobs(id),
    lat           REAL,
    lng           REAL,
    recorded_by   INTEGER NOT NULL REFERENCES users(id),
    recorded_at   TEXT DEFAULT (datetime('now')),
    notes         TEXT
);

CREATE INDEX IF NOT EXISTS idx_trailer_loc_events_trailer ON trailer_location_events(trailer_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_trailer_loc_events_kind ON trailer_location_events(location_kind);
CREATE INDEX IF NOT EXISTS idx_trailer_loc_events_job ON trailer_location_events(job_id);


-- ═══════════════════════════════════════════════════════════════════
-- ORDER ATTACHMENTS — polymorphic attachments for JPOs, POs, Returns
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS order_attachments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT    NOT NULL CHECK(entity_type IN ('jpo', 'po', 'return')),
    entity_id   INTEGER NOT NULL,
    file_path   TEXT    NOT NULL,
    file_name   TEXT    NOT NULL,
    file_type   TEXT,
    file_size   INTEGER,
    description TEXT,
    uploaded_by INTEGER REFERENCES users(id),
    deleted_at  TEXT,
    created_at  TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_order_attachments_entity
    ON order_attachments(entity_type, entity_id);
  `},HE={name:"013_tools_supplier_extras",sql:`
-- ═══════════════════════════════════════════════════════════════════
-- ALTER tools — depreciation + calibration columns
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE tools ADD COLUMN depreciation_method TEXT
    CHECK (depreciation_method IS NULL OR depreciation_method IN (
        'straight_line', 'declining_balance', 'sum_of_years'
    ));
ALTER TABLE tools ADD COLUMN salvage_value REAL DEFAULT 0;
ALTER TABLE tools ADD COLUMN useful_life_years INTEGER;
ALTER TABLE tools ADD COLUMN calibration_due_date TEXT;


-- ═══════════════════════════════════════════════════════════════════
-- ALTER tool_maintenance_records — calibration tracking fields
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_certificate TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_provider TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_standard TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_result TEXT
    CHECK (calibration_result IS NULL OR calibration_result IN (
        'pass', 'fail', 'adjusted', 'out_of_tolerance'
    ));


-- ═══════════════════════════════════════════════════════════════════
-- TOOL DEPRECIATION ENTRIES — annual depreciation schedule
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS tool_depreciation_entries (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    year_number         INTEGER NOT NULL,
    fiscal_year         TEXT    NOT NULL,
    beginning_value     REAL    NOT NULL,
    depreciation_amount REAL    NOT NULL,
    accumulated         REAL    NOT NULL,
    ending_value        REAL    NOT NULL,
    deleted_at          TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(tool_id, year_number)
);

CREATE INDEX IF NOT EXISTS idx_tool_depr_tool ON tool_depreciation_entries(tool_id);
CREATE INDEX IF NOT EXISTS idx_tool_depr_year ON tool_depreciation_entries(fiscal_year);


-- ═══════════════════════════════════════════════════════════════════
-- NOTEBOOK ENTRY TOOLS — link notebook tasks to required tools
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS notebook_entry_tools (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id   INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    tool_id    INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    notes      TEXT,
    created_by INTEGER NOT NULL REFERENCES users(id),
    deleted_at TEXT,
    created_at TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(entry_id, tool_id)
);

CREATE INDEX IF NOT EXISTS idx_nb_entry_tools_entry ON notebook_entry_tools(entry_id);
CREATE INDEX IF NOT EXISTS idx_nb_entry_tools_tool  ON notebook_entry_tools(tool_id);


-- ═══════════════════════════════════════════════════════════════════
-- SUPPLIER PORTAL TOKENS — access tokens for supplier portal
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS supplier_portal_tokens (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    supplier_id  INTEGER NOT NULL REFERENCES suppliers(id),
    token        TEXT    NOT NULL UNIQUE,
    note         TEXT,
    is_active    INTEGER NOT NULL DEFAULT 1,
    expires_at   TEXT,
    last_used_at TEXT,
    created_by   INTEGER REFERENCES users(id),
    deleted_at   TEXT,
    created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_supplier_portal_tokens_supplier
    ON supplier_portal_tokens(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_portal_tokens_token
    ON supplier_portal_tokens(token);


-- ═══════════════════════════════════════════════════════════════════
-- SUPPLIER PO ACKNOWLEDGMENTS — supplier acknowledgment tracking
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS supplier_po_acknowledgments (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id              INTEGER NOT NULL REFERENCES purchase_orders(id),
    supplier_id        INTEGER NOT NULL REFERENCES suppliers(id),
    token_id           INTEGER REFERENCES supplier_portal_tokens(id),
    estimated_delivery TEXT,
    supplier_notes     TEXT,
    acknowledged_at    TEXT NOT NULL DEFAULT (datetime('now')),
    deleted_at         TEXT,
    UNIQUE(po_id)
);
  `},WE={name:"014_contacts_costs_profiles",sql:`
-- ═══════════════════════════════════════════════════════════════════
-- ENTITY CONTACTS — contacts for customers, GCs, suppliers
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS entity_contacts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT    NOT NULL
                CHECK(entity_type IN ('customer', 'general_contractor', 'supplier')),
    entity_id   INTEGER NOT NULL,
    first_name  TEXT    NOT NULL,
    last_name   TEXT    NOT NULL DEFAULT '',
    role        TEXT    NOT NULL,
    phone       TEXT    NOT NULL,
    email       TEXT,
    is_primary  INTEGER DEFAULT 0,
    notes       TEXT,
    is_active   INTEGER DEFAULT 1,
    deleted_at  TEXT,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_entity_contacts_entity ON entity_contacts(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_contacts_name   ON entity_contacts(last_name, first_name);


-- ═══════════════════════════════════════════════════════════════════
-- JOB ↔ CUSTOMER (many-to-many)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS job_customers (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id        INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    customer_id   INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    contact_role  TEXT    DEFAULT 'owner'
                  CHECK(contact_role IN (
                      'owner', 'property_manager', 'tenant',
                      'site_contact', 'billing', 'other'
                  )),
    is_primary    INTEGER DEFAULT 0,
    notes         TEXT,
    deleted_at    TEXT,
    created_at    TEXT    DEFAULT (datetime('now')),
    UNIQUE(job_id, customer_id, contact_role)
);

CREATE INDEX IF NOT EXISTS idx_job_customers_job      ON job_customers(job_id);
CREATE INDEX IF NOT EXISTS idx_job_customers_customer  ON job_customers(customer_id);


-- ═══════════════════════════════════════════════════════════════════
-- JOB ↔ GENERAL CONTRACTORS (many-to-many)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS job_general_contractors (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    gc_id           INTEGER NOT NULL REFERENCES general_contractors(id) ON DELETE CASCADE,
    relationship    TEXT    NOT NULL
                    CHECK(relationship IN ('they_are_gc', 'we_hired_them')),
    contract_amount REAL,
    contract_number TEXT,
    is_primary      INTEGER DEFAULT 0,
    notes           TEXT,
    deleted_at      TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(job_id, gc_id)
);

CREATE INDEX IF NOT EXISTS idx_job_gc_job  ON job_general_contractors(job_id);
CREATE INDEX IF NOT EXISTS idx_job_gc_gc   ON job_general_contractors(gc_id);
CREATE INDEX IF NOT EXISTS idx_job_gc_rel  ON job_general_contractors(relationship);


-- ═══════════════════════════════════════════════════════════════════
-- COST LAYERS — FIFO/LIFO inventory cost tracking
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS cost_layers (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id       INTEGER NOT NULL REFERENCES parts(id),
    purchase_date TEXT    NOT NULL,
    po_line_id    INTEGER REFERENCES po_line_items(id),
    original_qty  INTEGER NOT NULL,
    remaining_qty INTEGER NOT NULL,
    unit_cost     REAL    NOT NULL,
    created_at    TEXT    DEFAULT (datetime('now')),
    CHECK(remaining_qty >= 0)
);

CREATE INDEX IF NOT EXISTS idx_cost_layers_part ON cost_layers(part_id, remaining_qty);
CREATE INDEX IF NOT EXISTS idx_cost_layers_date ON cost_layers(part_id, purchase_date);


-- ═══════════════════════════════════════════════════════════════════
-- COMPANY COST SETTINGS — margin & pricing defaults
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS company_cost_settings (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    setting_key   TEXT UNIQUE NOT NULL,
    setting_value TEXT NOT NULL,
    updated_by    INTEGER REFERENCES users(id),
    updated_at    TEXT DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO company_cost_settings (setting_key, setting_value)
VALUES
    ('default_margin_percent', '25'),
    ('cost_method', 'weighted_average'),
    ('auto_update_pricing', 'true');


-- ═══════════════════════════════════════════════════════════════════
-- COMPANY PROFILES — company/branch info for PDF headers
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS company_profiles (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    name               TEXT NOT NULL,
    address_street     TEXT,
    address_city       TEXT,
    address_state      TEXT,
    address_zip        TEXT,
    phone              TEXT,
    email              TEXT,
    website            TEXT,
    logo_path          TEXT,
    contractor_license TEXT,
    insurance_info     TEXT,
    tax_id             TEXT,
    is_primary         INTEGER NOT NULL DEFAULT 0,
    branch_name        TEXT,
    notes              TEXT,
    deleted_at         TEXT,
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at         TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ═══════════════════════════════════════════════════════════════════
-- ALTER PARTS — cost tracking columns
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE parts ADD COLUMN weighted_avg_cost REAL DEFAULT 0;
ALTER TABLE parts ADD COLUMN custom_margin_percent REAL;
ALTER TABLE parts ADD COLUMN cost_last_updated TEXT;


-- ═══════════════════════════════════════════════════════════════════
-- ALTER JOBS — budget tracking columns
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE jobs ADD COLUMN budget_limit REAL;
ALTER TABLE jobs ADD COLUMN budget_alert_percent REAL DEFAULT 80;
  `},KE={name:"015_job_team_suppliers",sql:`
-- ─── JOB TEAM MEMBERS ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_team_members (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id      INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    role        TEXT    NOT NULL DEFAULT 'member'
                  CHECK (role IN ('lead', 'member')),
    assigned_at TEXT    NOT NULL DEFAULT (datetime('now')),
    assigned_by INTEGER REFERENCES users(id),
    notes       TEXT,
    deleted_at  TEXT,
    UNIQUE (job_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_jtm_job ON job_team_members(job_id);
CREATE INDEX IF NOT EXISTS idx_jtm_user ON job_team_members(user_id);

-- ─── EXPLICIT PREFERRED SUPPLIERS PER JOB ─────────────────────
-- Separate from job_preferences which tracks auto-learned prefs.
-- This stores manually-set supplier rankings (primary, backup1, backup2).
CREATE TABLE IF NOT EXISTS job_preferred_suppliers (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id      INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
    rank        INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    deleted_at  TEXT,
    UNIQUE (job_id, supplier_id)
);
CREATE INDEX IF NOT EXISTS idx_jps_job ON job_preferred_suppliers(job_id);
  `},YE={name:"016_companions_alternatives",sql:`
-- ─── TYPE ↔ COLOR LINKS ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS type_color_links (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    type_id     INTEGER NOT NULL REFERENCES part_types(id) ON DELETE CASCADE,
    color_id    INTEGER NOT NULL REFERENCES part_colors(id) ON DELETE CASCADE,
    image_url   TEXT,
    sort_order  INTEGER DEFAULT 0,
    created_at  TEXT    DEFAULT (datetime('now')),
    UNIQUE(type_id, color_id)
);
CREATE INDEX IF NOT EXISTS idx_tcl_type ON type_color_links(type_id);
CREATE INDEX IF NOT EXISTS idx_tcl_color ON type_color_links(color_id);

-- ─── TYPE ↔ BRAND LINKS ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS type_brand_links (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    type_id    INTEGER NOT NULL REFERENCES part_types(id) ON DELETE CASCADE,
    brand_id   INTEGER REFERENCES brands(id) ON DELETE CASCADE,
    created_at TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_tbl_type  ON type_brand_links(type_id);
CREATE INDEX IF NOT EXISTS idx_tbl_brand ON type_brand_links(brand_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tbl_unique_type_brand
    ON type_brand_links(type_id, COALESCE(brand_id, 0));

-- ─── COMPANION RULES ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS companion_rules (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT NOT NULL,
    description     TEXT,
    style_match     TEXT NOT NULL DEFAULT 'auto'
                    CHECK(style_match IN ('auto', 'any', 'explicit')),
    qty_mode        TEXT NOT NULL DEFAULT 'sum'
                    CHECK(qty_mode IN ('sum', 'max', 'ratio')),
    qty_ratio       REAL DEFAULT 1.0,
    is_active       INTEGER DEFAULT 1,
    created_by      INTEGER REFERENCES users(id),
    created_at      TEXT DEFAULT (datetime('now')),
    updated_at      TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS companion_rule_sources (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id         INTEGER NOT NULL REFERENCES companion_rules(id) ON DELETE CASCADE,
    category_id     INTEGER NOT NULL REFERENCES part_categories(id),
    style_id        INTEGER REFERENCES part_styles(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_crs_unique ON companion_rule_sources(rule_id, category_id, COALESCE(style_id, 0));
CREATE INDEX IF NOT EXISTS idx_crs_rule ON companion_rule_sources(rule_id);

CREATE TABLE IF NOT EXISTS companion_rule_targets (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id         INTEGER NOT NULL REFERENCES companion_rules(id) ON DELETE CASCADE,
    category_id     INTEGER NOT NULL REFERENCES part_categories(id),
    style_id        INTEGER REFERENCES part_styles(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_crt_unique ON companion_rule_targets(rule_id, category_id, COALESCE(style_id, 0));
CREATE INDEX IF NOT EXISTS idx_crt_rule ON companion_rule_targets(rule_id);

-- ─── COMPANION SUGGESTIONS ──────────────────────────────────
CREATE TABLE IF NOT EXISTS companion_suggestions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id             INTEGER REFERENCES companion_rules(id) ON DELETE SET NULL,
    target_category_id  INTEGER NOT NULL REFERENCES part_categories(id),
    target_style_id     INTEGER REFERENCES part_styles(id),
    target_description  TEXT NOT NULL,
    suggested_qty       INTEGER NOT NULL,
    approved_qty        INTEGER,
    reason_type         TEXT NOT NULL DEFAULT 'rule'
                        CHECK(reason_type IN ('rule', 'learned', 'mixed')),
    reason_text         TEXT NOT NULL,
    status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK(status IN ('pending', 'approved', 'discarded')),
    triggered_by        INTEGER REFERENCES users(id),
    decided_by          INTEGER REFERENCES users(id),
    decided_at          TEXT,
    order_id            INTEGER,
    notes               TEXT,
    created_at          TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_suggestions_status ON companion_suggestions(status);
CREATE INDEX IF NOT EXISTS idx_suggestions_created ON companion_suggestions(created_at);

CREATE TABLE IF NOT EXISTS companion_suggestion_sources (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    suggestion_id       INTEGER NOT NULL REFERENCES companion_suggestions(id) ON DELETE CASCADE,
    category_id         INTEGER NOT NULL REFERENCES part_categories(id),
    category_name       TEXT,
    style_id            INTEGER REFERENCES part_styles(id),
    style_name          TEXT,
    qty                 INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_css_suggestion ON companion_suggestion_sources(suggestion_id);

-- ─── CO-OCCURRENCE LEARNING ─────────────────────────────────
CREATE TABLE IF NOT EXISTS co_occurrence_pairs (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    category_a_id       INTEGER NOT NULL REFERENCES part_categories(id),
    category_b_id       INTEGER NOT NULL REFERENCES part_categories(id),
    co_occurrence_count INTEGER NOT NULL DEFAULT 0,
    total_jobs_a        INTEGER NOT NULL DEFAULT 0,
    total_jobs_b        INTEGER NOT NULL DEFAULT 0,
    avg_ratio_a_to_b    REAL DEFAULT 1.0,
    confidence          REAL DEFAULT 0.0,
    last_computed       TEXT DEFAULT (datetime('now')),
    UNIQUE(category_a_id, category_b_id),
    CHECK(category_a_id < category_b_id)
);
CREATE INDEX IF NOT EXISTS idx_cooccurrence_a ON co_occurrence_pairs(category_a_id);
CREATE INDEX IF NOT EXISTS idx_cooccurrence_b ON co_occurrence_pairs(category_b_id);

CREATE TABLE IF NOT EXISTS companion_feedback (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    suggestion_id       INTEGER NOT NULL REFERENCES companion_suggestions(id),
    rule_id             INTEGER REFERENCES companion_rules(id),
    action              TEXT NOT NULL CHECK(action IN ('approved', 'discarded')),
    suggested_qty       INTEGER NOT NULL,
    final_qty           INTEGER,
    source_categories   TEXT,
    target_category_id  INTEGER,
    target_style_id     INTEGER,
    user_id             INTEGER REFERENCES users(id),
    created_at          TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_feedback_rule ON companion_feedback(rule_id);

-- ─── PART ALTERNATIVES ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS part_alternatives (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id             INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    alternative_part_id INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    relationship        TEXT NOT NULL DEFAULT 'substitute'
                        CHECK(relationship IN ('substitute', 'upgrade', 'compatible')),
    preference          INTEGER NOT NULL DEFAULT 0,
    notes               TEXT,
    created_by          INTEGER REFERENCES users(id),
    created_at          TEXT DEFAULT (datetime('now')),
    UNIQUE(part_id, alternative_part_id),
    CHECK(part_id != alternative_part_id)
);
CREATE INDEX IF NOT EXISTS idx_part_alt_part ON part_alternatives(part_id);
CREATE INDEX IF NOT EXISTS idx_part_alt_alt ON part_alternatives(alternative_part_id);
  `},VE=[{name:"000_change_log",sql:`
      CREATE TABLE IF NOT EXISTS _change_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
        changed_fields TEXT,
        old_values TEXT,
        timestamp TEXT NOT NULL DEFAULT (datetime('now')),
        synced INTEGER NOT NULL DEFAULT 0,
        sync_batch_id TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_change_log_unsynced ON _change_log(synced, timestamp);
      CREATE INDEX IF NOT EXISTS idx_change_log_table ON _change_log(table_name, record_id);
    `},IE,kE,DE,FE,UE,PE,ME,XE,qE,GE,BE,$E,HE,WE,KE,YE],JE=Object.freeze(Object.defineProperty({__proto__:null,migrations:VE},Symbol.toStringTag,{value:"Module"}));let pr=!1;const qe=new Map,ga=new Set;let mr=-1;async function QE(){await(await p()).run(`
    CREATE TABLE IF NOT EXISTS _scheduler_state (
      job_id   TEXT PRIMARY KEY,
      last_run TEXT,
      status   TEXT DEFAULT 'ok'
    )
  `)}async function zE(e){const r=(await(await p()).query("SELECT last_run FROM _scheduler_state WHERE job_id = ?",[e])).values[0];return r?.last_run?new Date(r.last_run):null}async function yr(e,t="ok"){await(await p()).run(`INSERT OR REPLACE INTO _scheduler_state (job_id, last_run, status)
     VALUES (?, datetime('now'), ?)`,[e,t])}async function ZE(){const s=(await(await p()).run("DELETE FROM notifications WHERE created_at < datetime('now', '-30 days')"))?.changes?.changes??0;s>0&&console.log(`[scheduler] Purged ${s} old notifications`)}async function ep(){const s=(await(await p()).run(`DELETE FROM _change_log
     WHERE synced = 1 AND timestamp < datetime('now', '-90 days')`))?.changes?.changes??0;s>0&&console.log(`[scheduler] Purged ${s} old change_log entries`)}async function tp(){if(Se())try{const{appDataDir:e,join:t}=await N(async()=>{const{appDataDir:y,join:f}=await import("./vendor-DivU4Fss.js").then(v=>v.j);return{appDataDir:y,join:f}},__vite__mapDeps([0,1])),{mkdir:s,exists:r,readDir:n,remove:i}=await N(async()=>{const{mkdir:y,exists:f,readDir:v,remove:h}=await import("@tauri-apps/plugin-fs");return{mkdir:y,exists:f,readDir:v,remove:h}},[]),o=await e(),c=await t(o,"backups");await r(c)||await s(c,{recursive:!0});const d=new Date().toISOString().replace(/[:.]/g,"-").slice(0,19),l=await t(c,`wiredpart-backup-${d}.db`);await(await p()).run(`VACUUM INTO '${l}'`),console.log(`[scheduler] DB backup created: ${l}`);const E=5,m=(await n(c)).filter(y=>y.name?.startsWith("wiredpart-backup-")&&y.name?.endsWith(".db")).sort((y,f)=>(f.name??"").localeCompare(y.name??""));if(m.length>E)for(const y of m.slice(E)){const f=await t(c,y.name);await i(f),console.log(`[scheduler] Removed old backup: ${y.name}`)}}catch(e){throw console.error("[scheduler] DB backup failed:",e),e}}function ap(){qe.set("notification_cleanup",{id:"notification_cleanup",hour:0,minute:20,enabled:!0,fn:ZE}),qe.set("change_log_retention",{id:"change_log_retention",hour:1,minute:0,enabled:!0,fn:ep}),qe.set("db_backup",{id:"db_backup",hour:2,minute:0,enabled:!0,fn:tp})}async function sp(){const e=new Date,t=e.getHours(),s=e.getMinutes(),r=t*60+s;r!==mr&&(ga.clear(),mr=r);for(const n of qe.values())n.enabled&&(ga.has(n.id)||t===n.hour&&s===n.minute&&(ga.add(n.id),await as(n)))}async function as(e){console.log(`[scheduler] Running job: ${e.id}`);try{await e.fn(),await yr(e.id,"ok")}catch(t){console.error(`[scheduler] Job ${e.id} failed:`,t),await yr(e.id,"error")}}async function rp(){const e=Date.now(),t=1440*60*1e3;for(const s of qe.values()){if(!s.enabled)continue;const r=await zE(s.id);(!r||e-r.getTime()>t)&&(console.log(`[scheduler] Catching up missed job: ${s.id}`),await as(s))}}async function Ln(){pr||Se()&&(await QE(),ap(),pr=!0,console.log("[scheduler] Starting scheduler with jobs:",[...qe.keys()].join(", ")),await rp(),setInterval(()=>{sp().catch(e=>console.error("[scheduler] Tick error:",e))},6e4))}async function np(e){const t=qe.get(e);return t?(await as(t),!0):!1}const fy=Object.freeze(Object.defineProperty({__proto__:null,runJobManually:np,startScheduler:Ln},Symbol.toStringTag,{value:"Module"}));let It=!1,lt=null;function ip(){return It?Promise.resolve():lt||(Se()?(lt=(async()=>{try{console.log("[local] Initializing local database..."),await Ir(),console.log("[local] Database initialized, restoring sync state..."),await qr(),console.log("[local] Starting background scheduler..."),await Ln(),It=!0,console.log("[local] Local system ready.")}catch(e){throw console.error("[local] Failed to initialize:",e),lt=null,e}})(),lt):(It=!0,Promise.resolve()))}function op(){return It}const vy=Object.freeze(Object.defineProperty({__proto__:null,initLocalSystem:ip,isLocalSystemReady:op},Symbol.toStringTag,{value:"Module"})),cp=new Y("chat_channels"),bt=new Y("chat_messages"),lp=new Y("chat_mentions"),Sn=new Y("qa_threads");async function Cn(e){return(await(await p()).query(`SELECT cc.*,
       j.job_name, j.job_number,
       (SELECT COUNT(*) FROM chat_channel_members WHERE channel_id = cc.id) as member_count,
       (SELECT cm.content FROM chat_messages cm
        WHERE cm.channel_id = cc.id AND cm.deleted_at IS NULL
        ORDER BY cm.created_at DESC LIMIT 1) as last_message_preview,
       (SELECT cm.created_at FROM chat_messages cm
        WHERE cm.channel_id = cc.id AND cm.deleted_at IS NULL
        ORDER BY cm.created_at DESC LIMIT 1) as last_message_at,
       (SELECT COUNT(*) FROM chat_messages cm
        WHERE cm.channel_id = cc.id
          AND cm.deleted_at IS NULL
          AND cm.sender_id != ?
          AND cm.id > COALESCE(
            (SELECT last_read_message_id FROM chat_read_receipts
             WHERE channel_id = cc.id AND user_id = ?), 0)
       ) as unread_count
     FROM chat_channels cc
     JOIN chat_channel_members ccm ON ccm.channel_id = cc.id
     LEFT JOIN jobs j ON j.id = cc.job_id
     WHERE ccm.user_id = ? AND ccm.left_at IS NULL AND cc.is_active = 1
     ORDER BY last_message_at DESC NULLS LAST`,[e,e,e])).values}async function On(e,t){const s=await p(),r=t?.limit??50,n=["cm.channel_id = ?","cm.deleted_at IS NULL"],i=[e];t?.before_id&&(n.push("cm.id < ?"),i.push(t.before_id));const o=n.join(" AND ");i.push(r+1);const d=(await s.query(`SELECT cm.*,
       u.display_name as sender_name,
       reply.content as reply_preview,
       ru.display_name as reply_sender_name
     FROM chat_messages cm
     JOIN users u ON u.id = cm.sender_id
     LEFT JOIN chat_messages reply ON reply.id = cm.reply_to_id
     LEFT JOIN users ru ON ru.id = reply.sender_id
     WHERE ${o}
     ORDER BY cm.created_at DESC
     LIMIT ?`,i)).values,l=d.length>r;return l&&d.pop(),{messages:d.reverse(),has_more:l}}async function jn(e){return(await(await p()).query(`SELECT ccm.*, u.display_name, u.username
     FROM chat_channel_members ccm
     JOIN users u ON u.id = ccm.user_id
     WHERE ccm.channel_id = ? AND ccm.left_at IS NULL`,[e])).values}async function An(e){return(await(await p()).query(`SELECT cm.*, u.display_name as sender_name
     FROM chat_messages cm
     JOIN users u ON u.id = cm.sender_id
     WHERE cm.channel_id = ? AND cm.pinned_at IS NOT NULL AND cm.deleted_at IS NULL
     ORDER BY cm.pinned_at DESC`,[e])).values}async function In(e,t,s){const r=await bt.insert({channel_id:e,sender_id:t,message_type:s.message_type??"text",content:s.content??null,media_path:s.media_path??null,reply_to_id:s.reply_to_id??null});if(await X("chat_messages",r,"INSERT"),s.mention_ids?.length)for(const n of s.mention_ids){const i=await lp.insert({message_id:r,mentioned_user_id:n});await X("chat_mentions",i,"INSERT")}return await cp.update(e,{updated_at:new Date().toISOString()}),await X("chat_channels",e,"UPDATE"),r}async function kn(e,t){await bt.update(e,{content:t,edited_at:new Date().toISOString()}),await X("chat_messages",e,"UPDATE")}async function Dn(e){await bt.update(e,{deleted_at:new Date().toISOString()}),await X("chat_messages",e,"UPDATE")}async function Fn(e,t){await bt.update(e,{pinned_at:new Date().toISOString(),pinned_by:t}),await X("chat_messages",e,"UPDATE")}async function Un(e){await bt.update(e,{pinned_at:null,pinned_by:null}),await X("chat_messages",e,"UPDATE")}async function Pn(e,t,s){await(await p()).run(`INSERT INTO chat_read_receipts (channel_id, user_id, last_read_message_id, read_at)
     VALUES (?, ?, ?, datetime('now'))
     ON CONFLICT(channel_id, user_id)
     DO UPDATE SET last_read_message_id = MAX(last_read_message_id, excluded.last_read_message_id),
                   read_at = datetime('now')`,[e,t,s])}async function Mn(e){const t=await p(),s=[],r=[];e?.job_id&&(s.push("qt.job_id = ?"),r.push(e.job_id)),e?.status&&(s.push("qt.status = ?"),r.push(e.status)),e?.assigned_to&&(s.push("qt.assigned_to = ?"),r.push(e.assigned_to));const n=s.length?`WHERE ${s.join(" AND ")}`:"";return r.push(e?.limit??100),(await t.query(`SELECT qt.*,
       ua.display_name as asker_name,
       uas.display_name as assigned_name,
       j.job_number
     FROM qa_threads qt
     JOIN users ua ON ua.id = qt.asked_by
     LEFT JOIN users uas ON uas.id = qt.assigned_to
     JOIN jobs j ON j.id = qt.job_id
     ${n}
     ORDER BY qt.updated_at DESC
     LIMIT ?`,r)).values}async function Xn(e,t,s,r,n="normal"){const i=await Sn.insert({job_id:e,asked_by:t,subject:s,status:"open",priority:n,current_level:"worker"});return await X("qa_threads",i,"INSERT"),i}async function qn(e,t,s){await Sn.update(e,{status:"answered",answer_text:s,answered_by:t,answered_at:new Date().toISOString(),updated_at:new Date().toISOString()}),await X("qa_threads",e,"UPDATE")}const Ry=Object.freeze(Object.defineProperty({__proto__:null,answerQuestion:qn,askQuestion:Xn,deleteMessage:Dn,editMessage:kn,getChannelMembers:jn,getChannelMessages:On,getInbox:Cn,getPinnedMessages:An,listQAThreads:Mn,markChannelRead:Pn,pinMessage:Fn,sendMessage:In,unpinMessage:Un},Symbol.toStringTag,{value:"Module"})),gr=["order_update","job_update","system","warehouse","approval","chat"],dp=["order_update","job_update","system","warehouse","approval","chat"];async function Gn(e){const r=(await(await p()).query("SELECT COUNT(*) AS cnt FROM notifications WHERE user_id = ? AND is_read = 0",[e])).values[0]?.cnt??0;return{unread_count:Number(r)}}async function Bn(e,t){const s=await p(),r=t?.limit??20,n=t?.offset??0,i=t?.unread_only??!1,o=["user_id = ?"],c=[e];i&&o.push("is_read = 0");const d=o.join(" AND "),l=await s.query(`SELECT COUNT(*) AS cnt FROM notifications WHERE ${d}`,c),u=Number(l.values[0]?.cnt??0),E=await s.query("SELECT COUNT(*) AS cnt FROM notifications WHERE user_id = ? AND is_read = 0",[e]),_=Number(E.values[0]?.cnt??0);return{notifications:(await s.query(`SELECT * FROM notifications WHERE ${d} ORDER BY created_at DESC LIMIT ? OFFSET ?`,[...c,r,n])).values.map(up),total:u,unread_count:_}}function up(e){return{...e,is_read:e.is_read===1||e.is_read===!0}}async function $n(e,t){const s=await p();if(t.all)await s.run("UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0",[e]);else if(t.ids&&t.ids.length>0){const r=t.ids.map(()=>"?").join(", ");await s.run(`UPDATE notifications SET is_read = 1 WHERE user_id = ? AND id IN (${r})`,[e,...t.ids])}return{message:"ok"}}async function Hn(e){const s=await(await p()).query("SELECT notification_type, is_enabled FROM notification_preferences WHERE user_id = ?",[e]),r=new Map;for(const i of s.values)r.set(i.notification_type,i.is_enabled===1||i.is_enabled===!0);const n=gr.map(i=>({type:i,enabled:r.has(i)?r.get(i):!0,channels:["in_app"]}));for(const[i,o]of r)gr.includes(i)||n.push({type:i,enabled:o,channels:["in_app"]});return{preferences:n}}async function Wn(e,t){const s=await p();for(const r of t)await s.run(`INSERT INTO notification_preferences (user_id, notification_type, is_enabled)
       VALUES (?, ?, ?)
       ON CONFLICT(user_id, notification_type) DO UPDATE SET is_enabled = excluded.is_enabled`,[e,r.type,r.enabled?1:0]);return{message:"ok"}}async function Kn(e){const t=await p(),s=`notification_sound_${e}_`,r=await t.query("SELECT key, value FROM settings WHERE key LIKE ?",[`${s}%`]),n=[];for(const o of r.values){const c=o.key.replace(s,"");try{const d=JSON.parse(o.value);n.push({type:c,sound:d.sound??"default",volume:d.volume??.5,enabled:d.enabled??!0})}catch{}}const i=new Set(n.map(o=>o.type));for(const o of dp)i.has(o)||n.push({type:o,sound:"default",volume:.5,enabled:!0});return{settings:n}}const wy=Object.freeze(Object.defineProperty({__proto__:null,getNotificationBadge:Gn,getNotificationPreferences:Hn,getNotificationSoundSettings:Kn,listNotifications:Bn,markNotificationsRead:$n,updateNotificationPreferences:Wn},Symbol.toStringTag,{value:"Module"})),Ye="wp_security_",Yn=`${Ye}device_private_key`,Yt=`${Ye}device_public_key`,ss=`${Ye}device_certificate`,rs=`${Ye}device_cert_signature`,Vt=`${Ye}company_id`,pt=`${Ye}db_encryption_key`,Jt=`${Ye}device_id`,Qt=new Map;async function ke(e,t){ce()?localStorage.setItem(e,t):Qt.set(e,t)}async function fe(e){return ce()?localStorage.getItem(e):Qt.get(e)??null}async function _p(e){ce()?localStorage.removeItem(e):Qt.delete(e)}function Vn(){const e=new Uint8Array(32);return crypto.getRandomValues(e),btoa(String.fromCharCode(...e))}function Ep(){const e=new Uint8Array(16);return crypto.getRandomValues(e),Array.from(e).map(t=>t.toString(16).padStart(2,"0")).join("")}async function Jn(e){if(await ke(Jt,e),!await fe(pt)){const s=Vn();await ke(pt,s)}}async function Qn(){return ce()?fe(pt):null}async function zn(e,t){await ke(Yt,e),await ke(Yn,t)}async function Zn(){return fe(Yt)}async function ei(e,t,s,r){await ke(ss,e),await ke(rs,t),await ke(Vt,s)}async function it(){const e=await fe(ss),t=await fe(rs),s=await fe(Vt);if(!e||!t||!s)return null;try{const r=JSON.parse(e);return{certificateData:e,signature:t,companyId:s,expiresAt:r.expires_at??""}}catch{return null}}async function ti(){const e=await it();return!e||!e.expiresAt?!1:new Date(e.expiresAt)>new Date}async function ai(){const e=await fe(Jt),t=await fe(Vt),s=await fe(Yt);if(!e)return null;const r=await it();return{deviceId:e,companyId:t??"",publicKey:s??"",hasCertificate:r!==null}}async function si(){const e=await it();return!e||e.expiresAt&&new Date(e.expiresAt)<new Date?null:{company_id:e.companyId,certificate_data:e.certificateData,signature:e.signature}}async function ri(){const e=await fe(Jt),t=await it();return!e||!t?null:{type:"BT_HELLO",device_id:e,company_id:t.companyId,certificate_data:t.certificateData,signature:t.signature,nonce:Ep(),timestamp:new Date().toISOString()}}async function ni(){const e=[Yn,Yt,ss,rs,Vt,pt,Jt];for(const t of e)await _p(t);Qt.clear()}async function ii(){const e=Vn();return await ke(pt,e),e}const oi=Object.freeze(Object.defineProperty({__proto__:null,clearDeviceSecurity:ni,createBtHello:ri,getDbEncryptionKey:Qn,getDeviceIdentity:ai,getDevicePublicKey:Zn,getStoredCertificate:it,getSyncAuthFields:si,initialiseDeviceSecurity:Jn,isCertificateValid:ti,rotateDbEncryptionKey:ii,storeCertificate:ei,storeDeviceKeypair:zn},Symbol.toStringTag,{value:"Module"}));async function xe(e,t){const{invoke:s}=await N(async()=>{const{invoke:r}=await import("./vendor-DivU4Fss.js").then(n=>n.i);return{invoke:r}},__vite__mapDeps([0,1]));return s(e,t)}class pp{_status="unavailable";_nearbyDevices=new Map;_statusListeners=new Set;_deviceListeners=new Set;_syncListeners=new Set;_peerPollTimer=null;_messagePollTimer=null;constructor(){this._checkAvailability()}async _checkAvailability(){if(!ce()){this._setStatus("unavailable");return}try{const t=await xe("multipeer_is_running");this._setStatus(t?"running":"ready")}catch{this._setStatus("unavailable")}}get status(){return this._status}get nearbyDevices(){return Array.from(this._nearbyDevices.values())}async start(t,s,r){if(this._status==="unavailable")return console.warn("[BT] Multipeer not available on this platform"),!1;if(this._status==="running")return console.log("[BT] Multipeer already running"),!0;try{const n=await xe("start_multipeer",{device_id:t,device_name:s,company_id:r});return n?(this._setStatus("running"),this._startPolling(),console.log("[BT] Multipeer started — advertising + browsing")):(this._setStatus("error"),console.error("[BT] Multipeer start returned false")),n}catch(n){return console.error("[BT] Failed to start Multipeer:",n),this._setStatus("error"),!1}}async stop(){if(this._stopPolling(),this._nearbyDevices.clear(),this._status!=="unavailable"){try{await xe("stop_multipeer")}catch{}this._setStatus("ready"),this._notifyDeviceListeners(),console.log("[BT] Multipeer stopped")}}async sendToPeer(t,s){if(this._status!=="running"&&this._status!=="syncing")return!1;try{return await xe("multipeer_send",{peer_device_id:t,data:s}),!0}catch(r){return console.error(`[BT] Send to ${t} failed:`,r),!1}}async popReceived(){if(this._status==="unavailable")return null;try{return await xe("multipeer_pop_received")??null}catch{return null}}async getReceiveCount(){if(this._status==="unavailable")return 0;try{return await xe("multipeer_receive_count")}catch{return 0}}async isRunning(){if(this._status==="unavailable")return!1;try{return await xe("multipeer_is_running")}catch{return!1}}getConnectedPeers(){return this.nearbyDevices.filter(t=>t.state==="connected")}async startScan(){console.warn("[BT] startScan() is deprecated — use start(deviceId, name, companyId)")}async stopScan(){await this.stop()}async checkAvailability(){if(!ce())return{supported:!1,enabled:!1};try{return await xe("multipeer_is_running"),{supported:!0,enabled:!0}}catch{return{supported:!1,enabled:!1}}}onStatusChange(t){return this._statusListeners.add(t),()=>{this._statusListeners.delete(t)}}onDevicesUpdated(t){return this._deviceListeners.add(t),()=>{this._deviceListeners.delete(t)}}onSyncComplete(t){return this._syncListeners.add(t),()=>{this._syncListeners.delete(t)}}_startPolling(){this._stopPolling(),this._peerPollTimer=setInterval(()=>this._pollPeers(),5e3),this._messagePollTimer=setInterval(()=>this._pollMessages(),3e3),this._pollPeers()}_stopPolling(){this._peerPollTimer&&(clearInterval(this._peerPollTimer),this._peerPollTimer=null),this._messagePollTimer&&(clearInterval(this._messagePollTimer),this._messagePollTimer=null)}async _pollPeers(){try{const t=await xe("get_multipeer_peers"),s=Date.now(),r=new Set;for(const n of t){r.add(n.device_id);const i=this._nearbyDevices.get(n.device_id);this._nearbyDevices.set(n.device_id,{deviceId:n.device_id,name:n.device_name,companyId:n.company_id,state:n.state,lastSeen:i?.lastSeen??s})}for(const n of this._nearbyDevices.keys())r.has(n)||this._nearbyDevices.delete(n);this._notifyDeviceListeners()}catch(t){console.error("[BT] Peer poll error:",t)}}async _pollMessages(){try{const t=await this.getReceiveCount();if(t===0)return;for(let s=0;s<t;s++){const r=await this.popReceived();if(!r)break;try{const n=atob(r.data),i=JSON.parse(n);if(Array.isArray(i)&&i.length>0){const o=await xe("push_to_sync_inbox",{changes:i});console.log(`[BT] Deposited ${o} changes from ${r.from_device_id} into sync inbox`)}}catch(n){console.error("[BT] Failed to parse received message:",n)}}}catch(t){console.error("[BT] Message poll error:",t)}}_setStatus(t){this._status=t,this._statusListeners.forEach(s=>s(t))}_notifyDeviceListeners(){const t=this.nearbyDevices;this._deviceListeners.forEach(s=>s(t))}_notifySyncListeners(t){this._syncListeners.forEach(s=>s(t))}}const mp=new pp,zt=Object.freeze(Object.defineProperty({__proto__:null,btService:mp},Symbol.toStringTag,{value:"Module"}));async function yp(e){const t=await p(),s=await rt(),r={applied:0,conflicts:0,skipped:0,errors:0};for(const n of e)try{if(n.operation==="DELETE")await gp(t,n),r.applied++;else if(n.operation==="INSERT"){const i=await ci(t,n,s);r.applied++,i&&r.conflicts++}else if(n.operation==="UPDATE"){const i=await Tp(t,n,s);r.applied++,r.conflicts+=i}else r.skipped++}catch(i){console.error(`[conflict-resolver] Failed to apply ${n.operation} on ${n.table_name}.${n.record_id}:`,i),r.errors++}return r}async function gp(e,t){try{await e.run(`UPDATE [${t.table_name}] SET deleted_at = ? WHERE id = ?`,[t.timestamp,t.record_id])}catch{await e.run(`DELETE FROM [${t.table_name}] WHERE id = ?`,[t.record_id])}}async function ci(e,t,s){const r=Ra(t.record_data);if(!r)return!1;const n=await li(e,t.table_name,t.record_id);if(!n){const u=Object.keys(r),E=u.map(()=>"?").join(", "),_=u.map(m=>r[m]);return await e.run(`INSERT OR IGNORE INTO [${t.table_name}] (${u.join(", ")}) VALUES (${E})`,_),!1}const i=n.updated_at??n.created_at??"1970-01-01",o=t.timestamp,c=await di(e,t.table_name,t.record_id),d={},l=[];for(const[u,E]of Object.entries(r)){if(u==="id")continue;const _=n[u];c.has(u)?o>i?(d[u]=E,l.push({table_name:t.table_name,record_id:t.record_id,field_name:u,local_value:Ie(_),remote_value:Ie(E),winner:"remote",local_device:s,remote_device:t.device_id,local_ts:i,remote_ts:o})):l.push({table_name:t.table_name,record_id:t.record_id,field_name:u,local_value:Ie(_),remote_value:Ie(E),winner:"local",local_device:s,remote_device:t.device_id,local_ts:i,remote_ts:o}):d[u]=E}if(Object.keys(d).length>0){const u=Object.keys(d).map(_=>`${_} = ?`).join(", "),E=Object.values(d);await e.run(`UPDATE [${t.table_name}] SET ${u} WHERE id = ?`,[...E,t.record_id])}return l.length>0&&await ui(e,l),l.length>0}async function Tp(e,t,s){const r=Ra(t.changed_fields),n=Ra(t.record_data);if(!r&&n)return await ci(e,{...t},s)?1:0;if(!r)return 0;const i=await li(e,t.table_name,t.record_id);if(!i){if(n){const E=Object.keys(n),_=E.map(()=>"?").join(", "),m=E.map(y=>n[y]);await e.run(`INSERT OR IGNORE INTO [${t.table_name}] (${E.join(", ")}) VALUES (${_})`,m)}return 0}const o=i.updated_at??i.created_at??"1970-01-01",c=t.timestamp,d=await di(e,t.table_name,t.record_id),l={},u=[];for(const[E,_]of Object.entries(r)){if(E==="id")continue;const m=i[E];d.has(E)?c>o?(l[E]=_,u.push({table_name:t.table_name,record_id:t.record_id,field_name:E,local_value:Ie(m),remote_value:Ie(_),winner:"remote",local_device:s,remote_device:t.device_id,local_ts:o,remote_ts:c})):u.push({table_name:t.table_name,record_id:t.record_id,field_name:E,local_value:Ie(m),remote_value:Ie(_),winner:"local",local_device:s,remote_device:t.device_id,local_ts:o,remote_ts:c}):l[E]=_}if(Object.keys(l).length>0){const E=Object.keys(l).map(m=>`${m} = ?`).join(", "),_=Object.values(l);await e.run(`UPDATE [${t.table_name}] SET ${E} WHERE id = ?`,[..._,t.record_id])}return u.length>0&&await ui(e,u),u.length}async function li(e,t,s){try{const r=await e.query(`SELECT * FROM [${t}] WHERE id = ?`,[s]);if(r.values&&r.values.length>0)return r.values[0]}catch{}return null}async function di(e,t,s){const r=new Set;try{const n=await e.query(`SELECT changed_fields FROM _change_log
       WHERE table_name = ? AND record_id = ? AND synced = 0
       ORDER BY timestamp DESC`,[t,s]);for(const i of n.values)if(i.changed_fields)try{const o=typeof i.changed_fields=="string"?JSON.parse(i.changed_fields):i.changed_fields;for(const c of Object.keys(o))r.add(c)}catch{}}catch{}return r}async function ui(e,t){for(const s of t)try{await e.run(`INSERT INTO _conflict_log
           (table_name, record_id, field_name, local_value, remote_value,
            winner, local_device, remote_device, local_ts, remote_ts)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,[s.table_name,s.record_id,s.field_name,s.local_value,s.remote_value,s.winner,s.local_device,s.remote_device,s.local_ts,s.remote_ts])}catch(r){console.error("[conflict-resolver] Failed to log conflict:",r)}}function Ra(e){if(!e)return null;if(typeof e=="object")return e;try{return JSON.parse(e)}catch{return null}}function Ie(e){return e==null?null:typeof e=="string"?e:JSON.stringify(e)}async function Np(e=50){return(await(await p()).query("SELECT * FROM _conflict_log WHERE reviewed = 0 ORDER BY resolved_at DESC LIMIT ?",[e])).values??[]}async function hp(e){await(await p()).run("UPDATE _conflict_log SET reviewed = 1 WHERE id = ?",[e])}async function xp(){const s=(await(await p()).query(`
    SELECT
      COUNT(*) as total,
      SUM(CASE WHEN reviewed = 0 THEN 1 ELSE 0 END) as unreviewed,
      SUM(CASE WHEN resolved_at > datetime('now', '-1 day') THEN 1 ELSE 0 END) as last24h
    FROM _conflict_log
  `)).values?.[0]??{};return{total:s.total??0,unreviewed:s.unreviewed??0,last24h:s.last24h??0}}const bp=Object.freeze(Object.defineProperty({__proto__:null,getConflictStats:xp,getUnreviewedConflicts:Np,markConflictReviewed:hp,resolveAndApplyChanges:yp},Symbol.toStringTag,{value:"Module"}));async function St(e,t=[]){const s=await p();try{const n=(await s.query(e,t)).values[0];if(!n)return 0;const i=Object.values(n)[0];return typeof i=="number"?i:0}catch{return 0}}async function Ge(e,t=[]){const s=await p();try{return(await s.query(e,t)).values}catch{return[]}}async function _i(){const[e,t,s,r]=await Promise.all([St("SELECT COUNT(*) AS c FROM parts WHERE is_active = 1"),St("SELECT COUNT(*) AS c FROM jobs WHERE status IN ('active', 'in_progress')"),St("SELECT COUNT(*) AS c FROM purchase_orders WHERE status = 'pending'"),St(`
      SELECT COUNT(*) AS c FROM (
        SELECT p.id
        FROM parts p
        JOIN stock s ON s.part_id = p.id AND s.location_type = 'warehouse'
        WHERE p.is_active = 1
          AND p.min_stock_level > 0
        GROUP BY p.id
        HAVING SUM(s.qty) < p.min_stock_level
      )
    `)]);return{kpis:{total_parts:e,active_jobs:t,pending_orders:s,low_stock_alerts:r},quick_actions:[{label:"New Job",icon:"briefcase",route:"/jobs/active"},{label:"Create PO",icon:"shopping-cart",route:"/orders/purchase-orders/new"},{label:"Stock Check",icon:"search",route:"/warehouse/inventory"},{label:"Pull Parts",icon:"arrow-right-left",route:"/warehouse/staging"}],user_name:""}}async function Ei(e){const t=await Ge(`SELECT va.vehicle_id, va.is_take_home,
            va.home_to_shop_miles,
            v.vehicle_name, v.vehicle_number
     FROM vehicle_assignments va
     JOIN vehicles v ON v.id = va.vehicle_id
     WHERE va.user_id = ?
       AND va.is_active = 1
       AND (va.end_date IS NULL OR va.end_date >= date('now', 'localtime'))
     LIMIT 1`,[e]);if(t.length===0)return{has_vehicle:!1,suggested:[],all_destinations:[]};const s=t[0],r=s.vehicle_id,n=[],i=await Ge(`SELECT id, job_name, gps_lat, gps_lng, distance_from_shop_miles
     FROM jobs
     WHERE status IN ('active', 'in_progress')
     ORDER BY job_name ASC`);for(const l of i)n.push({type:"job",label:l.job_name,address:null,gps_lat:l.gps_lat??null,gps_lng:l.gps_lng??null,miles_estimate:l.distance_from_shop_miles??null,job_id:l.id,trip_count_30d:0});const o=await Ge(`SELECT vtl.to_label, COUNT(*) AS trip_count
     FROM vehicle_trip_legs vtl
     JOIN vehicle_mileage_logs vml ON vml.id = vtl.mileage_log_id
     WHERE vml.driver_id = ?
       AND vml.log_date >= date('now', '-30 days', 'localtime')
     GROUP BY vtl.to_label
     ORDER BY trip_count DESC`,[e]),c=new Map(o.map(l=>[l.to_label,l.trip_count]));for(const l of n)l.trip_count_30d=c.get(l.label)??0;const d=[...n].sort((l,u)=>(u.trip_count_30d??0)-(l.trip_count_30d??0));return{has_vehicle:!0,vehicle_id:r,vehicle_name:s.vehicle_name,vehicle_number:s.vehicle_number,suggested:d.slice(0,3),all_destinations:n}}async function pi(e,t){const s=await p(),r=new Date().toISOString().slice(0,10),n=await Ge(`SELECT vehicle_id FROM vehicle_assignments
     WHERE user_id = ? AND is_active = 1
       AND (end_date IS NULL OR end_date >= date('now', 'localtime'))
     LIMIT 1`,[e]);if(n.length===0)throw new Error("No active vehicle assignment found");const i=n[0].vehicle_id,o=await Ge(`SELECT id FROM vehicle_mileage_logs
     WHERE vehicle_id = ? AND driver_id = ? AND log_date = ?
     LIMIT 1`,[i,e,r]);let c;o.length>0?c=o[0].id:c=(await s.run(`INSERT INTO vehicle_mileage_logs (vehicle_id, driver_id, log_date, created_at, updated_at)
       VALUES (?, ?, ?, datetime('now'), datetime('now'))`,[i,e,r])).changes.lastId;const d=await s.run(`INSERT INTO vehicle_trip_legs
       (mileage_log_id, leg_order, leg_type, from_label, to_label,
        estimated_miles, to_job_id, from_job_id, created_at, updated_at)
     VALUES (?, 1, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))`,[c,t.leg_type,t.from_label,t.to_label,t.estimated_miles??null,t.to_job_id??null,t.from_job_id??null]);return{mileage_log_id:c,trip_leg_id:d.changes.lastId}}async function mi(e=60){return Ge(`SELECT c.user_id,
            u.first_name || ' ' || u.last_name AS user_name,
            c.cert_name,
            c.expiry_date,
            CAST(julianday(c.expiry_date) - julianday(date('now', 'localtime')) AS INTEGER) AS days_until_expiry
     FROM certifications c
     JOIN users u ON u.id = c.user_id
     WHERE c.expiry_date IS NOT NULL
       AND c.is_active = 1
       AND c.deleted_at IS NULL
       AND c.expiry_date <= date('now', '+' || ? || ' days', 'localtime')
       AND c.expiry_date >= date('now', '-30 days', 'localtime')
     ORDER BY c.expiry_date ASC`,[e])}async function yi(e=60){const t=await Ge(`SELECT id, vehicle_name, vehicle_number,
            insurance_expiry, registration_expiry
     FROM vehicles
     WHERE is_active = 1
       AND (
         (insurance_expiry IS NOT NULL
          AND insurance_expiry <= date('now', '+' || ? || ' days', 'localtime')
          AND insurance_expiry >= date('now', '-30 days', 'localtime'))
         OR
         (registration_expiry IS NOT NULL
          AND registration_expiry <= date('now', '+' || ? || ' days', 'localtime')
          AND registration_expiry >= date('now', '-30 days', 'localtime'))
       )
     ORDER BY COALESCE(insurance_expiry, registration_expiry) ASC`,[e,e]),s=new Date().toISOString().slice(0,10),r=new Date(s).getTime(),n=[];for(const i of t)for(const[o,c]of[["insurance","insurance_expiry"],["registration","registration_expiry"]]){const d=i[c];if(!d)continue;const l=Math.round((new Date(d).getTime()-r)/(1e3*60*60*24));l>e||l<-30||n.push({vehicle_id:i.id,vehicle_name:i.vehicle_name,vehicle_number:i.vehicle_number,alert_type:o,expiry_date:d,days_until_expiry:l})}return n.sort((i,o)=>i.days_until_expiry-o.days_until_expiry),n}const Ly=Object.freeze(Object.defineProperty({__proto__:null,getCertAlerts:mi,getDashboard:_i,getFastDriveContext:Ei,getVehicleExpiryAlerts:yi,startDrive:pi},Symbol.toStringTag,{value:"Module"}));function ot(e,t){const s=[],r=[];return t?.date_from&&(s.push(`${e} >= ?`),r.push(t.date_from)),t?.date_to&&(s.push(`${e} <= ?`),r.push(t.date_to)),{where:s.length?s.join(" AND "):"1=1",values:r}}async function Zt(e,t){return(await(await p()).query("SELECT setting_value FROM settings WHERE setting_key = ? AND category = 'costs'",[e])).values[0]?.setting_value??t}async function gi(){return(await(await p()).query(`SELECT s.setting_key, s.setting_value, s.updated_by, s.updated_at,
       u.display_name as updated_by_name
     FROM settings s
     LEFT JOIN users u ON u.id = s.updated_by
     WHERE s.category = 'costs'
     ORDER BY s.setting_key`)).values}async function Ti(e){return(await(await p()).query(`SELECT s.id, s.part_id, s.unit_cost, s.qty as remaining_qty,
       s.qty as original_qty, s.created_at,
       NULL as purchase_date, NULL as po_line_id, NULL as po_number
     FROM stock s
     WHERE s.part_id = ? AND s.qty > 0
     ORDER BY s.created_at ASC`,[e])).values}async function Ni(e,t=90){return(await(await p()).query(`SELECT DATE(ri.created_at) as date,
       SUM(ri.qty_received * ri.unit_cost) / SUM(ri.qty_received) as weighted_avg_cost,
       SUM(ri.qty_received) as total_qty
     FROM receiving_session_items ri
     WHERE ri.part_id = ?
       AND ri.deleted_at IS NULL
       AND ri.created_at >= DATE('now', '-' || ? || ' days')
     GROUP BY DATE(ri.created_at)
     ORDER BY date ASC`,[e,t])).values}async function ea(e){const t=await p(),r=(await t.query(`SELECT SUM(qty) as total_qty,
       CASE WHEN SUM(qty) > 0
         THEN SUM(qty * unit_cost) / SUM(qty)
         ELSE 0 END as weighted_avg_cost,
       COUNT(*) as active_layers,
       MAX(created_at) as cost_last_updated
     FROM stock
     WHERE part_id = ? AND qty > 0`,[e])).values[0]??{},i=(await t.query("SELECT custom_margin, sell_price FROM parts WHERE id = ?",[e])).values[0]??{},o=parseFloat(await Zt("default_margin","30")),c=i.custom_margin??o,d=r.weighted_avg_cost??0,l=d*(1+c/100);return{part_id:e,weighted_avg_cost:d,custom_margin_percent:i.custom_margin??null,effective_margin_percent:c,calculated_sell_price:l,cost_last_updated:r.cost_last_updated??null,active_layers:r.active_layers??0}}async function hi(e,t){return await(await p()).run(`UPDATE parts SET custom_margin = ?,
       sell_price = unit_cost * (1 + ? / 100.0),
       updated_at = ?
     WHERE id = ?`,[t,t,new Date().toISOString(),e]),ea(e)}async function xi(e){const t=await p(),s=parseFloat(await Zt("default_margin","30"));return await t.run(`UPDATE parts SET custom_margin = NULL,
       sell_price = unit_cost * (1 + ? / 100.0),
       updated_at = ?
     WHERE id = ?`,[s,new Date().toISOString(),e]),ea(e)}async function bi(){const e=await p(),t=parseFloat(await Zt("default_margin","30")),s=new Date().toISOString(),n=(await e.query("SELECT COUNT(*) as cnt FROM parts WHERE custom_margin IS NOT NULL AND deleted_at IS NULL")).values[0]?.cnt??0;return await e.run(`UPDATE parts SET
       custom_margin = NULL,
       sell_price = unit_cost * (1 + ? / 100.0),
       updated_at = ?
     WHERE deleted_at IS NULL`,[t,s]),{cleared_count:n,message:`Cleared ${n} custom margin(s). All parts now use the default ${t}% margin.`}}async function fi(e){const t=await p(),{where:s,values:r}=ot("ri.created_at",e),i=(await t.query(`SELECT
       COALESCE(SUM(ri.qty_received * ri.unit_cost), 0) as total_spend,
       COUNT(DISTINCT ri.po_id) as order_count,
       COUNT(DISTINCT po.supplier_id) as active_suppliers
     FROM receiving_session_items ri
     JOIN purchase_orders po ON po.id = ri.po_id
     WHERE ri.deleted_at IS NULL AND ${s}`,r)).values[0]??{},o=i.total_spend??0,c=i.order_count??0;return{total_spend:o,order_count:c,avg_order_size:c>0?o/c:0,active_suppliers:i.active_suppliers??0}}async function vi(e){const t=await p(),{where:s,values:r}=ot("ri.created_at",e),i=(await t.query(`SELECT COALESCE(SUM(ri.qty_received * ri.unit_cost), 0) as grand_total
     FROM receiving_session_items ri
     WHERE ri.deleted_at IS NULL AND ${s}`,r)).values[0]?.grand_total??0;return(await t.query(`SELECT
       po.supplier_id,
       s.name as supplier_name,
       SUM(ri.qty_received * ri.unit_cost) as total_spend,
       COUNT(DISTINCT ri.po_id) as order_count
     FROM receiving_session_items ri
     JOIN purchase_orders po ON po.id = ri.po_id
     JOIN suppliers s ON s.id = po.supplier_id
     WHERE ri.deleted_at IS NULL AND ${s}
     GROUP BY po.supplier_id
     ORDER BY total_spend DESC`,r)).values.map(c=>({supplier_id:c.supplier_id,supplier_name:c.supplier_name,total_spend:c.total_spend,order_count:c.order_count,pct_of_total:i>0?c.total_spend/i*100:0}))}async function Ri(e){const t=await p(),{where:s,values:r}=ot("ri.created_at",e);return(await t.query(`SELECT
       p.category_id,
       COALESCE(pc.name, 'Uncategorized') as category_name,
       SUM(ri.qty_received * ri.unit_cost) as total_spend,
       COUNT(DISTINCT ri.part_id) as item_count
     FROM receiving_session_items ri
     JOIN parts p ON p.id = ri.part_id
     LEFT JOIN part_categories pc ON pc.id = p.category_id
     WHERE ri.deleted_at IS NULL AND ${s}
     GROUP BY p.category_id
     ORDER BY total_spend DESC`,r)).values}async function wi(e){const t=await p(),{where:s,values:r}=ot("ri.created_at",e);return(await t.query(`SELECT
       po.job_id,
       j.job_name,
       SUM(ri.qty_received * ri.unit_cost) as total_spend,
       j.budget_limit
     FROM receiving_session_items ri
     JOIN purchase_orders po ON po.id = ri.po_id
     LEFT JOIN jobs j ON j.id = po.job_id
     WHERE ri.deleted_at IS NULL AND po.job_id IS NOT NULL AND ${s}
     GROUP BY po.job_id
     ORDER BY total_spend DESC`,r)).values.map(i=>({job_id:i.job_id,job_name:i.job_name,total_spend:i.total_spend,budget_limit:i.budget_limit,budget_pct:i.budget_limit&&i.budget_limit>0?i.total_spend/i.budget_limit*100:null}))}async function Li(e){const t=await p(),{where:s,values:r}=ot("ri.created_at",e),i=(e?.group_by??"month")==="week"?"%Y-W%W":"%Y-%m";return(await t.query(`SELECT
       strftime('${i}', ri.created_at) as period_label,
       SUM(ri.qty_received * ri.unit_cost) as total_spend,
       COUNT(DISTINCT ri.po_id) as order_count
     FROM receiving_session_items ri
     WHERE ri.deleted_at IS NULL AND ${s}
     GROUP BY period_label
     ORDER BY period_label ASC`,r)).values}async function Si(e){const t=await p(),r=(await t.query("SELECT id, job_name, budget_limit FROM jobs WHERE id = ?",[e])).values[0]??{},i=(await t.query(`SELECT
       COALESCE(SUM(hours), 0) as total_labor_hours,
       COALESCE(SUM(hours * pay_rate), 0) as total_labor_cost
     FROM labor_entries
     WHERE job_id = ? AND deleted_at IS NULL`,[e])).values[0]??{},c=(await t.query(`SELECT COALESCE(SUM(sm.qty * sm.unit_cost), 0) as total_parts_cost
     FROM stock_movements sm
     WHERE sm.to_type = 'job' AND sm.to_id = ? AND sm.deleted_at IS NULL`,[e])).values[0]??{},d=i.total_labor_cost??0,l=c.total_parts_cost??0,u=d+l,E=r.budget_limit??null,_=parseFloat(await Zt("budget_alert_percent","80"));return{job_id:e,job_name:r.job_name??"",total_parts_cost:l,total_labor_cost:d,total_labor_hours:i.total_labor_hours??0,combined_total:u,budget_limit:E,budget_remaining:E!=null?E-u:null,budget_pct:E!=null&&E>0?u/E*100:null,budget_alert_percent:_}}async function Ci(e){const t=await p(),r=(await t.query("SELECT budget_limit FROM jobs WHERE id = ?",[e])).values[0]?.budget_limit??null,n=await t.query(`SELECT COALESCE(SUM(sm.qty * sm.unit_cost), 0) as cost
     FROM stock_movements sm
     WHERE sm.to_type = 'job' AND sm.to_id = ? AND sm.deleted_at IS NULL`,[e]),i=await t.query(`SELECT COALESCE(SUM(hours * pay_rate), 0) as cost
     FROM labor_entries
     WHERE job_id = ? AND deleted_at IS NULL`,[e]),o=(n.values[0]?.cost??0)+(i.values[0]?.cost??0);let c=null,d=null;return r!=null&&r>0&&(c=o/r*100,c>=100?d="critical":c>=80?d="warning":d="ok"),{job_id:e,budget_limit:r,current_spend:o,budget_pct:c,alert_level:d}}async function Oi(e){const t=await p(),{where:s,values:r}=ot("ri.created_at",e);return(await t.query(`SELECT
       ri.part_id,
       p.description as part_name,
       s.name as supplier_name,
       po.po_number,
       pol.unit_cost as quoted_price,
       ri.unit_cost as actual_price,
       (ri.unit_cost - pol.unit_cost) as variance_amount,
       CASE WHEN pol.unit_cost > 0
         THEN ((ri.unit_cost - pol.unit_cost) / pol.unit_cost) * 100
         ELSE 0 END as variance_pct
     FROM receiving_session_items ri
     JOIN purchase_order_lines pol ON pol.po_id = ri.po_id AND pol.part_id = ri.part_id
     JOIN purchase_orders po ON po.id = ri.po_id
     JOIN parts p ON p.id = ri.part_id
     LEFT JOIN suppliers s ON s.id = po.supplier_id
     WHERE ri.deleted_at IS NULL
       AND ri.unit_cost IS NOT NULL
       AND pol.unit_cost IS NOT NULL
       AND ABS(ri.unit_cost - pol.unit_cost) > 0.001
       AND ${s}
     ORDER BY ABS(variance_pct) DESC`,r)).values.map(i=>({...i,variance_level:Math.abs(i.variance_pct)>=20?"danger":Math.abs(i.variance_pct)>=5?"warning":"ok"}))}async function ns(){const e=await p(),t=await e.query(`SELECT id, job_name, budget_limit
     FROM jobs
     WHERE budget_limit IS NOT NULL AND budget_limit > 0
       AND deleted_at IS NULL AND status != 'closed'`),s=[];for(const r of t.values){const n=await e.query(`SELECT COALESCE(SUM(sm.qty * sm.unit_cost), 0) as cost
       FROM stock_movements sm
       WHERE sm.to_type = 'job' AND sm.to_id = ? AND sm.deleted_at IS NULL`,[r.id]),i=await e.query(`SELECT COALESCE(SUM(hours * pay_rate), 0) as cost
       FROM labor_entries
       WHERE job_id = ? AND deleted_at IS NULL`,[r.id]),o=(n.values[0]?.cost??0)+(i.values[0]?.cost??0),c=o/r.budget_limit*100;c>=80&&s.push({job_id:r.id,job_name:r.job_name,budget_limit:r.budget_limit,current_spend:o,pct_used:c,alert_level:c>=100?"danger":"warning"})}return s.sort((r,n)=>n.pct_used-r.pct_used)}async function ji(){const e=await p(),t=new Date().toISOString().slice(0,10),s=await e.query(`SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE status = 'draft' AND deleted_at IS NULL`),r=await e.query(`SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE status = 'approved' AND deleted_at IS NULL`),n=await e.query(`SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE status = 'return_pending' AND deleted_at IS NULL`),i=await e.query(`SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE expected_delivery < ? AND status IN ('submitted','acknowledged')
       AND deleted_at IS NULL`,[t]),o={jpos_awaiting_approval:s.values[0]?.cnt??0,pos_to_submit:r.values[0]?.cnt??0,returns_to_sort:n.values[0]?.cnt??0,overdue_deliveries:i.values[0]?.cnt??0},c=new Date;c.setDate(c.getDate()+7);const d=c.toISOString().slice(0,10),u=(await e.query(`SELECT po.id as po_id, po.po_number,
       s.name as supplier_name,
       po.expected_delivery,
       (SELECT COUNT(*) FROM purchase_order_lines pol WHERE pol.po_id = po.id) as line_count,
       CASE WHEN po.expected_delivery < ? THEN 1 ELSE 0 END as is_overdue
     FROM purchase_orders po
     LEFT JOIN suppliers s ON s.id = po.supplier_id
     WHERE po.expected_delivery IS NOT NULL
       AND po.expected_delivery <= ?
       AND po.status IN ('submitted','acknowledged')
       AND po.deleted_at IS NULL
     ORDER BY po.expected_delivery ASC`,[t,d])).values,E=u.filter(T=>!T.is_overdue),_=u.filter(T=>T.is_overdue),m=await e.query(`SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE DATE(created_at) = ? AND deleted_at IS NULL`,[t]),y=await e.query(`SELECT COUNT(*) as cnt FROM receiving_session_items
     WHERE DATE(created_at) = ? AND deleted_at IS NULL AND qty_received > 0`,[t]),f=await e.query(`SELECT COUNT(*) as cnt FROM purchase_orders
     WHERE DATE(updated_at) = ? AND status = 'returned' AND deleted_at IS NULL`,[t]),v={orders_created:m.values[0]?.cnt??0,items_received:y.values[0]?.cnt??0,returns_processed:f.values[0]?.cnt??0},h=await ns();return{pending_actions:o,expected_deliveries:E,overdue_items:_,todays_activity:v,budget_alerts:h}}const de=Object.freeze(Object.defineProperty({__proto__:null,clearCustomMargin:xi,enforceDefaultMargin:bi,getBudgetAlerts:ns,getCompanySettings:gi,getCostHistory:Ni,getCostLayers:Ti,getDailyReport:ji,getJobBudgetStatus:Ci,getJobCostRollup:Si,getPartCostSummary:ea,getPriceVarianceReport:Oi,getSpendingByCategory:Ri,getSpendingByJob:wi,getSpendingBySupplier:vi,getSpendingSummary:fi,getSpendingTrend:Li,setCustomMargin:hi},Symbol.toStringTag,{value:"Module"}));async function Ai(e){return(await(await p()).query(`SELECT tor.*, u.display_name as user_name,
       au.display_name as approver_name
     FROM time_off_requests tor
     JOIN users u ON u.id = tor.user_id
     LEFT JOIN users au ON au.id = tor.approved_by
     WHERE tor.user_id = ?
     ORDER BY tor.start_date DESC`,[e])).values}async function Ii(e){return(await(await p()).query(`SELECT da.*,
       j.job_name, j.job_number,
       j.address_line1 as job_address,
       u.display_name as user_name
     FROM dispatch_assignments da
     JOIN jobs j ON j.id = da.job_id
     JOIN users u ON u.id = da.user_id
     WHERE da.dispatch_date = ?
     ORDER BY u.display_name ASC, da.start_time ASC`,[e])).values}const Sy=Object.freeze(Object.defineProperty({__proto__:null,getDispatchForDate:Ii,getMyTimeOff:Ai},Symbol.toStringTag,{value:"Module"}));async function ki(){const e=await p(),t=(await e.query("SELECT * FROM part_categories WHERE is_active = 1 ORDER BY sort_order, name")).values,s=(await e.query("SELECT * FROM part_styles WHERE is_active = 1 ORDER BY sort_order, name")).values,r=(await e.query("SELECT * FROM part_types WHERE is_active = 1 ORDER BY sort_order, name")).values,n=(await e.query("SELECT * FROM part_colors WHERE is_active = 1 ORDER BY sort_order, name")).values,i=(await e.query("SELECT * FROM type_color_links")).values,o=(await e.query("SELECT * FROM type_brand_links")).values,c={};for(const E of i){c[E.type_id]||(c[E.type_id]=[]);const _=n.find(m=>m.id===E.color_id);_&&c[E.type_id].push({..._,link_id:E.id,image_url:E.image_url})}const d={};for(const E of o)d[E.type_id]||(d[E.type_id]=[]),d[E.type_id].push({link_id:E.id,brand_id:E.brand_id});const l={};for(const E of r)l[E.style_id]||(l[E.style_id]=[]),l[E.style_id].push({...E,colors:c[E.id]??[],brand_links:d[E.id]??[]});const u={};for(const E of s)u[E.category_id]||(u[E.category_id]=[]),u[E.category_id].push({...E,types:l[E.id]??[]});return{categories:t.map(E=>({...E,styles:u[E.id]??[]}))}}async function Di(e){const t=await p(),s=[],r=[];e?.is_active!==void 0&&(s.push("is_active = ?"),r.push(e.is_active?1:0)),e?.search&&(s.push("name LIKE ?"),r.push(`%${e.search}%`));const n=s.length?`WHERE ${s.join(" AND ")}`:"";return(await t.query(`SELECT * FROM part_categories ${n} ORDER BY sort_order, name`,r)).values}async function Fi(e){const t=await p(),s=await t.run("INSERT INTO part_categories (name, description, sort_order, is_active) VALUES (?, ?, ?, ?)",[e.name,e.description??null,e.sort_order??0,e.is_active??1]);return await X("part_categories",s.changes.lastId,"INSERT"),(await t.query("SELECT * FROM part_categories WHERE id = ?",[s.changes.lastId])).values[0]}async function Ui(e,t){const s=await p(),r=[],n=[];for(const[i,o]of Object.entries(t))r.push(`${i} = ?`),n.push(o);return r.length&&(r.push("updated_at = datetime('now')"),n.push(e),await s.run(`UPDATE part_categories SET ${r.join(", ")} WHERE id = ?`,n),await X("part_categories",e,"UPDATE",Object.keys(t))),(await s.query("SELECT * FROM part_categories WHERE id = ?",[e])).values[0]}async function Pi(e){await(await p()).run("DELETE FROM part_categories WHERE id = ?",[e]),await X("part_categories",e,"DELETE")}async function Mi(e,t){const s=await p(),r=["category_id = ?"],n=[e];return t?.is_active!==void 0&&(r.push("is_active = ?"),n.push(t.is_active?1:0)),(await s.query(`SELECT * FROM part_styles WHERE ${r.join(" AND ")} ORDER BY sort_order, name`,n)).values}async function Xi(e){const t=await p(),s=await t.run("INSERT INTO part_styles (category_id, name, description, image_url, sort_order, is_active) VALUES (?,?,?,?,?,?)",[e.category_id,e.name,e.description??null,e.image_url??null,e.sort_order??0,e.is_active??1]);return await X("part_styles",s.changes.lastId,"INSERT"),(await t.query("SELECT * FROM part_styles WHERE id = ?",[s.changes.lastId])).values[0]}async function qi(e,t){const s=await p(),r=[],n=[];for(const[i,o]of Object.entries(t))r.push(`${i} = ?`),n.push(o);return r.length&&(r.push("updated_at = datetime('now')"),n.push(e),await s.run(`UPDATE part_styles SET ${r.join(", ")} WHERE id = ?`,n),await X("part_styles",e,"UPDATE",Object.keys(t))),(await s.query("SELECT * FROM part_styles WHERE id = ?",[e])).values[0]}async function Gi(e){await(await p()).run("DELETE FROM part_styles WHERE id = ?",[e]),await X("part_styles",e,"DELETE")}async function Bi(e,t){const s=await p(),r=["style_id = ?"],n=[e];return t?.is_active!==void 0&&(r.push("is_active = ?"),n.push(t.is_active?1:0)),(await s.query(`SELECT * FROM part_types WHERE ${r.join(" AND ")} ORDER BY sort_order, name`,n)).values}async function $i(e){return(await(await p()).query("SELECT * FROM part_types WHERE id = ?",[e])).values[0]??null}async function Hi(e){const t=await p(),s=await t.run("INSERT INTO part_types (style_id, name, description, color, image_url, sort_order, is_active) VALUES (?,?,?,?,?,?,?)",[e.style_id,e.name,e.description??null,e.color??null,e.image_url??null,e.sort_order??0,e.is_active??1]);return await X("part_types",s.changes.lastId,"INSERT"),(await t.query("SELECT * FROM part_types WHERE id = ?",[s.changes.lastId])).values[0]}async function Wi(e,t){const s=await p(),r=[],n=[];for(const[i,o]of Object.entries(t))r.push(`${i} = ?`),n.push(o);return r.length&&(r.push("updated_at = datetime('now')"),n.push(e),await s.run(`UPDATE part_types SET ${r.join(", ")} WHERE id = ?`,n),await X("part_types",e,"UPDATE",Object.keys(t))),(await s.query("SELECT * FROM part_types WHERE id = ?",[e])).values[0]}async function Ki(e){await(await p()).run("DELETE FROM part_types WHERE id = ?",[e]),await X("part_types",e,"DELETE")}async function is(e){return(await(await p()).query(`SELECT tcl.*, pc.name as color_name, pc.hex_code
     FROM type_color_links tcl
     JOIN part_colors pc ON pc.id = tcl.color_id
     WHERE tcl.type_id = ? ORDER BY tcl.sort_order`,[e])).values}async function Yi(e,t){const s=await p();for(const r of t)await s.run("INSERT OR IGNORE INTO type_color_links (type_id, color_id) VALUES (?, ?)",[e,r]);return is(e)}async function Vi(e,t){await(await p()).run("DELETE FROM type_color_links WHERE type_id = ? AND color_id = ?",[e,t])}async function Ji(e){return(await(await p()).query(`SELECT tbl.*, b.name as brand_name
     FROM type_brand_links tbl
     LEFT JOIN brands b ON b.id = tbl.brand_id
     WHERE tbl.type_id = ?`,[e])).values}async function Qi(e,t){const s=await p(),r=await s.run(`INSERT INTO type_brand_links (type_id, brand_id) VALUES (?, ?)
     ON CONFLICT(type_id, COALESCE(brand_id, 0)) DO NOTHING`,[e,t]);return r.changes.lastId&&await X("type_brand_links",r.changes.lastId,"INSERT"),(await s.query("SELECT * FROM type_brand_links WHERE type_id = ? AND COALESCE(brand_id, 0) = ?",[e,t??0])).values[0]}async function zi(e,t){const s=await p();t===null||t===0?await s.run("DELETE FROM type_brand_links WHERE type_id = ? AND brand_id IS NULL",[e]):await s.run("DELETE FROM type_brand_links WHERE type_id = ? AND brand_id = ?",[e,t])}async function Zi(e,t){const s=await p();return t===null||t===0?(await s.query("SELECT * FROM parts WHERE type_id = ? AND brand_id IS NULL AND is_active = 1 ORDER BY name",[e])).values:(await s.query("SELECT * FROM parts WHERE type_id = ? AND brand_id = ? AND is_active = 1 ORDER BY name",[e,t])).values}async function eo(e,t,s){const r=await p(),n=(await r.query("SELECT pt.*, ps.category_id FROM part_types pt JOIN part_styles ps ON ps.id = pt.style_id WHERE pt.id = ?",[e])).values[0],i=(await r.query("SELECT name FROM part_colors WHERE id = ?",[s])).values[0],o=t?(await r.query("SELECT name FROM brands WHERE id = ?",[t])).values[0]:null,c=`${n?.name??""} ${i?.name??""}${o?` (${o.name})`:""}`.trim(),d=await r.run("INSERT INTO parts (category_id, style_id, type_id, color_id, brand_id, name, part_type) VALUES (?,?,?,?,?,?,?)",[n?.category_id,n?.style_id,e,s,t,c,t?"specific":"general"]);return await X("parts",d.changes.lastId,"INSERT"),(await r.query("SELECT * FROM parts WHERE id = ?",[d.changes.lastId])).values[0]}async function to(e){const t=await p(),s=[],r=[];e?.is_active!==void 0&&(s.push("is_active = ?"),r.push(e.is_active?1:0)),e?.search&&(s.push("name LIKE ?"),r.push(`%${e.search}%`));const n=s.length?`WHERE ${s.join(" AND ")}`:"";return(await t.query(`SELECT * FROM part_colors ${n} ORDER BY sort_order, name`,r)).values}async function ao(e){const t=await p(),s=await t.run("INSERT INTO part_colors (name, hex_code, sort_order, is_active) VALUES (?,?,?,?)",[e.name,e.hex_code??null,e.sort_order??0,e.is_active??1]);return await X("part_colors",s.changes.lastId,"INSERT"),(await t.query("SELECT * FROM part_colors WHERE id = ?",[s.changes.lastId])).values[0]}async function so(e,t){const s=await p(),r=[],n=[];for(const[i,o]of Object.entries(t))r.push(`${i} = ?`),n.push(o);return r.length&&(n.push(e),await s.run(`UPDATE part_colors SET ${r.join(", ")} WHERE id = ?`,n),await X("part_colors",e,"UPDATE",Object.keys(t))),(await s.query("SELECT * FROM part_colors WHERE id = ?",[e])).values[0]}async function ro(e){await(await p()).run("DELETE FROM part_colors WHERE id = ?",[e]),await X("part_colors",e,"DELETE")}async function no(e){const t=await p(),s=["p.is_active = 1"],r=[];if(e?.search){s.push("(p.name LIKE ? OR p.code LIKE ? OR p.description LIKE ?)");const l=`%${e.search}%`;r.push(l,l,l)}e?.category_id&&(s.push("p.category_id = ?"),r.push(e.category_id)),e?.style_id&&(s.push("p.style_id = ?"),r.push(e.style_id)),e?.type_id&&(s.push("p.type_id = ?"),r.push(e.type_id)),e?.brand_id&&(s.push("p.brand_id = ?"),r.push(e.brand_id)),e?.is_deprecated!==void 0&&(s.push("p.is_deprecated = ?"),r.push(e.is_deprecated?1:0));const n=`WHERE ${s.join(" AND ")}`,i=e?.page_size??e?.limit??100,o=e?.page?(e.page-1)*i:e?.offset??0,c=await t.query(`SELECT COUNT(*) as cnt FROM parts p ${n}`,r);return{items:(await t.query(`SELECT p.*,
       c.name as category_name,
       ps.name as style_name,
       pt.name as type_name,
       b.name as brand_name,
       pc.name as color_name,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p
     LEFT JOIN part_categories c ON c.id = p.category_id
     LEFT JOIN part_styles ps ON ps.id = p.style_id
     LEFT JOIN part_types pt ON pt.id = p.type_id
     LEFT JOIN brands b ON b.id = p.brand_id
     LEFT JOIN part_colors pc ON pc.id = p.color_id
     ${n}
     ORDER BY p.name ASC
     LIMIT ? OFFSET ?`,[...r,i,o])).values,total:c.values[0]?.cnt??0}}async function os(e){return(await(await p()).query(`SELECT p.*,
       c.name as category_name,
       ps.name as style_name,
       pt.name as type_name,
       b.name as brand_name,
       pc.name as color_name,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p
     LEFT JOIN part_categories c ON c.id = p.category_id
     LEFT JOIN part_styles ps ON ps.id = p.style_id
     LEFT JOIN part_types pt ON pt.id = p.type_id
     LEFT JOIN brands b ON b.id = p.brand_id
     LEFT JOIN part_colors pc ON pc.id = p.color_id
     WHERE p.id = ?`,[e])).values[0]??null}async function io(e,t){const s=await p(),r=[],n=[];for(const[i,o]of Object.entries(t))r.push(`${i} = ?`),n.push(o);return r.length&&(r.push("updated_at = datetime('now')"),n.push(e),await s.run(`UPDATE parts SET ${r.join(", ")} WHERE id = ?`,n),await X("parts",e,"UPDATE",Object.keys(t))),os(e)}async function oo(e){const t=await p();if((await t.query("SELECT SUM(qty) as total FROM stock WHERE part_id = ?",[e])).values[0]?.total>0)throw new Error("Cannot delete part with existing stock");await t.run("DELETE FROM parts WHERE id = ?",[e]),await X("parts",e,"DELETE")}async function co(e){const t=await p(),s=["p.is_active = 1"],r=[];if(e?.search){s.push("(p.name LIKE ? OR p.code LIKE ?)");const o=`%${e.search}%`;r.push(o,o)}e?.category_id&&(s.push("p.category_id = ?"),r.push(e.category_id)),e?.is_deprecated!==void 0&&(s.push("p.is_deprecated = ?"),r.push(e.is_deprecated?1:0));const n=s.join(" AND ");return(await t.query(`SELECT p.category_id, c.name as category_name, p.brand_id, b.name as brand_name, COUNT(*) as part_count
     FROM parts p
     LEFT JOIN part_categories c ON c.id = p.category_id
     LEFT JOIN brands b ON b.id = p.brand_id
     WHERE ${n}
     GROUP BY p.category_id, p.brand_id
     ORDER BY c.name, b.name`,r)).values}async function lo(){return(await(await p()).query("SELECT COUNT(*) as cnt FROM parts WHERE brand_id IS NOT NULL AND (manufacturer_part_number IS NULL OR manufacturer_part_number = '')")).values[0]?.cnt??0}async function uo(e,t){const s=await p(),r=[],n=[];t.company_cost_price!==void 0&&(r.push("company_cost_price = ?"),n.push(t.company_cost_price)),t.company_markup_percent!==void 0&&(r.push("company_markup_percent = ?"),n.push(t.company_markup_percent)),r.length&&(r.push("updated_at = datetime('now')"),n.push(e),await s.run(`UPDATE parts SET ${r.join(", ")} WHERE id = ?`,n),await X("parts",e,"UPDATE",["company_cost_price","company_markup_percent"]))}async function _o(e){const t=await p(),s=[],r=[];e?.is_active!==void 0&&(s.push("b.is_active = ?"),r.push(e.is_active?1:0)),e?.search&&(s.push("b.name LIKE ?"),r.push(`%${e.search}%`));const n=s.length?`WHERE ${s.join(" AND ")}`:"";return(await t.query(`SELECT b.*,
       (SELECT COUNT(*) FROM parts WHERE brand_id = b.id) as part_count,
       (SELECT COUNT(*) FROM brand_supplier_links WHERE brand_id = b.id) as supplier_count
     FROM brands b ${n} ORDER BY b.name`,r)).values}async function Eo(e){const t=await p(),s=await t.run("INSERT INTO brands (name, website, notes, is_active) VALUES (?,?,?,?)",[e.name,e.website??null,e.notes??null,e.is_active??1]);return await X("brands",s.changes.lastId,"INSERT"),(await t.query("SELECT * FROM brands WHERE id = ?",[s.changes.lastId])).values[0]}async function po(e,t){const s=await p(),r=[],n=[];for(const[i,o]of Object.entries(t))r.push(`${i} = ?`),n.push(o);return r.length&&(r.push("updated_at = datetime('now')"),n.push(e),await s.run(`UPDATE brands SET ${r.join(", ")} WHERE id = ?`,n),await X("brands",e,"UPDATE",Object.keys(t))),(await s.query("SELECT * FROM brands WHERE id = ?",[e])).values[0]}async function mo(e){await(await p()).run("DELETE FROM brands WHERE id = ?",[e]),await X("brands",e,"DELETE")}async function yo(e){return(await(await p()).query(`SELECT bsl.*, s.name as supplier_name
     FROM brand_supplier_links bsl
     JOIN suppliers s ON s.id = bsl.supplier_id
     WHERE bsl.brand_id = ? AND bsl.is_active = 1`,[e])).values}async function go(e){return(await(await p()).query(`SELECT bsl.*, b.name as brand_name
     FROM brand_supplier_links bsl
     JOIN brands b ON b.id = bsl.brand_id
     WHERE bsl.supplier_id = ? AND bsl.is_active = 1`,[e])).values}async function To(e){const t=await p(),s=await t.run(`INSERT INTO brand_supplier_links (brand_id, supplier_id, account_number, notes)
     VALUES (?,?,?,?)`,[e.brand_id,e.supplier_id,e.account_number??null,e.notes??null]);return await X("brand_supplier_links",s.changes.lastId,"INSERT"),(await t.query("SELECT * FROM brand_supplier_links WHERE id = ?",[s.changes.lastId])).values[0]}async function No(e){await(await p()).run("DELETE FROM brand_supplier_links WHERE id = ?",[e]),await X("brand_supplier_links",e,"DELETE")}async function ho(e){const t=await p(),s=[],r=[];e?.is_active!==void 0&&(s.push("is_active = ?"),r.push(e.is_active?1:0)),e?.search&&(s.push("name LIKE ?"),r.push(`%${e.search}%`));const n=s.length?`WHERE ${s.join(" AND ")}`:"";return(await t.query(`SELECT s.*,
       (SELECT COUNT(*) FROM brand_supplier_links WHERE supplier_id = s.id) as brand_count
     FROM suppliers s ${n} ORDER BY s.name`,r)).values}async function xo(e){const t=await p(),s=["name","contact_name","email","phone","address","website","rep_name","rep_email","rep_phone","notes","delivery_method","delivery_days","special_order_lead_days","delivery_notes","driver_name","driver_phone","driver_email"],r=s.map(i=>e[i]??null),n=await t.run(`INSERT INTO suppliers (${s.join(",")}) VALUES (${s.map(()=>"?").join(",")})`,r);return await X("suppliers",n.changes.lastId,"INSERT"),(await t.query("SELECT * FROM suppliers WHERE id = ?",[n.changes.lastId])).values[0]}async function bo(e,t){const s=await p(),r=[],n=[];for(const[i,o]of Object.entries(t))r.push(`${i} = ?`),n.push(o);return r.length&&(r.push("updated_at = datetime('now')"),n.push(e),await s.run(`UPDATE suppliers SET ${r.join(", ")} WHERE id = ?`,n),await X("suppliers",e,"UPDATE",Object.keys(t))),(await s.query("SELECT * FROM suppliers WHERE id = ?",[e])).values[0]}async function fo(e){await(await p()).run("DELETE FROM suppliers WHERE id = ?",[e]),await X("suppliers",e,"DELETE")}async function vo(e){const t=await p(),s=e?.page_size??50,r=e?.page?(e.page-1)*s:0,n=(await t.query("SELECT COUNT(*) as cnt FROM parts WHERE is_active = 1")).values[0];return{items:(await t.query(`SELECT p.id, p.code, p.name, p.brand_id,
       p.forecast_adu_30, p.forecast_adu_90,
       p.forecast_reorder_point, p.forecast_target_qty,
       p.forecast_suggested_order, p.forecast_days_until_low,
       p.forecast_last_run,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p WHERE p.is_active = 1 ORDER BY p.forecast_days_until_low ASC
     LIMIT ? OFFSET ?`,[s,r])).values,total:n?.cnt??0}}async function Ro(){const e=await p(),t=new Date().toISOString(),s=(await e.query("SELECT id FROM parts WHERE is_active = 1")).values;let r=0,n=0;for(const i of s)try{const c=((await e.query(`SELECT COALESCE(SUM(qty), 0) as total FROM stock_movements
         WHERE part_id = ? AND movement_type = 'consume'
         AND created_at >= datetime('now', '-30 days')`,[i.id])).values[0]?.total??0)/30,l=((await e.query(`SELECT COALESCE(SUM(qty), 0) as total FROM stock_movements
         WHERE part_id = ? AND movement_type = 'consume'
         AND created_at >= datetime('now', '-90 days')`,[i.id])).values[0]?.total??0)/90,u=Math.max(c,l),E=Math.ceil(u*14),_=Math.ceil(u*30),m=(await e.query("SELECT COALESCE(SUM(qty), 0) as total FROM stock WHERE part_id = ? AND location_type = 'warehouse'",[i.id])).values[0]?.total??0,y=u>0?Math.floor(m/u):999,f=Math.max(0,_-m);await e.run(`UPDATE parts SET forecast_adu_30 = ?, forecast_adu_90 = ?,
         forecast_reorder_point = ?, forecast_target_qty = ?,
         forecast_suggested_order = ?, forecast_days_until_low = ?,
         forecast_last_run = ? WHERE id = ?`,[c,l,E,_,f,y,t,i.id]),r++}catch{n++}return{recalculated:r,errors:n,total_parts:s.length}}async function wo(){const t=(await(await p()).query(`SELECT p.*, c.name as category_name, b.name as brand_name
     FROM parts p
     LEFT JOIN part_categories c ON c.id = p.category_id
     LEFT JOIN brands b ON b.id = p.brand_id
     WHERE p.is_active = 1 ORDER BY p.name`)).values,s=`id,code,name,category,brand,cost_price,markup,sell_price,uom,min_stock,max_stock,reorder_point
`,r=t.map(n=>`${n.id},"${n.code??""}","${n.name}","${n.category_name??""}","${n.brand_name??""}",${n.company_cost_price},${n.company_markup_percent},${n.company_sell_price},"${n.unit_of_measure}",${n.min_stock_level},${n.max_stock_level},${n.reorder_point}`).join(`
`);return new Blob([s+r],{type:"text/csv"})}async function Lo(e){const s=(await e.text()).split(`
`).filter(o=>o.trim());if(s.length<2)return{created:0,updated:0,errors:0,skipped:0};const r=await p();let n=0,i=0;for(let o=1;o<s.length;o++)try{const c=s[o].split(",").map(y=>y.replace(/^"|"$/g,"").trim()),[,d,l,,,u,E]=c;if(!l)continue;const _=parseFloat(u)||0,m=parseFloat(E)||0;await r.run(`INSERT INTO parts (code, name, category_id, company_cost_price, company_markup_percent)
         VALUES (?, ?, 1, ?, ?)`,[d||null,l,_,m]),n++}catch{i++}return{created:n,updated:0,errors:i,skipped:0}}async function ta(){const e=await p(),t=(await e.query("SELECT * FROM companion_rules ORDER BY name")).values;for(const s of t)s.sources=(await e.query(`SELECT crs.*, c.name as category_name, s.name as style_name
       FROM companion_rule_sources crs
       JOIN part_categories c ON c.id = crs.category_id
       LEFT JOIN part_styles s ON s.id = crs.style_id
       WHERE crs.rule_id = ?`,[s.id])).values,s.targets=(await e.query(`SELECT crt.*, c.name as category_name, s.name as style_name
       FROM companion_rule_targets crt
       JOIN part_categories c ON c.id = crt.category_id
       LEFT JOIN part_styles s ON s.id = crt.style_id
       WHERE crt.rule_id = ?`,[s.id])).values;return t}async function So(e){const t=await p(),r=(await t.run(`INSERT INTO companion_rules (name, description, style_match, qty_mode, qty_ratio, is_active, created_by)
     VALUES (?,?,?,?,?,?,?)`,[e.name,e.description??null,e.style_match??"auto",e.qty_mode??"sum",e.qty_ratio??1,e.is_active??1,e.created_by??null])).changes.lastId;await X("companion_rules",r,"INSERT");for(const n of e.sources??[])await t.run("INSERT INTO companion_rule_sources (rule_id, category_id, style_id) VALUES (?,?,?)",[r,n.category_id,n.style_id??null]);for(const n of e.targets??[])await t.run("INSERT INTO companion_rule_targets (rule_id, category_id, style_id) VALUES (?,?,?)",[r,n.category_id,n.style_id??null]);return(await ta()).find(n=>n.id===r)}async function Co(e,t){const s=await p(),r=[],n=[];for(const i of["name","description","style_match","qty_mode","qty_ratio","is_active"])t[i]!==void 0&&(r.push(`${i} = ?`),n.push(t[i]));if(r.length&&(r.push("updated_at = datetime('now')"),n.push(e),await s.run(`UPDATE companion_rules SET ${r.join(", ")} WHERE id = ?`,n),await X("companion_rules",e,"UPDATE")),t.sources){await s.run("DELETE FROM companion_rule_sources WHERE rule_id = ?",[e]);for(const i of t.sources)await s.run("INSERT INTO companion_rule_sources (rule_id, category_id, style_id) VALUES (?,?,?)",[e,i.category_id,i.style_id??null])}if(t.targets){await s.run("DELETE FROM companion_rule_targets WHERE rule_id = ?",[e]);for(const i of t.targets)await s.run("INSERT INTO companion_rule_targets (rule_id, category_id, style_id) VALUES (?,?,?)",[e,i.category_id,i.style_id??null])}return(await ta()).find(i=>i.id===e)}async function Oo(e){await(await p()).run("DELETE FROM companion_rules WHERE id = ?",[e]),await X("companion_rules",e,"DELETE")}async function jo(e){const t=await p(),s=e.items??[];if(!s.length)return[];const r=[...new Set(s.map(c=>c.category_id))],n=r.map(()=>"?").join(","),i=(await t.query(`SELECT DISTINCT cr.* FROM companion_rules cr
     JOIN companion_rule_sources crs ON crs.rule_id = cr.id
     WHERE cr.is_active = 1 AND crs.category_id IN (${n})`,r)).values,o=[];for(const c of i){const d=(await t.query(`SELECT crt.*, c.name as category_name FROM companion_rule_targets crt
       JOIN part_categories c ON c.id = crt.category_id WHERE crt.rule_id = ?`,[c.id])).values;for(const l of d){const u=s.reduce((y,f)=>y+(f.qty??1),0),E=c.qty_mode==="sum"?u:c.qty_mode==="max"?Math.max(...s.map(y=>y.qty??1)):Math.ceil(u*(c.qty_ratio??1)),_=await t.run(`INSERT INTO companion_suggestions (rule_id, target_category_id, target_style_id, target_description, suggested_qty, reason_type, reason_text, triggered_by)
         VALUES (?,?,?,?,?,?,?,?)`,[c.id,l.category_id,l.style_id??null,`${l.category_name} companion`,E,"rule",`Rule: ${c.name}`,e.triggered_by??null]),m=(await t.query("SELECT * FROM companion_suggestions WHERE id = ?",[_.changes.lastId])).values[0];o.push(m)}}return o}async function Ao(e){const t=await p(),s=[],r=[];e?.status&&(s.push("status = ?"),r.push(e.status));const n=s.length?`WHERE ${s.join(" AND ")}`:"",i=e?.page_size??50,o=e?.page?(e.page-1)*i:0;return(await t.query(`SELECT cs.*, c.name as target_category_name
     FROM companion_suggestions cs
     JOIN part_categories c ON c.id = cs.target_category_id
     ${n} ORDER BY cs.created_at DESC LIMIT ? OFFSET ?`,[...r,i,o])).values}async function Io(e,t){const s=await p();return await s.run(`UPDATE companion_suggestions SET status = ?, decided_by = ?, decided_at = datetime('now'),
     approved_qty = ?, notes = ? WHERE id = ?`,[t.decision,t.decided_by??null,t.approved_qty??null,t.notes??null,e]),await X("companion_suggestions",e,"UPDATE"),(await s.query("SELECT * FROM companion_suggestions WHERE id = ?",[e])).values[0]}async function ko(){const e=await p(),t=(await e.query("SELECT COUNT(*) as cnt FROM companion_rules WHERE is_active = 1")).values[0],s=(await e.query("SELECT COUNT(*) as cnt FROM companion_suggestions WHERE status = 'pending'")).values[0],r=(await e.query("SELECT COUNT(*) as cnt FROM companion_suggestions WHERE status = 'approved'")).values[0],n=(await e.query("SELECT COUNT(*) as cnt FROM co_occurrence_pairs")).values[0];return{active_rules:t?.cnt??0,pending_suggestions:s?.cnt??0,approved_suggestions:r?.cnt??0,co_occurrence_pairs:n?.cnt??0}}async function Do(e){return(await(await p()).query(`SELECT pa.*, p.name as alternative_name, p.code as alternative_code
     FROM part_alternatives pa
     JOIN parts p ON p.id = pa.alternative_part_id
     WHERE pa.part_id = ?
     UNION ALL
     SELECT pa.*, p.name as alternative_name, p.code as alternative_code
     FROM part_alternatives pa
     JOIN parts p ON p.id = pa.part_id
     WHERE pa.alternative_part_id = ?`,[e,e])).values}async function Fo(e,t){const s=await p(),r=await s.run(`INSERT INTO part_alternatives (part_id, alternative_part_id, relationship, preference, notes, created_by)
     VALUES (?,?,?,?,?,?)`,[e,t.alternative_part_id,t.relationship??"substitute",t.preference??0,t.notes??null,t.created_by??null]);return await X("part_alternatives",r.changes.lastId,"INSERT"),(await s.query("SELECT * FROM part_alternatives WHERE id = ?",[r.changes.lastId])).values[0]}async function Uo(e,t){const s=await p(),r=[],n=[];for(const[i,o]of Object.entries(t))r.push(`${i} = ?`),n.push(o);return r.length&&(n.push(e),await s.run(`UPDATE part_alternatives SET ${r.join(", ")} WHERE id = ?`,n),await X("part_alternatives",e,"UPDATE",Object.keys(t))),(await s.query("SELECT * FROM part_alternatives WHERE id = ?",[e])).values[0]}async function Po(e){await(await p()).run("DELETE FROM part_alternatives WHERE id = ?",[e]),await X("part_alternatives",e,"DELETE")}const U=Object.freeze(Object.defineProperty({__proto__:null,createBrand:Eo,createBrandSupplierLink:To,createCategory:Fi,createColor:ao,createCompanionRule:So,createStyle:Xi,createSupplier:xo,createType:Hi,decideCompanionSuggestion:Io,deleteBrand:mo,deleteBrandSupplierLink:No,deleteCategory:Pi,deleteColor:ro,deleteCompanionRule:Oo,deletePart:oo,deleteStyle:Gi,deleteSupplier:fo,deleteType:Ki,exportPartsCsv:wo,generateCompanionSuggestions:jo,getBrandSuppliers:yo,getCatalogGroups:co,getCategories:Di,getCompanionStats:ko,getForecasting:vo,getHierarchy:ki,getPart:os,getPendingPartNumbersCount:lo,getSupplierBrands:go,getType:$i,importPartsCsv:Lo,linkBrandToType:Qi,linkColorsToType:Yi,linkPartAlternative:Fo,listBrands:_o,listColors:to,listCompanionRules:ta,listCompanionSuggestions:Ao,listPartAlternatives:Do,listParts:no,listPartsForTypeBrand:Zi,listStylesByCategory:Mi,listSuppliers:ho,listTypeBrands:Ji,listTypeColors:is,listTypesByStyle:Bi,quickCreatePart:eo,recalculateForecasts:Ro,unlinkBrandFromType:zi,unlinkColorFromType:Vi,unlinkPartAlternative:Po,updateBrand:po,updateCategory:Ui,updateColor:so,updateCompanionRule:Co,updatePart:io,updatePartAlternative:Uo,updatePartPricing:uo,updateStyle:qi,updateSupplier:bo,updateType:Wi},Symbol.toStringTag,{value:"Module"}));function fp(e){switch(e.split(".").pop()?.toLowerCase()){case"csv":return[{name:"CSV Files",extensions:["csv"]}];case"pdf":return[{name:"PDF Documents",extensions:["pdf"]}];case"json":return[{name:"JSON Files",extensions:["json"]}];case"iif":return[{name:"IIF Files (QuickBooks)",extensions:["iif"]}];case"xlsx":return[{name:"Excel Files",extensions:["xlsx"]}];case"zip":return[{name:"ZIP Archives",extensions:["zip"]}];case"db":case"sqlite":return[{name:"Database Files",extensions:["db","sqlite"]}];default:return[{name:"All Files",extensions:["*"]}]}}async function vp(e,t){return ce()?wp(e,t):(Rp(e,t),!0)}function Rp(e,t){let s;e instanceof Blob?s=e:typeof e=="string"?s=new Blob([e],{type:"text/plain;charset=utf-8"}):s=new Blob([e.buffer],{type:"application/octet-stream"});const r=URL.createObjectURL(s),n=document.createElement("a");n.href=r,n.download=t,document.body.appendChild(n),n.click(),document.body.removeChild(n),URL.revokeObjectURL(r)}async function wp(e,t){const{save:s}=await N(async()=>{const{save:o}=await import("./vendor-DivU4Fss.js").then(c=>c.k);return{save:o}},__vite__mapDeps([0,1])),{writeTextFile:r,writeFile:n}=await N(async()=>{const{writeTextFile:o,writeFile:c}=await import("@tauri-apps/plugin-fs");return{writeTextFile:o,writeFile:c}},[]),i=await s({defaultPath:t,filters:fp(t)});if(!i)return!1;if(typeof e=="string")await r(i,e);else if(e instanceof Uint8Array)await n(i,e);else{const o=await e.arrayBuffer();await n(i,new Uint8Array(o))}return!0}async function Lp(e){if(!ce())return null;const{open:t}=await N(async()=>{const{open:o}=await import("./vendor-DivU4Fss.js").then(c=>c.k);return{open:o}},__vite__mapDeps([0,1])),{readTextFile:s}=await N(async()=>{const{readTextFile:o}=await import("@tauri-apps/plugin-fs");return{readTextFile:o}},[]),r=await t({multiple:!1,filters:e??[{name:"All Files",extensions:["*"]}]});if(!r)return null;const n=typeof r=="string"?r:r.path,i=await s(n);return{path:n,contents:i}}const Tr=Object.freeze(Object.defineProperty({__proto__:null,exportFile:vp,importFile:Lp},Symbol.toStringTag,{value:"Module"})),Ze=new Y("customers"),mt=new Y("general_contractors"),Me=new Y("entity_contacts"),Mo=new Y("job_customers"),Xo=new Y("job_general_contractors");async function qo(e={}){const t=await p(),s=e.page??1,r=e.page_size??25,n=["c.deleted_at IS NULL"],i=[];if(e.search){n.push("(c.name LIKE ? OR c.company_name LIKE ? OR c.email LIKE ?)");const u=`%${e.search}%`;i.push(u,u,u)}e.customer_type&&(n.push("c.customer_type = ?"),i.push(e.customer_type)),e.is_active!==void 0&&(n.push("c.is_active = ?"),i.push(e.is_active?1:0));const o=n.join(" AND "),d=(await t.query(`SELECT COUNT(*) as cnt FROM customers c WHERE ${o}`,i)).values[0]?.cnt??0;return{items:(await t.query(`SELECT c.*,
       (SELECT COUNT(*) FROM job_customers jc WHERE jc.customer_id = c.id) as job_count,
       (SELECT COUNT(*) FROM entity_contacts ec
        WHERE ec.entity_type = 'customer' AND ec.entity_id = c.id AND ec.deleted_at IS NULL) as contact_count
     FROM customers c
     WHERE ${o}
     ORDER BY c.name ASC
     LIMIT ? OFFSET ?`,[...i,r,(s-1)*r])).values,total:d,page:s,page_size:r}}async function Go(e,t=20){const s=await p(),r=`%${e}%`;return(await s.query(`SELECT c.*,
       (SELECT COUNT(*) FROM job_customers jc WHERE jc.customer_id = c.id) as job_count,
       (SELECT COUNT(*) FROM entity_contacts ec
        WHERE ec.entity_type = 'customer' AND ec.entity_id = c.id AND ec.deleted_at IS NULL) as contact_count
     FROM customers c
     WHERE c.deleted_at IS NULL AND c.is_active = 1
       AND (c.name LIKE ? OR c.company_name LIKE ?)
     ORDER BY c.name ASC
     LIMIT ?`,[r,r,t])).values}async function aa(e){const t=await p(),r=(await t.query(`SELECT c.*,
       (SELECT COUNT(*) FROM job_customers jc WHERE jc.customer_id = c.id) as job_count
     FROM customers c
     WHERE c.id = ? AND c.deleted_at IS NULL`,[e])).values[0];if(!r)return null;const n=await t.query(`SELECT * FROM entity_contacts
     WHERE entity_type = 'customer' AND entity_id = ? AND deleted_at IS NULL
     ORDER BY is_primary DESC, first_name ASC`,[e]);return r.contacts=n.values,r}async function Bo(e){const t=new Date().toISOString(),s=await Ze.insert({name:e.name??`${e.first_name??""} ${e.last_name??""}`.trim(),company_name:e.company_name??null,customer_type:e.customer_type??"commercial",email:e.email??null,phone:e.phone??null,address:e.address??null,city:e.city??null,state:e.state??null,zip:e.zip??null,notes:e.notes??null,is_active:1,created_at:t,updated_at:t});return aa(s)}async function $o(e,t){return await Ze.update(e,{...t,updated_at:new Date().toISOString()}),aa(e)}async function Ho(e,t){await Ze.update(e,{is_active:t?1:0,updated_at:new Date().toISOString()})}async function Wo(e,t=!1){const s=["entity_type = 'customer'","entity_id = ?","deleted_at IS NULL"],r=[e];return t||s.push("is_active = 1"),await Me.findAll(s.join(" AND "),r,"is_primary DESC, first_name ASC")}async function Ko(e,t){const s=new Date().toISOString();return{id:await Me.insert({entity_type:"customer",entity_id:e,first_name:t.first_name,last_name:t.last_name,title:t.title??t.role??null,email:t.email??null,phone:t.phone??null,is_primary:t.is_primary?1:0,is_active:1,notes:t.notes??null,created_at:s,updated_at:s})}}async function Yo(e){return(await(await p()).query(`SELECT jc.*, j.job_number, j.name as job_name, j.status as job_status,
       j.address as job_address, j.city as job_city, j.state as job_state
     FROM job_customers jc
     JOIN jobs j ON j.id = jc.job_id
     WHERE jc.customer_id = ? AND j.deleted_at IS NULL
     ORDER BY j.created_at DESC`,[e])).values}async function Vo(e={}){const t=await p(),s=e.page??1,r=e.page_size??25,n=["g.deleted_at IS NULL"],i=[];if(e.search){n.push("(g.company_name LIKE ? OR g.contact_name LIKE ? OR g.email LIKE ?)");const u=`%${e.search}%`;i.push(u,u,u)}e.trade_type&&(n.push("g.trade_type = ?"),i.push(e.trade_type)),e.is_active!==void 0&&(n.push("g.is_active = ?"),i.push(e.is_active?1:0));const o=n.join(" AND "),d=(await t.query(`SELECT COUNT(*) as cnt FROM general_contractors g WHERE ${o}`,i)).values[0]?.cnt??0;return{items:(await t.query(`SELECT g.*,
       (SELECT COUNT(*) FROM job_general_contractors jg WHERE jg.gc_id = g.id) as job_count,
       (SELECT COUNT(*) FROM entity_contacts ec
        WHERE ec.entity_type = 'gc' AND ec.entity_id = g.id AND ec.deleted_at IS NULL) as contact_count
     FROM general_contractors g
     WHERE ${o}
     ORDER BY g.company_name ASC
     LIMIT ? OFFSET ?`,[...i,r,(s-1)*r])).values,total:d,page:s,page_size:r}}async function Jo(e,t=20){const s=await p(),r=`%${e}%`;return(await s.query(`SELECT g.*,
       (SELECT COUNT(*) FROM job_general_contractors jg WHERE jg.gc_id = g.id) as job_count,
       (SELECT COUNT(*) FROM entity_contacts ec
        WHERE ec.entity_type = 'gc' AND ec.entity_id = g.id AND ec.deleted_at IS NULL) as contact_count
     FROM general_contractors g
     WHERE g.deleted_at IS NULL AND g.is_active = 1
       AND (g.company_name LIKE ? OR g.contact_name LIKE ?)
     ORDER BY g.company_name ASC
     LIMIT ?`,[r,r,t])).values}async function sa(e){const t=await p(),r=(await t.query(`SELECT g.*,
       (SELECT COUNT(*) FROM job_general_contractors jg WHERE jg.gc_id = g.id) as job_count
     FROM general_contractors g
     WHERE g.id = ? AND g.deleted_at IS NULL`,[e])).values[0];if(!r)return null;const n=await t.query(`SELECT * FROM entity_contacts
     WHERE entity_type = 'gc' AND entity_id = ? AND deleted_at IS NULL
     ORDER BY is_primary DESC, first_name ASC`,[e]);return r.contacts=n.values,r}async function Qo(e){const t=new Date().toISOString(),s=await mt.insert({company_name:e.company_name,contact_name:e.contact_name??null,email:e.email??null,phone:e.phone??null,address:e.address??null,city:e.city??null,state:e.state??null,zip:e.zip??null,relationship:e.relationship??"we_work_for_them",notes:e.notes??null,is_active:1,created_at:t,updated_at:t});return sa(s)}async function zo(e,t){return await mt.update(e,{...t,updated_at:new Date().toISOString()}),sa(e)}async function Zo(e,t){await mt.update(e,{is_active:t?1:0,updated_at:new Date().toISOString()})}async function ec(e,t=!1){const s=["entity_type = 'gc'","entity_id = ?","deleted_at IS NULL"],r=[e];return t||s.push("is_active = 1"),Me.findAll(s.join(" AND "),r,"is_primary DESC, first_name ASC")}async function tc(e,t){const s=new Date().toISOString();return{id:await Me.insert({entity_type:"gc",entity_id:e,first_name:t.first_name,last_name:t.last_name,title:t.title??t.role??null,email:t.email??null,phone:t.phone??null,is_primary:t.is_primary?1:0,is_active:1,notes:t.notes??null,created_at:s,updated_at:s})}}async function ac(e){return(await(await p()).query(`SELECT jg.*, j.job_number, j.name as job_name, j.status as job_status,
       j.address as job_address, j.city as job_city, j.state as job_state
     FROM job_general_contractors jg
     JOIN jobs j ON j.id = jg.job_id
     WHERE jg.gc_id = ? AND j.deleted_at IS NULL
     ORDER BY j.created_at DESC`,[e])).values}async function sc(e,t=!1){const s=["entity_type = 'supplier'","entity_id = ?","deleted_at IS NULL"],r=[e];return t||s.push("is_active = 1"),Me.findAll(s.join(" AND "),r,"is_primary DESC, first_name ASC")}async function rc(e,t){const s=new Date().toISOString();return{id:await Me.insert({entity_type:"supplier",entity_id:e,first_name:t.first_name,last_name:t.last_name,title:t.title??t.role??null,email:t.email??null,phone:t.phone??null,is_primary:t.is_primary?1:0,is_active:1,notes:t.notes??null,created_at:s,updated_at:s})}}async function nc(e,t=50){const s=await p(),r=`%${e}%`;return(await s.query(`SELECT ec.*,
       CASE ec.entity_type
         WHEN 'customer'  THEN (SELECT c.name FROM customers c WHERE c.id = ec.entity_id)
         WHEN 'gc'        THEN (SELECT g.company_name FROM general_contractors g WHERE g.id = ec.entity_id)
         WHEN 'supplier'  THEN (SELECT s.name FROM suppliers s WHERE s.id = ec.entity_id)
       END as entity_name
     FROM entity_contacts ec
     WHERE ec.deleted_at IS NULL
       AND (ec.first_name LIKE ? OR ec.last_name LIKE ? OR ec.email LIKE ? OR ec.phone LIKE ?)
     ORDER BY ec.first_name ASC, ec.last_name ASC
     LIMIT ?`,[r,r,r,r,t])).values}async function ic(e,t){return await Me.update(e,{...t,updated_at:new Date().toISOString()}),{id:e}}async function oc(e){return await Me.update(e,{deleted_at:new Date().toISOString()}),{id:e}}async function cc(e){return(await(await p()).query(`SELECT jc.*, c.name as customer_name, c.company_name,
       c.email, c.phone, c.is_active
     FROM job_customers jc
     JOIN customers c ON c.id = jc.customer_id
     WHERE jc.job_id = ? AND c.deleted_at IS NULL
     ORDER BY c.name ASC`,[e])).values}async function lc(e,t){return{id:await Mo.insert({job_id:e,customer_id:t.customer_id,role:t.contact_role??t.role??null,created_at:new Date().toISOString()})}}async function dc(e,t){await Mo.delete(t)}async function uc(e){return(await(await p()).query(`SELECT jg.*, g.company_name, g.contact_name,
       g.email, g.phone, g.is_active
     FROM job_general_contractors jg
     JOIN general_contractors g ON g.id = jg.gc_id
     WHERE jg.job_id = ? AND g.deleted_at IS NULL
     ORDER BY g.company_name ASC`,[e])).values}async function _c(e,t){return{id:await Xo.insert({job_id:e,gc_id:t.gc_id,role:t.relationship??t.role??null,created_at:new Date().toISOString()})}}async function Ec(e,t){await Xo.delete(t)}async function pc(e){const t={created:0,skipped:0,errors:[]},s=new Date().toISOString();for(let r=0;r<e.length;r++){const n=e[r];try{const i=(n.name??"").trim();if(!i){t.skipped++;continue}if((await Ze.findAll("name = ? AND deleted_at IS NULL",[i])).length>0){t.skipped++;continue}await Ze.insert({name:i,company_name:n.company_name??null,customer_type:n.customer_type??"commercial",email:n.email??null,phone:n.phone??null,address:n.address??null,city:n.city??null,state:n.state??null,zip:n.zip??null,notes:n.notes??null,is_active:1,created_at:s,updated_at:s}),t.created++}catch(i){t.errors.push({row:r+1,error:i.message??String(i)})}}return t}async function mc(e){const t={created:0,skipped:0,errors:[]},s=new Date().toISOString();for(let r=0;r<e.length;r++){const n=e[r];try{const i=(n.company_name??"").trim();if(!i){t.skipped++;continue}if((await mt.findAll("company_name = ? AND deleted_at IS NULL",[i])).length>0){t.skipped++;continue}await mt.insert({company_name:i,contact_name:n.contact_name??null,email:n.email??null,phone:n.phone??null,address:n.address??null,city:n.city??null,state:n.state??null,zip:n.zip??null,relationship:n.relationship??"we_work_for_them",notes:n.notes??null,is_active:1,created_at:s,updated_at:s}),t.created++}catch(i){t.errors.push({row:r+1,error:i.message??String(i)})}}return t}async function yc(e=.8){const t=await p(),s=[],r=await t.query(`SELECT a.id as a_id, a.name as a_name, a.email as a_email, a.phone as a_phone,
            b.id as b_id, b.name as b_name, b.email as b_email, b.phone as b_phone
     FROM customers a
     JOIN customers b ON a.email = b.email AND a.id < b.id
     WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL
       AND a.email IS NOT NULL AND a.email != ''`);for(const c of r.values)s.push({a:{id:c.a_id,name:c.a_name,email:c.a_email,phone:c.a_phone},b:{id:c.b_id,name:c.b_name,email:c.b_email,phone:c.b_phone},similarity:1,match_type:"email"});const n=await t.query(`SELECT a.id as a_id, a.name as a_name, a.email as a_email, a.phone as a_phone,
            b.id as b_id, b.name as b_name, b.email as b_email, b.phone as b_phone
     FROM customers a
     JOIN customers b ON a.phone = b.phone AND a.id < b.id
     WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL
       AND a.phone IS NOT NULL AND a.phone != ''
       AND (a.email IS NULL OR b.email IS NULL OR a.email != b.email)`);for(const c of n.values)s.push({a:{id:c.a_id,name:c.a_name,email:c.a_email,phone:c.a_phone},b:{id:c.b_id,name:c.b_name,email:c.b_email,phone:c.b_phone},similarity:.9,match_type:"phone"});const i=new Set(s.map(c=>`${c.a.id}-${c.b.id}`)),o=await t.query(`SELECT a.id as a_id, a.name as a_name, a.email as a_email, a.phone as a_phone,
            b.id as b_id, b.name as b_name, b.email as b_email, b.phone as b_phone
     FROM customers a
     JOIN customers b ON LOWER(a.name) = LOWER(b.name) AND a.id < b.id
     WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL`);for(const c of o.values){const d=`${c.a_id}-${c.b_id}`;i.has(d)||s.push({a:{id:c.a_id,name:c.a_name,email:c.a_email,phone:c.a_phone},b:{id:c.b_id,name:c.b_name,email:c.b_email,phone:c.b_phone},similarity:.8,match_type:"name"})}return s}async function gc(e,t){const s=await p(),r=new Date().toISOString();return await s.run(`UPDATE entity_contacts
     SET entity_id = ?, updated_at = ?
     WHERE entity_type = 'customer' AND entity_id = ? AND deleted_at IS NULL`,[e,r,t]),await s.run(`UPDATE job_customers
     SET customer_id = ?
     WHERE customer_id = ?
       AND job_id NOT IN (SELECT job_id FROM job_customers WHERE customer_id = ?)`,[e,t,e]),await s.run("DELETE FROM job_customers WHERE customer_id = ?",[t]),await Ze.update(t,{is_active:0,notes:`Merged into customer #${e} on ${r}`,updated_at:r}),{keep_id:e,merged_id:t}}const J=Object.freeze(Object.defineProperty({__proto__:null,addCustomerContact:Ko,addGCContact:tc,addSupplierContact:rc,createCustomer:Bo,createGC:Qo,deleteEntityContact:oc,findDuplicateCustomers:yc,getCustomer:aa,getCustomerContacts:Wo,getCustomerJobs:Yo,getCustomers:qo,getGC:sa,getGCContacts:ec,getGCJobs:ac,getGCs:Vo,getJobCustomers:cc,getJobGCs:uc,getSupplierContacts:sc,importContractorsCSV:mc,importCustomersCSV:pc,linkCustomerToJob:lc,linkGCToJob:_c,mergeCustomers:gc,searchCustomers:Go,searchDirectory:nc,searchGCs:Jo,toggleCustomerActive:Ho,toggleGCActive:Zo,unlinkCustomerFromJob:dc,unlinkGCFromJob:Ec,updateCustomer:$o,updateEntityContact:ic,updateGC:zo},Symbol.toStringTag,{value:"Module"})),Sp=["pending","active","on_hold","completed","cancelled","continuous_maintenance","on_call"],cs=new Y("jobs");async function Tc(e,t){const s=await p();let r=e.job_number;if(!r){const c=((await s.query("SELECT COUNT(*) as cnt FROM jobs")).values[0]?.cnt??0)+1;r=`J-${String(c).padStart(4,"0")}`}const n={job_number:r,job_name:e.job_name,customer_name:e.customer_name??null,address_line1:e.address_line1??null,address_line2:e.address_line2??null,city:e.city??null,state:e.state??null,zip:e.zip??null,gps_lat:e.gps_lat??null,gps_lng:e.gps_lng??null,status:"pending",job_type:e.job_type??"service",priority:e.priority??"normal",lead_user_id:e.lead_user_id??null,bill_rate_type_id:e.bill_rate_type_id??null,start_date:e.start_date??null,due_date:e.due_date??null,notes:e.notes??null,created_by:t,created_at:new Date().toISOString(),updated_at:new Date().toISOString()},i=await cs.insert(n);return await ct(i)}async function ct(e){return(await(await p()).query(`SELECT j.*,
       COALESCE(
         (SELECT SUM(le.regular_hours + le.overtime_hours)
          FROM labor_entries le WHERE le.job_id = j.id AND le.clock_out IS NOT NULL), 0
       ) as total_labor_hours,
       (SELECT COUNT(*) FROM labor_entries le
        WHERE le.job_id = j.id AND le.status = 'clocked_in') as active_workers,
       (SELECT COUNT(*) FROM notebook_entries ne
        JOIN notebook_sections ns ON ns.id = ne.section_id
        JOIN notebooks nb ON nb.id = ns.notebook_id
        WHERE nb.job_id = j.id AND ne.entry_type = 'task'
          AND ne.task_status != 'done' AND ne.is_deleted = 0) as open_task_count
     FROM jobs j WHERE j.id = ?`,[e])).values[0]??null}async function Nc(e){const t=await p(),s=[],r=[];if(e?.status?(s.push("j.status = ?"),r.push(e.status)):s.push("j.status NOT IN ('completed', 'cancelled')"),e?.search){s.push("(j.job_name LIKE ? OR j.job_number LIKE ? OR j.customer_name LIKE ?)");const _=`%${e.search}%`;r.push(_,_,_)}e?.job_type&&(s.push("j.job_type = ?"),r.push(e.job_type)),e?.priority&&(s.push("j.priority = ?"),r.push(e.priority));const n=s.length?`WHERE ${s.join(" AND ")}`:"",i=e?.sort_by??"created_at",o=e?.sort_dir==="asc"?"ASC":"DESC",c=e?.limit??100,d=e?.offset??0,u=(await t.query(`SELECT COUNT(*) as cnt FROM jobs j ${n}`,r)).values[0]?.cnt??0;return{items:(await t.query(`SELECT j.*,
       COALESCE(
         (SELECT SUM(le.regular_hours + le.overtime_hours)
          FROM labor_entries le WHERE le.job_id = j.id AND le.clock_out IS NOT NULL), 0
       ) as total_labor_hours,
       (SELECT COUNT(*) FROM labor_entries le
        WHERE le.job_id = j.id AND le.status = 'clocked_in') as active_workers
     FROM jobs j ${n}
     ORDER BY j.${i} ${o}
     LIMIT ? OFFSET ?`,[...r,c,d])).values,total:u}}async function hc(e,t){const s={...t,updated_at:new Date().toISOString()};return await cs.update(e,s)?ct(e):null}async function xc(e,t){if(!Sp.includes(t))throw new Error(`Invalid job status: ${t}`);const s={status:t,updated_at:new Date().toISOString()};return(t==="completed"||t==="cancelled")&&(s.completed_date=new Date().toISOString()),await cs.update(e,s),ct(e)}const yt=new Y("bill_rate_types");async function bc(e=!0){const t=await p(),s=e?"WHERE is_active = 1":"";return(await t.query(`SELECT * FROM bill_rate_types ${s} ORDER BY sort_order, name`)).values}async function fc(e){const t=await yt.insert({name:e.name,description:e.description??null,sort_order:e.sort_order??0,is_active:1,created_at:new Date().toISOString()});return await yt.getById(t)}async function vc(e,t){const s={};return t.name!==void 0&&(s.name=t.name),t.description!==void 0&&(s.description=t.description),t.sort_order!==void 0&&(s.sort_order=t.sort_order),t.is_active!==void 0&&(s.is_active=t.is_active?1:0),await yt.update(e,s),await yt.getById(e)}async function Rc(e){await yt.update(e,{is_active:0})}async function wc(e){return(await(await p()).query(`SELECT jp.*, p.part_number, p.description as part_description,
            u.display_name as user_name
     FROM job_parts jp
     LEFT JOIN parts p ON p.id = jp.part_id
     LEFT JOIN users u ON u.id = jp.consumed_by
     WHERE jp.job_id = ?
     ORDER BY jp.consumed_at DESC`,[e])).values}async function ls(e=!0){const t=await p(),s=e?"WHERE is_active = 1":"";return(await t.query(`SELECT * FROM clock_out_questions ${s} ORDER BY sort_order, id`)).values}async function Lc(e,t){const s=new Date().toISOString(),r=new Y("clock_out_questions"),n=await r.insert({question_text:e.question_text,answer_type:e.answer_type??"text",is_required:e.is_required!==!1?1:0,sort_order:e.sort_order??0,is_active:1,created_by:t,created_at:s,updated_at:s});return await r.getById(n)}async function Sc(e,t){const s=new Y("clock_out_questions"),r={updated_at:new Date().toISOString()};return t.question_text!==void 0&&(r.question_text=t.question_text),t.answer_type!==void 0&&(r.answer_type=t.answer_type),t.is_required!==void 0&&(r.is_required=t.is_required?1:0),t.sort_order!==void 0&&(r.sort_order=t.sort_order),await s.update(e,r),await s.getById(e)}async function Cc(e){const t=await p();for(let s=0;s<e.length;s++)await t.run("UPDATE clock_out_questions SET sort_order = ?, updated_at = ? WHERE id = ?",[s,new Date().toISOString(),e[s]])}async function Oc(e){await new Y("clock_out_questions").update(e,{is_active:0,updated_at:new Date().toISOString()})}async function ds(e,t=!1){const s=await p(),r=["job_id = ?"];return t&&r.push("status = 'pending'"),(await s.query(`SELECT * FROM one_time_questions WHERE ${r.join(" AND ")} ORDER BY created_at DESC`,[e])).values}async function jc(e,t,s){const r=new Y("one_time_questions"),n=await r.insert({job_id:e,target_user_id:t.target_user_id??null,question_text:t.question_text,answer_type:t.answer_type??"text",status:"pending",created_by:s,shown_at_clock_in:0,created_at:new Date().toISOString()});return await X("one_time_questions",n,"INSERT",{job_id:e}),await r.getById(n)}async function Ac(e){const[t,s,r]=await Promise.all([ls(!0),ds(e,!0),ct(e)]);return{global_questions:t,one_time_questions:s,job:r}}async function Ic(e){const t=await p(),s=[],r=[];e?.date_from&&(s.push("dr.report_date >= ?"),r.push(e.date_from)),e?.date_to&&(s.push("dr.report_date <= ?"),r.push(e.date_to));const n=s.length?`WHERE ${s.join(" AND ")}`:"";return(await t.query(`SELECT dr.*, j.job_name, j.job_number
     FROM daily_reports dr
     JOIN jobs j ON j.id = dr.job_id
     ${n}
     ORDER BY dr.report_date DESC`,r)).values}async function kc(e,t){return(await(await p()).query(`SELECT dr.*, j.job_name, j.job_number
     FROM daily_reports dr
     JOIN jobs j ON j.id = dr.job_id
     WHERE dr.job_id = ? AND dr.report_date = ?`,[e,t])).values[0]??null}async function us(e,t){const s=await p(),r=["jp.job_id = ?","jp.deleted_at IS NULL"],n=[e];return t?.preference_type&&(r.push("jp.preference_type = ?"),n.push(t.preference_type)),t?.category&&(r.push("jp.category = ?"),n.push(t.category)),(await s.query(`SELECT jp.* FROM job_preferences jp
     WHERE ${r.join(" AND ")}
     ORDER BY jp.confidence_score DESC`,n)).values}async function Dc(e,t){const r=(await us(e,{...t?{category:t}:{}})).filter(n=>n.is_active);return{brands:r.filter(n=>n.preference_type==="brand").map(n=>({text_value:n.text_value??"",confidence:n.confidence_score})),colors:r.filter(n=>n.preference_type==="color").map(n=>({text_value:n.text_value??"",confidence:n.confidence_score})),suppliers:r.filter(n=>n.preference_type==="supplier").map(n=>({entity_id:n.entity_id??0,text_value:n.text_value??"",confidence:n.confidence_score})),parts:r.filter(n=>n.preference_type==="part").map(n=>({entity_id:n.entity_id??0,text_value:n.text_value??"",confidence:n.confidence_score}))}}async function Fc(e){return(await(await p()).query(`SELECT jps.*, s.name as supplier_name
     FROM job_preferred_suppliers jps
     LEFT JOIN suppliers s ON s.id = jps.supplier_id
     WHERE jps.job_id = ? AND jps.deleted_at IS NULL
     ORDER BY jps.rank ASC`,[e])).values}async function Uc(e,t){const s=await p(),r=new Date().toISOString();await s.run("UPDATE job_preferred_suppliers SET deleted_at = ? WHERE job_id = ? AND deleted_at IS NULL",[r,e]);const n=[];for(let i=0;i<t.length;i++){const o=await s.run(`INSERT INTO job_preferred_suppliers (job_id, supplier_id, rank, created_at)
       VALUES (?, ?, ?, ?)`,[e,t[i],i,r]),c=o.lastInsertId??o.changes?.lastId??0;n.push({id:c,supplier_id:t[i],rank:i}),await X("job_preferred_suppliers",c,"INSERT",{job_id:e,supplier_id:t[i]})}return n}async function Pc(e){return(await(await p()).query(`SELECT jtm.*, u.display_name, u.email
     FROM job_team_members jtm
     JOIN users u ON u.id = jtm.user_id
     WHERE jtm.job_id = ? AND jtm.deleted_at IS NULL
     ORDER BY jtm.role DESC, u.display_name`,[e])).values}async function Mc(e,t,s){const r=await p(),n=new Date().toISOString();return await r.run(`INSERT INTO job_team_members (job_id, user_id, role, assigned_at, assigned_by, notes)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(job_id, user_id) DO UPDATE SET
       role = excluded.role, assigned_by = excluded.assigned_by,
       notes = excluded.notes, deleted_at = NULL`,[e,t.user_id,t.role??"member",n,s,t.notes??null]),await X("job_team_members",0,"INSERT",{job_id:e,user_id:t.user_id}),(await r.query(`SELECT jtm.*, u.display_name, u.email
     FROM job_team_members jtm
     JOIN users u ON u.id = jtm.user_id
     WHERE jtm.job_id = ? AND jtm.user_id = ?`,[e,t.user_id])).values[0]}async function Xc(e,t){await(await p()).run("UPDATE job_team_members SET deleted_at = ? WHERE id = ? AND job_id = ?",[new Date().toISOString(),t,e]),await X("job_team_members",t,"DELETE",{job_id:e})}const Cy=Object.freeze(Object.defineProperty({__proto__:null,addJobTeamMember:Mc,createBillRateType:fc,createGlobalQuestion:Lc,createJob:Tc,createOneTimeQuestion:jc,deactivateGlobalQuestion:Oc,deleteBillRateType:Rc,getActiveJobs:Nc,getAllReports:Ic,getBillRateTypes:bc,getClockOutBundle:Ac,getGlobalQuestions:ls,getJob:ct,getJobParts:wc,getJobPreferences:us,getJobPreferredSuppliers:Fc,getJobSuggestions:Dc,getJobTeam:Pc,getOneTimeQuestions:ds,getReport:kc,removeJobTeamMember:Xc,reorderGlobalQuestions:Cc,setJobPreferredSuppliers:Uc,updateBillRateType:vc,updateGlobalQuestion:Sc,updateJob:hc,updateJobStatus:xc},Symbol.toStringTag,{value:"Module"})),wa=new Y("labor_entries");async function qc(e,t){if(await _s(e))throw new Error("Already clocked in. Clock out first.");const r=new Date().toISOString(),n={user_id:e,job_id:t.job_id,clock_in:r,clock_out:null,regular_hours:0,overtime_hours:0,drive_time_minutes:0,clock_in_gps_lat:t.gps_lat??null,clock_in_gps_lng:t.gps_lng??null,clock_out_gps_lat:null,clock_out_gps_lng:null,clock_in_photo_path:t.photo_path??null,clock_out_photo_path:null,status:"clocked_in",notes:null,created_at:r},i=await wa.insert(n);return await ra(i)}async function Gc(e,t){const s=await p(),r=await wa.getById(t.labor_entry_id);if(!r)throw new Error("Labor entry not found");if(r.user_id!==e)throw new Error("Not your labor entry");if(r.status!=="clocked_in")throw new Error("Entry is not clocked in");const n=new Date().toISOString(),i=new Date(r.clock_in).getTime(),c=(new Date(n).getTime()-i)/(1e3*60*60),d=t.drive_time_minutes??0,l=Math.max(0,c-d/60),u=Math.min(l,8),E=Math.max(0,l-8),_={clock_out:n,regular_hours:Math.round(u*100)/100,overtime_hours:Math.round(E*100)/100,drive_time_minutes:d,clock_out_gps_lat:t.gps_lat??null,clock_out_gps_lng:t.gps_lng??null,clock_out_photo_path:t.photo_path??null,status:"clocked_out",notes:t.notes??r.notes};if(await wa.update(t.labor_entry_id,_),t.responses?.length)for(const m of t.responses)await s.run(`INSERT INTO clock_out_responses (labor_entry_id, question_id, answer_text, answer_photo_path, created_at)
         VALUES (?, ?, ?, ?, ?)`,[t.labor_entry_id,m.question_id,m.answer_text,m.answer_photo_path??null,n]),await X("clock_out_responses",0,"INSERT",{labor_entry_id:t.labor_entry_id,question_id:m.question_id});if(t.one_time_answers?.length)for(const m of t.one_time_answers)await s.run(`INSERT INTO one_time_questions (job_id, question_text, answer_text, asked_by, created_at)
         VALUES (?, ?, ?, ?, ?)`,[r.job_id,m.question_text,m.answer_text,e,n]),await X("one_time_questions",0,"INSERT",{job_id:r.job_id,question_text:m.question_text});return await ra(t.labor_entry_id)}async function _s(e){const r=(await(await p()).query(`SELECT le.*, j.job_name, j.job_number
     FROM labor_entries le
     JOIN jobs j ON j.id = le.job_id
     WHERE le.user_id = ? AND le.status = 'clocked_in'
     ORDER BY le.clock_in DESC
     LIMIT 1`,[e])).values[0];if(!r)return null;const n=(Date.now()-new Date(r.clock_in).getTime())/(1e3*60);return{entry:r,elapsed_minutes:Math.round(n)}}async function ra(e){return(await(await p()).query(`SELECT le.*, j.job_name, j.job_number, u.display_name as user_name
     FROM labor_entries le
     JOIN jobs j ON j.id = le.job_id
     JOIN users u ON u.id = le.user_id
     WHERE le.id = ?`,[e])).values[0]??null}async function Bc(e,t,s){const r=await p(),n=["le.job_id = ?"],i=[e];return t&&(n.push("le.clock_in >= ?"),i.push(t)),s&&(n.push("le.clock_in <= ?"),i.push(s)),(await r.query(`SELECT le.*, u.display_name as user_name
     FROM labor_entries le
     JOIN users u ON u.id = le.user_id
     WHERE ${n.join(" AND ")}
     ORDER BY le.clock_in DESC`,i)).values}const Oy=Object.freeze(Object.defineProperty({__proto__:null,clockIn:qc,clockOut:Gc,getActiveClock:_s,getLaborEntry:ra,getLaborForJob:Bc},Symbol.toStringTag,{value:"Module"}));async function $c(){const e=await p(),s=(await e.query("SELECT COALESCE(SUM(qty), 0) as total FROM stock WHERE location_type = 'warehouse'")).values[0]?.total??0,r=await e.query(`SELECT
       COUNT(*) as total_parts,
       SUM(CASE WHEN wh_qty >= p.min_stock_level AND wh_qty <= p.max_stock_level THEN 1 ELSE 0 END) as healthy
     FROM (
       SELECT part_id, COALESCE(SUM(qty), 0) as wh_qty
       FROM stock WHERE location_type = 'warehouse'
       GROUP BY part_id
     ) sq
     JOIN parts p ON p.id = sq.part_id
     WHERE p.is_active = 1`),n=r.values[0]?.total_parts??1,i=r.values[0]?.healthy??0,o=n>0?Math.round(i/n*100):100,d=(await e.query(`SELECT COUNT(*) as cnt
     FROM (
       SELECT part_id, COALESCE(SUM(qty), 0) as wh_qty
       FROM stock WHERE location_type = 'warehouse'
       GROUP BY part_id
     ) sq
     JOIN parts p ON p.id = sq.part_id
     WHERE p.is_active = 1 AND sq.wh_qty < p.min_stock_level`)).values[0]?.cnt??0,u=(await e.query("SELECT COUNT(*) as cnt FROM stock WHERE location_type = 'pulled' AND qty > 0")).values[0]?.cnt??0;return{stock_health_pct:o,total_units:s,shortfall_count:d,pending_task_count:u}}async function Hc(e=10){return(await(await p()).query(`SELECT sm.id, sm.movement_type, sm.qty, sm.created_at,
       p.part_number, p.description as part_desc,
       u.display_name as performer_name,
       sm.from_location_type, sm.to_location_type
     FROM stock_movements sm
     JOIN parts p ON p.id = sm.part_id
     LEFT JOIN users u ON u.id = sm.performed_by
     ORDER BY sm.created_at DESC
     LIMIT ?`,[e])).values.map(r=>({id:r.id,summary:`${r.performer_name??"Unknown"} ${r.movement_type}d ${r.qty}× ${r.part_number} (${r.from_location_type??"external"} → ${r.to_location_type??"external"})`,movement_type:r.movement_type,performer_name:r.performer_name,created_at:r.created_at}))}async function Wc(e){const t=await p(),s=["p.is_active = 1"],r=[];if(e?.search){s.push("(p.part_number LIKE ? OR p.description LIKE ?)");const _=`%${e.search}%`;r.push(_,_)}e?.category_id&&(s.push("p.category_id = ?"),r.push(e.category_id));const n=`WHERE ${s.join(" AND ")}`,o={name:"p.part_number",qty:"warehouse_qty",status:"stock_status"}[e?.sort??"name"]??"p.part_number",c=e?.limit??100,d=e?.offset??0,l=await t.query(`SELECT COUNT(*) as cnt FROM parts p ${n}`,r);let E=(await t.query(`SELECT p.id, p.part_number, p.description,
       c.name as category_name, b.name as brand_name,
       COALESCE(sq.wh_qty, 0) as warehouse_qty,
       p.min_stock_level as min_stock,
       p.max_stock_level as max_stock,
       p.reorder_point,
       CASE
         WHEN COALESCE(sq.wh_qty, 0) < p.min_stock_level THEN 'below_min'
         WHEN COALESCE(sq.wh_qty, 0) > p.max_stock_level THEN 'above_max'
         ELSE 'healthy'
       END as status,
       sq.last_moved
     FROM parts p
     LEFT JOIN categories c ON c.id = p.category_id
     LEFT JOIN brands b ON b.id = p.brand_id
     LEFT JOIN (
       SELECT part_id,
         SUM(qty) as wh_qty,
         MAX(updated_at) as last_moved
       FROM stock WHERE location_type = 'warehouse'
       GROUP BY part_id
     ) sq ON sq.part_id = p.id
     ${n}
     ORDER BY ${o} ASC
     LIMIT ? OFFSET ?`,[...r,c,d])).values;return e?.status&&(E=E.filter(_=>_.status===e.status)),{items:E,total:l.values[0]?.cnt??0}}async function Kc(e,t=20){const s=await p(),r=`%${e}%`;return(await s.query(`SELECT p.id, p.part_number, p.description,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p
     WHERE p.is_active = 1 AND (p.part_number LIKE ? OR p.description LIKE ?)
     ORDER BY p.part_number ASC
     LIMIT ?`,[r,r,t])).values}const jy=Object.freeze(Object.defineProperty({__proto__:null,getDashboardKPIs:$c,getInventoryGrid:Wc,getRecentActivity:Hc,searchParts:Kc},Symbol.toStringTag,{value:"Module"})),Es={"warehouse:pulled":{type:"transfer",photoRequired:!1},"pulled:truck":{type:"transfer",photoRequired:!1},"pulled:trailer":{type:"transfer",photoRequired:!1},"warehouse:truck":{type:"transfer",photoRequired:!1},"warehouse:trailer":{type:"transfer",photoRequired:!1},"truck:trailer":{type:"transfer",photoRequired:!1},"trailer:truck":{type:"transfer",photoRequired:!1},"truck:job":{type:"consume",photoRequired:!0},"trailer:job":{type:"consume",photoRequired:!0},"job:truck":{type:"return",photoRequired:!0},"job:trailer":{type:"return",photoRequired:!0},"truck:warehouse":{type:"return",photoRequired:!1},"trailer:warehouse":{type:"return",photoRequired:!1},"pulled:warehouse":{type:"return",photoRequired:!1},"trailer:pulled":{type:"return",photoRequired:!1}};async function ps(e){const t=[],s=[],r=`${e.from_location_type}:${e.to_location_type}`;if(!Es[r])return t.push(`Invalid movement path: ${e.from_location_type} → ${e.to_location_type}`),{valid:!1,errors:t,warnings:s};if(!e.items.length)return t.push("No items in movement request"),{valid:!1,errors:t,warnings:s};if(e.items.length>20)return t.push("Maximum 20 items per movement"),{valid:!1,errors:t,warnings:s};const n=await p();for(const i of e.items){if(i.qty<1){t.push(`Invalid quantity for part ${i.part_id}: must be >= 1`);continue}const o=await n.query("SELECT id, part_number, description FROM parts WHERE id = ?",[i.part_id]);if(!o.values.length){t.push(`Part ${i.part_id} not found`);continue}const d=(await n.query(`SELECT COALESCE(SUM(qty), 0) as available
       FROM stock
       WHERE part_id = ? AND location_type = ? AND location_id = ?`,[i.part_id,e.from_location_type,e.from_location_id])).values[0]?.available??0;d<i.qty?t.push(`Insufficient stock for ${o.values[0].part_number}: need ${i.qty}, have ${d} at ${e.from_location_type}`):d===i.qty&&s.push(`${o.values[0].part_number} will be 0 at source after this move`)}return{valid:t.length===0,errors:t,warnings:s}}async function Yc(e){const t=await p(),s=`${e.from_location_type}:${e.to_location_type}`,r=Es[s];if(!r)throw new Error(`Invalid movement path: ${s}`);const n=[];let i=0,o=0;const c=[];for(const d of e.items){const u=(await t.query("SELECT id, part_number, description, company_cost_price FROM parts WHERE id = ?",[d.part_id])).values[0];if(!u)continue;let E=d.supplier_id??null,_=null;if(!E){const g=await t.query(`SELECT s.supplier_id, sup.name
         FROM stock s
         LEFT JOIN suppliers sup ON sup.id = s.supplier_id
         WHERE s.part_id = ? AND s.location_type = ? AND s.location_id = ? AND s.qty > 0
         ORDER BY s.updated_at ASC
         LIMIT 1`,[d.part_id,e.from_location_type,e.from_location_id]);g.values.length&&(E=g.values[0].supplier_id,_=g.values[0].name)}const y=(await t.query(`SELECT COALESCE(SUM(qty), 0) as qty FROM stock
       WHERE part_id = ? AND location_type = ? AND location_id = ?`,[d.part_id,e.from_location_type,e.from_location_id])).values[0]?.qty??0,v=(await t.query(`SELECT COALESCE(SUM(qty), 0) as qty FROM stock
       WHERE part_id = ? AND location_type = ? AND location_id = ?`,[d.part_id,e.to_location_type,e.to_location_id])).values[0]?.qty??0,h=u.company_cost_price??0,T=h*d.qty;n.push({part_id:d.part_id,part_number:u.part_number,part_description:u.description,qty:d.qty,supplier_id:E,supplier_name:_,source_before:y,source_after:y-d.qty,dest_before:v,dest_after:v+d.qty,unit_cost:h,line_value:T}),i+=d.qty,o+=T}return{lines:n,total_qty:i,total_value:o,movement_type:r.type,photo_required:r.photoRequired,warnings:c}}async function Vc(e,t){const s=await ps(e);if(!s.valid)return{success:!1,movements:[],total_items:0,total_qty:0,message:s.errors.join("; ")};const r=await p(),n=`${e.from_location_type}:${e.to_location_type}`,i=Es[n],o=new Date().toISOString(),c=[];let d=0;for(const l of e.items){let u=l.supplier_id??null;u||(u=(await r.query(`SELECT supplier_id FROM stock
         WHERE part_id = ? AND location_type = ? AND location_id = ? AND qty > 0
         ORDER BY updated_at ASC LIMIT 1`,[l.part_id,e.from_location_type,e.from_location_id])).values[0]?.supplier_id??null);const E=await r.query("SELECT company_cost_price, company_sell_price FROM parts WHERE id = ?",[l.part_id]),_=E.values[0]?.company_cost_price??0,m=E.values[0]?.company_sell_price??0;if((await r.run(`UPDATE stock SET qty = qty - ?, updated_at = ?
       WHERE part_id = ? AND location_type = ? AND location_id = ?
         AND qty >= ?
         ${u!=null?"AND supplier_id = ?":"AND supplier_id IS NULL"}`,[l.qty,o,l.part_id,e.from_location_type,e.from_location_id,l.qty,...u!=null?[u]:[]])).changes.changes===0&&(await r.run(`UPDATE stock SET qty = qty - ?, updated_at = ?
         WHERE part_id = ? AND location_type = ? AND location_id = ? AND qty >= ?`,[l.qty,o,l.part_id,e.from_location_type,e.from_location_id,l.qty])).changes.changes===0)throw new Error(`Failed to deduct stock for part ${l.part_id} — insufficient quantity`);const f=await r.query(`SELECT id, qty FROM stock
       WHERE part_id = ? AND location_type = ? AND location_id = ?
         ${u!=null?"AND supplier_id = ?":"AND supplier_id IS NULL"}`,[l.part_id,e.to_location_type,e.to_location_id,...u!=null?[u]:[]]);f.values.length?await r.run("UPDATE stock SET qty = qty + ?, updated_at = ? WHERE id = ?",[l.qty,o,f.values[0].id]):await r.run(`INSERT INTO stock (part_id, location_type, location_id, qty, supplier_id, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,[l.part_id,e.to_location_type,e.to_location_id,l.qty,u,o]);const h=(await r.run(`INSERT INTO stock_movements
         (part_id, qty, from_location_type, from_location_id,
          to_location_type, to_location_id, supplier_id,
          movement_type, reason, job_id, reference_number, notes,
          performed_by, photo_path, scan_confirmed, gps_lat, gps_lng,
          unit_cost_at_move, unit_sell_at_move, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,[l.part_id,l.qty,e.from_location_type,e.from_location_id,e.to_location_type,e.to_location_id,u,i.type,e.reason??null,e.job_id??null,e.reference_number??null,e.notes??null,t,e.photo_path??null,e.scan_confirmed?1:0,e.gps_lat??null,e.gps_lng??null,_,m,o])).changes.lastId;c.push(h),d+=l.qty,await X("stock_movements",h,"INSERT",{part_id:l.part_id,qty:l.qty,from:`${e.from_location_type}:${e.from_location_id}`,to:`${e.to_location_type}:${e.to_location_id}`})}return await r.run("DELETE FROM stock WHERE qty <= 0"),{success:!0,movements:c,total_items:e.items.length,total_qty:d,message:`Moved ${d} items successfully`}}async function Jc(e,t=20){return(await(await p()).query(`SELECT sm.*, p.part_number, p.description as part_description,
       u.display_name as performer_name
     FROM stock_movements sm
     JOIN parts p ON p.id = sm.part_id
     LEFT JOIN users u ON u.id = sm.performed_by
     WHERE sm.performed_by = ?
     ORDER BY sm.created_at DESC
     LIMIT ?`,[e,t])).values}const Ay=Object.freeze(Object.defineProperty({__proto__:null,calculatePreview:Yc,executeMovement:Vc,getRecentMovements:Jc,validateMovement:ps},Symbol.toStringTag,{value:"Module"})),La=new Y("job_parts_orders"),Cp=new Y("jpo_line_items");async function Qc(e,t){const s=await p(),r=new Date().toISOString(),i=((await s.query("SELECT COUNT(*) as cnt FROM job_parts_orders")).values[0]?.cnt??0)+1,o=`JPO-${String(i).padStart(5,"0")}`,c=await La.insert({job_id:e.job_id??null,order_number:o,status:"draft",priority:e.priority??"normal",order_type:e.order_type??"job",has_special_items:(e.special_items?.length??0)>0?1:0,smart_suggestions_enabled:1,requested_by:t,approved_by:null,approved_at:null,notes:e.notes??null,created_at:r,updated_at:r});for(const d of e.lines)await Cp.insert({jpo_id:c,part_id:d.part_id,qty_requested:d.qty_requested,qty_ordered:0,qty_received:0,priority:d.priority??"normal",notes:d.notes??null,suggested_supplier_id:d.suggested_supplier_id??null,created_at:r});if(e.special_items?.length)for(const d of e.special_items)await s.run(`INSERT INTO special_items (jpo_id, description, qty, estimated_cost, vendor_suggestion, notes, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,[c,d.description,d.qty,d.estimated_cost??null,d.vendor_suggestion??null,d.notes??null,r]);return await na(c)}async function zc(e,t){const s=await La.getById(e);return!s||s.status!=="draft"?null:(await La.update(e,{status:"pending_approval",updated_at:new Date().toISOString()}),await Op("jpo",e,"draft","pending_approval",t),na(e))}async function na(e){return(await(await p()).query(`SELECT jpo.*,
       j.job_name, j.job_number,
       u.display_name as requester_name,
       (SELECT COUNT(*) FROM jpo_line_items WHERE jpo_id = jpo.id) as line_count
     FROM job_parts_orders jpo
     LEFT JOIN jobs j ON j.id = jpo.job_id
     LEFT JOIN users u ON u.id = jpo.requested_by
     WHERE jpo.id = ?`,[e])).values[0]??null}async function Zc(e){return(await(await p()).query(`SELECT jli.*,
       p.part_number, p.description as part_description,
       s.name as supplier_name
     FROM jpo_line_items jli
     JOIN parts p ON p.id = jli.part_id
     LEFT JOIN suppliers s ON s.id = jli.suggested_supplier_id
     WHERE jli.jpo_id = ?
     ORDER BY jli.created_at ASC`,[e])).values}async function el(e){const t=await p(),s=[],r=[];e?.status&&(s.push("jpo.status = ?"),r.push(e.status)),e?.job_id&&(s.push("jpo.job_id = ?"),r.push(e.job_id)),e?.requested_by&&(s.push("jpo.requested_by = ?"),r.push(e.requested_by));const n=s.length?`WHERE ${s.join(" AND ")}`:"",i=e?.limit??100,o=e?.offset??0,c=await t.query(`SELECT COUNT(*) as cnt FROM job_parts_orders jpo ${n}`,r);return{items:(await t.query(`SELECT jpo.*,
       j.job_name, j.job_number,
       u.display_name as requester_name,
       (SELECT COUNT(*) FROM jpo_line_items WHERE jpo_id = jpo.id) as line_count
     FROM job_parts_orders jpo
     LEFT JOIN jobs j ON j.id = jpo.job_id
     LEFT JOIN users u ON u.id = jpo.requested_by
     ${n}
     ORDER BY jpo.created_at DESC
     LIMIT ? OFFSET ?`,[...r,i,o])).values,total:c.values[0]?.cnt??0}}async function Op(e,t,s,r,n,i){await(await p()).run(`INSERT INTO order_status_history (entity_type, entity_id, old_status, new_status, changed_by, notes, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,[e,t,s,r,n,null,new Date().toISOString()])}const Iy=Object.freeze(Object.defineProperty({__proto__:null,createJPO:Qc,getJPO:na,getJPOLines:Zc,listJPOs:el,submitJPO:zc},Symbol.toStringTag,{value:"Module"})),ms=new Y("notebooks"),Pt=new Y("notebook_sections"),ve=new Y("notebook_entries"),jp=["planned","parts_ordered","parts_delivered","in_progress","done"];async function ys(e){const t=await p(),s=[],r=[];e?.job_id&&(s.push("nb.job_id = ?"),r.push(e.job_id)),e?.include_archived||s.push("nb.is_archived = 0");const n=s.length?`WHERE ${s.join(" AND ")}`:"";return(await t.query(`SELECT nb.*,
       j.job_name, j.job_number,
       u.display_name as creator_name,
       (SELECT COUNT(*) FROM notebook_sections WHERE notebook_id = nb.id) as section_count,
       (SELECT COUNT(*) FROM notebook_entries ne
        JOIN notebook_sections ns ON ns.id = ne.section_id
        WHERE ns.notebook_id = nb.id AND ne.entry_type = 'task' AND ne.is_deleted = 0) as task_count,
       (SELECT COUNT(*) FROM notebook_entries ne
        JOIN notebook_sections ns ON ns.id = ne.section_id
        WHERE ns.notebook_id = nb.id AND ne.entry_type = 'task'
          AND ne.task_status != 'done' AND ne.is_deleted = 0) as open_task_count
     FROM notebooks nb
     LEFT JOIN jobs j ON j.id = nb.job_id
     LEFT JOIN users u ON u.id = nb.created_by
     ${n}
     ORDER BY nb.updated_at DESC
     LIMIT ?`,[...r,e?.limit??100])).values}async function Mt(e){const t=await p(),r=(await t.query(`SELECT nb.*, j.job_name, j.job_number, u.display_name as creator_name
     FROM notebooks nb
     LEFT JOIN jobs j ON j.id = nb.job_id
     LEFT JOIN users u ON u.id = nb.created_by
     WHERE nb.id = ?`,[e])).values[0];if(!r)return null;const n=await t.query("SELECT * FROM notebook_sections WHERE notebook_id = ? ORDER BY sort_order ASC",[e]),i=[];for(const o of n.values){const c=await t.query(`SELECT ne.*, u.display_name as creator_name, au.display_name as assignee_name
       FROM notebook_entries ne
       LEFT JOIN users u ON u.id = ne.created_by
       LEFT JOIN users au ON au.id = ne.task_assigned_to
       WHERE ne.section_id = ? AND ne.is_deleted = 0
       ORDER BY ne.sort_order ASC`,[o.id]);i.push({...o,entries:c.values})}return{notebook:r,sections:i}}async function gs(e,t){const s=new Date().toISOString(),r=await ms.insert({title:e.title,description:e.description??null,job_id:e.job_id??null,template_id:e.template_id??null,created_by:t,is_archived:0,created_at:s,updated_at:s});return e.template_id&&await Ap(e.template_id,r,t),(await ys()).find(i=>i.id===r)}async function tl(e,t){const n=((await(await p()).query("SELECT MAX(sort_order) as max_order FROM notebook_sections WHERE notebook_id = ?",[e])).values[0]?.max_order??0)+1,i=await Pt.insert({notebook_id:e,name:t.name,section_type:t.section_type??"notes",sort_order:n,is_locked:0,created_at:new Date().toISOString()});return await Pt.getById(i)}async function al(e,t,s){const r=await p(),n=new Date().toISOString(),o=((await r.query("SELECT MAX(sort_order) as max_order FROM notebook_entries WHERE section_id = ?",[e])).values[0]?.max_order??0)+1,c=await ve.insert({section_id:e,title:t.title,content:t.content??null,entry_type:t.entry_type??"note",field_type:t.field_type??null,field_required:t.field_required?1:0,field_filled_by:null,task_status:t.task_status??(t.entry_type==="task"?"planned":null),task_due_date:t.task_due_date??null,task_assigned_to:t.task_assigned_to??null,task_parts_note:t.task_parts_note??null,created_by:s,updated_by:null,is_deleted:0,deleted_by:null,deleted_at:null,sort_order:o,created_at:n,updated_at:n}),d=await Pt.getById(e);return d&&await ms.update(d.notebook_id,{updated_at:n},!1),await ve.getById(c)}async function Ts(e,t,s){const r=await ve.getById(e);if(!r||r.is_deleted)return null;const n={updated_by:s,updated_at:new Date().toISOString()};return t.title!==void 0&&(n.title=t.title),t.content!==void 0&&(n.content=t.content),t.task_status!==void 0&&(n.task_status=t.task_status),t.task_due_date!==void 0&&(n.task_due_date=t.task_due_date),t.task_assigned_to!==void 0&&(n.task_assigned_to=t.task_assigned_to),t.task_parts_note!==void 0&&(n.task_parts_note=t.task_parts_note),r.entry_type==="field"&&t.content&&!r.field_filled_by&&(n.field_filled_by=s),await ve.update(e,n),await ve.getById(e)}async function sl(e,t){return ve.update(e,{is_deleted:1,deleted_by:t,deleted_at:new Date().toISOString()})}async function rl(e,t){if(!jp.includes(t))throw new Error(`Invalid task status: ${t}`);const s=await ve.getById(e);return!s||s.entry_type!=="task"?null:(await ve.update(e,{task_status:t,updated_at:new Date().toISOString()}),await ve.getById(e))}async function nl(){return(await(await p()).query(`SELECT t.*, u.display_name as creator_name,
       (SELECT COUNT(*) FROM template_sections WHERE template_id = t.id) as section_count
     FROM notebook_templates t
     LEFT JOIN users u ON u.id = t.created_by
     WHERE t.is_active = 1
     ORDER BY t.name ASC`)).values}async function il(e){const t=await p(),r=(await t.query(`SELECT t.*, u.display_name as creator_name
     FROM notebook_templates t
     LEFT JOIN users u ON u.id = t.created_by
     WHERE t.id = ?`,[e])).values[0];if(!r)return null;const n=await t.query("SELECT * FROM template_sections WHERE template_id = ? ORDER BY sort_order ASC",[e]),i=[];for(const o of n.values){const c=await t.query("SELECT * FROM template_entries WHERE section_id = ? ORDER BY sort_order ASC",[o.id]);i.push({...o,entries:c.values})}return{...r,sections:i}}async function ol(e,t){const s=await p(),r=await s.query(`SELECT nb.*, j.job_name, j.job_number, u.display_name as creator_name
     FROM notebooks nb
     LEFT JOIN jobs j ON j.id = nb.job_id
     LEFT JOIN users u ON u.id = nb.created_by
     WHERE nb.job_id = ? AND nb.is_archived = 0
     LIMIT 1`,[e]);if(r.values.length>0){const c=r.values[0];return await Mt(c.id)}const i=(await s.query("SELECT job_name FROM jobs WHERE id = ?",[e])).values[0]?.job_name??`Job ${e}`,o=await gs({title:`${i} Notebook`,job_id:e},t);return await Mt(o.id)}async function cl(e){await ms.update(e,{is_archived:1,updated_at:new Date().toISOString()})}async function ll(e,t){const s=await p();for(let r=0;r<t.length;r++)await s.run("UPDATE notebook_sections SET sort_order = ? WHERE id = ? AND notebook_id = ?",[r,t[r],e])}async function dl(e,t,s){return Ts(e,{content:t.content},s)}async function ul(e,t){const s=await p();for(let r=0;r<t.length;r++)await s.run("UPDATE notebook_entries SET sort_order = ? WHERE id = ? AND section_id = ?",[r,t[r],e])}async function _l(e,t,s){const r=await p(),n=["updated_at = datetime('now')"],i=[];t!==void 0&&(n.push("task_status = ?"),i.push(t)),s!==void 0&&(n.push("task_assigned_to = ?"),i.push(s));const o=e.map(()=>"?").join(",");return i.push(...e),await r.run(`UPDATE notebook_entries SET ${n.join(", ")} WHERE id IN (${o}) AND entry_type = 'task'`,i),{updated:e.length}}async function Ap(e,t,s){const r=await p(),n=new Date().toISOString(),i=await r.query("SELECT * FROM template_sections WHERE template_id = ? ORDER BY sort_order ASC",[e]);for(const o of i.values){const c=await Pt.insert({notebook_id:t,name:o.name,section_type:o.section_type,sort_order:o.sort_order,is_locked:o.is_locked,created_at:n},!1),d=await r.query("SELECT * FROM template_entries WHERE section_id = ? ORDER BY sort_order ASC",[o.id]);for(const l of d.values)await ve.insert({section_id:c,title:l.title,content:l.default_content,entry_type:l.entry_type,field_type:l.field_type,field_required:l.field_required,field_filled_by:null,task_status:l.entry_type==="task"?"planned":null,task_due_date:null,task_assigned_to:null,task_parts_note:null,created_by:s,updated_by:null,is_deleted:0,deleted_by:null,deleted_at:null,sort_order:l.sort_order,created_at:n,updated_at:n},!1)}}const ky=Object.freeze(Object.defineProperty({__proto__:null,archiveNotebook:cl,bulkUpdateTasks:_l,createEntry:al,createNotebook:gs,createSection:tl,deleteEntry:sl,getJobNotebook:ol,getNotebook:Mt,getTemplateFull:il,listNotebooks:ys,listTemplates:nl,reorderEntries:ul,reorderSections:ll,updateEntry:Ts,updateFieldValue:dl,updateTaskStatus:rl},Symbol.toStringTag,{value:"Module"})),El=new Y("tools"),pl=new Y("tool_movements");async function ml(e){const t=await p(),s=["t.is_active = 1"],r=[];if(e?.category&&(s.push("t.category = ?"),r.push(e.category)),e?.status&&(s.push("t.status = ?"),r.push(e.status)),e?.location_type&&(s.push("t.location_type = ?"),r.push(e.location_type)),e?.search){s.push("(t.name LIKE ? OR t.tool_number LIKE ? OR t.serial_number LIKE ?)");const l=`%${e.search}%`;r.push(l,l,l)}const n=`WHERE ${s.join(" AND ")}`,i=e?.limit??100,o=e?.offset??0,c=await t.query(`SELECT COUNT(*) as cnt FROM tools t ${n}`,r);return{items:(await t.query(`SELECT t.*, u.display_name as assigned_to_name,
       CASE t.location_type
         WHEN 'warehouse' THEN 'Warehouse'
         WHEN 'truck' THEN (SELECT name FROM vehicles WHERE id = t.location_id)
         WHEN 'job' THEN (SELECT job_name FROM jobs WHERE id = t.location_id)
         ELSE t.location_type
       END as location_name
     FROM tools t
     LEFT JOIN users u ON u.id = t.assigned_to
     ${n}
     ORDER BY t.tool_number ASC
     LIMIT ? OFFSET ?`,[...r,i,o])).values,total:c.values[0]?.cnt??0}}async function et(e){return(await(await p()).query(`SELECT t.*, u.display_name as assigned_to_name,
       CASE t.location_type
         WHEN 'warehouse' THEN 'Warehouse'
         WHEN 'truck' THEN (SELECT name FROM vehicles WHERE id = t.location_id)
         WHEN 'job' THEN (SELECT job_name FROM jobs WHERE id = t.location_id)
         ELSE t.location_type
       END as location_name
     FROM tools t
     LEFT JOIN users u ON u.id = t.assigned_to
     WHERE t.id = ?`,[e])).values[0]??null}async function yl(e){return(await(await p()).query(`SELECT t.*, u.display_name as assigned_to_name
     FROM tools t
     LEFT JOIN users u ON u.id = t.assigned_to
     WHERE t.barcode = ? OR t.tool_number = ?`,[e,e])).values[0]??null}async function gl(e,t,s){const r=new Date().toISOString(),n=await et(e);if(!n)throw new Error("Tool not found");if(n.status!=="available")throw new Error(`Tool is ${n.status}, cannot checkout`);return await pl.insert({tool_id:e,from_location_type:n.location_type,from_location_id:n.location_id,to_location_type:t.to_location_type,to_location_id:t.to_location_id,movement_type:"checkout",reason:t.reason??null,job_id:t.job_id??null,performed_by:s,verified_by:null,condition_at_move:t.condition_at_move??n.condition_rating,created_at:r}),await El.update(e,{location_type:t.to_location_type,location_id:t.to_location_id,assigned_to:s,status:"checked_out",condition_rating:t.condition_at_move??n.condition_rating,updated_at:r}),await et(e)}async function Tl(e,t,s){const r=new Date().toISOString(),n=await et(e);if(!n)throw new Error("Tool not found");const i=t.to_location_type??"warehouse",o=t.to_location_id??1;return await pl.insert({tool_id:e,from_location_type:n.location_type,from_location_id:n.location_id,to_location_type:i,to_location_id:o,movement_type:"return",reason:t.reason??null,job_id:null,performed_by:s,verified_by:null,condition_at_move:t.condition_at_move??n.condition_rating,created_at:r}),await El.update(e,{location_type:i,location_id:o,assigned_to:null,status:"available",condition_rating:t.condition_at_move??n.condition_rating,updated_at:r}),await et(e)}async function Nl(e,t){return(await(await p()).query(`SELECT t.*, u.display_name as assigned_to_name
     FROM tools t
     LEFT JOIN users u ON u.id = t.assigned_to
     WHERE t.location_type = ? AND t.location_id = ? AND t.is_active = 1
     ORDER BY t.name ASC`,[e,t])).values}const Dy=Object.freeze(Object.defineProperty({__proto__:null,checkoutTool:gl,getTool:et,getToolByBarcode:yl,getToolsAtLocation:Nl,listTools:ml,returnTool:Tl},Symbol.toStringTag,{value:"Module"}));async function hl(e){const t=await p(),r=(await t.query("SELECT default_truck_id FROM users WHERE id = ?",[e])).values[0]?.default_truck_id;return r?(await t.query("SELECT * FROM vehicles WHERE id = ?",[r])).values[0]??null:(await t.query(`SELECT v.* FROM vehicles v
     JOIN vehicle_assignments va ON va.vehicle_id = v.id
     WHERE va.user_id = ? AND va.is_active = 1
     ORDER BY va.start_date DESC
     LIMIT 1`,[e])).values[0]??null}async function xl(e){return(await(await p()).query("SELECT * FROM vehicles WHERE id = ?",[e])).values[0]??null}async function bl(){return(await(await p()).query("SELECT * FROM vehicles WHERE is_active = 1 ORDER BY vehicle_number ASC")).values}async function fl(e){return(await(await p()).query(`SELECT va.*, v.name as vehicle_name, v.vehicle_number,
       u.display_name as user_name
     FROM vehicle_assignments va
     JOIN vehicles v ON v.id = va.vehicle_id
     JOIN users u ON u.id = va.user_id
     WHERE va.vehicle_id = ? AND va.is_active = 1
     ORDER BY va.start_date DESC`,[e])).values}async function vl(e){return(await(await p()).query(`SELECT s.part_id, p.part_number, p.description, SUM(s.qty) as qty
     FROM stock s
     JOIN parts p ON p.id = s.part_id
     WHERE s.location_type = 'truck' AND s.location_id = ? AND s.qty > 0
     GROUP BY s.part_id
     ORDER BY p.part_number ASC`,[e])).values}const Fy=Object.freeze(Object.defineProperty({__proto__:null,getMyVehicle:hl,getTruckInventory:vl,getVehicle:xl,getVehicleAssignments:fl,listVehicles:bl},Symbol.toStringTag,{value:"Module"})),ft=new Y("certifications"),Sa=new Y("wage_history"),Xt=new Y("employee_notes"),qt=new Y("user_skills"),Ns=new Y("employee_teams"),Ca=new Y("employee_team_members");async function Rl(e){const t=new Date().toISOString(),s=await ft.insert({user_id:e.user_id,cert_type:e.cert_type,cert_name:e.cert_name,issuing_authority:e.issuing_authority??null,cert_number:e.cert_number??null,issued_date:e.issued_date??null,expiry_date:e.expiry_date??null,notes:e.notes??null,document_path:e.document_path??null,is_active:1,created_at:t,updated_at:t});return await hs(s)}async function hs(e){const t=await ft.getById(e);return t||null}async function xs(e,t){const s=["user_id = ?","deleted_at IS NULL"],r=[e];return await ft.findAll(s.join(" AND "),r,"expiry_date ASC")}async function wl(e){return ft.update(e,{deleted_at:new Date().toISOString()})}async function bs(e){const t=await Sa.insert({user_id:e.user_id,pay_rate:e.pay_rate,effective_date:e.effective_date,reason:e.reason??null,changed_by:e.changed_by??null,created_at:new Date().toISOString()});return await Sa.getById(t)}async function fs(e){return await Sa.findAll("user_id = ?",[e],"effective_date DESC")}async function vs(e){return(await(await p()).query(`SELECT pay_rate FROM wage_history
     WHERE user_id = ? AND effective_date <= date('now')
     ORDER BY effective_date DESC, id DESC LIMIT 1`,[e])).values[0]?.pay_rate??null}async function Ll(e){const t=new Date().toISOString(),s=await Xt.insert({user_id:e.user_id,note_type:e.note_type??"general",title:e.title,body:e.body,is_private:e.is_private??0,created_by:e.created_by,created_at:t,updated_at:t});return await Xt.getById(s)}async function Rs(e,t){const s=["user_id = ?","deleted_at IS NULL"],r=[e];return t?.note_type&&(s.push("note_type = ?"),r.push(t.note_type)),await Xt.findAll(s.join(" AND "),r,"created_at DESC")}async function Sl(e){return Xt.update(e,{deleted_at:new Date().toISOString()})}async function Cl(e){const t=await qt.insert({user_id:e.user_id,skill_name:e.skill_name,proficiency:e.proficiency??"intermediate",years_experience:e.years_experience??null,verified_by:e.verified_by??null,verified_at:e.verified_by?new Date().toISOString():null,created_at:new Date().toISOString()});return await qt.getById(t)}async function ws(e){return await qt.findAll("user_id = ? AND deleted_at IS NULL",[e],"skill_name ASC")}async function Ol(e){return qt.update(e,{deleted_at:new Date().toISOString()})}async function jl(e){const t=new Date().toISOString(),s=await Ns.insert({name:e.name,description:e.description??null,lead_user_id:e.lead_user_id??null,is_active:1,created_at:t,updated_at:t});return await ia(s)}async function ia(e){return(await(await p()).query(`SELECT t.*,
       (SELECT COUNT(*) FROM employee_team_members m
        WHERE m.team_id = t.id AND m.deleted_at IS NULL) as member_count,
       (SELECT u.display_name FROM users u WHERE u.id = t.lead_user_id) as lead_name
     FROM employee_teams t
     WHERE t.id = ? AND t.deleted_at IS NULL`,[e])).values[0]??null}async function Al(e){const t=await p(),s=["t.deleted_at IS NULL"];return e?.include_inactive||s.push("t.is_active = 1"),(await t.query(`SELECT t.*,
       (SELECT COUNT(*) FROM employee_team_members m
        WHERE m.team_id = t.id AND m.deleted_at IS NULL) as member_count,
       (SELECT u.display_name FROM users u WHERE u.id = t.lead_user_id) as lead_name
     FROM employee_teams t
     WHERE ${s.join(" AND ")}
     ORDER BY t.name ASC`)).values}async function Il(e,t){return await Ns.update(e,{...t,updated_at:new Date().toISOString()})?ia(e):null}async function kl(e){return Ns.update(e,{deleted_at:new Date().toISOString()})}async function Dl(e,t,s="member"){const r=await Ca.insert({team_id:e,user_id:t,role:s,joined_at:new Date().toISOString()});return await Ca.getById(r)}async function Fl(e){return Ca.update(e,{deleted_at:new Date().toISOString()})}async function Ul(e,t,s){return(await(await p()).run(`UPDATE employee_team_members SET role = ?
     WHERE team_id = ? AND user_id = ? AND deleted_at IS NULL`,[s,e,t])).changes.changes>0}const Ls=new Y("users");async function Pl(e={}){const t=await p(),s=e.page??1,r=e.page_size??50,n=(s-1)*r,i=["u.deleted_at IS NULL"],o=[];if(e.search){i.push("(u.display_name LIKE ? OR u.email LIKE ? OR u.phone LIKE ?)");const m=`%${e.search}%`;o.push(m,m,m)}e.is_active!==void 0&&(i.push("u.is_active = ?"),o.push(e.is_active?1:0));let c="";e.hat_id&&(c="JOIN user_hats uh ON uh.user_id = u.id AND uh.is_active = 1",i.push("uh.hat_id = ?"),o.push(e.hat_id));const d=i.join(" AND "),u=(await t.query(`SELECT COUNT(DISTINCT u.id) as cnt FROM users u ${c} WHERE ${d}`,o)).values[0]?.cnt??0,E=await t.query(`SELECT DISTINCT u.id, u.display_name, u.email, u.phone, u.certification,
            u.hire_date, u.pay_rate, u.is_active, u.avatar_url
     FROM users u ${c}
     WHERE ${d}
     ORDER BY u.display_name ASC
     LIMIT ? OFFSET ?`,[...o,r,n]),_=[];for(const m of E.values){const y=await t.query(`SELECT h.name FROM hats h
       JOIN user_hats uh ON uh.hat_id = h.id
       WHERE uh.user_id = ? AND uh.is_active = 1`,[m.id]),f=await t.query(`SELECT COUNT(*) as cnt FROM certifications
       WHERE user_id = ? AND deleted_at IS NULL AND is_active = 1`,[m.id]);_.push({id:m.id,display_name:m.display_name,email:m.email,phone:m.phone,certification:m.certification,hire_date:m.hire_date,pay_rate:m.pay_rate,is_active:!!m.is_active,avatar_url:m.avatar_url,hat_names:y.values.map(v=>v.name),active_cert_count:f.values[0]?.cnt??0})}return{items:_,total:u,page:s,page_size:r}}async function Ss(e){const t=await p(),r=(await t.query("SELECT * FROM users WHERE id = ? AND deleted_at IS NULL",[e])).values[0];if(!r)return null;const n=await t.query(`SELECT h.id, h.name, h.level FROM hats h
     JOIN user_hats uh ON uh.hat_id = h.id
     WHERE uh.user_id = ? AND uh.is_active = 1`,[e]),i=await t.query(`SELECT DISTINCT hp.permission_key FROM hat_permissions hp
     JOIN user_hats uh ON uh.hat_id = hp.hat_id
     WHERE uh.user_id = ? AND uh.is_active = 1
     ORDER BY hp.permission_key`,[e]),o=await xs(e),c=await fs(e),d=await Rs(e,{}),l=await ws(e),u=await vs(e);return{id:r.id,display_name:r.display_name,email:r.email,phone:r.phone,certification:r.certification,hire_date:r.hire_date,pay_rate:r.pay_rate,is_active:!!r.is_active,avatar_url:r.avatar_url,emergency_contact_name:r.emergency_contact_name,emergency_contact_phone:r.emergency_contact_phone,hats:n.values,permissions:i.values.map(E=>E.permission_key),certifications:o,wage_history:c,notes:d,skills:l,current_pay_rate:u,created_at:r.created_at,updated_at:r.updated_at}}async function Cs(e){const t=await p(),s=new Date().toISOString();let r;try{const i=new TextEncoder,o=await crypto.subtle.digest("SHA-256",i.encode(e.pin));r="sha256:"+Array.from(new Uint8Array(o)).map(d=>d.toString(16).padStart(2,"0")).join("")}catch{r="__PLACEHOLDER_HASH__"}const n=await Ls.insert({display_name:e.display_name,pin_hash:r,email:e.email??null,phone:e.phone??null,certification:e.certification??null,hire_date:e.hire_date??null,pay_rate:e.pay_rate??null,emergency_contact_name:e.emergency_contact_name??null,emergency_contact_phone:e.emergency_contact_phone??null,is_active:1,avatar_url:null,created_at:s,updated_at:s});if(e.hat_ids&&e.hat_ids.length>0)for(const i of e.hat_ids)await t.run("INSERT OR IGNORE INTO user_hats (user_id, hat_id, is_active) VALUES (?, ?, 1)",[n,i]);return e.pay_rate!=null&&await bs({user_id:n,pay_rate:e.pay_rate,effective_date:e.hire_date??s.split("T")[0],reason:"hire"}),await Ss(n)}async function Ml(e,t){return await Ls.update(e,{is_active:t?1:0,updated_at:new Date().toISOString()}),{user_id:e,is_active:t}}const tt=new Y("hats");async function Xl(e){const t=await p(),s=await t.query("SELECT permission_key FROM hat_permissions WHERE hat_id = ? ORDER BY permission_key",[e.id]),r=await t.query("SELECT COUNT(*) as cnt FROM user_hats WHERE hat_id = ? AND is_active = 1",[e.id]);return{id:e.id,name:e.name,description:e.description,level:e.level??0,is_builtin:!!e.is_builtin,permissions:s.values.map(n=>n.permission_key),user_count:r.values[0]?.cnt??0,created_at:e.created_at}}async function ql(){const t=await(await p()).query("SELECT * FROM hats ORDER BY level DESC, name ASC"),s=[];for(const r of t.values)s.push(await Xl(r));return s}async function at(e){const t=await tt.getById(e);return t?Xl(t):null}async function Gl(e){const t=await p(),s=await tt.insert({name:e.name,description:e.description??null,level:e.level??0,is_builtin:0,created_at:new Date().toISOString()});if(e.permissions&&e.permissions.length>0)for(const r of e.permissions)await t.run("INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key) VALUES (?, ?)",[s,r]);return await at(s)}async function Bl(e,t){const s={};return t.name!==void 0&&(s.name=t.name),t.description!==void 0&&(s.description=t.description),t.level!==void 0&&(s.level=t.level),Object.keys(s).length===0||await tt.update(e,s)?at(e):null}async function $l(e){const t=await tt.getById(e);if(!t||t.is_builtin)return!1;const s=await p();return await s.run("DELETE FROM hat_permissions WHERE hat_id = ?",[e]),await s.run("UPDATE user_hats SET is_active = 0 WHERE hat_id = ?",[e]),tt.delete(e)}async function Hl(e,t){const s=await p();if(!await tt.getById(e))return null;await s.run("DELETE FROM hat_permissions WHERE hat_id = ?",[e]);for(const n of t)await s.run("INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key) VALUES (?, ?)",[e,n]);return at(e)}const Nr={parts:["parts.view","parts.create","parts.edit","parts.delete","parts.import","parts.export","parts.manage_categories"],inventory:["inventory.view","inventory.adjust","inventory.transfer","inventory.count","inventory.audit"],orders:["orders.view","orders.create","orders.edit","orders.delete","orders.approve","orders.receive","orders.return"],jobs:["jobs.view","jobs.create","jobs.edit","jobs.delete","jobs.assign","jobs.close","jobs.manage_labor"],labor:["labor.view","labor.clock_in","labor.clock_out","labor.edit_entries","labor.approve","labor.view_all"],fleet:["fleet.view","fleet.manage_vehicles","fleet.manage_assignments","fleet.manage_maintenance","fleet.view_mileage"],people:["people.view","people.create","people.edit","people.delete","people.manage_hats","people.manage_permissions","people.view_wages","people.manage_wages","people.view_notes","people.manage_notes"],tools:["tools.view","tools.manage","tools.checkout","tools.return","tools.manage_kits","tools.manage_maintenance"],warehouse:["warehouse.view","warehouse.manage","warehouse.receive","warehouse.ship","warehouse.audit"],reports:["reports.view","reports.create","reports.export","reports.manage_periods","reports.billing"],scheduling:["scheduling.view","scheduling.manage","scheduling.dispatch","scheduling.approve_pto"],admin:["admin.full_access","admin.manage_users","admin.manage_settings","admin.manage_devices","admin.view_audit_log"]};async function Wl(){const e=await p(),s=(await e.query("SELECT id, name, level FROM hats ORDER BY level DESC, name ASC")).values,r=await e.query("SELECT hat_id, permission_key FROM hat_permissions ORDER BY permission_key"),n=new Map;for(const d of s)n.set(d.id,new Set);for(const d of r.values){const l=n.get(d.hat_id);l&&l.add(d.permission_key)}const i=new Set;for(const d of Object.values(Nr))for(const l of d)i.add(l);const o=[];for(const d of r.values)i.has(d.permission_key)||(i.add(d.permission_key),o.push(d.permission_key));const c={};for(const[d,l]of Object.entries(Nr))c[d]=l.map(u=>({permission_key:u,domain:d,hat_values:Object.fromEntries(s.map(E=>[E.id,n.get(E.id)?.has(u)??!1]))}));return o.length>0&&(c.other=o.sort().map(d=>({permission_key:d,domain:"other",hat_values:Object.fromEntries(s.map(l=>[l.id,n.get(l.id)?.has(d)??!1]))}))),{hats:s,domains:c}}async function Kl(e,t){return await Ls.update(e,{avatar_url:t,updated_at:new Date().toISOString()}),{avatar_url:t}}async function Yl(e,t){return await ft.update(e,{document_path:t,updated_at:new Date().toISOString()}),{document_path:t}}async function Vl(e){const t=e.trim().split(`
`);if(t.length<2)return{created:0,skipped:0,errors:[{row:0,error:"No data rows found"}]};const s=t[0].split(",").map(v=>v.trim().toLowerCase().replace(/['"]/g,"")),r=v=>s.indexOf(v),n=r("display_name"),i=r("pin"),o=r("email"),c=r("phone"),d=r("certification"),l=r("hire_date"),u=r("pay_rate"),E=r("hat_id");if(n===-1)return{created:0,skipped:0,errors:[{row:0,error:"Missing required column: display_name"}]};if(i===-1)return{created:0,skipped:0,errors:[{row:0,error:"Missing required column: pin"}]};const _={created:0,skipped:0,errors:[]},y=await(await p()).query("SELECT display_name FROM users WHERE deleted_at IS NULL"),f=new Set(y.values.map(v=>v.display_name?.toLowerCase()));for(let v=1;v<t.length;v++){const h=t[v].trim();if(!h)continue;const T=Ip(h),g=T[n]?.trim(),L=T[i]?.trim();if(!g){_.errors.push({row:v+1,error:"Missing display_name"}),_.skipped++;continue}if(!L){_.errors.push({row:v+1,error:"Missing pin"}),_.skipped++;continue}if(f.has(g.toLowerCase())){_.errors.push({row:v+1,error:`Duplicate: "${g}" already exists`}),_.skipped++;continue}try{const w=E>=0&&T[E]?T[E].split(",").map(C=>parseInt(C.trim(),10)).filter(C=>!isNaN(C)):void 0,O=u>=0&&T[u]?parseFloat(T[u]):void 0;await Cs({display_name:g,pin:L,email:o>=0&&T[o]?.trim()||null,phone:c>=0&&T[c]?.trim()||null,certification:d>=0&&T[d]?.trim()||null,hire_date:l>=0&&T[l]?.trim()||null,pay_rate:O!=null&&!isNaN(O)?O:null,hat_ids:w&&w.length>0?w:null}),f.add(g.toLowerCase()),_.created++}catch(w){_.errors.push({row:v+1,error:w.message||"Unknown error"}),_.skipped++}}return _}function Ip(e){const t=[];let s="",r=!1;for(let n=0;n<e.length;n++){const i=e[n];r?i==='"'?n+1<e.length&&e[n+1]==='"'?(s+='"',n++):r=!1:s+=i:i==='"'?r=!0:i===","?(t.push(s.trim()),s=""):s+=i}return t.push(s.trim()),t}const Uy=Object.freeze(Object.defineProperty({__proto__:null,addTeamMember:Dl,addUserSkill:Cl,addWageEntry:bs,createCertification:Rl,createEmployee:Cs,createEmployeeNote:Ll,createHat:Gl,createTeam:jl,deleteCertification:wl,deleteEmployeeNote:Sl,deleteHat:$l,deleteTeam:kl,deleteUserSkill:Ol,getCertification:hs,getCurrentPayRate:vs,getEmployee:Ss,getEmployeeNotes:Rs,getEmployees:Pl,getHat:at,getHats:ql,getPermissionMatrix:Wl,getTeam:ia,getUserCertifications:xs,getUserSkills:ws,getWageHistory:fs,importEmployeesCSV:Vl,listTeams:Al,removeTeamMember:Fl,setHatPermissions:Hl,toggleEmployeeActive:Ml,updateHat:Bl,updateTeam:Il,updateTeamMemberRole:Ul,uploadCertificationDocument:Yl,uploadEmployeeAvatar:Kl},Symbol.toStringTag,{value:"Module"})),gt=new Y("report_annotations"),Tt=new Y("report_share_tokens"),Oa=new Y("report_templates");async function Jl(e){const t=new Date().toISOString(),s=await gt.insert({report_type:e.report_type,context_key:e.context_key,content:e.content,author_id:e.author_id,created_at:t,updated_at:t});return await gt.getById(s)}async function Os(e,t){return(await(await p()).query(`SELECT ra.*, u.display_name as author_name
     FROM report_annotations ra
     LEFT JOIN users u ON u.id = ra.author_id
     WHERE ra.report_type = ? AND ra.context_key = ? AND ra.deleted_at IS NULL
     ORDER BY ra.created_at DESC`,[e,t])).values}async function Ql(e,t){return await gt.update(e,{...t,updated_at:new Date().toISOString()})?await gt.getById(e):null}async function zl(e){return gt.update(e,{deleted_at:new Date().toISOString()})}function kp(){const e="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";let t="";for(let s=0;s<32;s++)t+=e.charAt(Math.floor(Math.random()*e.length));return t}async function Zl(e){const t=await Tt.insert({token:kp(),report_type:e.report_type,context_params:JSON.stringify(e.context_params),label:e.label??null,created_by:e.created_by,expires_at:e.expires_at??null,is_active:1,created_at:new Date().toISOString()});return await Tt.getById(t)}async function js(e){return(await Tt.findAll("token = ? AND deleted_at IS NULL",[e]))[0]??null}async function ed(e){const t=await p(),s=["st.deleted_at IS NULL"],r=[];return e?.report_type&&(s.push("st.report_type = ?"),r.push(e.report_type)),e?.active_only&&(s.push("st.is_active = 1"),s.push("(st.expires_at IS NULL OR st.expires_at > datetime('now'))")),(await t.query(`SELECT st.*, u.display_name as created_by_name
     FROM report_share_tokens st
     LEFT JOIN users u ON u.id = st.created_by
     WHERE ${s.join(" AND ")}
     ORDER BY st.created_at DESC`,r)).values}async function td(e){return Tt.update(e,{is_active:0})}async function As(e){await Tt.update(e,{last_accessed_at:new Date().toISOString()},!1)}async function ad(e){const t=new Date().toISOString(),s=await Oa.insert({name:e.name,report_type:e.report_type,config_json:JSON.stringify(e.config_json),created_by:e.created_by,created_at:t,updated_at:t});return await Oa.getById(s)}async function sd(e){const t=await p(),s=["rt.deleted_at IS NULL"],r=[];return e&&(s.push("rt.report_type = ?"),r.push(e)),(await t.query(`SELECT rt.*, u.display_name as created_by_name
     FROM report_templates rt
     LEFT JOIN users u ON u.id = rt.created_by
     WHERE ${s.join(" AND ")}
     ORDER BY rt.name ASC`,r)).values}async function rd(e){return Oa.update(e,{deleted_at:new Date().toISOString()})}async function me(e,t=[]){const s=await p();try{return(await s.query(e,t)).values??[]}catch{return[]}}async function nd(e,t=[]){const s=await p();try{const n=(await s.query(e,t)).values?.[0];if(!n)return 0;const i=Object.values(n)[0];return typeof i=="number"?i:0}catch{return 0}}function Is(e){const t=new Map;for(const r of e){const i=`${r.user_id??r.employee_id??0}|${r.date}`,o=t.get(i)??[];o.push(r),t.set(i,o)}const s=[];for(const r of Array.from(t.values())){const n=r.reduce((c,d)=>c+d.total_hours,0),i=Math.max(0,n-8),o=n-i;for(const c of r){const d=n>0?c.total_hours/n:0;s.push({...c,regular_hours:Math.round(o*d*100)/100,overtime_hours:Math.round(i*d*100)/100})}}return s}function ge(e){if(e.length===0)return"";const t=Object.keys(e[0]);return[t.join(","),...e.map(r=>t.map(n=>{const i=r[n];if(i==null)return"";const o=String(i);return o.includes(",")||o.includes('"')||o.includes(`
`)?`"${o.replace(/"/g,'""')}"`:o}).join(","))].join(`
`)}async function oa(e){const{start_date:t,end_date:s}=e,r=await me(`SELECT id, job_number, job_name, estimated_hours
     FROM jobs
     WHERE status IN ('active', 'on_hold', 'continuous_maintenance', 'on_call')
       AND deleted_at IS NULL
     ORDER BY job_number`),n=[];for(const i of r){const o=await nd(`SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
       FROM labor_entries
       WHERE job_id = ? AND date(clock_in) >= ? AND date(clock_in) <= ?
         AND status != 'clocked_in'`,[i.id,t,s]),c=await me(`SELECT
         COALESCE(SUM(qty_consumed * COALESCE(unit_cost_at_consume, 0)), 0) as cost,
         COALESCE(SUM(qty_consumed * COALESCE(unit_sell_at_consume, 0)), 0) as sell
       FROM job_parts
       WHERE job_id = ? AND date(consumed_at) >= ? AND date(consumed_at) <= ?`,[i.id,t,s]),d=c[0]?.cost??0,l=c[0]?.sell??0,u=i.estimated_hours??null,E=u&&u>0?Math.round(o/u*1e4)/100:null;n.push({job_id:i.id,job_number:i.job_number,job_name:i.job_name,total_labor_hours:Math.round(o*100)/100,total_parts_cost:Math.round(d*100)/100,total_parts_sell:Math.round(l*100)/100,budget_limit:u,budget_used_pct:E})}return n}async function vt(e){const{job_id:t,start_date:s,end_date:r}=e,i=(await me(`SELECT j.job_name, j.job_number, j.estimated_hours, j.bill_rate_type_id
     FROM jobs j WHERE j.id = ?`,[t]))[0]??{job_name:"",job_number:"",estimated_hours:null,bill_rate_type_id:null};let o=null;i.bill_rate_type_id&&(o=(await me("SELECT name FROM bill_rate_types WHERE id = ?",[i.bill_rate_type_id]))[0]?.name??null);const c=await me(`SELECT
       le.user_id,
       COALESCE(u.display_name, 'Unknown') as display_name,
       date(le.clock_in) as date,
       le.clock_in,
       le.clock_out,
       (le.regular_hours + le.overtime_hours) as total_hours,
       brt.name as bill_rate_name
     FROM labor_entries le
     LEFT JOIN users u ON u.id = le.user_id
     LEFT JOIN jobs j ON j.id = le.job_id
     LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
     WHERE le.job_id = ? AND date(le.clock_in) >= ? AND date(le.clock_in) <= ?
       AND le.status != 'clocked_in'
     ORDER BY le.clock_in`,[t,s,r]),l=Is(c).map(g=>({employee_id:g.user_id,employee:g.display_name,date:g.date,clock_in:g.clock_in,clock_out:g.clock_out,regular_hours:g.regular_hours,overtime_hours:g.overtime_hours,total_hours:g.total_hours,bill_rate_type:g.bill_rate_name})),u=await me(`SELECT
       jp.part_id,
       p.name as part_name,
       p.code as part_code,
       jp.qty_consumed as qty,
       COALESCE(jp.unit_cost_at_consume, 0) as unit_cost,
       COALESCE(jp.unit_sell_at_consume, 0) as sell_price,
       (jp.qty_consumed * COALESCE(jp.unit_cost_at_consume, 0)) as total_cost,
       (jp.qty_consumed * COALESCE(jp.unit_sell_at_consume, 0)) as total_sell
     FROM job_parts jp
     LEFT JOIN parts p ON p.id = jp.part_id
     WHERE jp.job_id = ? AND date(jp.consumed_at) >= ? AND date(jp.consumed_at) <= ?
     ORDER BY jp.consumed_at`,[t,s,r]),E=await me(`SELECT
       date(sm.created_at) as date,
       p.name as part_name,
       sm.from_location_type as from_location,
       sm.to_location_type as to_location,
       sm.qty,
       sm.movement_type
     FROM stock_movements sm
     LEFT JOIN parts p ON p.id = sm.part_id
     WHERE sm.job_id = ? AND date(sm.created_at) >= ? AND date(sm.created_at) <= ?
     ORDER BY sm.created_at`,[t,s,r]),_=l.reduce((g,L)=>g+L.total_hours,0),m=l.reduce((g,L)=>g+L.regular_hours,0),y=l.reduce((g,L)=>g+L.overtime_hours,0),f=u.reduce((g,L)=>g+L.total_cost,0),v=u.reduce((g,L)=>g+L.total_sell,0),h=i.estimated_hours??null,T=h&&h>0?Math.round(_/h*1e4)/100:null;return{job_id:t,job_name:i.job_name,job_number:i.job_number,bill_rate_type:o,period_start:s,period_end:r,labor:l,parts:u,movements:E,summary:{total_labor_hours:Math.round(_*100)/100,total_regular_hours:Math.round(m*100)/100,total_overtime_hours:Math.round(y*100)/100,total_parts_cost:Math.round(f*100)/100,total_parts_sell:Math.round(v*100)/100,budget_limit:h,budget_used_pct:T}}}async function ca(e){const{start_date:t,end_date:s,employee_id:r,group_by:n="day"}=e;let i=null;r&&(i=(await me("SELECT display_name FROM users WHERE id = ?",[r]))[0]?.display_name??null);const o=["date(le.clock_in) >= ?","date(le.clock_in) <= ?","le.status != 'clocked_in'"],c=[t,s];r&&(o.push("le.user_id = ?"),c.push(r));const d=await me(`SELECT
       le.id,
       le.user_id,
       date(le.clock_in) as date,
       le.job_id,
       COALESCE(j.job_name, 'Unknown') as job_name,
       COALESCE(j.job_number, '') as job_number,
       le.clock_in,
       le.clock_out,
       (le.regular_hours + le.overtime_hours) as total_hours,
       brt.name as bill_rate_name,
       le.clock_in_gps_lat,
       le.clock_in_gps_lng,
       le.clock_out_gps_lat,
       le.clock_out_gps_lng
     FROM labor_entries le
     LEFT JOIN jobs j ON j.id = le.job_id
     LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
     WHERE ${o.join(" AND ")}
     ORDER BY le.clock_in`,c),u=Is(d).map(h=>({id:h.id,date:h.date,job_id:h.job_id,job_name:h.job_name,job_number:h.job_number,clock_in:h.clock_in,clock_out:h.clock_out,regular_hours:h.regular_hours,overtime_hours:h.overtime_hours,total_hours:h.total_hours,bill_rate_type:h.bill_rate_name,gps_in:h.clock_in_gps_lat!=null&&h.clock_in_gps_lng!=null?{lat:h.clock_in_gps_lat,lng:h.clock_in_gps_lng}:null,gps_out:h.clock_out_gps_lat!=null&&h.clock_out_gps_lng!=null?{lat:h.clock_out_gps_lat,lng:h.clock_out_gps_lng}:null})),E=new Map;for(const h of u){const T=E.get(h.date)??[];T.push(h),E.set(h.date,T)}const _=Array.from(E.entries()).sort(([h],[T])=>h.localeCompare(T)).map(([h,T])=>{const g=T.reduce((O,C)=>O+C.total_hours,0),L=T.reduce((O,C)=>O+C.regular_hours,0),w=T.reduce((O,C)=>O+C.overtime_hours,0);return{date:h,entries:T,total_hours:Math.round(g*100)/100,regular_hours:Math.round(L*100)/100,overtime_hours:Math.round(w*100)/100}}),m=u.reduce((h,T)=>h+T.total_hours,0),y=u.reduce((h,T)=>h+T.regular_hours,0),f=u.reduce((h,T)=>h+T.overtime_hours,0),v=new Set(u.map(h=>h.job_id));return{employee_id:r??null,employee_name:i,period_start:t,period_end:s,group_by:n,entries:u,day_groups:_,summary:{total_hours:Math.round(m*100)/100,regular_hours:Math.round(y*100)/100,overtime_hours:Math.round(f*100)/100,days_worked:E.size,jobs_worked:v.size}}}async function la(e){const{start_date:t,end_date:s,job_id:r}=e,n=r?"AND le.job_id = ?":"",i=r?[t,s,r]:[t,s],o=await me(`SELECT
       le.user_id,
       COALESCE(u.display_name, 'Unknown') as display_name,
       date(le.clock_in) as date,
       le.job_id,
       COALESCE(j.job_name, '') as job_name,
       COALESCE(j.job_number, '') as job_number,
       (le.regular_hours + le.overtime_hours) as total_hours,
       brt.name as bill_rate_name
     FROM labor_entries le
     LEFT JOIN users u ON u.id = le.user_id
     LEFT JOIN jobs j ON j.id = le.job_id
     LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
     WHERE date(le.clock_in) >= ? AND date(le.clock_in) <= ?
       AND le.status != 'clocked_in'
       ${n}
     ORDER BY le.clock_in`,i),c=Is(o),d=new Map;for(const T of c){const g=d.get(T.user_id);g?(g.totalHours+=T.total_hours,g.regularHours+=T.regular_hours,g.overtimeHours+=T.overtime_hours,g.jobs.add(T.job_id),g.days.add(T.date)):d.set(T.user_id,{employee:T.display_name,totalHours:T.total_hours,regularHours:T.regular_hours,overtimeHours:T.overtime_hours,jobs:new Set([T.job_id]),days:new Set([T.date])})}const l=Array.from(d.entries()).map(([T,g])=>({employee_id:T,employee:g.employee,total_hours:Math.round(g.totalHours*100)/100,regular_hours:Math.round(g.regularHours*100)/100,overtime_hours:Math.round(g.overtimeHours*100)/100,jobs_worked:g.jobs.size,days_worked:g.days.size,avg_hours_per_day:g.days.size>0?Math.round(g.totalHours/g.days.size*100)/100:0})),u=new Map;for(const T of c){const g=u.get(T.job_id);g?(g.totalHours+=T.total_hours,g.employees.add(T.user_id)):u.set(T.job_id,{job_name:T.job_name,job_number:T.job_number,totalHours:T.total_hours,employees:new Set([T.user_id])})}const E=Array.from(u.entries()).map(([T,g])=>({job_id:T,job_name:g.job_name,job_number:g.job_number,total_hours:Math.round(g.totalHours*100)/100,employee_count:g.employees.size})),_=new Map;for(const T of c){const g=T.bill_rate_name??"Unassigned",L=_.get(g);L?(L.totalHours+=T.total_hours,L.count+=1):_.set(g,{totalHours:T.total_hours,count:1})}const m=Array.from(_.entries()).map(([T,g])=>({rate_type:T,total_hours:Math.round(g.totalHours*100)/100,entry_count:g.count})),y=new Set(c.map(T=>T.date)),f=c.reduce((T,g)=>T+g.total_hours,0),v=c.reduce((T,g)=>T+g.regular_hours,0),h=c.reduce((T,g)=>T+g.overtime_hours,0);return{period_start:t,period_end:s,by_employee:l,by_job:E,by_bill_rate:m,totals:{total_hours:Math.round(f*100)/100,regular_hours:Math.round(v*100)/100,overtime_hours:Math.round(h*100)/100,total_employees:d.size,total_jobs:u.size,total_days:y.size}}}const Dp=50;async function da(e){const{start_date:t,end_date:s,job_id:r}=e,i=await me(`SELECT DISTINCT j.id, j.job_name, j.job_number, j.status,
            j.estimated_hours, j.billing_rate
     FROM jobs j
     WHERE j.deleted_at IS NULL ${r?"AND j.id = ?":""}
     ORDER BY j.job_number`,r?[r]:[]),o=[];for(const y of i){const f=await nd(`SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
       FROM labor_entries
       WHERE job_id = ? AND date(clock_in) >= ? AND date(clock_in) <= ?
         AND status != 'clocked_in'`,[y.id,t,s]),v=await me(`SELECT
         COALESCE(SUM(qty_consumed * COALESCE(unit_cost_at_consume, 0)), 0) as cost,
         COALESCE(SUM(qty_consumed * COALESCE(unit_sell_at_consume, 0)), 0) as sell
       FROM job_parts
       WHERE job_id = ? AND date(consumed_at) >= ? AND date(consumed_at) <= ?`,[y.id,t,s]),h=v[0]?.cost??0,T=v[0]?.sell??0;if(!r&&f===0&&h===0)continue;const g=y.billing_rate??Dp,L=f*g,w=L+h,O=T-h,C=y.estimated_hours??null,W=C!=null?C-f:null,Q=C&&C>0?Math.round(f/C*1e4)/100:null;o.push({job_id:y.id,job_name:y.job_name,job_number:y.job_number,status:y.status,labor_hours:Math.round(f*100)/100,labor_cost:Math.round(L*100)/100,parts_cost:Math.round(h*100)/100,parts_sell:Math.round(T*100)/100,total_cost:Math.round(w*100)/100,parts_margin:Math.round(O*100)/100,budget_limit:C,budget_remaining:W!=null?Math.round(W*100)/100:null,budget_utilization_pct:Q})}const c=o.reduce((y,f)=>y+f.labor_cost,0),d=o.reduce((y,f)=>y+f.parts_cost,0),l=o.reduce((y,f)=>y+f.parts_sell,0),u=o.reduce((y,f)=>y+f.labor_hours,0);let E=0,_=0,m=0;for(const y of o)y.budget_limit==null?m++:y.budget_utilization_pct!=null&&y.budget_utilization_pct>100?_++:E++;return{period_start:t,period_end:s,by_job:o,totals:{total_labor_cost:Math.round(c*100)/100,total_parts_cost:Math.round(d*100)/100,total_parts_sell:Math.round(l*100)/100,total_combined_cost:Math.round((c+d)*100)/100,total_parts_margin:Math.round((l-d)*100)/100,total_labor_hours:Math.round(u*100)/100,jobs_under_budget:E,jobs_over_budget:_,jobs_no_budget:m}}}async function ks(e){const t=e.start_date??"2000-01-01",s=e.end_date??"2099-12-31";let r="";switch(e.report_type){case"pre-billing":{if(e.job_id){const n=await vt({job_id:e.job_id,start_date:t,end_date:s});r+=`=== LABOR ===
`,r+=ge(n.labor),r+=`

=== PARTS ===
`,r+=ge(n.parts),r+=`

=== MOVEMENTS ===
`,r+=ge(n.movements),r+=`

=== SUMMARY ===
`,r+=ge([n.summary])}else{const n=await oa({start_date:t,end_date:s});r=ge(n)}break}case"timesheet":{const n=await ca({start_date:t,end_date:s,employee_id:e.employee_id});r=ge(n.entries.map(i=>({date:i.date,job_number:i.job_number,job_name:i.job_name,clock_in:i.clock_in,clock_out:i.clock_out??"",regular_hours:i.regular_hours,overtime_hours:i.overtime_hours,total_hours:i.total_hours,bill_rate_type:i.bill_rate_type??""})));break}case"labor-overview":{const n=await la({start_date:t,end_date:s,job_id:e.job_id});r+=`=== BY EMPLOYEE ===
`,r+=ge(n.by_employee),r+=`

=== BY JOB ===
`,r+=ge(n.by_job),r+=`

=== BY BILL RATE ===
`,r+=ge(n.by_bill_rate),r+=`

=== TOTALS ===
`,r+=ge([n.totals]);break}case"profitability":{const n=await da({start_date:t,end_date:s,job_id:e.job_id});r=ge(n.by_job),r+=`

=== TOTALS ===
`,r+=ge([n.totals]);break}}return new Blob([r],{type:"text/csv"})}async function id(e){const{format:t,job_ids:s,period_start:r,period_end:n,include_labor:i=!0,include_parts:o=!0}=e,c=[],d=s&&s.length>0?s:(await me("SELECT id FROM jobs WHERE deleted_at IS NULL ORDER BY job_number")).map(u=>u.id);for(const u of d){const E=await vt({job_id:u,start_date:r,end_date:n});if(t==="quickbooks"){if(i&&E.labor.length>0){c.push("!TIMEACT	DATE	JOB	EMPLOYEE	DURATION	BILLABLESTATUS");for(const _ of E.labor)c.push(`TIMEACT	${_.date}	${E.job_number}	${_.employee}	${_.total_hours}	Billable`)}if(o&&E.parts.length>0){c.push("!TRNS	DATE	ACCNT	NAME	AMOUNT	MEMO");for(const _ of E.parts)c.push(`TRNS	${n}	Cost of Goods	${E.job_number}	${_.total_cost}	${_.part_name}`)}}else if(t==="general_ledger"){if(i){c.push("Date,Account,Description,Debit,Credit,Job");for(const _ of E.labor){const m=Math.round(_.total_hours*(E.bill_rate_type,50)*100)/100;c.push(`${_.date},5000 - Labor,${_.employee} - ${E.job_number},${m},,${E.job_number}`)}}if(o)for(const _ of E.parts)c.push(`${n},5100 - Materials,${_.part_name} - ${E.job_number},${_.total_cost},,${E.job_number}`)}else if(i){c.push("Employee,Date,Job,Regular Hours,Overtime Hours,Total Hours");for(const _ of E.labor)c.push(`${_.employee},${_.date},${E.job_number},${_.regular_hours},${_.overtime_hours},${_.total_hours}`)}}const l=c.join(`
`);return new Blob([l],{type:"text/csv"})}async function od(e){const t=[];for(const s of e){const r=s.report_type,i=await(await ks({report_type:r,format:s.format??"csv",job_id:s.job_id,employee_id:s.employee_id,start_date:s.start_date,end_date:s.end_date})).text();t.push(`
========== ${s.report_type.toUpperCase()} (${s.start_date} to ${s.end_date}) ==========
`),t.push(i)}return new Blob(t,{type:"text/csv"})}async function cd(e){const t=await js(e);if(!t||!t.is_active)throw new Error("Invalid or expired share token");if(t.expires_at&&new Date(t.expires_at)<new Date)throw new Error("Share token has expired");await As(t.id);const s=typeof t.context_params=="string"?JSON.parse(t.context_params):t.context_params;let r={};const n=s.start_date??s.period_start??"2000-01-01",i=s.end_date??s.period_end??"2099-12-31";switch(t.report_type){case"pre-billing":{s.job_id?r=await vt({job_id:s.job_id,start_date:n,end_date:i}):r={jobs:await oa({start_date:n,end_date:i})};break}case"timesheet":{r=await ca({start_date:n,end_date:i,employee_id:s.employee_id});break}case"labor-overview":{r=await la({start_date:n,end_date:i,job_id:s.job_id});break}case"profitability":{r=await da({start_date:n,end_date:i,job_id:s.job_id});break}default:r={error:`Unknown report type: ${t.report_type}`}}const o=s.context_key??`${t.report_type}:${n}:${i}`,c=await Os(t.report_type,o);return{report_type:t.report_type,label:t.label,generated_at:new Date().toISOString(),context_params:s,data:r,annotations:c}}const Py=Object.freeze(Object.defineProperty({__proto__:null,createAnnotation:Jl,createShareToken:Zl,createTemplate:ad,deactivateShareToken:td,deleteAnnotation:zl,deleteTemplate:rd,generateBookkeeperExport:id,generateExport:ks,generateExportBundle:od,getAnnotations:Os,getLaborOverview:la,getPreBilling:vt,getPreBillingAllJobs:oa,getProfitability:da,getPublicReport:cd,getShareTokenByValue:js,getTimesheets:ca,listShareTokens:ed,listTemplates:sd,recordTokenAccess:As,updateAnnotation:Ql},Symbol.toStringTag,{value:"Module"})),Ds=new Y("billing_periods");async function ld(e){const t=new Date().toISOString(),s=await Ds.insert({job_id:e.job_id??null,period_start:e.period_start,period_end:e.period_end,notes:e.notes??null,created_at:t,updated_at:t});return await Rt(s)}async function Rt(e){return(await(await p()).query(`SELECT bp.*,
       j.job_name,
       u.display_name as locked_by_name,
       CASE WHEN bp.locked_at IS NOT NULL THEN 1 ELSE 0 END as is_locked
     FROM billing_periods bp
     LEFT JOIN jobs j ON j.id = bp.job_id
     LEFT JOIN users u ON u.id = bp.locked_by
     WHERE bp.id = ?`,[e])).values[0]??null}async function dd(e){const t=await p(),s=["bp.deleted_at IS NULL"],r=[];e?.job_id!==void 0&&(e.job_id===0?s.push("bp.job_id IS NULL"):(s.push("bp.job_id = ?"),r.push(e.job_id))),e?.locked_only&&s.push("bp.locked_at IS NOT NULL"),e?.unlocked_only&&s.push("bp.locked_at IS NULL");const n=s.join(" AND "),i=e?.limit??100,o=e?.offset??0,c=await t.query(`SELECT COUNT(*) as cnt FROM billing_periods bp WHERE ${n}`,r);return{items:(await t.query(`SELECT bp.*,
       j.job_name,
       u.display_name as locked_by_name,
       CASE WHEN bp.locked_at IS NOT NULL THEN 1 ELSE 0 END as is_locked
     FROM billing_periods bp
     LEFT JOIN jobs j ON j.id = bp.job_id
     LEFT JOIN users u ON u.id = bp.locked_by
     WHERE ${n}
     ORDER BY bp.period_start DESC
     LIMIT ? OFFSET ?`,[...r,i,o])).values,total:c.values[0]?.cnt??0}}async function ud(e,t){return await Ds.update(e,{locked_at:new Date().toISOString(),locked_by:t,updated_at:new Date().toISOString()})?Rt(e):null}async function _d(e){return await Ds.update(e,{locked_at:null,locked_by:null,updated_at:new Date().toISOString()})?Rt(e):null}const My=Object.freeze(Object.defineProperty({__proto__:null,createBillingPeriod:ld,getBillingPeriod:Rt,listBillingPeriods:dd,lockBillingPeriod:ud,unlockBillingPeriod:_d},Symbol.toStringTag,{value:"Module"})),Fp=new Y("supplier_po_acknowledgments");async function Ed(e){return(await(await p()).query(`SELECT spt.*, s.name as supplier_name, u.display_name as created_by_name
     FROM supplier_portal_tokens spt
     LEFT JOIN suppliers s ON s.id = spt.supplier_id
     LEFT JOIN users u ON u.id = spt.created_by
     WHERE spt.id = ?`,[e])).values[0]??null}async function pd(e){const t=await Fp.insert({po_id:e.po_id,supplier_id:e.supplier_id,token_id:e.token_id??null,estimated_delivery:e.estimated_delivery??null,supplier_notes:e.supplier_notes??null,acknowledged_at:new Date().toISOString()});return await Fs(t)}async function Fs(e){return(await(await p()).query(`SELECT spa.*, po.po_number, s.name as supplier_name
     FROM supplier_po_acknowledgments spa
     LEFT JOIN purchase_orders po ON po.id = spa.po_id
     LEFT JOIN suppliers s ON s.id = spa.supplier_id
     WHERE spa.id = ?`,[e])).values[0]??null}const Xy=Object.freeze(Object.defineProperty({__proto__:null,createAcknowledgment:pd,getAcknowledgment:Fs,getPortalToken:Ed},Symbol.toStringTag,{value:"Module"})),qy=Object.freeze(Object.defineProperty({__proto__:null,addCustomerContact:Ko,addGCContact:tc,addJobTeamMember:Mc,addSupplierContact:rc,addTeamMember:Dl,addUserSkill:Cl,addWageEntry:bs,answerQuestion:qn,archiveNotebook:cl,askQuestion:Xn,authenticateByPin:on,bulkUpdateTasks:_l,calculatePreview:Yc,checkoutTool:gl,clearCustomMargin:xi,clearDeviceSecurity:ni,clockIn:qc,clockOut:Gc,createAcknowledgment:pd,createAnnotation:Jl,createBillRateType:fc,createBillingPeriod:ld,createBrand:Eo,createBrandSupplierLink:To,createBtHello:ri,createCertification:Rl,createColor:ao,createCompanionRule:So,createCompanyProfile:Tn,createCustomer:Bo,createEmployee:Cs,createEmployeeNote:Ll,createEntry:al,createGC:Qo,createGlobalQuestion:Lc,createHat:Gl,createJPO:Qc,createJob:Tc,createNotebook:gs,createOneTimeQuestion:jc,createPartCategory:Fi,createSection:tl,createShareToken:Zl,createStyle:Xi,createSupplier:xo,createTeam:jl,createTemplate:ad,createType:Hi,deactivateGlobalQuestion:Oc,deactivateShareToken:td,decideCompanionSuggestion:Io,deleteAnnotation:zl,deleteBillRateType:Rc,deleteBrand:mo,deleteBrandSupplierLink:No,deleteCertification:wl,deleteColor:ro,deleteCompanionRule:Oo,deleteCompanyProfile:hn,deleteEmployeeNote:Sl,deleteEntityContact:oc,deleteEntry:sl,deleteHat:$l,deleteMessage:Dn,deletePartCategory:Pi,deletePartLocal:oo,deleteStyle:Gi,deleteSupplier:fo,deleteTeam:kl,deleteTemplate:rd,deleteType:Ki,deleteUserSkill:Ol,editMessage:kn,enforceDefaultMargin:bi,executeMovement:Vc,exportPartsCsv:wo,findDuplicateCustomers:yc,generateBookkeeperExport:id,generateCompanionSuggestions:jo,generateExport:ks,generateExportBundle:od,getAcknowledgment:Fs,getActiveClock:_s,getActiveJobs:Nc,getActiveUsers:cn,getAllJobReports:Ic,getAllSettings:_n,getAnnotations:Os,getBillRateTypes:bc,getBillingCycle:es,getBillingPeriod:Rt,getBrandSuppliers:yo,getBudgetAlerts:ns,getCatalogGroups:co,getCategories:Di,getCertAlerts:mi,getCertification:hs,getChannelMembers:jn,getChannelMessages:On,getClockOutBundle:Ac,getCompanionStats:ko,getCostHistory:Ni,getCostLayers:Ti,getCostSettings:gi,getCurrentPayRate:vs,getCustomer:aa,getCustomerContacts:Wo,getCustomerJobs:Yo,getCustomers:qo,getDailyReport:ji,getDashboard:_i,getDashboardKPIs:$c,getDbEncryptionKey:Qn,getDeviceIdentity:ai,getDevicePublicKey:Zn,getDispatchForDate:Ii,getEmployee:Ss,getEmployeeNotes:Rs,getEmployees:Pl,getFastDriveContext:Ei,getForecasting:vo,getGC:sa,getGCContacts:ec,getGCJobs:ac,getGCs:Vo,getGlobalQuestions:ls,getHat:at,getHats:ql,getHierarchy:ki,getInbox:Cn,getInventoryGrid:Wc,getJPO:na,getJPOLines:Zc,getJob:ct,getJobBudgetStatus:Ci,getJobCostRollup:Si,getJobCustomers:cc,getJobGCs:uc,getJobNotebook:ol,getJobParts:wc,getJobPreferences:us,getJobPreferredSuppliers:Fc,getJobReport:kc,getJobSuggestions:Dc,getJobTeam:Pc,getLaborEntry:ra,getLaborForJob:Bc,getLaborOverview:la,getMyTimeOff:Ai,getMyVehicle:hl,getNotebook:Mt,getNotebookTemplateFull:il,getNotificationBadge:Gn,getNotificationPreferences:Hn,getNotificationSoundSettings:Kn,getOneTimeQuestions:ds,getPDFSettings:Za,getPart:os,getPartCostSummary:ea,getPayPeriod:ts,getPayrollColumns:Rn,getPendingPartNumbersCount:lo,getPermissionMatrix:Wl,getPinnedMessages:An,getPortalToken:Ed,getPreBilling:vt,getPreBillingAllJobs:oa,getPriceVarianceReport:Oi,getProfitability:da,getPublicReport:cd,getRecentActivity:Hc,getRecentMovements:Jc,getSetting:En,getShareTokenByValue:js,getSpendingByCategory:Ri,getSpendingByJob:wi,getSpendingBySupplier:vi,getSpendingSummary:fi,getSpendingTrend:Li,getStoredCertificate:it,getSupplierBrands:go,getSupplierContacts:sc,getSyncAuthFields:si,getTeam:ia,getTheme:za,getTimesheets:ca,getTool:et,getToolByBarcode:yl,getToolsAtLocation:Nl,getTruckInventory:vl,getType:$i,getUser:$t,getUserCertifications:xs,getUserPermissions:Ya,getUserSkills:ws,getVehicle:xl,getVehicleAssignments:fl,getVehicleExpiryAlerts:yi,getWageHistory:fs,getWarrantyLengthDays:mn,hasPermission:ln,importContractorsCSV:mc,importCustomersCSV:pc,importEmployeesCSV:Vl,importPartsCsv:Lo,initialiseDeviceSecurity:Jn,isCertificateValid:ti,linkBrandToType:Qi,linkColorsToType:Yi,linkCustomerToJob:lc,linkGCToJob:_c,linkPartAlternative:Fo,listBillingPeriods:dd,listBrands:_o,listColors:to,listCompanionRules:ta,listCompanionSuggestions:Ao,listCompanyProfiles:gn,listJPOs:el,listNotebookTemplates:nl,listNotebooks:ys,listNotifications:Bn,listPartAlternatives:Do,listParts:no,listPartsForTypeBrand:Zi,listQAThreads:Mn,listShareTokens:ed,listStylesByCategory:Mi,listSuppliers:ho,listTeams:Al,listTemplates:sd,listTools:ml,listTypeBrands:Ji,listTypeColors:is,listTypesByStyle:Bi,listVehicles:bl,lockBillingPeriod:ud,markChannelRead:Pn,markNotificationsRead:$n,mergeCustomers:gc,pinMessage:Fn,quickCreatePart:eo,recalculateForecasts:Ro,recordTokenAccess:As,removeJobTeamMember:Xc,removeTeamMember:Fl,reorderEntries:ul,reorderGlobalQuestions:Cc,reorderSections:ll,returnTool:Tl,rotateDbEncryptionKey:ii,searchCustomers:Go,searchDirectory:nc,searchGCs:Jo,searchWarehouseParts:Kc,sendMessage:In,setCustomMargin:hi,setHatPermissions:Hl,setJobPreferredSuppliers:Uc,startDrive:pi,storeCertificate:ei,storeDeviceKeypair:zn,submitJPO:zc,toggleCustomerActive:Ho,toggleEmployeeActive:Ml,toggleGCActive:Zo,unlinkBrandFromType:zi,unlinkColorFromType:Vi,unlinkCustomerFromJob:dc,unlinkGCFromJob:Ec,unlinkPartAlternative:Po,unlockBillingPeriod:_d,unpinMessage:Un,updateAnnotation:Ql,updateBillRateType:vc,updateBillingCycle:fn,updateBrand:po,updateColor:so,updateCompanionRule:Co,updateCompanyProfile:Nn,updateCustomer:$o,updateEntityContact:ic,updateEntry:Ts,updateFieldValue:dl,updateGC:zo,updateGlobalQuestion:Sc,updateHat:Bl,updateJob:hc,updateJobStatus:xc,updateNotificationPreferences:Wn,updatePDFSettings:xn,updatePartAlternative:Uo,updatePartCategory:Ui,updatePartLocal:io,updatePartPricing:uo,updatePayPeriod:vn,updatePayrollColumns:wn,updateSetting:pn,updateStyle:qi,updateSupplier:bo,updateTaskStatus:rl,updateTeam:Il,updateTeamMemberRole:Ul,updateTheme:un,updateType:Wi,updateWarrantyLengthDays:yn,uploadCertificationDocument:Yl,uploadCompanyLogo:bn,uploadEmployeeAvatar:Kl,validateMovement:ps},Symbol.toStringTag,{value:"Module"}));export{cy as $,Hm as A,F as B,Ce as C,ry as D,le as E,ny as F,Rm as G,wm as H,q as I,ey as J,sy as K,Wp as L,Ne as M,Ba as N,x_ as O,gm as P,Ft as Q,Kr as R,z as S,Jr as T,Qu as U,Lu as V,wu as W,Kp as X,Jm as Y,ly as Z,N as _,G as a,Iu as a$,Pm as a0,iy as a1,Dm as a2,Xm as a3,Mm as a4,Gm as a5,B_ as a6,$_ as a7,Um as a8,qm as a9,cm as aA,sm as aB,nm as aC,om as aD,be as aE,$p as aF,Ys as aG,Se as aH,Hp as aI,Ey as aJ,my as aK,Ny as aL,gy as aM,hy as aN,by as aO,xy as aP,py as aQ,yy as aR,Ty as aS,pm as aT,Bp as aU,vu as aV,Ru as aW,qp as aX,_m as aY,Em as aZ,Au as a_,Bm as aa,Km as ab,oy as ac,$m as ad,Vm as ae,Ym as af,Qm as ag,Wm as ah,zm as ai,Zm as aj,Or as ak,Ma as al,dm as am,tu as an,ce as ao,lm as ap,Vp as aq,Qp as ar,zp as as,Zp as at,Jp as au,tm as av,am as aw,em as ax,rm as ay,im as az,o_ as b,rt as b0,mm as b1,Fu as b2,Cm as b3,uy as b4,Om as b5,jm as b6,dy as b7,Am as b8,Im as b9,Xy as bA,qy as bB,_y as ba,km as bb,kr as bc,ou as bd,um as be,ym as bf,Ja as bg,fy as bh,vy as bi,Ry as bj,wy as bk,oi as bl,Ly as bm,Sy as bn,Tr as bo,Cy as bp,Oy as bq,jy as br,Ay as bs,Iy as bt,ky as bu,Dy as bv,Fy as bw,Uy as bx,Py as by,My as bz,we as c,ba as d,R as e,x as f,Gp as g,Yp as h,Fe as i,Nm as j,ma as k,Ha as l,hm as m,xm as n,bm as o,fm as p,vm as q,Lm as r,Sm as s,Tm as t,Pe as u,Ka as v,H as w,Fm as x,ty as y,ay as z};
