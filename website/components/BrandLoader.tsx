"use client";

import Image from "next/image";
import { useEffect, useState } from "react";

export default function BrandLoader() {
 const [visible, setVisible] = useState(true);
 const [exiting, setExiting] = useState(false);

 useEffect(() => {
  let hideTimer: number | undefined;
  let removeTimer: number | undefined;

  const finish = () => {
   if (removeTimer !== undefined) return;
   setExiting(true);
   removeTimer = window.setTimeout(() => setVisible(false), 240);
  };

  if (document.readyState === "complete") {
   hideTimer = window.setTimeout(finish, 320);
  } else {
   window.addEventListener("load", finish, { once: true });
   hideTimer = window.setTimeout(finish, 1400);
  }

  return () => {
   if (hideTimer !== undefined) window.clearTimeout(hideTimer);
   if (removeTimer !== undefined) window.clearTimeout(removeTimer);
   window.removeEventListener("load", finish);
  };
 }, []);

 if (!visible) return null;

 return (
  <div
   className={`brand-loader${exiting ? " is-hidden" : ""}`}
   role="status"
   aria-label="Loading Snotee"
   aria-live="polite"
   aria-hidden={exiting}
  >
   <div className="brand-loader-mark">
    <Image src="/snote-logo.png" alt="" width={140} height={140} priority quality={100} />
   </div>
   <span className="brand-loader-word">snotee</span>
   <span className="brand-loader-track" aria-hidden="true"><i /></span>
  </div>
 );
}
