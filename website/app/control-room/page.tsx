"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import Link from "next/link";

type Notification = { id:string; title:string; body:string; category:string; action_url:string|null; created_at:string; published_at:string|null; expires_at:string|null };
const empty = { title:"", body:"", category:"announcement", actionUrl:"", expiresAt:"", published:false };

export default function ControlRoom() {
  const [password,setPassword]=useState("");
  const [signedIn,setSignedIn]=useState(false);
  const [items,setItems]=useState<Notification[]>([]);
  const [form,setForm]=useState(empty);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState("");
  const [notice,setNotice]=useState("");
  const request=async(method:string,body?:unknown,url="/api/control-room/notifications")=>{
    const response=await fetch(url,{method,headers:{"Content-Type":"application/json"},...(body===undefined?{}:{body:JSON.stringify(body)})});
    const data=await response.json().catch(()=>({error:"Unexpected server response"}));
    if(!response.ok)throw new Error(data.error||"Request failed");
    return data;
  };
  const refresh=useCallback(async()=>{try{const data=await request("GET");setItems(data.notifications||[]);setSignedIn(true);setError("")}catch(e){setSignedIn(false);if(e instanceof Error&&e.message!=="Session expired. Sign in again.")setError(e.message)}},[]);
  useEffect(()=>{void refresh()},[refresh]);
  async function login(e:FormEvent){e.preventDefault();setBusy(true);setError("");try{await request("POST",{action:"login",password});setSignedIn(true);setPassword("");await refresh()}catch(e){setError(e instanceof Error?e.message:"Login failed")}finally{setBusy(false)}}
  async function publish(e:FormEvent){e.preventDefault();setBusy(true);setError("");setNotice("");try{await request("POST",{...form,expiresAt:form.expiresAt?new Date(form.expiresAt).toISOString():null});setForm(empty);setNotice(form.published?"Published to Snote beta inbox.":"Saved as draft.");await refresh()}catch(e){setError(e instanceof Error?e.message:"Could not save notification")}finally{setBusy(false)}}
  async function toggle(item:Notification){setBusy(true);setError("");try{await request("PATCH",{id:item.id,published:!item.published_at});await refresh()}catch(e){setError(e instanceof Error?e.message:"Could not update notification")}finally{setBusy(false)}}
  async function remove(item:Notification){if(!window.confirm("Delete this notification permanently?"))return;setBusy(true);try{await request("DELETE",undefined,"/api/control-room/notifications?id="+encodeURIComponent(item.id));await refresh()}catch(e){setError(e instanceof Error?e.message:"Could not delete notification")}finally{setBusy(false)}}
  return <main className="shell section control-room">
    <div className="eyebrow">SNOTE / ADMINISTRATION</div>
    <div className="control-head"><div><h1 className="title">Control Room<span>.</span></h1><p className="lead">Publish announcements to the Snote website and the connected beta app inbox.</p></div><Link className="button" href="/notifications">View notification centre ↗</Link></div>
    {!signedIn?<form className="card control-login" onSubmit={login}><h2>Admin sign-in</h2><p className="muted">Private publishing access. Use the server-configured Control Room password.</p><label className="control-field">Password<input autoComplete="current-password" type="password" value={password} onChange={e=>setPassword(e.target.value)} required /></label><button className="button" disabled={busy}>{busy?"Checking…":"Unlock Control Room"}</button>{error&&<p className="control-error" role="alert">{error}</p>}</form>:<div className="control-grid">
      <form className="card control-composer" onSubmit={publish}><div className="control-card-head"><div><span className="pill">COMPOSER</span><h2>New notification</h2></div><span className="muted">Max 120 / 2,000 chars</span></div>
        <label className="control-field">Title<input maxLength={120} value={form.title} onChange={e=>setForm({...form,title:e.target.value})} required /></label>
        <label className="control-field">Message<textarea maxLength={2000} rows={5} value={form.body} onChange={e=>setForm({...form,body:e.target.value})} required /></label>
        <div className="control-fields-row"><label className="control-field">Category<select value={form.category} onChange={e=>setForm({...form,category:e.target.value})}><option value="announcement">Announcement</option><option value="release">Release</option><option value="maintenance">Maintenance</option><option value="security">Security</option><option value="feature">Feature</option></select></label><label className="control-field">Expires (optional)<input type="datetime-local" value={form.expiresAt} onChange={e=>setForm({...form,expiresAt:e.target.value})}/></label></div>
        <label className="control-field">Action URL (optional)<input type="url" placeholder="https://…" value={form.actionUrl} onChange={e=>setForm({...form,actionUrl:e.target.value})}/></label>
        <label className="control-check"><input type="checkbox" checked={form.published} onChange={e=>setForm({...form,published:e.target.checked})}/> Publish immediately to website and beta app inbox</label>
        <button className="button" disabled={busy}>{busy?"Saving…":form.published?"Publish notification":"Save draft"}</button>
        {error&&<p className="control-error" role="alert">{error}</p>}{notice&&<p className="control-success" role="status">{notice}</p>}
      </form>
      <section className="card control-list"><div className="control-card-head"><div><span className="pill">DELIVERY</span><h2>Notification feed</h2></div><button className="button button-quiet" onClick={()=>void refresh()}>Refresh</button></div>
        <div className="control-stats"><div><strong>{items.length}</strong><span>Total</span></div><div><strong>{items.filter(x=>x.published_at).length}</strong><span>Published</span></div><div><strong>{items.filter(x=>!x.published_at).length}</strong><span>Drafts</span></div></div>
        {items.length===0?<p className="muted">No notifications yet. Create one to begin.</p>:<div className="control-items">{items.map(item=><article className="control-item" key={item.id}><div className="control-item-top"><span className={"control-status "+(item.published_at?"is-live":"")}>{item.published_at?"LIVE":"DRAFT"}</span><span className="muted">{item.category}</span><time>{new Date(item.created_at).toLocaleString()}</time></div><h3>{item.title}</h3><p>{item.body}</p>{item.action_url&&<a href={item.action_url} target="_blank" rel="noreferrer">Action link ↗</a>}<div className="control-item-actions"><button className="button button-quiet" disabled={busy} onClick={()=>void toggle(item)}>{item.published_at?"Unpublish":"Publish"}</button><button className="button button-danger" disabled={busy} onClick={()=>void remove(item)}>Delete</button></div></article>)}</div>}
      </section>
    </div>}
    <p className="control-footnote">Publishing writes to the shared Supabase feed. The app syncs while online when its Updates &amp; notifications screen refreshes. OS-level push notifications require platform push credentials and are not enabled by this feed alone.</p>
  </main>
}
