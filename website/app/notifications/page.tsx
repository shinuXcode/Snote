"use client";
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@supabase/supabase-js";
type Notice={id:string;title:string;body:string;category:string;action_url:string|null;created_at:string;published_at:string|null;expires_at:string|null};
const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
const client=url&&key?createClient(url,key):null;
export default function NotificationsPage(){
 const [items,setItems]=useState<Notice[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState("");
 const load=useCallback(async()=>{if(!client){setError("Notification feed is not configured yet.");setLoading(false);return;}try{const now=new Date().toISOString();const {data,error}=await client.from("website_notifications").select("id,title,body,category,action_url,created_at,published_at,expires_at").not("published_at","is",null).lte("published_at",now).order("published_at",{ascending:false}).limit(100);if(error)throw error;setItems(((data||[]) as Notice[]).filter(x=>!x.expires_at||x.expires_at>now));setError("")}catch(e){setError(e instanceof Error?e.message:"Could not load notifications")}finally{setLoading(false)}},[]);
 useEffect(()=>{void load();const timer=setInterval(()=>void load(),60000);return()=>clearInterval(timer)},[load]);
 return <main className="shell section notification-page"><div className="eyebrow">SNOTE / NOTICEBOARD</div><div className="control-head"><div><h1 className="title">Notification centre<span>.</span></h1><p className="lead">Product updates and announcements shared with the Snote beta app.</p></div><Link className="button" href="/docs">Documentation ↗</Link></div>
 <div className="notification-feed-head"><div><span className="pill">LIVE FEED</span><h2>Latest updates</h2></div><button className="button button-quiet" onClick={()=>{setLoading(true);void load()}}>Refresh</button></div>
 {loading?<div className="card notification-empty">Loading announcements…</div>:error?<div className="card notification-empty"><h2>Feed unavailable</h2><p>{error}</p></div>:items.length===0?<div className="card notification-empty"><h2>All quiet for now</h2><p>New announcements will appear here after they are published in the Control Room.</p></div>:<div className="notification-feed">{items.map(item=><article className="card notification-card" key={item.id}><div className="notification-meta"><span className="pill">{item.category}</span><time>{new Date(item.published_at||item.created_at).toLocaleString()}</time></div><h2>{item.title}</h2><p>{item.body}</p>{item.action_url&&<a className="notification-action" href={item.action_url} target="_blank" rel="noreferrer">Learn more ↗</a>}</article>)}</div>}
 <p className="notification-note">The website feed is public. The app imports published notices into its local notification inbox when connected to the internet and configured with the same Supabase project.</p></main>
}
