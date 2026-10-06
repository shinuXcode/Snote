"use client";

import {motion} from "motion/react";
import Link from "next/link";

export default function MotionHero(){
  return <section className="hero">
    <motion.div
      className="orb orb-a"
      animate={{scale:[1,1.18,1],opacity:[.35,.72,.35],rotate:[0,20,0]}}
      transition={{duration:9,repeat:Infinity,ease:"easeInOut"}}
    />
    <motion.div
      className="orb orb-b"
      animate={{scale:[1.1,.9,1.1],opacity:[.18,.45,.18],x:[0,70,0],y:[0,-35,0]}}
      transition={{duration:12,repeat:Infinity,ease:"easeInOut"}}
    />
    <div className="hero-grid" />
    <div className="shell hero-content">
      <motion.img
        className="hero-logo"
        src="/snote-logo.svg"
        alt=""
        initial={{opacity:0,scale:.75,rotate:-8}}
        animate={{opacity:1,scale:1,rotate:0}}
        transition={{duration:.8,ease:[.22,1,.36,1]}}
      />
      <motion.div
        initial={{opacity:0,y:24}}
        animate={{opacity:1,y:0}}
        transition={{duration:.7,delay:.08}}
      >
        <div className="eyebrow">Open source · offline first · cross platform</div>
        <h1>Write<br/><span>without limits.</span></h1>
        <p>A calm handwriting workspace for stylus, rich text, PDFs and ideas — designed around ownership, speed and continuity.</p>
        <div className="row hero-actions">
          <Link className="cta" href="/download">Get Snote</Link>
          <Link className="ghost-cta" href="/features">Explore features</Link>
        </div>
      </motion.div>
      <div className="hero-ribbon">
        {["Vector ink","Paper templates","PDF layers","Cloud identity","Local first"].map((item,i)=><motion.span key={item} initial={{opacity:0,y:10}} animate={{opacity:1,y:0}} transition={{delay:.35+i*.08}}>{item}</motion.span>)}
      </div>
    </div>
  </section>
}
