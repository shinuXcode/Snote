"use client";
import { useState } from "react";
import Link from "next/link";
import ThemeToggle from "./ThemeToggle";
import Icon from "./Icon";
import NotificationCenter from "./NotificationCenter";
const items = [["/how-it-works","Showcase"],["/features","Features"],["/docs","Docs"],["/founder","Founder"],["/download","Download"]];
export default function MobileNav() {
 const [open,setOpen] = useState(false);
 return <div className="mobile-nav"><NotificationCenter/><ThemeToggle compact/><button className="icon-button" aria-label={open ? "Close navigation" : "Open navigation"} aria-expanded={open} onClick={()=>setOpen(!open)}><Icon name={open ? "close" : "menu"} size={19}/></button>{open && <div className="mobile-menu">{items.map(([href,label])=><Link key={href} href={href} onClick={()=>setOpen(false)}>{label}</Link>)}</div>}</div>;
}
