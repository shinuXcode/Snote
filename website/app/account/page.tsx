"use client";

import {useCallback,useEffect,useState} from "react";
import {createClient,type SupabaseClient} from "@supabase/supabase-js";
import Reveal from "../../components/Reveal";

type Note={
  id:string;
  title:string;
  updated_at:string;
  note_type:string;
  content_json:unknown;
};

const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
const client:SupabaseClient|null=url&&key?createClient(url,key):null;

function saveBlob(name:string,body:string,mime="application/json"){
  const blob=new Blob([body],{type:mime});
  const href=URL.createObjectURL(blob);
  const a=document.createElement("a");
  a.href=href;
  a.download=name;
  a.click();
  URL.revokeObjectURL(href);
}

export default function Account(){
  const[email,setEmail]=useState("");
  const[password,setPassword]=useState("");
  const[user,setUser]=useState<string|null>(null);
  const[notes,setNotes]=useState<Note[]>([]);
  const[error,setError]=useState("");
  const[loading,setLoading]=useState(false);

  const load=useCallback(async()=>{
    if(!client)return;
    const result=await client.from("notes").select("id,title,updated_at,note_type,content_json").order("updated_at",{ascending:false});
    if(result.error)setError(result.error.message);
    else setNotes((result.data??[]) as Note[]);
  },[]);

  useEffect(()=>{
    if(!client)return;
    client.auth.getUser().then(({data})=>{
      setUser(data.user?.email??null);
      if(data.user)void load();
    });
    const {data}=client.auth.onAuthStateChange((_event,session)=>{
      const emailValue=session?.user?.email??null;
      setUser(emailValue);
      if(emailValue)void load();
      else setNotes([]);
    });
    return()=>data.subscription.unsubscribe();
  },[load]);

  async function auth(kind:"login"|"signup"){
    if(!client){setError("Add Supabase environment variables to the Vercel deployment.");return}
    setError("");setLoading(true);
    try{
      const result=kind==="login"
        ? await client.auth.signInWithPassword({email,password})
        : await client.auth.signUp({email,password});
      if(result.error)throw result.error;
      if(kind==="signup"&&!result.data.session)setError("Check your email to confirm your Snote account.");
    }catch(e){setError(e instanceof Error?e.message:String(e))}
    finally{setLoading(false)}
  }

  async function google(){
    if(!client){setError("Supabase is not configured.");return}
    const result=await client.auth.signInWithOAuth({
      provider:"google",
      options:{redirectTo:window.location.origin+"/account"}
    });
    if(result.error)setError(result.error.message);
  }

  function download(n:Note){
    saveBlob(
      (n.title||"snote").replace(/[^a-z0-9-_ ]/gi,"_")+".snote.json",
      JSON.stringify({format:"snote-json-v1",note:n},null,2)
    );
  }

  function exportAll(){
    saveBlob("snote-notebook.snote.json",JSON.stringify({format:"snote-json-v1",notes},null,2));
  }

  return <main className="shell section">
    <Reveal><div className="eyebrow">Account portal</div><h1 className="title">Your notebook, on the web.</h1><p className="lead">Sign in with the same Snote account used by the app and export your cloud-synced notes directly.</p></Reveal>
    {!user ? <Reveal><div className="card form">
      <input className="input" placeholder="Email" value={email} onChange={e=>setEmail(e.target.value)} />
      <input className="input" placeholder="Password" type="password" value={password} onChange={e=>setPassword(e.target.value)} />
      <div className="row">
        <button className="button" disabled={loading} onClick={()=>auth("login")}>Sign in</button>
        <button className="button" disabled={loading} onClick={()=>auth("signup")}>Create account</button>
        <button className="button" disabled={loading} onClick={google}>Google</button>
      </div>
      {error&&<p className="muted">{error}</p>}
    </div></Reveal> : <Reveal><div className="card">
      <div className="row" style={{justifyContent:"space-between",alignItems:"center"}}>
        <div><div className="eyebrow">Signed in</div><h2>{user}</h2></div>
        <div className="row">
          <button className="button" onClick={exportAll} disabled={!notes.length}>Export all</button>
          <button className="button" onClick={load}>Refresh</button>
          <button className="button" onClick={()=>client?.auth.signOut()}>Sign out</button>
        </div>
      </div>
      {error&&<p className="muted">{error}</p>}
      {notes.length===0?<p className="muted">No synced notes are visible yet. Create a note in Snote and reconnect.</p>:notes.map(n=><div className="note" key={n.id}>
        <div><b>{n.title||"Untitled"}</b><div className="muted">{new Date(n.updated_at).toLocaleString()} · {n.note_type}</div></div>
        <button className="button" onClick={()=>download(n)}>Download</button>
      </div>)}
    </div></Reveal>}
  </main>
}
