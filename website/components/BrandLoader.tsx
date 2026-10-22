"use client";
import { useEffect, useState } from "react";
export default function BrandLoader() {
 const [visible,setVisible] = useState(true);
 useEffect(() => {
  const started = Date.now();
  const timer = window.setTimeout(() => setVisible(false), Math.max(450, 950 - (Date.now()-started)));
  return () => window.clearTimeout(timer);
 }, []);
 if (!visible) return null;
 return <div className="brand-loader" role="status" aria-label="Loading Snote" aria-live="polite">
  <div className="brand-loader-mark"><img src="/snote-logo.svg" alt="" /></div>
  <span className="brand-loader-word">snote</span>
  <span className="brand-loader-track"><i /></span>
 </div>;
}
