"use client";
import { useEffect, useState } from "react";
export default function ThemeToggle({ compact = false }: { compact?: boolean }) {
 const [theme,setTheme] = useState<"dark"|"light">("dark");
 useEffect(()=>{ const saved=window.localStorage.getItem("snote-theme"); const next=saved==="light"?"light":"dark"; setTheme(next); document.documentElement.dataset.theme=next; },[]);
 function toggle(){ const next=theme==="dark"?"light":"dark"; setTheme(next); document.documentElement.dataset.theme=next; window.localStorage.setItem("snote-theme",next); }
 return <button className={compact?"theme-toggle theme-toggle-compact":"theme-toggle"} type="button" onClick={toggle} aria-label={theme==="dark"?"Switch to light mode":"Switch to dark mode"} title={theme==="dark"?"Light mode":"Dark mode"}>{theme==="dark"?<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.93 4.93l1.42 1.42m11.3 11.3 1.42 1.42M2 12h2m16 0h2M4.93 19.07l1.42-1.42m11.3-11.3 1.42-1.42"/></svg>:<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20.8 14.1A8.5 8.5 0 0 1 9.9 3.2 8.7 8.7 0 1 0 20.8 14.1Z"/></svg>}<span className="sr-only">{theme==="dark"?"Light mode":"Dark mode"}</span></button>;
}
