"use client";

import {useState} from "react";
import Link from "next/link";

const items=[["/features","Features"],["/how-it-works","How it works"],["/download","Download"],["/founder","Founder"],["/account","Account"]];

export default function MobileNav(){
  const[open,setOpen]=useState(false);
  return <div className="mobile-nav">
    <button className="icon-button" aria-label="Open navigation" onClick={()=>setOpen(!open)}>☰</button>
    {open && <div className="mobile-menu">
      {items.map(([href,label])=><Link key={href} href={href} onClick={()=>setOpen(false)}>{label}</Link>)}
    </div>}
  </div>;
}
