import Link from "next/link";
import Reveal from "../../components/Reveal";

const version="0.3.0";
const releases="https://github.com/shinuXcode/Snote/releases/latest/download";
const web=process.env.NEXT_PUBLIC_SNOTE_WEB_APP_URL || "/";

const builds=[
  ["Android","APK",releases+"/Snote-Android.apk","Install on supported Android devices"],
  ["Windows","ZIP",releases+"/Snote-Windows.zip","Portable desktop build"],
  ["macOS","ZIP",releases+"/Snote-macOS.zip","macOS desktop build"],
  ["Linux","TAR.GZ",releases+"/Snote-Linux.tar.gz","Linux desktop bundle"],
  ["iOS","UNSIGNED ZIP",releases+"/Snote-iOS-unsigned.zip","Development build; App Store signing required"],
  ["Web","Browser",web,"Open the browser app"],
];

export default function Page(){
  return <main className="shell section">
    <Reveal><div className="eyebrow">Download center</div><h1 className="title">Snote {version}</h1><p className="lead">Every platform uses the same notebook format and account identity.</p></Reveal>
    <div className="grid">
      {builds.map(([name,type,url,desc])=><Reveal key={name}><article className="card feature-card"><span className="pill">{type}</span><h2>{name}</h2><p className="muted">{desc}</p><a className="cta" href={url}>{name==="Web"?"Launch":"Download"}</a></article></Reveal>)}
    </div>
    <Reveal><div className="card" style={{marginTop:18}}><div className="eyebrow">Release policy</div><h2>Published only from passing release builds.</h2><p className="muted">The tagged release workflow builds platform artifacts, runs analyze/tests and publishes the same versioned assets used by this page.</p><Link href="/account">Open the note portal →</Link></div></Reveal>
  </main>
}
