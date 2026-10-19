"use client";
import { useEffect, useState } from "react";
import Icon from "./Icon";
export default function ThemeToggle({ compact = false }: { compact?: boolean }) {
 const [theme,setTheme] = useState<"dark"|"light">("dark");
 useEffect(()=>{ const saved=window.localStorage.getItem("snote-theme"); const next=saved==="light"?"light":"dark"; setTheme(next); document.documentElement.dataset.theme=next; },[]);
 function toggle(){ const next=theme==="dark"?"light":"dark"; setTheme(next); document.documentElement.dataset.theme=next; window.localStorage.setItem("snote-theme",next); }
 return <button className={compact?"theme-toggle theme-toggle-compact":"theme-toggle"} type="button" onClick={toggle} aria-label={theme==="dark"?"Switch to light mode":"Switch to dark mode"} title={theme==="dark"?"Light mode":"Dark mode"}><Icon name={theme==="dark"?"sun":"moon"} size={21}/><span className="sr-only">{theme==="dark"?"Light mode":"Dark mode"}</span></button>;
}
