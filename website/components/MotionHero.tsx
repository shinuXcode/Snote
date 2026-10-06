"use client";
import {motion} from "motion/react";
import Link from "next/link";
export default function MotionHero(){return <section className="hero"><motion.div className="orb" animate={{scale:[1,1.18,1],opacity:[.5,.8,.5]}} transition={{duration:7,repeat:Infinity}}/><div className="shell"><motion.div initial={{opacity:0,y:24}} animate={{opacity:1,y:0}} transition={{duration:.7}}><div className="eyebrow">Open source · offline first · cross platform</div><h1>Write<br/>without limits.</h1><p>A calm handwriting workspace for stylus, rich text, PDFs and ideas — designed to keep your notes yours.</p><Link className="cta" href="/download">Get Snote</Link></motion.div></div></section>}
