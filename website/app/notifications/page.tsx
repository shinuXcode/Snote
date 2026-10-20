"use client";
import { useEffect, useState } from "react";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
type Notice={id:string;title:string;body:string;category:string;target:string;action_url:string|null;published_at:string|null;created_at:string};
const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
export default function NotificationsPage(){
 const [items,setItems]=useState<Notice[]>([]);
 const [state,setState]=useState<"loading"|"ready"|"setup"|"error">("loading");
 const [client,setClient]=useState<SupabaseClient|null>(null);
 useEffect(()=>{if(!url||!key){setState("setup");return;}const sb=createClient(url,key);setClient(sb);
 const load=async()=>{const {data,error}=await sb.from("snote_notifications").select("id,title,body,category,target,action_url,published_at,created_at").eq("published",true).in("target",["all","website"]).order("published_at",{ascending:false,nullsFirst:false}).limit(50);if(error){setState("error");return;}setItems(data??[]);setState("ready");};
 void load();const channel=sb.channel("website-notifications-page").on("postgres_changes",{event:"*",schema:"public",table:"snote_notifications"},()=>void load()).subscribe();return()=>{void sb.removeChannel(channel);};},[]);
 return <main style={{maxWidth:1040,margin:"0 auto",padding:"150px 24px 100px",minHeight:"70vh"}}>
 <div style={{fontSize:11,letterSpacing:".24em",color:"#999",textTransform:"uppercase"}}>SNOTE / LIVE UPDATES</div>
 <h1 style={{fontSize:"clamp(40px,7vw,76px)",lineHeight:1,letterSpacing:"-.06em",margin:"20px 0"}}>Notification centre<span style={{color:"#999"}}>.</span></h1>
 <p style={{color:"#aaa",maxWidth:640,lineHeight:1.7}}>Release notes, feature announcements, maintenance notices, and important Snote updates. Published changes appear automatically when the shared feed is configured.</p>
 {state==="setup"&&<section style={panel}><h2>Notifications are not connected yet</h2><p>Configure the Supabase URL and publishable key, apply the notification migration, and enable Realtime before announcements can appear here.</p></section>}
 {state==="error"&&<section style={panel}><h2>Feed unavailable</h2><p>The notification service could not be reached. Try again later.</p><button style={button} onClick={()=>location.reload()}>Retry</button></section>}
 {state==="loading"&&<p style={{color:"#999",padding:"32px 0"}}>Loading announcements…</p>}
 {state==="ready"&&items.length===0&&<section style={panel}><h2>No announcements yet</h2><p>New published Snote updates will appear here.</p></section>}
 {state==="ready"&&items.length>0&&<div style={{display:"grid",gap:14,marginTop:34}}>{items.map(n=><article key={n.id} style={panel}><div style={{display:"flex",gap:12,alignItems:"center",flexWrap:"wrap"}}><span style={tag}>{n.category}</span><span style={{fontSize:12,color:"#888"}}>{n.published_at?new Date(n.published_at).toLocaleString():new Date(n.created_at).toLocaleDateString()}</span><span style={{fontSize:11,color:"#888"}}>For {n.target}</span></div><h2 style={{fontSize:24,margin:"16px 0 8px"}}>{n.title}</h2><p style={{whiteSpace:"pre-wrap",lineHeight:1.75,color:"#bbb",margin:0}}>{n.body}</p>{n.action_url&&/^https:\/\//i.test(n.action_url)&&<a href={n.action_url} target="_blank" rel="noreferrer" style={{display:"inline-block",marginTop:16,textDecoration:"underline"}}>Learn more ↗</a>}</article>)}</div>}
 <div style={{marginTop:28,fontSize:12,color:"#777"}}>Website updates use realtime refresh. In-app and OS notifications require compatible app code and, for push delivery, a configured push service.</div>
 </main>;
}
const panel={border:"1px solid #ffffff20",borderRadius:20,background:"#ffffff06",padding:24};
const button={border:"1px solid #ffffff40",borderRadius:99,padding:"10px 16px",background:"#fff",color:"#111",cursor:"pointer"};
const tag={border:"1px solid #ffffff25",borderRadius:99,padding:"5px 10px",fontSize:11,textTransform:"uppercase" as const,letterSpacing:".1em"};
