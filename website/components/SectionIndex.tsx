"use client";
export default function SectionIndex(){
 const sections=[["01","home"],["02","blueprint-roll"],["03","features"],["04","lower-section"]];
 function jump(index:number,id:string){document.getElementById(id)?.scrollIntoView({behavior:"smooth",block:"start"});document.querySelectorAll(".hero-index button").forEach((button,i)=>{if(i===index)button.setAttribute("aria-current","location");else button.removeAttribute("aria-current")})}
 return <nav className="hero-index" aria-label="Jump between homepage sections">{sections.map(([number,id],index)=><button key={number} type="button" className={index===0?"is-active":""} aria-label={["Home","Highlights","Features","More about Snote"][index]} aria-current={index===0?"location":undefined} onClick={()=>jump(index,id)}>{number}</button>)}</nav>
}
