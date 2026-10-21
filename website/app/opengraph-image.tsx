import { ImageResponse } from "next/og";
export const runtime = "edge";
export const alt = "Snote — open-source handwriting notes and PDF annotation";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export default function OpenGraphImage() {
 return new ImageResponse(
  <div style={{width:"100%",height:"100%",display:"flex",flexDirection:"column",justifyContent:"space-between",padding:"72px",background:"#f5f3ee",color:"#20211e",fontFamily:"sans-serif"}}>
   <div style={{display:"flex",alignItems:"center",gap:"18px",fontSize:32,fontWeight:700}}><div style={{width:64,height:64,borderRadius:18,background:"#20211e",color:"#f5f3ee",display:"flex",alignItems:"center",justifyContent:"center",fontSize:38}}>s.</div><span>snote</span><span style={{fontSize:17,fontWeight:500,marginLeft:12,color:"#77786f"}}>OPEN SOURCE · LOCAL FIRST</span></div>
   <div style={{display:"flex",flexDirection:"column",gap:18}}><div style={{fontSize:76,fontWeight:700,lineHeight:1.05,letterSpacing:-3}}>Make room for<br/>better thinking.</div><div style={{fontSize:29,color:"#65665e"}}>Handwriting · Digital notebooks · PDF annotation</div></div>
   <div style={{display:"flex",justifyContent:"space-between",fontSize:20,color:"#65665e"}}><span>Open-source note-taking workspace</span><span>snote-showcase.vercel.app</span></div>
  </div>,
  { ...size }
 );
}
